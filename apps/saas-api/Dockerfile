# SaaS Management API Docker Image
# Phase 3 (#1674): User/Group/Org management backend

FROM node:20-alpine

LABEL org.opencontainers.image.title="saas-api" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.source="https://github.com/kushin77/code-server" \
      org.opencontainers.image.documentation="https://kushnir.cloud/docs/api"

WORKDIR /app

# Install dependencies
COPY apps/saas-api/package.json ./
RUN npm install --only=production && npm cache clean --force

# Copy application code
COPY apps/saas-api/src ./src

# Create non-root user for Alpine
RUN apk add --no-cache shadow && \
    useradd -m -u 1001 saas-api && \
    chown -R saas-api:saas-api /app

USER saas-api

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD node -e "require('http').get('http://localhost:5000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

CMD ["node", "src/index.js"]
