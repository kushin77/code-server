# Single-stage Dockerfile for session-broker service
# Per-user/per-session isolation broker for code-server (#752)

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
RUN useradd -m -u 1000 -g 999 session-broker 2>/dev/null || true && \
    usermod -aG docker session-broker 2>/dev/null || true

WORKDIR /workspace

# Copy entire workspace
COPY pnpm-workspace.yaml pnpm-lock.yaml .npmrc package.json ./
COPY apps/session-broker ./apps/session-broker

# Install dependencies and build
RUN npm install -g pnpm@9.15.4 && \
    pnpm install --frozen-lockfile && \
    cd apps/session-broker && \
    pnpm run build

# Setup final app directory
WORKDIR /app
RUN cp -r /workspace/apps/session-broker/dist . && \
    cp /workspace/apps/session-broker/package.json . && \
    mkdir -p node_modules && \
    # Copy pnpm's store
    cp -r /workspace/node_modules/.pnpm node_modules/ 2>/dev/null || true && \
    # Manually copy each dependency
    for dep in express cookie-parser dockerode pg uuid winston joi axios redis; do \
      [ -d "/workspace/node_modules/$dep" ] && cp -r "/workspace/node_modules/$dep" node_modules/; \
    done && \
    # Copy package.json file if exists
    [ -f "/workspace/node_modules/package.json" ] && cp "/workspace/node_modules/package.json" node_modules/ || true

# Fix permissions
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
