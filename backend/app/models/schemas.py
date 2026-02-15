from __future__ import annotations
from pydantic import BaseModel, Field
from typing import Optional, List, Literal, Dict, Any

class CropMeta(BaseModel):
    bodyPart: str = Field(..., description="e.g. top/bottom/shoes")
    garmentType: str = Field(..., description="e.g. jacket/tshirt/jeans")
    name: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[List[str]] = None

class IngestResult(BaseModel):
    garmentId: str
    vectorPointId: int
    bodyPart: str
    garmentType: str

class GarmentOut(BaseModel):
    id: str
    userId: str
    bodyPart: str
    garmentType: str
    name: Optional[str] = None
    description: Optional[str] = None
    tags: List[str] = []
    image: Dict[str, Any]
    embedding: Dict[str, Any]
    createdAt: str

class SearchHit(BaseModel):
    garment: GarmentOut
    score: float

class SearchResponse(BaseModel):
    query: str
    hits: List[SearchHit]
