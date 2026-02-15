FROM python:3.11-slim

WORKDIR /app

# System deps for Pillow
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy wheel and install Actian Cortex client
COPY wheels/actiancortex-0.1.0b1-py3-none-any.whl /app/wheels/
RUN pip install --no-cache-dir /app/wheels/actiancortex-0.1.0b1-py3-none-any.whl

COPY app /app/app

ENV PYTHONUNBUFFERED=1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
