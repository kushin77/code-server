FROM python:3.11-slim@sha256:b1ad68e8e2e89c6a9db7b025e02e55b9a6e6556f088f1577f68e06d9e88e31d5

LABEL org.opencontainers.image.title="Execution Scheduler"
LABEL org.opencontainers.image.description="Intelligent task routing for local/CI/edge/cloud execution"
LABEL org.opencontainers.image.version="1.0"

# Create non-root user (UID 1003 for execution-scheduler)
RUN useradd -u 1003 -m -s /sbin/nologin scheduler

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Security: Drop unnecessary capabilities, install curl for health check
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch to non-root user
USER scheduler

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

# Start FastAPI service with uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
