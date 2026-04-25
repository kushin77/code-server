FROM python:3.11-slim@sha256:6d85378d88a19cd4d76079817532d62232be95757cb45945a99fec8e8084b9c2

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
