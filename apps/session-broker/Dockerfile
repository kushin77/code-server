# Multi-stage Dockerfile for session-broker service
# Per-user/per-session isolation broker for code-server (#752)

# ════════════════════════════════════════════════════════════════════════════
# Stage 1: Build
# ════════════════════════════════════════════════════════════════════════════

FROM node:22-slim AS builder

WORKDIR /build

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && \
    npm run build

# ════════════════════════════════════════════════════════════════════════════
# Stage 2: Runtime
# ════════════════════════════════════════════════════════════════════════════

FROM node:22-slim

LABEL maintainer="kushnir@bioenergystrategies.com"
LABEL description="Session broker for per-user/per-session code-server isolation"
LABEL version="1.0.0"

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for service
RUN useradd -m -u 1000 session-broker

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
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Start service
CMD ["node", "dist/index.js"]
