# app/api/routes_style.py
from __future__ import annotations

import base64
import io
import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import httpx
from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from PIL import Image
from pymongo import ReturnDocument

from app.core.config import settings
from app.db.mongo import counters_collection, garments_collection, get_db
from app.models.schemas import Category, WardrobeItem
from app.services.storage import store_image_bytes
from app.services.vectorai import garment_doc_to_payload, garment_doc_to_text, get_vector_ai

# ---- Try to reuse your existing image safety helper (path differs across your files) ----
try:
    from app.core.security import validate_image_bytes  # type: ignore
except Exception:  # pragma: no cover
    from app.security import validate_image_bytes  # type: ignore

router = APIRouter(prefix="/style", tags=["style"])


# -------------------------
# helpers
# -------------------------

def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _base_url(req: Request) -> str:
    return str(req.base_url).rstrip("/")


def _make_thumb(image_bytes: bytes, *, max_size: int = 512) -> bytes:
    with Image.open(io.BytesIO(image_bytes)) as im:
        im = im.convert("RGB")
        im.thumbnail((max_size, max_size))
        out = io.BytesIO()
        im.save(out, format="JPEG", quality=85, optimize=True)
        return out.getvalue()


def _encode_jpeg(img: Image.Image, *, quality: int = 90) -> bytes:
    out = io.BytesIO()
    img.convert("RGB").save(out, format="JPEG", quality=quality, optimize=True)
    return out.getvalue()


def _crop_normalized_box(image_bytes: bytes, box: Dict[str, Any]) -> bytes:
    """
    box: {"x":0..1, "y":0..1, "w":0..1, "h":0..1}
    Returns cropped JPEG bytes.
    """
    with Image.open(io.BytesIO(image_bytes)) as im:
        im = im.convert("RGB")
        W, H = im.size

        x = float(box.get("x", 0.0))
        y = float(box.get("y", 0.0))
        w = float(box.get("w", 0.0))
        h = float(box.get("h", 0.0))

        # clamp
        x = max(0.0, min(1.0, x))
        y = max(0.0, min(1.0, y))
        w = max(0.0, min(1.0, w))
        h = max(0.0, min(1.0, h))

        left = int(round(x * W))
        top = int(round(y * H))
        right = int(round((x + w) * W))
        bottom = int(round((y + h) * H))

        left = max(0, min(W - 1, left))
        top = max(0, min(H - 1, top))
        right = max(left + 1, min(W, right))
        bottom = max(top + 1, min(H, bottom))

        cropped = im.crop((left, top, right, bottom))
        return _encode_jpeg(cropped, quality=90)


