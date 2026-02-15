# app/services/wardrobe.py
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from bson import ObjectId

from app.db.mongo import garments_collection
from app.services.storage import store_image_bytes
from app.services.vectorai import get_vector_ai


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class CreateItemInput:
    user_id: str
    label: str
    category: str  # all|tshirts|pants|outerwear|shoes|accessories|unknown
    dominant_color_hex: str  # #RRGGBB
    image_bytes: bytes
    filename: str
    content_type: str
    # provenance for judges / debugging
    gemini_prompt: Optional[str] = None
    gemini_raw: Optional[Dict[str, Any]] = None


def create_item(*, inp: CreateItemInput) -> str:
    """
    Create a wardrobe item:
    - store image in GridFS
    - store metadata in Mongo
    - upsert vector point in VectorAI
    Returns Mongo item id as string.
    """
    # 1) store image
    file_id = store_image_bytes(
        inp.image_bytes,
        filename=inp.filename,
        content_type=inp.content_type,
    )

    # 2) insert Mongo doc
    col = garments_collection()
    doc: Dict[str, Any] = {
        "userId": inp.user_id,
        "label": inp.label,
        "category": inp.category,
        "dominantColorHex": inp.dominant_color_hex,
        "image": {
            "storage": "gridfs",
            "fileId": file_id,
            "mimeType": inp.content_type,
            "filename": inp.filename,
        },
        "source": {
            "geminiPrompt": inp.gemini_prompt,
            "geminiRaw": inp.gemini_raw,
        },
        "createdAt": _now_iso(),
    }

    mongo_id = col.insert_one(doc).inserted_id
    item_id = str(mongo_id)

    # 3) upsert vector (use text fields only; image bytes already in GridFS)
    vector_ai = get_vector_ai()
    payload = {
        "userId": inp.user_id,
        "category": inp.category,
    }
    text = f"{inp.label} | category:{inp.category} | color:{inp.dominant_color_hex}"
    vector_ai.upsert(item_id=item_id, payload=payload, text=text)

    return item_id


def get_item(*, item_id: str) -> Dict[str, Any]:
    col = garments_collection()
    doc = col.find_one({"_id": ObjectId(item_id)})
    if not doc:
        raise KeyError("Item not found")
    doc["id"] = str(doc.pop("_id"))
    return doc


def list_items(*, user_id: str, limit: int = 20) -> List[Dict[str, Any]]:
    col = garments_collection()
    cur = col.find({"userId": user_id}).sort("createdAt", -1).limit(limit)
    out: List[Dict[str, Any]] = []
    for d in cur:
        d["id"] = str(d.pop("_id"))
        out.append(d)
    return out


def search_items(
    *,
    user_id: str,
    q: str,
    limit: int = 10,
    category: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """
    Vector-first search. Returns Mongo docs in ranked order.
    """
    vector_ai = get_vector_ai()
    hits = vector_ai.search(user_id=user_id, q=q, limit=limit, category=category)

    if not hits:
        return []

    # fetch docs in hit order
    col = garments_collection()
    docs: List[Dict[str, Any]] = []
    for h in hits:
        _id = h.get("id")
        if not _id:
            continue
        try:
            doc = col.find_one({"_id": ObjectId(_id), "userId": user_id})
            if not doc:
                continue
            doc["id"] = str(doc.pop("_id"))
            doc["_score"] = float(h.get("score", 0.0))
            docs.append(doc)
        except Exception:
            continue
    return docs
