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
    box: {"x":0.1, "y":0.1, "w":0.1, "h":0.1}
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
    """
    Atomic counter in Mongo.
    """
    res = counters_collection().find_one_and_update(
        {"_id": name},
        {"$inc": {"seq": 1}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    return int(res["seq"])


# -------------------------
# Gemini calls
# -------------------------

async def _gemini_studio_product_photo(
    *,
    image_bytes: bytes,
    mime_type: str = "image/jpeg",
) -> bytes:
    """
    Uses Gemini image model to "re-render" the garment on a pure white studio background.

    Returns: image bytes (often PNG; sometimes JPEG). Caller should detect magic bytes.
    """
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not set")

    model = os.getenv("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image").strip() or "gemini-2.5-flash-image"

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    params = {"key": api_key}

    b64 = base64.b64encode(image_bytes).decode("utf-8")

    prompt = (
        "You are an expert ecommerce product photographer and retoucher.\n"
        "TASK: Create a clean studio product photo of the SAME garment shown in the input image.\n"
        "STRICT RULES:\n"
        "- Preserve the garment EXACTLY (same colors, patterns, logos, text, graphics). Do not invent details.\n"
        "- Do not change garment shape, neckline, sleeve length, or fit.\n"
        "- Remove the background completely.\n"
        "- Place the garment centered on a pure white #FFFFFF seamless studio background.\n"
        "- Lighting: soft even studio lighting, minimal shadows (very subtle grounding shadow ok).\n"
        "- Output: ONE image only.\n"
        "Return an IMAGE output (not text)."
    )

    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": mime_type, "data": b64}},
                ],
            }
        ],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
        },
    }

    async with httpx.AsyncClient(timeout=90.0) as client:
        resp = await client.post(url, params=params, json=payload)
        resp.raise_for_status()
        data = resp.json()

    try:
        parts = data["candidates"][0]["content"]["parts"]
    except Exception:
        raise RuntimeError(f"Gemini returned unexpected response: {data}")

    for p in parts:
        inline = p.get("inline_data") or p.get("inlineData")
        if inline and inline.get("data"):
            return base64.b64decode(inline["data"])

    raise RuntimeError(f"Gemini returned no image parts. Response parts={parts}")


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
            "      {\n"
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
            "- If shoes are visible, set barefoot=false and include a shoes item.\n"
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
            "- colors per item: provide 1–3 DOMINANT colors only (simple names like black, white, grey, blue)\n"
            "- overall_palette: 3–6 colors max\n"
            "- If the person is barefoot, set barefoot=true and do NOT add a shoes item.\n"
            "- If shoes are visible, set barefoot=false and include a shoes item.\n"
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
# endpoints
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
# NEW: parse -> crop -> (optional studioify) -> ingest -> vector index
# -------------------------

@router.post("/parse-and-ingest-crops")
async def parse_and_ingest_crops(
    request: Request,
    userId: str = Form(...),
    prompt: str | None = Form(None),
    personImage: UploadFile = File(...),
    saveRequest: bool = Form(True),
    maxItems: int = Form(10),
    studioify: bool = Form(True),
):
    """
    1) Gemini parse WITH boxes
    2) crop each item from person image
    3) optionally run Gemini image model to "studioify" each crop
    4) store crops in GridFS
    5) insert wardrobe docs into Mongo
    6) upsert into VectorAI

    Returns: { requestId, parsed, createdItems, createdCount }
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

    base = _base_url(request)
    vec = get_vector_ai()

    created: List[WardrobeItem] = []

    for it in items:
        if not isinstance(it, dict):
            continue

        box = it.get("box")
        if not isinstance(box, dict):
            # no box -> cannot crop
            continue

        category = (it.get("category") or "").strip().lower()
        typ = (it.get("type") or "").strip()
        colors = it.get("colors") or []
        pattern = it.get("pattern")
        material = it.get("material")

        # Validate category against schema enum
        try:
            cat_enum = Category(category)
        except Exception:
            continue

        # Crop from original person image
        try:
            crop_jpeg = _crop_normalized_box(img_bytes, box)
        except Exception:
            continue

        # Optionally "studioify" via Gemini image model
        final_bytes = crop_jpeg
        final_name = "garment_crop.jpg"
        final_mime = "image/jpeg"

        if bool(studioify):
            try:
                gemini_img = await _gemini_studio_product_photo(
                    image_bytes=crop_jpeg,
                    mime_type="image/jpeg",
                )

                # detect if JPEG magic bytes; otherwise treat as PNG
                if gemini_img[:3] == b"\xff\xd8\xff":
                    final_bytes = gemini_img
                    final_name = "garment_studio.jpg"
                    final_mime = "image/jpeg"
                else:
                    final_bytes = gemini_img
                    final_name = "garment_studio.png"
                    final_mime = "image/png"
            except Exception:
                # fallback to raw crop
                final_bytes = crop_jpeg
                final_name = "garment_crop.jpg"
                final_mime = "image/jpeg"

        # Store final crop + thumbnail in GridFS
        image_file_id = store_image_bytes(
            final_bytes,
            filename=final_name,
            content_type=final_mime,
        )
        thumb_bytes = _make_thumb(final_bytes, max_size=512)
        thumb_file_id = store_image_bytes(
            thumb_bytes,
            filename="garment_thumb.jpg",
            content_type="image/jpeg",
        )

        # Create Mongo garment doc
        item_num = _next_counter("garments")
        item_id = f"item_{item_num}"

        doc = {
            "_id": item_id,
            "itemId": item_id,
            "userId": user_id,
            "category": cat_enum.value,
            "type": typ,
            "colors": colors,
            "material": material,
            "pattern": pattern,
            "season": None,
            "fit": None,
            "extra": {
                "source": "gemini_crop",
                "styleRequestId": request_id,
                "box": box,
                "studioify": bool(studioify),
            },
            "imageFileId": str(image_file_id),
            "thumbFileId": str(thumb_file_id),
            "version": 1,
            "createdAt": now,
            "updatedAt": now,
            "deletedAt": None,
        }

        garments_collection().insert_one(doc)

        # Build urls
        image_url = f"{base}/wardrobe/media/{image_file_id}"
        thumb_url = f"{base}/wardrobe/media/{thumb_file_id}"

        # Upsert into VectorAI
        text = garment_doc_to_text(doc)
        payload = garment_doc_to_payload(doc)
        vec.upsert(item_id=item_id, payload=payload, text=text)

        created.append(
            WardrobeItem(
                itemId=item_id,
                userId=user_id,
                category=cat_enum,
                type=typ,
                colors=colors,
                material=material,
                pattern=pattern,
                season=None,
                fit=None,
                extra=doc.get("extra"),
                imageFileId=str(image_file_id),
                thumbFileId=str(thumb_file_id),
                imageUrl=image_url,
                thumbUrl=thumb_url,
                version=1,
                createdAt=now,
                updatedAt=now,
                deletedAt=None,
            )
        )

    return {
        "requestId": request_id,
        "storedPersonImage": bool(person_image_doc),
        "parsed": parsed,
        "createdItems": [c.model_dump() for c in created],
        "createdCount": len(created),
    }