def _next_counter(name: str) -> int:
    doc = counters_collection().find_one_and_update(
        {"_id": name},
        {"$inc": {"seq": 1}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    return int((doc or {}).get("seq", 0))


def _new_item_id() -> str:
    n = _next_counter("wardrobe_item_id")
    return f"item_{n}"


def _new_change_seq() -> int:
    return _next_counter("wardrobe_change_seq")


def _coerce_category(raw: Any) -> str:
    v = str(raw or "").strip().lower()
    allowed = {c.value for c in Category}
    return v if v in allowed else "top"


def _coerce_colors(raw: Any) -> List[str]:
    if raw is None:
        return []
    if isinstance(raw, str):
        return [raw.strip()] if raw.strip() else []
    if isinstance(raw, list):
        out = []
        for c in raw:
            s = str(c).strip()
            if s:
                out.append(s)
        return out
    return []


# -------------------------
# Gemini
# -------------------------

async def _gemini_parse_person_outfit(
    *,
    image_bytes: bytes,
    mime_type: str,
    prompt: Optional[str],
    include_boxes: bool,
) -> Dict[str, Any]:
    """
    Calls Gemini with an image and returns parsed JSON (best-effort).
    Requires env: GEMINI_API_KEY
    Optional env: GEMINI_MODEL (default: gemini-2.5-flash)
    """
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not set")

    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash").strip() or "gemini-2.5-flash"
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    params = {"key": api_key}

    if include_boxes:
        instruction = (
            "Return JSON ONLY (no markdown, no backticks).\n"
            "Task: Analyze this person's outfit and return items with bounding boxes.\n"
            "Output schema:\n"
            "{\n"
            '  "outfit": {\n'
            '    "items": [\n'
            '      {\n'
            '        "category":"outerwear|top|bottom|shoes|accessory",\n'
            '        "type":"string",\n'
            '        "colors":["string"],\n'
            '        "pattern":null|string,\n'
            '        "material":null|string,\n'
            '        "box":{"x":0.0,"y":0.0,"w":0.0,"h":0.0}\n'
            "      }\n"
            "    ],\n"
            '    "style_tags": ["string"],\n'
            '    "overall_palette": ["string"],\n'
            '    "barefoot": boolean,\n'
            '    "notes": "string"\n'
            "  }\n"
            "}\n"
            "Rules:\n"
            "- category must be exactly one of: outerwear, top, bottom, shoes, accessory\n"
            "- colors per item: 1–3 DOMINANT colors only\n"
            "- overall_palette: 3–6 colors max\n"
            "- box coordinates are NORMALIZED floats in [0,1], relative to the full image\n"
            "- box should tightly cover the visible garment region\n"
            "- If you are not confident about a box, omit the item entirely (do not hallucinate boxes)\n"
            "- If barefoot, set barefoot=true and do NOT add a shoes item.\n"
            "- If shoes visible, set barefoot=false and include a shoes item.\n"
            "- If uncertain about material/pattern, use null.\n"
        )
    else:
        instruction = (
            "Return JSON ONLY (no markdown, no backticks).\n"
            "Task: Analyze this person's outfit.\n"
            "Output schema:\n"
            "{\n"
            '  "outfit": {\n'
            '    "items": [\n'
            '      {"category":"outerwear|top|bottom|shoes|accessory","type":"string","colors":["string"],'
            '"pattern":null|string,"material":null|string}\n'
            "    ],\n"
            '    "style_tags": ["string"],\n'
            '    "overall_palette": ["string"],\n'
            '    "barefoot": boolean,\n'
            '    "notes": "string"\n'
            "  }\n"
            "}\n"
            "Rules:\n"
            "- category must be exactly one of: outerwear, top, bottom, shoes, accessory\n"
            "- colors per item: 1–3 DOMINANT colors only\n"
            "- overall_palette: 3–6 colors max\n"
            "- If barefoot, set barefoot=true and do NOT add a shoes item.\n"
            "- If shoes visible, set barefoot=false and include a shoes item.\n"
            "- If uncertain about material/pattern, use null.\n"
        )

    user_prompt = (prompt or "").strip()
    user_text = instruction + ("\nUser prompt: " + user_prompt if user_prompt else "")

    b64 = base64.b64encode(image_bytes).decode("utf-8")
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": user_text},
                    {"inline_data": {"mime_type": mime_type, "data": b64}},
                ],
            }
        ],
        "generationConfig": {
            "temperature": 0.2,
            "response_mime_type": "application/json",
        },
    }

    async with httpx.AsyncClient(timeout=45.0) as client:
        resp = await client.post(url, params=params, json=payload)
        resp.raise_for_status()
        data = resp.json()

    text = ""
    try:
        text = data["candidates"][0]["content"]["parts"][0].get("text", "") or ""
    except Exception:
        text = ""

    text = text.strip()
    if not text:
        return {"error": "empty_gemini_response", "raw": data}

    try:
        return json.loads(text)
    except Exception:
        return {"raw": text}


# -------------------------
# existing endpoints
# -------------------------

@router.post("/request")
async def create_style_request(
    userId: str = Form(...),
    prompt: str = Form(...),
    personImage: UploadFile = File(...),
):
    if not personImage:
        raise HTTPException(status_code=400, detail="personImage is required")

    img_bytes = await personImage.read()
    if not img_bytes:
        raise HTTPException(status_code=400, detail="Empty image upload.")

    try:
        detected_mime = validate_image_bytes(img_bytes, personImage.content_type)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    db = get_db()
    now = _utc_now_iso()

    image_doc: Optional[dict] = None
    if settings.store_person_image:
        file_id = store_image_bytes(
            img_bytes,
            filename=personImage.filename or "person.jpg",
            content_type=detected_mime,
        )
        image_doc = {
            "storage": "gridfs",
            "fileId": str(file_id),
            "mimeType": detected_mime,
            "filename": personImage.filename or "person.jpg",
        }

    doc = {
        "userId": (userId or "").strip(),
        "userPrompt": (prompt or "").strip(),
        "status": "received",
        "personImage": image_doc,
        "createdAt": now,
        "updatedAt": now,
        "error": None,
    }

    res = db.style_requests.insert_one(doc)

    return {
        "requestId": str(res.inserted_id),
        "storedPersonImage": bool(image_doc),
        "status": "received",
    }


