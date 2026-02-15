# app/core/config.py
from __future__ import annotations

from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
        # optional: allow ENV vars like SFHACKS_MONGO_URI, etc.
        env_prefix="SFHACKS_",
    )

    api_host: str = "0.0.0.0"
    api_port: int = 8000
    log_level: str = "info"

    mongo_uri: str = "mongodb://localhost:27017"
    mongo_db: str = "sfhacks"
    store_person_image: bool = False

    # Actian VectorAI / Cortex
    cortex_server: str = "localhost:50051"
    vector_collection: str = "wardrobe_items"
    vector_dim: int = 256

    # CORS
    cors_origins: str = "*"

    def cors_origins_list(self) -> List[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

settings = Settings()
