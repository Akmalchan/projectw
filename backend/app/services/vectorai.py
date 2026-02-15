from __future__ import annotations
from typing import Any, Dict, List, Optional, Tuple

from app.core.config import settings
from app.db.vector_client import get_vector_client, ensure_collection_exists

from cortex.filters import Filter, Field

def upsert_garment_point(
    point_id: int,
    vector: List[float],
    payload: Dict[str, Any],
) -> None:
    ensure_collection_exists(dimension=len(vector))
    client = get_vector_client()
    client.upsert(settings.vector_collection, id=point_id, vector=vector, payload=payload)

def search_garments(
    query_vector: List[float],
    user_id: str,
    body_part: Optional[str] = None,
    garment_type: Optional[str] = None,
    top_k: int = 10,
) -> List[Tuple[int, float, Dict[str, Any] | None]]:
    """Returns list of (point_id, score, payload)"""
    ensure_collection_exists(dimension=len(query_vector))
    client = get_vector_client()

    f = Filter().must(Field("user_id").eq(user_id))
    if body_part:
        f = f.must(Field("body_part").eq(body_part))
    if garment_type:
        f = f.must(Field("garment_type").eq(garment_type))

    # Prefer search() with filter (supported in API); if server filter is limited, fall back to unfiltered + app-side filter
    try:
        results = client.search(
            settings.vector_collection,
            query_vector,
            top_k=top_k,
            filter=f,
            with_payload=True,
        )
        out = []
        for r in results:
            out.append((int(r.id), float(r.score), getattr(r, "payload", None)))
        return out
    except Exception:
        # Fallback: basic search then filter by payload locally
        results = client.search(settings.vector_collection, query_vector, top_k=top_k * 5, with_payload=True)
        out = []
        for r in results:
            payload = getattr(r, "payload", None) or {}
            if payload.get("user_id") != user_id:
                continue
            if body_part and payload.get("body_part") != body_part:
                continue
            if garment_type and payload.get("garment_type") != garment_type:
                continue
            out.append((int(r.id), float(r.score), payload))
            if len(out) >= top_k:
                break
        return out