@router.post("/parse-person")
async def parse_person(
    userId: str = Form(...),
    prompt: str | None = Form(None),
    personImage: UploadFile = File(...),
    saveRequest: bool = Form(True),
    includeBoxes: bool = Form(False),
):
    """
    Takes a person photo and returns Gemini JSON describing the outfit.
    If includeBoxes=true -> include per-item normalized boxes.
    If saveRequest=true -> stores a style_requests doc with output.
    """
    if not personImage:
        raise HTTPException(status_code=400, detail="personImage is required")

    img_bytes = await personImage.read()
    if not img_bytes:
        raise HTTPException(status_code=400, detail="Empty image upload.")

    try:
        detected_mime = validate_image_bytes(img_bytes, personImage.content_type)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    image_doc: Optional[dict] = None
    if settings.store_person_image:
        file_id = store_image_bytes(
            img_bytes,
            filename=personImage.filename or "person.jpg",
            content_type=detected_mime,
        )
        image_doc = {
            "storage": "gridfs",
            "fileId": str(file_id),
            "mimeType": detected_mime,
            "filename": personImage.filename or "person.jpg",
        }

    try:
        result = await _gemini_parse_person_outfit(
            image_bytes=img_bytes,
            mime_type=detected_mime,
            prompt=prompt,
            include_boxes=bool(includeBoxes),
        )
    except httpx.HTTPStatusError as e:
        body = ""
        try:
            body = e.response.text
        except Exception:
            body = ""
        raise HTTPException(status_code=502, detail=f"Gemini error: {str(e)} {body}".strip())
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error calling Gemini: {str(e)}")

    request_id: Optional[str] = None
    if bool(saveRequest):
        db = get_db()
        now = _utc_now_iso()
        doc = {
            "userId": (userId or "").strip(),
            "userPrompt": (prompt or "").strip() if prompt else "",
            "status": "parsed",
            "personImage": image_doc,
            "geminiResult": result,
            "createdAt": now,
            "updatedAt": now,
            "error": None,
        }
        res = db.style_requests.insert_one(doc)
        request_id = str(res.inserted_id)

    return {
        "requestId": request_id,
        "storedPersonImage": bool(image_doc),
        "result": result,
    }


# -------------------------
# NEW: parse -> crop -> ingest -> vector index
# -------------------------

