# syntax=docker/dockerfile:1
# @file apps/copilot-engine/Dockerfile
# @module infrastructure/copilot-engine
# @description Immutable, production-grade container for the self-cleaning
#   multi-domain copilot engine. Base image is SHA256-pinned per GOV-002.
# @governance GOV-002: Immutable image, non-root user, health check, no secrets baked in

# ---------------------------------------------------------------------------
# Stage 1 — dependency install (cache-efficient)
# ---------------------------------------------------------------------------
FROM node:22-alpine@sha256:8ea2348b068a9544dae7317b4f3aafcdc032df1647bb7d768a05a5cad1a7683f AS deps

LABEL org.opencontainers.image.title="Copilot Engine"
LABEL org.opencontainers.image.description="Self-cleaning multi-domain copilot engine with semantic deduplication"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.vendor="code-server-enterprise"

WORKDIR /app

# Install production dependencies only
COPY package.json ./
RUN npm install --omit=dev --no-package-lock && npm cache clean --force

# ---------------------------------------------------------------------------
# Stage 2 — runtime image (minimal, non-root)
# ---------------------------------------------------------------------------
FROM node:22-alpine@sha256:8ea2348b068a9544dae7317b4f3aafcdc032df1647bb7d768a05a5cad1a7683f AS runtime

# Security: non-root user UID 1010 (dedicated for copilot-engine)
RUN addgroup -g 1010 copilot && adduser -u 1010 -G copilot -s /sbin/nologin -D copilot

WORKDIR /app

# Install curl for health check (smallest possible addition)
RUN apk add --no-cache curl

# Copy dependency tree from deps stage
COPY --from=deps --chown=1010:1010 /app/node_modules ./node_modules

# Copy application source
COPY --chown=1010:1010 package.json ./
COPY --chown=1010:1010 src/ ./src/

# Drop to non-root
USER copilot

EXPOSE 8030

# Health check — /health returns 200 when ANTHROPIC_API_KEY is present
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8030/health || exit 1

CMD ["node", "src/server.js"]
