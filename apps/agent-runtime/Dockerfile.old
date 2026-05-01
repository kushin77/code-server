FROM python:3.11-slim@sha256:6d85378d88a19cd4d76079817532d62232be95757cb45945a99fec8e8084b9c2

LABEL org.opencontainers.image.title="Agent Runtime"
LABEL org.opencontainers.image.description="Sandboxed agent execution with approval gating"
LABEL org.opencontainers.image.version="1.0"

# Create non-root user (UID 1005 for agent-runtime)
RUN useradd -u 1005 -m -s /sbin/nologin agent-runtime

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
USER agent-runtime

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8020/health || exit 1

# Start application
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8020"]
