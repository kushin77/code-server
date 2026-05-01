FROM python:3.11-slim@sha256:ff71127c215572121f1991bacf17f39ec5fcfd2de1f1c01a595835495bb9adfc

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Non-root user
RUN useradd -u 1008 -m -s /sbin/nologin reputation \
    && chown -R reputation:reputation /app

USER reputation

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Expose port
EXPOSE 8000

# Run application
CMD ["python", "main.py"]
