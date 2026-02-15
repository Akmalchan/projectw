# SF Hacks Backend (Wardrobe: Crops → MongoDB + Actian VectorAI DB)

This backend starts at the stage where you already have **cropped garment images** (from your segmentation/cropping model).
It stores garments (image + metadata) in MongoDB and stores embeddings + lightweight payload in Actian VectorAI DB for similarity search.

## What you get
- **POST /wardrobe/ingest-crops**: upload cropped garment images + metadata
- **GET /wardrobe/garments/{id}**: garment metadata
- **GET /wardrobe/garments/{id}/image**: stream crop image from GridFS
- **GET /wardrobe/search**: search wardrobe by text (deterministic baseline embedding) + optional filters
- **GET /health**: health checks for API + Mongo + VectorAI

## Quick start (Docker)
1) Copy `.env.example` → `.env` and edit if needed.
2) Run:
```bash
docker compose up --build
```
3) Open docs:
- http://localhost:8000/docs

## Local dev (no docker)
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install ./wheels/actiancortex-0.1.0b1-py3-none-any.whl
uvicorn app.main:app --reload --port 8000
```

## Notes
- Images are stored in **MongoDB GridFS** in this starter (simple + consistent).
- Embeddings are computed with a **deterministic baseline** (image histogram → vector, text hash → vector) so it runs anywhere.
  You can replace `app/services/embeddings.py` later with CLIP/SigLIP without changing the rest of the system.
