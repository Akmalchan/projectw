from __future__ import annotations
"""Embeddings service.

This starter uses **deterministic, lightweight** embeddings that work anywhere:
- image -> normalized grayscale histogram vector (fixed dim)
- text  -> deterministic pseudo-random vector based on hash(text)

Why: hackathon-friendly and avoids downloading large models.

Later you can swap these for CLIP/SigLIP/etc without changing DB or API layers.
"""

from dataclasses import dataclass
from typing import List
import numpy as np
from PIL import Image
import io
import hashlib

@dataclass(frozen=True)
class EmbeddingConfig:
    dim: int = 256

def _l2_normalize(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    if n == 0:
        return v
    return v / n

def embed_image_bytes(image_bytes: bytes, cfg: EmbeddingConfig) -> List[float]:
    # Convert to grayscale and compute histogram of `cfg.dim` bins
    img = Image.open(io.BytesIO(image_bytes)).convert("L")
    # Resize to reduce noise and keep stable
    img = img.resize((256, 256))
    arr = np.asarray(img, dtype=np.uint8).ravel()
    hist, _ = np.histogram(arr, bins=cfg.dim, range=(0, 256))
    vec = hist.astype(np.float32)
    vec = _l2_normalize(vec)
    return vec.tolist()

def embed_text(text: str, cfg: EmbeddingConfig) -> List[float]:
    # Deterministic pseudo-random vector based on sha256(text)
    h = hashlib.sha256(text.encode("utf-8")).digest()
    seed = int.from_bytes(h[:8], "little", signed=False)
    rng = np.random.default_rng(seed)
    vec = rng.standard_normal(cfg.dim).astype(np.float32)
    vec = _l2_normalize(vec)
    return vec.tolist()
