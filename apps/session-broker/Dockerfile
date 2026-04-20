# Multi-stage Dockerfile for session-broker service
# Per-user/per-session isolation broker for code-server (#752)

# ════════════════════════════════════════════════════════════════════════════
# Stage 1: Build
# ════════════════════════════════════════════════════════════════════════════

FROM node:22-slim@sha256:db9a3a15e8e8e2adbaf1e1c3d93dfb04c2e294bdd027490addb2391b8e61cc6a AS builder

WORKDIR /workspace

# Copy workspace root configuration
COPY pnpm-workspace.yaml pnpm-lock.yaml .npmrc ./

# Copy the session-broker package specifically  
COPY apps/session-broker ./apps/session-broker

# Install dependencies using pnpm with workspace context
# pnpm needs to be at workspace root to resolve catalog entries
RUN npm install -g pnpm@9.15.4 && \
    cd apps/session-broker && \
    pnpm install && \
    pnpm run build && \
    pnpm prune --omit=dev

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
COPY --from=builder /workspace/apps/session-broker/dist ./dist
COPY --from=builder /workspace/apps/session-broker/node_modules ./node_modules
COPY --from=builder /workspace/apps/session-broker/package*.json ./

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
