from __future__ import annotations

from pydantic import BaseModel, Field, constr
from typing import Optional, List, Literal

Category = Literal[
    "all", "tshirts", "pants", "outerwear", "shoes", "accessories", "unknown"
]

HexColor = constr(
    pattern=r"^#[0-9A-Fa-f]{6}$",
    strict=True,
)

SafeLabel = constr(
    min_length=1,
    max_length=80,
    strict=True,
)

ImageBase64 = constr(
    min_length=1,
    max_length=8_000_000,
    strict=True,
)

class WardrobeItemOut(BaseModel):
    id: Optional[str] = None
    label: SafeLabel = Field(..., description="Human-friendly label")
    category: Category = Field(..., description="Normalized category enum")
    dominantColorHex: HexColor = Field(..., description="Format: #RRGGBB")
    imageBase64: ImageBase64 = Field(..., description="Base64-encoded PNG/JPG bytes")

class WardrobeItemsResponse(BaseModel):
    items: List[WardrobeItemOut]

class WardrobeIngestItemResult(BaseModel):
    id: str = Field(..., description="Mongo item id")

class WardrobeIngestItemsResponse(BaseModel):
    items: List[WardrobeIngestItemResult]
