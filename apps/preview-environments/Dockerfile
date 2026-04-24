# Dockerfile for preview-environments
# FastAPI service for managing ephemeral preview environments

FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies
COPY apps/preview-environments/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY apps/preview-environments/main.py .

# Create non-root user with docker access
RUN useradd --create-home --shell /bin/bash app \
    && groupadd -f docker \
    && usermod -aG docker app \
    && chown -R app:app /app
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8004/health || exit 1

# Start the service
CMD ["python", "main.py"]