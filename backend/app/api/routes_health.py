from __future__ import annotations

from fastapi import APIRouter

from app.db.mongo import get_client
from app.db.vector_client import get_vector_client

router = APIRouter()


@router.get("/health")
def health():
    # Mongo ping
    mongo_ok = False
    try:
        get_client().admin.command("ping")
        mongo_ok = True
    except Exception:
        mongo_ok = False

    # VectorAI health
    # Avoid CortexClient.health_check() because in your wheel it can fail with:
    # AttributeError: 'NoneType' object has no attribute 'health_check'
    cortex_ok = False
    cortex_version = None
    try:
        client = get_vector_client()
        from app.core.config import settings
        _ = client.has_collection(settings.vector_collection)
        cortex_ok = True
    except Exception as e:
        cortex_ok = False
        cortex_version = f"error: {type(e).__name__}: {e}"

    return {
        "ok": mongo_ok and cortex_ok,
        "mongo": mongo_ok,
        "vectorai": cortex_ok,
        "vectorai_version": cortex_version,
    }