@router.post("/parse-and-ingest-crops")
async def parse_and_ingest_crops(
    request: Request,
    userId: str = Form(...),
    prompt: str | None = Form(None),
    personImage: UploadFile = File(...),
    saveRequest: bool = Form(True),
    maxItems: int = Form(10),
):
    """
    1) Gemini parse WITH boxes
    2) crop each item from person image
    3) store crops in GridFS
    4) insert wardrobe docs into Mongo
    5) upsert into VectorAI

    Returns: { requestId, createdItems, parsed }
    """
    user_id = (userId or "").strip()
    if not user_id:
        raise HTTPException(status_code=400, detail="userId is required")

    if not personImage:
        raise HTTPException(status_code=400, detail="personImage is required")

    img_bytes = await personImage.read()
    if not img_bytes:
        raise HTTPException(status_code=400, detail="Empty image upload.")

    try:
        detected_mime = validate_image_bytes(img_bytes, personImage.content_type)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Parse with boxes
    try:
        parsed = await _gemini_parse_person_outfit(
            image_bytes=img_bytes,
            mime_type=detected_mime,
            prompt=prompt,
            include_boxes=True,
        )
    except httpx.HTTPStatusError as e:
        body = ""
        try:
            body = e.response.text
        except Exception:
            body = ""
        raise HTTPException(status_code=502, detail=f"Gemini error: {str(e)} {body}".strip())
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error calling Gemini: {str(e)}")

    outfit = (parsed or {}).get("outfit") or {}
    items = outfit.get("items") or []
    if not isinstance(items, list):
        raise HTTPException(status_code=502, detail="Gemini returned invalid schema: outfit.items is not a list")

    # Limit items
    try:
        max_items = int(maxItems)
    except Exception:
        max_items = 10
    max_items = max(1, min(25, max_items))
    items = items[:max_items]

    db = get_db()
    now = _utc_now_iso()

    # Store original person image in style_requests if desired
    person_image_doc: Optional[dict] = None
    if settings.store_person_image:
        person_file_id = store_image_bytes(
            img_bytes,
            filename=personImage.filename or "person.jpg",
            content_type=detected_mime,
        )
        person_image_doc = {
            "storage": "gridfs",
            "fileId": str(person_file_id),
            "mimeType": detected_mime,
            "filename": personImage.filename or "person.jpg",
        }

    request_id: Optional[str] = None
    if bool(saveRequest):
        req_doc = {
            "userId": user_id,
            "userPrompt": (prompt or "").strip(),
            "status": "parsed_and_ingested",
            "personImage": person_image_doc,
            "geminiResult": parsed,
            "createdAt": now,
            "updatedAt": now,
            "error": None,
        }
        res = db.style_requests.insert_one(req_doc)
        request_id = str(res.inserted_id)

    created: List[WardrobeItem] = []
    vec = get_vector_ai()
    base = _base_url(request)

    for it in items:
        if not isinstance(it, dict):
            continue

        box = it.get("box")
        if not isinstance(box, dict):
            # instruction says omit items if no box; still guard here
            continue

        # Crop
        try:
            crop_jpeg = _crop_normalized_box(img_bytes, box)
        except Exception:
            continue

        # Store crop + thumb
        crop_file_id = store_image_bytes(
            crop_jpeg,
            filename="garment.jpg",
            content_type="image/jpeg",
        )
        thumb_bytes = _make_thumb(crop_jpeg, max_size=512)
        thumb_file_id = store_image_bytes(
            thumb_bytes,
            filename="garment_thumb.jpg",
            content_type="image/jpeg",
        )

        # Build wardrobe doc
        item_id = _new_item_id()
        change_seq = _new_change_seq()

        cat = _coerce_category(it.get("category"))
        typ = str(it.get("type") or "").strip() or "unknown garment"
        colors = _coerce_colors(it.get("colors"))
        material = it.get("material")
        pattern = it.get("pattern")

        extra: Dict[str, Any] = {
            "source": "gemini_crop",
            "styleRequestId": request_id,
            "box": box,
        }

        doc = {
            "_id": item_id,
            "userId": user_id,
            "category": cat,
            "type": typ,
            "colors": colors,
            "material": str(material).strip() if material else None,
            "pattern": str(pattern).strip() if pattern else None,
            "season": None,
            "fit": None,
            "extra": extra,
            "imageFileId": str(crop_file_id),
            "thumbFileId": str(thumb_file_id),
            "version": 1,
            "createdAt": now,
            "updatedAt": now,
            "deletedAt": None,
            "changeSeq": change_seq,
        }

        garments_collection().insert_one(doc)

        # VectorAI upsert
        text = garment_doc_to_text(doc)
        payload = garment_doc_to_payload(doc)
        vec.upsert(item_id=item_id, payload=payload, text=text)

        # Response model
        wi = WardrobeItem(
            itemId=item_id,
            userId=user_id,
            category=Category(cat),
            type=typ,
            colors=colors,
            material=str(material).strip() if material else None,
            pattern=str(pattern).strip() if pattern else None,
            season=None,
            fit=None,
            extra=extra,
            imageFileId=str(crop_file_id),
            thumbFileId=str(thumb_file_id),
            imageUrl=f"{base}/wardrobe/media/{crop_file_id}",
            thumbUrl=f"{base}/wardrobe/media/{thumb_file_id}",
            version=1,
            createdAt=now,
            updatedAt=now,
            deletedAt=None,
        )
        created.append(wi)

    return {
        "requestId": request_id,
        "storedPersonImage": bool(person_image_doc),
        "parsed": parsed,
        "createdItems": [c.model_dump() for c in created],
        "createdCount": len(created),
    }
