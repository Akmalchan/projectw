# app/db/vector_client.py
from __future__ import annotations

from cortex import CortexClient, DistanceMetric

from app.core.config import settings

_client: CortexClient | None = None


def get_vector_client() -> CortexClient:
    """
    Singleton Cortex client with a best-effort reconnect.
    """
    global _client
    if _client is None:
        _client = CortexClient(settings.cortex_server)
        _client.connect()
        return _client

    # Some Cortex client implementations keep an internal async client.
    # If it's missing, reconnect.
    if getattr(_client, "_async_client", None) is None:
        _client.connect()

    return _client


def ensure_collection_exists(dimension: int) -> None:
    """
    Idempotently ensure the configured collection exists with the given dimension.
    Fail fast if dimension mismatches (avoids silent bad search results).
    """
    client = get_vector_client()
    name = settings.vector_collection

    if client.has_collection(name):
        info = client.describe_collection(name)
        existing_dim = info.get("dimension")
        if existing_dim is not None and int(existing_dim) != int(dimension):
            raise RuntimeError(
                f"Vector collection '{name}' exists but dimension is {existing_dim}, expected {dimension}."
            )
        return

    client.create_collection(
        name=name,
        dimension=int(dimension),
        distance_metric=DistanceMetric.COSINE,
    )
