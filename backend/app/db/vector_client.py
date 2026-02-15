from __future__ import annotations
from app.core.config import settings

from cortex import CortexClient, DistanceMetric

_client: CortexClient | None = None


def get_vector_client() -> CortexClient:
    global _client
    if _client is None:
        _client = CortexClient(settings.cortex_server)
        _client.connect()  # <-- IMPORTANT (context manager would do this)
    else:
        # Safety: if client exists but connection wasn't established / was closed
        # (CortexClient keeps internal async client; if it's None, reconnect)
        if getattr(_client, "_async_client", None) is None:
            _client.connect()

    return _client


def ensure_collection_exists(dimension: int) -> None:
    client = get_vector_client()
    name = settings.vector_collection

    if client.has_collection(name):
        info = client.describe_collection(name)
        if int(info.get("dimension", dimension)) != int(dimension):
            raise RuntimeError(
                f"Vector collection '{name}' exists but dimension is {info.get('dimension')}, expected {dimension}."
            )
        return

    client.create_collection(
        name=name,
        dimension=dimension,
        distance_metric=DistanceMetric.COSINE,
    )
