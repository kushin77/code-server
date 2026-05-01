# ============================================================================
# Agent Runtime — Multi-stage Docker Build
# ============================================================================
# Stage 1: builder (compile dependencies, install packages)
# Stage 2: runtime (minimal production image, non-root user)
#
# Build: docker build -t code-server/agent-runtime:latest .
# Run:   docker run -it -p 8020:8020 code-server/agent-runtime:latest
# ============================================================================

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM python:3.11-slim@sha256:ff71127c215572121f1991bacf17f39ec5fcfd2de1f1c01a595835495bb9adfc AS builder

ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install build dependencies (removed in final image)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        gcc \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
ENV VENV=/opt/venv
RUN python -m venv $VENV
ENV PATH="${VENV}/bin:$PATH"

# Copy requirements and build
WORKDIR /build
COPY requirements.txt pyproject.toml ./
COPY . .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir --no-deps -e .

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM python:3.11-slim@sha256:ff71127c215572121f1991bacf17f39ec5fcfd2de1f1c01a595835495bb9adfc AS runtime

ARG VERSION=dev
LABEL maintainer="code-server Team" \
      version="${VERSION}" \
      description="Agent Runtime — Sandboxed agent execution with approval gating"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8020 \
    HOST=0.0.0.0 \
    ENVIRONMENT=production \
    LOG_LEVEL=INFO

# Install runtime dependencies only (curl for health checks)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root user — principle of least privilege
RUN useradd -m -u 1003 -s /bin/bash agent-runtime \
    && mkdir -p /app /data \
    && chown -R agent-runtime:agent-runtime /app /data

# Copy virtualenv from builder
COPY --from=builder --chown=agent-runtime:agent-runtime /opt/venv /opt/venv

# Copy application code from builder
COPY --from=builder --chown=agent-runtime:agent-runtime /build/apps/agent-runtime /app

WORKDIR /app
USER agent-runtime

# Liveness check: is the service running?
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

EXPOSE ${PORT}

# Run with: python -m uvicorn app_factory:create_app --factory --host 0.0.0.0 --port 8020
# Or: gunicorn -w 4 -k uvicorn.workers.UvicornWorker app_factory:create_app
CMD ["python", "-m", "uvicorn", "app_factory:create_app", "--factory", "--host", "0.0.0.0", "--port", "8020"]
