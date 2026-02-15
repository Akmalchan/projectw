from pymongo import MongoClient
from gridfs import GridFS
from app.core.config import settings

_client: MongoClient | None = None

def get_client() -> MongoClient:
    global _client
    if _client is None:
        _client = MongoClient(settings.mongo_uri)
    return _client

def get_db():
    return get_client()[settings.mongo_db]

def get_gridfs() -> GridFS:
    return GridFS(get_db())

def garments_collection():
    return get_db()["garments"]

def counters_collection():
    return get_db()["counters"]
