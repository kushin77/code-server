# Multi-stage Dockerfile for session-broker service
# Per-user/per-session isolation broker for code-server (#752)

# ════════════════════════════════════════════════════════════════════════════
# Stage 1: Build
# ════════════════════════════════════════════════════════════════════════════

FROM node:22-slim@sha256:db9a3a15e8e8e2adbaf1e1c3d93dfb04c2e294bdd027490addb2391b8e61cc6a AS builder

WORKDIR /workspace

# Copy workspace root configuration
COPY pnpm-workspace.yaml pnpm-lock.yaml .npmrc package.json ./

# Copy the session-broker package specifically  
COPY apps/session-broker ./apps/session-broker

# Install dependencies using pnpm with workspace context
RUN npm install -g pnpm@9.15.4 && \
    pnpm install --frozen-lockfile && \
    cd apps/session-broker && \
    pnpm run build

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

# Ensure docker group exists for /var/run/docker.sock access
RUN groupadd -g 999 docker 2>/dev/null || true

# Create non-root user for service
# UID 1000: standard non-root application user
# GID 999: docker group (matches host docker daemon group)
RUN useradd -m -u 1000 -g 999 session-broker 2>/dev/null || true && \
    usermod -aG docker session-broker 2>/dev/null || true

WORKDIR /app

# Copy built application, package.json, and workspace files
COPY --from=builder /workspace/apps/session-broker/dist ./dist
COPY --from=builder /workspace/apps/session-broker/package.json ./package.json
COPY --from=builder /workspace/pnpm-lock.yaml /pnpm-lock.yaml
COPY --from=builder /workspace/.npmrc /.npmrc

# Install production dependencies using pnpm
# We need pnpm because package.json has catalog: references
# Use --no-frozen-lockfile since we're in a clean runtime image
RUN npm install -g pnpm@9.15.4 && \
    pnpm install --prod --no-frozen-lockfile && \
    pnpm cache delete

# Set permissions using numeric IDs (more reliable than usernames)
RUN chown -R 1000:999 /app

# Switch to non-root user
USER 1000

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

# Start service
CMD ["node", "dist/index.js"]
