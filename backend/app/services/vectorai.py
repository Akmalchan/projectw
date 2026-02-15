# app/services/vectorai.py
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.core.config import settings
from app.services.embeddings import EmbeddingConfig, embed_text
from app.db.vector_client import ensure_collection_exists, get_vector_client


class VectorAI:
    """
    Thin wrapper over Actian VectorAI (Cortex).

    Conventions:
    - point id == Mongo garment/item id (string)
    - payload always includes userId for filtering
    - vectors are derived from deterministic text embeddings (swap later if needed)
    """

    def __init__(self) -> None:
        self.client = get_vector_client()
        self.collection = settings.vector_collection
        ensure_collection_exists(settings.vector_dim)
        self._cfg = EmbeddingConfig(dim=settings.vector_dim)

    def upsert(
        self,
        *,
        item_id: str,
        payload: Dict[str, Any],
        text: str,
    ) -> None:
        vector = embed_text(text, self._cfg)
        self.client.upsert(
            collection=self.collection,
            points=[{"id": item_id, "vector": vector, "payload": payload}],
        )

    def delete(self, *, item_id: str) -> None:
        self.client.delete(collection=self.collection, ids=[item_id])

    def search(
        self,
        *,
        user_id: str,
        q: str,
        limit: int = 10,
        category: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """
        Returns hits: [{id, score, payload}, ...]
        """
        vector = embed_text(q, self._cfg)

        flt: Dict[str, Any] = {"userId": user_id}
        if category and category != "all":
            flt["category"] = category

        return self.client.search(
            collection=self.collection,
            vector=vector,
            limit=limit,
            filter=flt,
        )


_vector_ai: Optional[VectorAI] = None


def get_vector_ai() -> VectorAI:
    global _vector_ai
    if _vector_ai is None:
        _vector_ai = VectorAI()
    return _vector_ai
