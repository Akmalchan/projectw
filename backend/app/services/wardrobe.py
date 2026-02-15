from __future__ import annotations
from typing import Any, Dict, List, Optional, Tuple
from bson import ObjectId
from datetime import datetime, timezone

from app.core.config import settings
from app.db.mongo import garments_collection, counters_collection
from app.services.storage import store_image_bytes
from app.services.embeddings import EmbeddingConfig, embed_image_bytes, embed_text
from app.services.vectorai import upsert_garment_point, search_garments

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()

def _next_point_id(name: str = "vector_point_id") -> int:
    col = counters_collection()
    doc = col.find_one_and_update(
        {"_id": name},
        {"$inc": {"seq": 1}},
        upsert=True,
        return_document=True,
    )
    return int(doc["seq"])

def create_garment_from_crop(
    *,
    user_id: str,
    crop_bytes: bytes,
    filename: str,
    content_type: str,
    body_part: str,
    garment_type: str,
    name: Optional[str],
    description: Optional[str],
    tags: Optional[List[str]],
) -> Tuple[str, int]:
    # 1) store image in GridFS
    file_id = store_image_bytes(crop_bytes, filename=filename, content_type=content_type)

    # 2) compute image embedding
    cfg = EmbeddingConfig(dim=settings.vector_dim)
    vec = embed_image_bytes(crop_bytes, cfg)

    # 3) insert Mongo garment doc
    garments = garments_collection()
    doc = {
        "userId": user_id,
        "bodyPart": body_part,
        "garmentType": garment_type,
        "name": name,
        "description": description,
        "tags": tags or [],
        "image": {
            "storage": "gridfs",
            "fileId": file_id,
            "mimeType": content_type,
            "filename": filename,
        },
        "embedding": {
            "model": "histogram_v1",
            "dim": len(vec),
        },
        "createdAt": _now_iso(),
    }
    mongo_id = garments.insert_one(doc).inserted_id

    # 4) upsert to VectorAI DB
    point_id = _next_point_id()
    payload = {
        "user_id": user_id,
        "body_part": body_part,
        "garment_type": garment_type,
        "mongo_id": str(mongo_id),
    }
    upsert_garment_point(point_id=point_id, vector=vec, payload=payload)

    # 5) save vector point id back to Mongo
    garments.update_one({"_id": mongo_id}, {"$set": {"embedding.vectorAiPointId": point_id}})

    return str(mongo_id), point_id

def get_garment(mongo_id: str) -> Dict[str, Any]:
    garments = garments_collection()
    doc = garments.find_one({"_id": ObjectId(mongo_id)})
    if not doc:
        raise KeyError("Garment not found")
    doc["id"] = str(doc.pop("_id"))
    # stringify fileId
    if "image" in doc and "fileId" in doc["image"]:
        doc["image"]["fileId"] = str(doc["image"]["fileId"])
    return doc

def search_wardrobe(
    *,
    user_id: str,
    query: str,
    body_part: Optional[str],
    garment_type: Optional[str],
    top_k: int,
) -> List[Tuple[Dict[str, Any], float]]:
    cfg = EmbeddingConfig(dim=settings.vector_dim)
    qvec = embed_text(query, cfg)

    hits = search_garments(
        query_vector=qvec,
        user_id=user_id,
        body_part=body_part,
        garment_type=garment_type,
        top_k=top_k,
    )

    garments = garments_collection()
    out: List[Tuple[Dict[str, Any], float]] = []
    for _pid, score, payload in hits:
        if not payload:
            continue
        mongo_id = payload.get("mongo_id")
        if not mongo_id:
            continue
        doc = garments.find_one({"_id": ObjectId(mongo_id)})
        if not doc:
            continue
        doc["id"] = str(doc.pop("_id"))
        if "image" in doc and "fileId" in doc["image"]:
            doc["image"]["fileId"] = str(doc["image"]["fileId"])
        out.append((doc, float(score)))
    return out
