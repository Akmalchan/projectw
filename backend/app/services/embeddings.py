from __future__ import annotations
"""Embeddings service.

Behavior:
- If GEMINI_API_KEY is set: use Gemini embedContent for text embeddings.
- Otherwise: use deterministic local fallback embeddings (hash-based).
"""

from dataclasses import dataclass
from typing import List
import numpy as np
from PIL import Image
import io
import hashlib
import os
import httpx


@dataclass(frozen=True)
class EmbeddingConfig:
    dim: int = 256


def _l2_normalize(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    if n == 0:
        return v
    return v / n


def embed_image_bytes(image_bytes: bytes, cfg: EmbeddingConfig) -> List[float]:
    # Keep local image embedding (still useful for future), unchanged.
    img = Image.open(io.BytesIO(image_bytes)).convert("L")
    img = img.resize((256, 256))
    arr = np.asarray(img, dtype=np.uint8).ravel()
    hist, _ = np.histogram(arr, bins=cfg.dim, range=(0, 256))
    vec = hist.astype(np.float32)
    vec = _l2_normalize(vec)
    return vec.tolist()


def _gemini_enabled() -> bool:
    return bool(os.getenv("GEMINI_API_KEY", "").strip())


def _gemini_embed_text(text: str, *, output_dimensionality: int) -> list[float]:
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    model = os.getenv("GEMINI_EMBED_MODEL", "gemini-embedding-001").strip() or "gemini-embedding-001"
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not set")

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:embedContent"
    params = {"key": api_key}
    payload = {
        "content": {"parts": [{"text": text}]},
        "output_dimensionality": int(output_dimensionality),  # <-- critical
    }

    with httpx.Client(timeout=30.0) as client:
        resp = client.post(url, params=params, json=payload)
        resp.raise_for_status()
        data = resp.json()

    values = data.get("embedding", {}).get("values")
    if not isinstance(values, list) or not values:
        raise RuntimeError("Gemini embedContent returned no embedding values")
    return [float(x) for x in values]



def embed_text(text: str, cfg: EmbeddingConfig) -> List[float]:
    """Embed text.

    IMPORTANT: If Gemini is enabled, cfg.dim must match the model's embedding dimension,
    otherwise VectorAI collection dimension and embedding dimension will disagree.
    """
    if _gemini_enabled():
        vec = np.asarray(_gemini_embed_text(text, output_dimensionality=cfg.dim), dtype=np.float32)
        if int(vec.shape[0]) != int(cfg.dim):
            raise RuntimeError(
                f"Gemini embedding dim is {int(vec.shape[0])}, but SFHACKS_VECTOR_DIM is {int(cfg.dim)}. "
                "Set SFHACKS_VECTOR_DIM to match GEMINI_EMBED_MODEL and recreate the VectorAI collection."
            )
        vec = _l2_normalize(vec)
        return vec.tolist()

    # Local deterministic fallback
    h = hashlib.sha256(text.encode("utf-8")).digest()
    seed = int.from_bytes(h[:8], "little", signed=False)
    rng = np.random.default_rng(seed)
    vec = rng.standard_normal(cfg.dim).astype(np.float32)
    vec = _l2_normalize(vec)
    return vec.tolist()

