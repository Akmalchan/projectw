from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, File, Form, UploadFile, HTTPException

from app.db.mongo import get_db
from app.services.storage import store_image_bytes
from app.core.config import settings

router = APIRouter(prefix="/style", tags=["style"])


@router.post("/request")
async def create_style_request(
    userId: str = Form(...),
    prompt: str = Form(...),
    personImage: UploadFile = File(...),
):
    if not personImage.content_type or not personImage.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="personImage must be an image.")

    # Read bytes now (we will either store or keep in-memory in later steps)
    img_bytes = await personImage.read()
    if not img_bytes:
        raise HTTPException(status_code=400, detail="Empty image upload.")

    db = get_db()

    now = datetime.now(timezone.utc).isoformat()

    image_doc: Optional[dict] = None
    if settings.store_person_image:
        file_id = store_image_bytes(
            img_bytes,
            filename=personImage.filename or "person.png",
            content_type=personImage.content_type,
        )
        image_doc = {
            "storage": "gridfs",
            "fileId": str(file_id),
            "mimeType": personImage.content_type,
            "filename": personImage.filename or "person.png",
        }

    doc = {
        "userId": userId,
        "userPrompt": prompt,
        "status": "received",
        "personImage": image_doc,  # None if not storing
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
