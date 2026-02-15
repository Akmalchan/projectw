# app/api/routes_wardrobe.py
from __future__ import annotations

from fastapi import APIRouter, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import Response

from app.core.security import validate_image_bytes
from app.models.schemas import WardrobeIngestResponse, WardrobeReindexResponse, WardrobeSyncResponse
from app.services.storage import read_image_bytes
from app.services.wardrobe import WardrobeService

router = APIRouter(prefix="/wardrobe", tags=["wardrobe"])
svc = WardrobeService()


def _base_url(req: Request) -> str:
    # Produces stable downloadable URLs for /wardrobe/media/{fileId}
    # (Request.base_url already contains scheme/host + trailing slash)
    return str(req.base_url).rstrip("/")


@router.post("/ingest", response_model=WardrobeIngestResponse)
async def ingest(
    request: Request,
    userId: str = Form(...),
    prompt: str | None = Form(None),
    file: UploadFile = File(...),
):
    user_id = (userId or "").strip()
    if not user_id:
        raise HTTPException(status_code=400, detail="userId is required")

    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty upload")

    # Validate image bytes (size, signature, content-type match)
    try:
        _ = validate_image_bytes(image_bytes, file.content_type)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    cursor, items = await svc.ingest(
        user_id=user_id,
        prompt=prompt,
        image_bytes=image_bytes,
        base_url=_base_url(request),
    )
    return WardrobeIngestResponse(cursor=cursor, items=items)


@router.get("/sync", response_model=WardrobeSyncResponse)
def sync(
    request: Request,
    userId: str = Query(...),
    cursor: str = Query("0"),
    limit: int = Query(200, ge=1, le=500),
):
    user_id = (userId or "").strip()
    if not user_id:
        raise HTTPException(status_code=400, detail="userId is required")

    next_cursor, ops = svc.sync(
        user_id=user_id,
        cursor=cursor,
        base_url=_base_url(request) + "/wardrobe",
        limit=limit,
    )
    return WardrobeSyncResponse(nextCursor=next_cursor, ops=ops)


@router.post("/reindex", response_model=WardrobeReindexResponse)
def reindex(
    userId: str = Form(...),
    includeDeleted: bool = Form(False),
    limit: int = Form(0),
):
    """
    Rebuild VectorAI vectors for this user's wardrobe from Mongo.
    """
    user_id = (userId or "").strip()
    if not user_id:
        raise HTTPException(status_code=400, detail="userId is required")

    stats = svc.reindex_vectorai(
        user_id=user_id,
        include_deleted=bool(includeDeleted),
        limit=int(limit),
    )
    return WardrobeReindexResponse(**stats)


@router.get("/media/{fileId}")
def media(fileId: str):
    """
    Stable, directly downloadable bytes endpoint.
    Frontend can GET this and save to local wardrobe/ folder.
    """
    try:
        data, content_type = read_image_bytes(fileId)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        raise HTTPException(status_code=404, detail="File not found")

    return Response(content=data, media_type=content_type or "application/octet-stream")
