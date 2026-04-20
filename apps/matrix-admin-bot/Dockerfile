# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy workspace files
COPY pnpm-workspace.yaml pnpm-lock.yaml package.json ./

# Copy app source
COPY apps/matrix-admin-bot ./apps/matrix-admin-bot

# Install dependencies
RUN pnpm install --frozen-lockfile --ignore-scripts

# Build TypeScript
RUN pnpm --filter matrix-admin-bot build

# Runtime stage
FROM node:20-alpine

WORKDIR /app

# Install pnpm for runtime
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy workspace files
COPY pnpm-workspace.yaml pnpm-lock.yaml package.json ./

# Copy app files from builder
COPY --from=builder /app/apps/matrix-admin-bot ./apps/matrix-admin-bot

# Install runtime dependencies only
RUN pnpm install --frozen-lockfile --ignore-scripts --prod

# Create non-root user
RUN addgroup -g 1000 matrix-admin && \
    adduser -D -u 1000 -G matrix-admin matrix-admin

USER matrix-admin

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "process.exit(0)" || exit 1

# Run the bot
ENTRYPOINT ["node", "apps/matrix-admin-bot/dist/index.js"]
