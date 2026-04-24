# Dockerfile for Presence Sidecar Service
# Real-time team presence tracking WebSocket service

FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY apps/presence-sidecar/package.json apps/presence-sidecar/package-lock.json ./

# Install dependencies
RUN npm ci --only=production

# Copy TypeScript source
COPY apps/presence-sidecar/src ./src
COPY apps/presence-sidecar/tsconfig.json ./

# Build TypeScript
RUN npm run build

# Runtime stage
FROM node:20-alpine

WORKDIR /app

# Install curl for health checks
RUN apk add --no-cache curl

# Copy built artifacts from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

# Create non-root user
RUN addgroup -g 1001 -S presence && \
    adduser -S presence -u 1001

USER presence

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:8089/health || exit 1

# Expose WebSocket and metrics ports
EXPOSE 8089

# Start service
CMD ["node", "dist/index.js"]
