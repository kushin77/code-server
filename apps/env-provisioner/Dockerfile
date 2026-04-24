FROM python:3.11-slim

LABEL org.opencontainers.image.title="env-provisioner" \
      org.opencontainers.image.description="P3-1553 Environment provisioning service" \
      org.opencontainers.image.vendor="elevatediq" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.source="https://github.com/kushin77/code-server-enterprise" \
      org.opencontainers.image.documentation="https://github.com/kushin77/code-server-enterprise/blob/main/apps/env-provisioner/README.md"

# Non-root user
RUN groupadd -r envprov && useradd -r -g envprov envprov

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY provisioner.py .
COPY main.py .

# Create necessary directories
RUN mkdir -p /app/config /app/artifacts && chown -R envprov:envprov /app

# Switch to non-root user
USER envprov:envprov

# Expose port
EXPOSE 8050

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8050/health || exit 1

# Start FastAPI service
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8050"]
