# ---------- Builder: compile/install Python deps into wheels ----------
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /build

# Build tools only in builder (keeps final image slim)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc \
  && rm -rf /var/lib/apt/lists/*

# Copy requirements and build wheels for them
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip wheel --no-cache-dir --wheel-dir /build/wheels -r requirements.txt

# Copy your local wheels (Actian Cortex client etc.)
# IMPORTANT: ensure wheels/ exists in repo and NOT excluded by .dockerignore
COPY wheels/ /build/local_wheels/


# ---------- Runtime: minimal, production container ----------
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Minimal runtime deps (TLS). Add others only if you truly need them.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install dependencies from prebuilt wheels (fast + reliable)
COPY --from=builder /build/wheels /tmp/wheels
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir /tmp/wheels/* \
 && rm -rf /tmp/wheels

# Install your local .whl files (Actian Cortex client)
COPY --from=builder /build/local_wheels /tmp/local_wheels
RUN if [ -d /tmp/local_wheels ] && ls /tmp/local_wheels/*.whl >/dev/null 2>&1; then \
      pip install --no-cache-dir /tmp/local_wheels/*.whl; \
    fi \
 && rm -rf /tmp/local_wheels

# Copy app code last for best caching
COPY . .

# Render sets $PORT; must bind to 0.0.0.0
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
