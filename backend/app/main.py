# app/main.py
from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes_health import router as health_router
from app.api.routes_style import router as style_router
from app.api.routes_wardrobe import router as wardrobe_router

app = FastAPI(title="SFHACKS Backend", version="1.0.0")

# For hackathon/dev: permissive CORS (tighten later)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(style_router)
app.include_router(wardrobe_router)
