from __future__ import annotations
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.api.routes_health import router as health_router
from app.api.routes_wardrobe import router as wardrobe_router
from app.api.routes_style import router as style_router


app = FastAPI(title="SF Hacks Backend", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(wardrobe_router)
app.include_router(style_router)

