# app/services/wardrobe.py
from __future__ import annotations

import base64
import io
import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import httpx
from PIL import Image
from pymongo import ReturnDocument

from app.db.mongo import counters_collection, garments_collection
from app.models.schemas import Category, WardrobeItem
from app.services.storage import store_image_bytes
from app.services.vectorai import get_vector_ai


# -------------------------
# Utilities
# -------------------------

def _utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _make_thumb(image_bytes: bytes, *, max_size: int = 512) -> bytes:
    """Create a bounded JPEG thumbnail."""
    with Image.open(io.BytesIO(image_bytes)) as im:
        im = im.convert("RGB")
        im.thumbnail((max_size, max_size))
        out = io.BytesIO()
        im.save(out, format="JPEG", quality=85, optimize=True)
        return out.getvalue()


def _decode_image(image_bytes: bytes) -> Image.Image:
    """Decode bytes into a PIL Image (RGB)."""
    with Image.open(io.BytesIO(image_bytes)) as im:
        im = im.convert("RGB")
        return im.copy()


def _encode_jpeg(img: Image.Image, *, quality: int = 90) -> bytes:
    """Encode PIL image as JPEG bytes."""
    out = io.BytesIO()
    img.convert("RGB").save(out, format="JPEG", quality=quality, optimize=True)
    return out.getvalue()


