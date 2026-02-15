from __future__ import annotations
from typing import Tuple
from bson import ObjectId
from app.db.mongo import get_gridfs

def store_image_bytes(data: bytes, filename: str, content_type: str) -> ObjectId:
    fs = get_gridfs()
    return fs.put(data, filename=filename, contentType=content_type)

def read_image_bytes(file_id: ObjectId) -> Tuple[bytes, str]:
    fs = get_gridfs()
    f = fs.get(file_id)
    content_type = getattr(f, "contentType", "application/octet-stream")
    return f.read(), content_type
