# app/models/schemas.py
from __future__ import annotations

from enum import Enum
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field


class Category(str, Enum):
    # LOCKED ENUM (frontend contract)
    outerwear = "outerwear"
    top = "top"
    bottom = "bottom"
    shoes = "shoes"
    accessory = "accessory"


class WardrobeItem(BaseModel):
    # Stable server ID, used as primary key client-side
    itemId: str

    userId: str

    # Locked taxonomy
    category: Category

    # Freeform label (e.g. "denim jacket")
    type: str

    # Optional metadata from Gemini
    colors: List[str] = Field(default_factory=list)          # hex or simple color names
    material: Optional[str] = None
    pattern: Optional[str] = None
    season: Optional[str] = None
    fit: Optional[str] = None
    extra: Dict[str, Any] = Field(default_factory=dict)

    # Media: stable downloadable URLs OR fileIds (we provide both)
    imageFileId: str
    thumbFileId: str
    imageUrl: str
    thumbUrl: str

    # Sync fields
    version: int
    createdAt: str
    updatedAt: str
    deletedAt: Optional[str] = None


class WardrobeIngestResponse(BaseModel):
    cursor: str
    items: List[WardrobeItem]


class SyncUpsertOp(BaseModel):
    op: Literal["upsert"] = "upsert"
    itemId: str
    data: WardrobeItem


class SyncDeleteOp(BaseModel):
    op: Literal["delete"] = "delete"
    itemId: str
    deletedAt: str


SyncOp = SyncUpsertOp | SyncDeleteOp


class WardrobeSyncResponse(BaseModel):
    nextCursor: str
    ops: List[SyncOp]


# NEW: reindex response
class WardrobeReindexResponse(BaseModel):
    userId: str
    mongoItems: int
    upserted: int
    skipped: int
    includeDeleted: bool