def _next_counter(name: str) -> int:
    """Atomic, monotonic counter in Mongo for itemId / changeSeq."""
    doc = counters_collection().find_one_and_update(
        {"_id": name},
        {"$inc": {"seq": 1}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    return int((doc or {}).get("seq", 0))


def _new_item_id() -> str:
    n = _next_counter("wardrobe_item_id")
    return f"item_{n}"


def _new_change_seq() -> int:
    return _next_counter("wardrobe_change_seq")


def _coerce_category(raw: Any) -> str:
    v = str(raw or "").strip().lower()
    allowed = {c.value for c in Category}
    return v if v in allowed else "top"


def _compact_join(parts: List[str]) -> str:
    return " ".join([p.strip() for p in parts if p and p.strip()])


def _garment_doc_to_text(d: Dict[str, Any]) -> str:
    """
    Deterministic text representation used for embeddings.
    Keep stable formatting so updates are predictable.
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


def _garment_doc_to_payload(d: Dict[str, Any]) -> Dict[str, Any]:
    """
    Payload stored alongside vectors, used for filtering.
    MUST include userId for safe multi-tenant search.
    """
    payload: Dict[str, Any] = {"userId": str(d.get("userId") or "").strip()}
    payload["itemId"] = str(d.get("_id"))

    if d.get("category") is not None:
        payload["category"] = d.get("category")
    if d.get("type") is not None:
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

    return payload


# -------------------------
# Gemini stage (optional)
# -------------------------

class GeminiClient:
    """
    Minimal Gemini REST client for garment metadata extraction (JSON-only).

    Env:
      GEMINI_API_KEY
      GEMINI_MODEL (default: gemini-2.5-flash)
    """

    def __init__(self) -> None:
        self.api_key = os.getenv("GEMINI_API_KEY", "").strip()
        self.model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash").strip()

    def enabled(self) -> bool:
        return bool(self.api_key)

    async def describe_garment_json(self, jpeg_bytes: bytes, prompt: Optional[str]) -> Dict[str, Any]:
        """
        Ask Gemini for JSON-only garment metadata for a SINGLE garment image.

        Output schema (JSON):
          category: one of outerwear, top, bottom, shoes, accessory
          type: string
          optional: colors[], material, pattern, season, fit
        """
        if not self.enabled():
            return {}

        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
        params = {"key": self.api_key}

        sys = (
            "You are a fashion tagging service. "
            "Return JSON ONLY (no markdown, no backticks). "
            "category MUST be exactly one of: outerwear, top, bottom, shoes, accessory. "
            "Include: category, type. Optionally include: colors (array), material, pattern, season, fit."
        )

        user = (prompt or "").strip()
        user_text = (
            f"User prompt: {user}\n"
            "Task: Identify the garment in this image and output JSON with the schema described."
        )

        b64 = base64.b64encode(jpeg_bytes).decode("utf-8")

        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {"text": sys + "\n\n" + user_text},
                        {"inline_data": {"mime_type": "image/jpeg", "data": b64}},
                    ],
                }
            ],
            "generationConfig": {
                "temperature": 0.2,
                "response_mime_type": "application/json",
            },
        }

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(url, params=params, json=payload)
            resp.raise_for_status()
            data = resp.json()

        text = ""
        try:
            text = data["candidates"][0]["content"]["parts"][0].get("text", "") or ""
        except Exception:
            text = ""

        text = text.strip()
        if not text:
            return {}

        try:
            return json.loads(text)
        except Exception:
            return {}


# -------------------------
# WardrobeService
# -------------------------

class WardrobeService:
    def __init__(self) -> None:
        self._gemini = GeminiClient()

    async def ingest(
        self,
        *,
        user_id: str,
        prompt: Optional[str],
        image_bytes: bytes,
        base_url: str,
    ) -> Tuple[str, List[WardrobeItem]]:
        """
        Ingest a single garment image (NO YOLO).

        - optional Gemini JSON tagging
        - store image + thumb in GridFS
        - insert wardrobe doc in Mongo with changeSeq
        - return (cursor, [WardrobeItem])
        """
        full_img = _decode_image(image_bytes)
        jpeg = _encode_jpeg(full_img)

        meta: Dict[str, Any] = {}
        try:
            meta = await self._gemini.describe_garment_json(jpeg, prompt)
        except Exception:
            meta = {}

        cat = _coerce_category(meta.get("category"))
        type_str = str(meta.get("type") or "").strip() or "unknown garment"

        colors = meta.get("colors", [])
        if not isinstance(colors, list):
            colors = []
        colors = [str(c).strip() for c in colors if str(c).strip()]

        material = meta.get("material")
        pattern = meta.get("pattern")
        season = meta.get("season")
        fit = meta.get("fit")

        # Store media
        image_file_id = store_image_bytes(jpeg, filename="garment.jpg", content_type="image/jpeg")
        thumb_bytes = _make_thumb(jpeg, max_size=512)
        thumb_file_id = store_image_bytes(thumb_bytes, filename="garment_thumb.jpg", content_type="image/jpeg")

        item_id = _new_item_id()
        created = _utc_iso()
        updated = created
        version = 1
        change_seq = _new_change_seq()

        image_url = f"{base_url}/wardrobe/media/{image_file_id}"
        thumb_url = f"{base_url}/wardrobe/media/{thumb_file_id}"

        extra = {
            k: v
            for k, v in dict(meta).items()
            if k not in {"category", "type", "colors", "material", "pattern", "season", "fit"}
        }

        item = WardrobeItem(
            itemId=item_id,
            userId=user_id,
            category=Category(cat),
            type=type_str,
            colors=colors,
            material=str(material).strip() if material else None,
            pattern=str(pattern).strip() if pattern else None,
            season=str(season).strip() if season else None,
            fit=str(fit).strip() if fit else None,
            extra=extra,
            imageFileId=str(image_file_id),
            thumbFileId=str(thumb_file_id),
            imageUrl=image_url,
            thumbUrl=thumb_url,
            version=version,
            createdAt=created,
            updatedAt=updated,
            deletedAt=None,
        )

        garments_collection().insert_one(
            {
                "_id": item_id,
                "userId": user_id,
                "category": cat,
                "type": type_str,
                "colors": colors,
                "material": str(material).strip() if material else None,
                "pattern": str(pattern).strip() if pattern else None,
                "season": str(season).strip() if season else None,
                "fit": str(fit).strip() if fit else None,
                "extra": extra,
                "imageFileId": str(image_file_id),
                "thumbFileId": str(thumb_file_id),
                "version": version,
                "createdAt": created,
                "updatedAt": updated,
                "deletedAt": None,
                "changeSeq": change_seq,
            }
        )

        cursor = str(_new_change_seq())
        return cursor, [item]

    def sync(
        self,
        *,
        user_id: str,
        cursor: str,
        base_url: str,
        limit: int = 200,
    ) -> Tuple[str, List[Dict[str, Any]]]:
        """
        Cursor = last seen changeSeq (string int).
        Returns ops sorted by changeSeq asc.

        base_url here is typically ".../wardrobe" so media URLs become ".../wardrobe/media/{fileId}".
        """
        try:
            last = int(cursor) if cursor else 0
        except Exception:
            last = 0

        q = {"userId": user_id, "changeSeq": {"$gt": last}}
        docs = list(garments_collection().find(q).sort("changeSeq", 1).limit(limit))

        ops: List[Dict[str, Any]] = []
        next_cursor = last

        for d in docs:
            next_cursor = max(next_cursor, int(d.get("changeSeq", 0)))

            item_id = str(d.get("_id"))
            deleted_at = d.get("deletedAt")

            if deleted_at:
                ops.append({"op": "delete", "itemId": item_id, "deletedAt": str(deleted_at)})
                continue

            image_file_id = str(d.get("imageFileId"))
            thumb_file_id = str(d.get("thumbFileId"))

            cat = _coerce_category(d.get("category", "top"))

            item = WardrobeItem(
                itemId=item_id,
                userId=user_id,
                category=Category(cat),
                type=str(d.get("type") or "unknown garment"),
                colors=list(d.get("colors") or []),
                material=d.get("material"),
                pattern=d.get("pattern"),
                season=d.get("season"),
                fit=d.get("fit"),
                extra=dict(d.get("extra") or {}),
                imageFileId=image_file_id,
                thumbFileId=thumb_file_id,
                imageUrl=f"{base_url}/media/{image_file_id}",
                thumbUrl=f"{base_url}/media/{thumb_file_id}",
                version=int(d.get("version") or 1),
                createdAt=str(d.get("createdAt") or _utc_iso()),
                updatedAt=str(d.get("updatedAt") or _utc_iso()),
                deletedAt=None,
            )

            ops.append({"op": "upsert", "itemId": item_id, "data": item.model_dump()})

        return str(next_cursor if next_cursor else last), ops

    def reindex_vectorai(
        self,
        *,
        user_id: str,
        include_deleted: bool = False,
        limit: int = 0,
    ) -> Dict[str, Any]:
        """
        Rebuild VectorAI vectors from Mongo wardrobe_items for this user.

        Uses VectorAI.upsert() per item (simple + consistent).
        """
        q: Dict[str, Any] = {"userId": user_id}
        if not include_deleted:
            q["deletedAt"] = None

        cursor = garments_collection().find(q)
        if limit and limit > 0:
            cursor = cursor.limit(int(limit))

        vec = get_vector_ai()

        total = 0
        upserted = 0
        skipped = 0

        for d in cursor:
            total += 1
            item_id = str(d.get("_id") or "")
            if not item_id:
                skipped += 1
                continue

            text = _garment_doc_to_text(d)
            payload = _garment_doc_to_payload(d)

            vec.upsert(item_id=item_id, payload=payload, text=text)
            upserted += 1

        return {
            "userId": user_id,
            "mongoItems": total,
            "upserted": upserted,
            "skipped": skipped,
            "includeDeleted": include_deleted,
        }
