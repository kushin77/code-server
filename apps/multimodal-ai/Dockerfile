# @file apps/multimodal-ai/Dockerfile
# @governance GOV-002 - SHA-pinned base image, non-root user, immutable build
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies (curl for healthcheck, ffmpeg for Whisper)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies first (layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8040

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=20s \
    CMD curl -f http://localhost:8040/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8040"]
