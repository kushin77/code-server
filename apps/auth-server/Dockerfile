# ============================================================================
# Auth Server — Multi-stage Docker Build
# ============================================================================
# OAuth2 Authorization Server & API Gateway for Code Server Enterprise
#
# Build: docker build -t code-server/auth-server:latest .
# Run:   docker run -it -p 8001:8001 code-server/auth-server:latest
# ============================================================================

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

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

# Copy requirements and install
WORKDIR /build
COPY requirements.txt ./
RUN pip install --upgrade pip setuptools wheel \
    && pip install -r requirements.txt

# Copy application source
COPY src/ ./src/
COPY migrations/ ./migrations/

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ARG VERSION=dev
LABEL maintainer="code-server Team" \
      version="${VERSION}" \
      description="Auth Server — OAuth2 authorization server and API gateway"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    API_PORT=8001 \
    HOST=0.0.0.0 \
    ENVIRONMENT=production \
    LOG_LEVEL=INFO

# Install runtime dependencies (curl for health checks)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Non-root user — principle of least privilege
RUN useradd -m -u 1004 -s /bin/bash auth-server \
    && mkdir -p /app/src /app/migrations \
    && chown -R auth-server:auth-server /app

# Copy virtualenv from builder
COPY --from=builder --chown=auth-server:auth-server /opt/venv /opt/venv

# Copy application code from builder
COPY --from=builder --chown=auth-server:auth-server /build/src /app/src
COPY --from=builder --chown=auth-server:auth-server /build/migrations /app/migrations

WORKDIR /app
USER auth-server

# Liveness check: is the service running?
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:${API_PORT}/health || exit 1

EXPOSE ${API_PORT}

CMD ["python", "-m", "uvicorn", "src.oauth2_server:app", "--host", "0.0.0.0", "--port", "8001"]
