FROM python:3.11-slim@sha256:b1ad68e8e2e89c6a9db7b025e02e55b9a6e6556f088f1577f68e06d9e88e31d5

LABEL org.opencontainers.image.title="Paperclip Control Plane"
LABEL org.opencontainers.image.description="Human-in-the-loop approval gating for agent execution"
LABEL org.opencontainers.image.version="1.0"

# Create non-root user (UID 1002 for paperclip-cp)
RUN useradd -u 1002 -m -s /sbin/nologin paperclip

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Security: Drop unnecessary capabilities
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch to non-root user
USER paperclip

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8010/health || exit 1

EXPOSE 8010

# Start FastAPI service with uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8010"]
