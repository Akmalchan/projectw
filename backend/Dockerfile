FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# System deps: pillow robustness + curl for debugging + build tools if wheels missing
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libjpeg62-turbo-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Actian Cortex wheel
COPY wheels/actiancortex-0.1.0b1-py3-none-any.whl /app/wheels/
RUN pip install --no-cache-dir /app/wheels/actiancortex-0.1.0b1-py3-none-any.whl

# Copy app code
COPY app /app/app

# Run as non-root
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
