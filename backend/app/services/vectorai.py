# app/services/vectorai.py
from __future__ import annotations

import hashlib
from typing import Any, Dict, List, Optional, Sequence, Tuple, Union

from app.core.config import settings
from app.services.embeddings import EmbeddingConfig, embed_text
from app.db.vector_client import ensure_collection_exists, get_vector_client


def _compact_join(parts: Sequence[str]) -> str:
    return " ".join([p.strip() for p in parts if p and p.strip()])


def _id_to_u64(item_id: Union[str, int]) -> int:
    """
    Actian Cortex expects a u64 (int) identifier. Your app uses string ids like 'item_123'.

    Strategy:
      1) if int -> use it (masked to u64)
      2) if 'item_<n>' -> parse <n> and use it
      3) else -> deterministic sha256(str)[:8] -> u64
    """
    if isinstance(item_id, int):
        return item_id & ((1 << 64) - 1)

    s = str(item_id)

    # Prefer numeric suffix for your counter ids
    if s.startswith("item_"):
        try:
            n = int(s.split("_", 1)[1])
            return n & ((1 << 64) - 1)
        except Exception:
            pass

    h = hashlib.sha256(s.encode("utf-8")).digest()[:8]
    return int.from_bytes(h, "big")


def garment_doc_to_text(d: Dict[str, Any]) -> str:
    """
    Turn a wardrobe Mongo doc into a stable text string for embeddings.
    Keep it deterministic: same doc -> same text.
    """
    category = str(d.get("category") or "").strip()
    typ = str(d.get("type") or "").strip()

    colors = d.get("colors") or []
    if isinstance(colors, str):
        colors = [colors]
    colors_txt = ", ".join([str(c).strip() for c in colors if str(c).strip()])

    material = str(d.get("material") or "").strip()
    pattern = str(d.get("pattern") or "").strip()
    season = str(d.get("season") or "").strip()
    fit = str(d.get("fit") or "").strip()

    extra = d.get("extra") or {}
    extra_bits: List[str] = []
    if isinstance(extra, dict):
        # only keep simple scalar-ish extra fields to avoid huge prompts
        for k, v in extra.items():
            if v is None:
                continue
            if isinstance(v, (str, int, float, bool)):
                vv = str(v).strip()
                if vv:
                    extra_bits.append(f"{k}:{vv}")

    return _compact_join(
        [
            f"category:{category}" if category else "",
            f"type:{typ}" if typ else "",
            f"colors:{colors_txt}" if colors_txt else "",
            f"material:{material}" if material else "",
            f"pattern:{pattern}" if pattern else "",
            f"season:{season}" if season else "",
            f"fit:{fit}" if fit else "",
            ("extra:" + " ".join(extra_bits)) if extra_bits else "",
        ]
    )


def garment_doc_to_payload(d: Dict[str, Any]) -> Dict[str, Any]:
    """
    Payload is what we can filter on in VectorAI search results.
    IMPORTANT: include userId always.
    """
    payload: Dict[str, Any] = {"userId": str(d.get("userId") or "").strip()}

    # useful filters / UI fields
    if d.get("category"):
        payload["category"] = d.get("category")
    if d.get("type"):
        payload["type"] = d.get("type")
    if d.get("colors") is not None:
        payload["colors"] = d.get("colors")
    if d.get("material") is not None:
        payload["material"] = d.get("material")
    if d.get("pattern") is not None:
        payload["pattern"] = d.get("pattern")
    if d.get("season") is not None:
        payload["season"] = d.get("season")
    if d.get("fit") is not None:
        payload["fit"] = d.get("fit")

    # stable ids to help the app (string Mongo id)
    payload["itemId"] = str(d.get("_id"))

    return payload


class VectorAI:
    """
    Thin wrapper over Actian VectorAI (Cortex).

    Conventions:
    - Mongo garment/item id is a string (e.g. "item_123")
    - Cortex requires a u64 integer id -> we convert internally
    - payload ALWAYS includes userId for filtering
    - payload SHOULD include itemId (string) for mapping back to Mongo
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

        # Ensure original string id is always present in payload
        payload = dict(payload or {})
        payload.setdefault("itemId", str(item_id))

        numeric_id = _id_to_u64(item_id)

        # Try "points=[...]" style first
        try:
            self.client.upsert(
                collection=self.collection,
                points=[{"id": numeric_id, "vector": vector, "payload": payload}],
            )
            return
        except TypeError:
            pass

        # Fallback: upsert(collection_name, id=..., vector=..., payload=...)
        self.client.upsert(self.collection, id=numeric_id, vector=vector, payload=payload)

    def batch_upsert(
        self,
        *,
        items: List[Tuple[str, List[float], Dict[str, Any]]],
    ) -> None:
        """
        items: [(mongo_item_id, vector, payload), ...]
        Converts ids to u64 for Cortex.
        """
        if not items:
            return

        # convert ids and enforce payload.itemId
        numeric_ids: List[int] = []
        vectors: List[List[float]] = []
        payloads: List[Dict[str, Any]] = []

        for mongo_id, vec, pl in items:
            pl = dict(pl or {})
            pl.setdefault("itemId", str(mongo_id))
            numeric_ids.append(_id_to_u64(mongo_id))
            vectors.append(vec)
            payloads.append(pl)

        # Preferred: batch_upsert(collection_name, ids=..., vectors=..., payloads=...)
        try:
            self.client.batch_upsert(self.collection, ids=numeric_ids, vectors=vectors, payloads=payloads)
            return
        except TypeError:
            pass
        except AttributeError:
            pass

        # Fallback: point-style upsert (single call with many points)
        try:
            points = [{"id": i, "vector": v, "payload": p} for i, v, p in zip(numeric_ids, vectors, payloads)]
            self.client.upsert(collection=self.collection, points=points)
            return
        except Exception:
            # Last resort: slow loop (still correct)
            for mongo_id, vec, pl in zip([it[0] for it in items], vectors, payloads):
                numeric_id = _id_to_u64(mongo_id)
                try:
                    self.client.upsert(
                        collection=self.collection,
                        points=[{"id": numeric_id, "vector": vec, "payload": pl}],
                    )
                except TypeError:
                    self.client.upsert(self.collection, id=numeric_id, vector=vec, payload=pl)
            return

    def delete(self, *, item_id: str) -> None:
        numeric_id = _id_to_u64(item_id)

        try:
            self.client.delete(collection=self.collection, ids=[numeric_id])
            return
        except TypeError:
            pass

        self.client.delete(self.collection, id=numeric_id)

    def search(
        self,
        *,
        user_id: str,
        q: str,
        limit: int = 10,
        category: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        vector = embed_text(q, self._cfg)

        flt: Dict[str, Any] = {"userId": user_id}
        if category and category != "all":
            flt["category"] = category

        # Try your current client shape
        try:
            return self.client.search(
                collection=self.collection,
                vector=vector,
                limit=limit,
                filter=flt,
            )
        except TypeError:
            pass

        # Fallback: search(collection_name, query=..., top_k=..., filter=..., with_payload=True)
        return self.client.search(self.collection, query=vector, top_k=limit, filter=flt, with_payload=True)


_vector_ai: Optional[VectorAI] = None


def get_vector_ai() -> VectorAI:
    global _vector_ai
    if _vector_ai is None:
        _vector_ai = VectorAI()
    return _vector_ai
