# @file        apps/prompt-gateway/Dockerfile
# @module      ai/security
# @description Container image for Prompt Gateway MVP
# @owner       ai/security
# @status      production-ready

FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .
COPY scanner.py .
COPY opa_client.py .
COPY audit.py .

# Copy configuration
COPY ../../config/prompt-gateway.yaml /etc/prompt-gateway/config.yaml
COPY ../../config/model-registry.yaml /etc/prompt-gateway/models.yaml

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:3250/health', timeout=5).raise_for_status()"

# Security: non-root user
RUN useradd -m -u 1000 gateway && chown -R gateway:gateway /app
USER gateway

# Expose port
EXPOSE 3250

# Start application
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3250", "--log-level", "info"]
