# app/services/storage.py
from __future__ import annotations

import mimetypes
from typing import Tuple

from bson import ObjectId
from gridfs import GridOut

from app.db.mongo import get_gridfs


def store_image_bytes(data: bytes, *, filename: str, content_type: str | None) -> str:
    """
    Store bytes in Mongo GridFS. Returns file id as a string.
    Canonical name used by routes_style.py and routes_wardrobe.py.
    """
    fs = get_gridfs()

    guessed, _ = mimetypes.guess_type(filename or "")
    ct = content_type or guessed or "application/octet-stream"

    _id = fs.put(data, filename=filename or "upload", contentType=ct)
    return str(_id)


def read_image_bytes(file_id: str) -> Tuple[bytes, str]:
    """
    Read bytes from GridFS by string id. Returns (bytes, content_type).
    Canonical name used by routes_wardrobe.py.
    """
    fs = get_gridfs()
    try:
        oid = ObjectId(file_id)
    except Exception as e:
        raise ValueError(f"Invalid GridFS id: {file_id}") from e

    grid_out: GridOut = fs.get(oid)
    content_type = getattr(grid_out, "contentType", "application/octet-stream")
    return grid_out.read(), content_type
