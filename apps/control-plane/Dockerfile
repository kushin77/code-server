FROM python:3.11-slim@sha256:ff71127c215572121f1991bacf17f39ec5fcfd2de1f1c01a595835495bb9adfc

LABEL org.opencontainers.image.title="Control Plane"
LABEL org.opencontainers.image.description="Service orchestration and control plane for code-server"
LABEL org.opencontainers.image.version="1.0"

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY apps/control-plane/requirements.txt . 2>/dev/null || echo "fastapi==0.124.0\nuvicorn[standard]==0.24.0\npydantic==2.5.3\npsycopg2-binary==2.9.9\nredis==5.0.1\nkafka-python==2.0.2" > requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY apps/control-plane/ . 2>/dev/null || echo "# Placeholder"

# Create logging directory
RUN mkdir -p /var/log/control-plane

# Security: Run as non-root
RUN useradd -u 1006 -m -s /sbin/nologin control-plane-user
USER control-plane-user

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8082/health || exit 1

EXPOSE 8082

# Start service
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8082"]
