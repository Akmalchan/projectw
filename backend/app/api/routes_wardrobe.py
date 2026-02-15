from __future__ import annotations

import base64
import io
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile
from PIL import Image

from app.models.schemas import (
    WardrobeItemOut,
    WardrobeItemsResponse,
    WardrobeIngestItemResult,
    WardrobeIngestItemsResponse,
)
from app.core.security import validate_user_id, validate_image_bytes
from app.services.storage import read_image_bytes
from app.services.wardrobe import CreateItemInput, create_item, list_items, search_items

router = APIRouter(prefix="/wardrobe", tags=["wardrobe"])


def _bytes_to_base64_image(img_bytes: bytes, *, max_out_bytes: int = 800_000) -> str:
    if len(img_bytes) <= max_out_bytes:
        return base64.b64encode(img_bytes).decode("ascii")

    # bounded recompress
    with Image.open(io.BytesIO(img_bytes)) as im:
        im = im.convert("RGB")
        im.thumbnail((1024, 1024))
        out = io.BytesIO()
        im.save(out, format="JPEG", quality=85, optimize=True)
        data = out.getvalue()
        if len(data) > max_out_bytes:
            out = io.BytesIO()
            im.save(out, format="JPEG", quality=70, optimize=True)
            data = out.getvalue()
        return base64.b64encode(data).decode("ascii")


def _doc_to_item(doc: Dict[str, Any]) -> WardrobeItemOut:
    image = doc.get("image") or {}
    file_id = image.get("fileId")
    if not file_id:
        raise HTTPException(status_code=500, detail="Item missing image.fileId")

    img_bytes, _ = read_image_bytes(str(file_id))
    return WardrobeItemOut(
        id=str(doc.get("id") or ""),
        label=str(doc.get("label") or "item"),
        category=str(doc.get("category") or "unknown"),
        dominantColorHex=str(doc.get("dominantColorHex") or "#000000"),
        imageBase64=_bytes_to_base64_image(img_bytes),
    )


@router.post("/ingest-crops", response_model=WardrobeIngestItemsResponse)
async def ingest_crops(
    userId: str = Form(...),
    label: List[str] = Form(...),
    category: List[str] = Form(...),
    dominantColorHex: List[str] = Form(...),
    files: List[UploadFile] = File(...),
    geminiPrompt: Optional[str] = Form(None),
):
    try:
        user_id = validate_user_id(userId)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    if not (len(files) == len(label) == len(category) == len(dominantColorHex)):
        raise HTTPException(status_code=400, detail="files/label/category/dominantColorHex must have same count")

    if len(files) > 20:
        raise HTTPException(status_code=400, detail="Too many files (max 20).")

    created: List[WardrobeIngestItemResult] = []

    for i, f in enumerate(files):
        raw = await f.read()
        if not raw:
            raise HTTPException(status_code=400, detail="Empty file.")

        try:
            detected_mime = validate_image_bytes(raw, f.content_type)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))

        item_id = create_item(
            inp=CreateItemInput(
                user_id=user_id,
                label=label[i],
                category=category[i],
                dominant_color_hex=dominantColorHex[i],
                image_bytes=raw,
                filename=f.filename or "crop",
                content_type=detected_mime,
                gemini_prompt=geminiPrompt,
                gemini_raw=None,
            )
        )
        created.append(WardrobeIngestItemResult(id=item_id))

    return WardrobeIngestItemsResponse(items=created)


@router.get("/items", response_model=WardrobeItemsResponse)
def get_items(
    userId: str = Query(...),
    limit: int = Query(10, ge=1, le=50),
):
    try:
        user_id = validate_user_id(userId)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    docs = list_items(user_id=user_id, limit=limit)
    items: List[WardrobeItemOut] = []
    for d in docs:
        try:
            items.append(_doc_to_item(d))
        except Exception:
            continue

    return WardrobeItemsResponse(items=items)


@router.get("/search-items", response_model=WardrobeItemsResponse)
def search_items_endpoint(
    userId: str = Query(...),
    q: str = Query(..., min_length=1, max_length=80),
    category: Optional[str] = Query(None),
    limit: int = Query(10, ge=1, le=50),
):
    try:
        user_id = validate_user_id(userId)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    docs = search_items(user_id=user_id, q=q, limit=limit, category=category)
    items: List[WardrobeItemOut] = []
    for d in docs:
        try:
            items.append(_doc_to_item(d))
        except Exception:
            continue

    return WardrobeItemsResponse(items=items)
