from __future__ import annotations
from fastapi import APIRouter, File, Form, UploadFile, HTTPException
from fastapi.responses import Response
from typing import Optional, List
from bson import ObjectId

from app.services.wardrobe import create_garment_from_crop, get_garment, search_wardrobe
from app.services.storage import read_image_bytes
from app.models.schemas import IngestResult, GarmentOut, SearchResponse, SearchHit

router = APIRouter(prefix="/wardrobe", tags=["wardrobe"])

@router.post("/ingest-crops", response_model=List[IngestResult])
async def ingest_crops(
    userId: str = Form(...),
    bodyPart: List[str] = Form(...),
    garmentType: List[str] = Form(...),
    files: List[UploadFile] = File(...),
    name: Optional[List[str]] = Form(None),
    description: Optional[List[str]] = Form(None),
    tags: Optional[List[str]] = Form(None),
):
    """Upload one or more cropped garment images.

Form-data fields:
- userId: string
- bodyPart: repeated (same count as files)
- garmentType: repeated (same count as files)
- files: repeated image files
- name/description: optional repeated, or omit
- tags: optional CSV or repeated; for starter we accept a single comma-separated string in the first element

Example (curl):
```bash
curl -X POST http://localhost:8000/wardrobe/ingest-crops \
  -F userId=u123 \
  -F bodyPart=top -F garmentType=jacket -F files=@crop1.png \
  -F bodyPart=bottom -F garmentType=jeans -F files=@crop2.png
```
"""
    if len(files) != len(bodyPart) or len(files) != len(garmentType):
        raise HTTPException(status_code=400, detail="files/bodyPart/garmentType counts must match")

    # Parse tags: allow tags=["a,b,c"] style
    parsed_tags: Optional[List[str]] = None
    if tags:
        if len(tags) == 1 and "," in tags[0]:
            parsed_tags = [t.strip() for t in tags[0].split(",") if t.strip()]
        else:
            parsed_tags = tags

    results: List[IngestResult] = []
    for i, f in enumerate(files):
        data = await f.read()
        n = name[i] if name and i < len(name) else None
        d = description[i] if description and i < len(description) else None

        garment_id, point_id = create_garment_from_crop(
            user_id=userId,
            crop_bytes=data,
            filename=f.filename or f"crop_{i}.bin",
            content_type=f.content_type or "application/octet-stream",
            body_part=bodyPart[i],
            garment_type=garmentType[i],
            name=n,
            description=d,
            tags=parsed_tags,
        )
        results.append(IngestResult(
            garmentId=garment_id,
            vectorPointId=point_id,
            bodyPart=bodyPart[i],
            garmentType=garmentType[i],
        ))

    return results


@router.get("/garments/{garment_id}", response_model=GarmentOut)
def get_garment_meta(garment_id: str):
    try:
        doc = get_garment(garment_id)
        return GarmentOut(
            id=doc["id"],
            userId=doc["userId"],
            bodyPart=doc["bodyPart"],
            garmentType=doc["garmentType"],
            name=doc.get("name"),
            description=doc.get("description"),
            tags=doc.get("tags", []),
            image=doc.get("image", {}),
            embedding=doc.get("embedding", {}),
            createdAt=doc.get("createdAt", ""),
        )
    except KeyError:
        raise HTTPException(status_code=404, detail="Garment not found")


@router.get("/garments/{garment_id}/image")
def get_garment_image(garment_id: str):
    try:
        doc = get_garment(garment_id)
        file_id = doc.get("image", {}).get("fileId")
        if not file_id:
            raise HTTPException(status_code=404, detail="No image for garment")
        data, content_type = read_image_bytes(ObjectId(file_id))
        return Response(content=data, media_type=content_type)
    except KeyError:
        raise HTTPException(status_code=404, detail="Garment not found")


@router.get("/search", response_model=SearchResponse)
def search(
    userId: str,
    q: str,
    bodyPart: Optional[str] = None,
    garmentType: Optional[str] = None,
    limit: int = 10,
):
    hits = search_wardrobe(
        user_id=userId,
        query=q,
        body_part=bodyPart,
        garment_type=garmentType,
        top_k=max(1, min(limit, 50)),
    )

    out_hits: List[SearchHit] = []
    for doc, score in hits:
        garment = GarmentOut(
            id=doc["id"],
            userId=doc["userId"],
            bodyPart=doc["bodyPart"],
            garmentType=doc["garmentType"],
            name=doc.get("name"),
            description=doc.get("description"),
            tags=doc.get("tags", []),
            image=doc.get("image", {}),
            embedding=doc.get("embedding", {}),
            createdAt=doc.get("createdAt", ""),
        )
        out_hits.append(SearchHit(garment=garment, score=score))

    return SearchResponse(query=q, hits=out_hits)
