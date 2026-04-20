# Multi-stage Dockerfile for session-broker service
# Per-user/per-session isolation broker for code-server (#752)

# ════════════════════════════════════════════════════════════════════════════
# Stage 1: Build
# ════════════════════════════════════════════════════════════════════════════

FROM node:22-slim@sha256:db9a3a15e8e8e2adbaf1e1c3d93dfb04c2e294bdd027490addb2391b8e61cc6a AS builder

WORKDIR /build

# Copy package files
COPY package*.json ./

# Install dependencies (including dev for TypeScript build)
RUN npm ci

# Copy source and compile
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

# ════════════════════════════════════════════════════════════════════════════
# Stage 2: Runtime
# ════════════════════════════════════════════════════════════════════════════

FROM node:22-slim@sha256:db9a3a15e8e8e2adbaf1e1c3d93dfb04c2e294bdd027490addb2391b8e61cc6a

LABEL maintainer="kushnir@bioenergystrategies.com"
LABEL description="Session broker for per-user/per-session code-server isolation"
LABEL version="1.0.0"

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for service and add to docker group for socket access
# UID 1000: standard non-root application user
# GID 999: docker group (matches host docker daemon group)
RUN useradd -m -u 1000 -g 999 session-broker 2>/dev/null || true
# Ensure docker group exists and add user to it for /var/run/docker.sock access
RUN groupadd -g 999 docker 2>/dev/null || true && \
    usermod -aG docker session-broker 2>/dev/null || true

WORKDIR /app

# Copy built application from builder
COPY --from=builder /build/dist ./dist
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/package*.json ./

# Set permissions
RUN chown -R session-broker:session-broker /app

# Switch to non-root user
USER session-broker

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

# Start service
CMD ["node", "dist/index.js"]
