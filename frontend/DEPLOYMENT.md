# Frontend Deployment Guide

**Status**: Phase 3A - Development Ready  
**Version**: 1.0.0  
**Date**: 2026-04-12

---

## Overview

This guide covers deploying the Enterprise RBAC Frontend Dashboard across development, staging, and production environments.

## Table of Contents

1. [Development Environment](#development-environment)
2. [Build Process](#build-process)
3. [Docker Deployment](#docker-deployment)
4. [Production Deployment](#production-deployment)
5. [Environment Configuration](#environment-configuration)
6. [Troubleshooting](#troubleshooting)
7. [Monitoring & Logs](#monitoring--logs)

---

## Development Environment

### Prerequisites

- Node.js 18+ (LTS recommended)
- npm 9+ or yarn 3+
- RBAC API running (configured via VITE_API_URL environment variable)

### Setup

```bash
# Clone or navigate to frontend directory
cd frontend

# Set API URL (MANDATE: Never localhost)
# For Docker development:
export VITE_API_URL=http://rbac-api:3001

# Install dependencies
npm install

# Start development server
npm run dev
```

**What happens**:
- Vite dev server starts on `http://localhost:3000`
- Hot Module Replacement (HMR) enabled for instant updates
- API proxy configured for `/api` → `${VITE_API_URL}` (set via environment)
- TypeScript type checking in watch mode
- SCSS/CSS hot-reload

### Development Workflow

```bash
# Terminal 1: Backend API
cd services/rbac-api
npm run dev

# Terminal 2: Frontend
cd frontend
npm run dev

# Terminal 3: Optional - PostgreSQL
docker run -d -p 5432:5432 postgres:15

# Terminal 4: Watch tests
npm run test:watch
```

### Environment Variables

**MANDATE: Never use `localhost` in any environment. Use domain DNS or container networks.**

Create `.env.local`:

```env
# Development (Docker): Use container network name
VITE_API_URL=http://rbac-api:3001

# Staging/Production: Use your domain
# VITE_API_URL=https://api.kushnir.cloud
# OR if API is proxied through main domain:
# VITE_API_URL=https://ide.kushnir.cloud/api

VITE_APP_NAME=RBAC Dashboard
VITE_APP_VERSION=1.0.0
VITE_LOG_LEVEL=debug
```

---

## Build Process

### Production Build

```bash
# Generate optimized build
npm run build

# Output: dist/ folder with:
# - index.html (3KB)
# - js/main-xxxxx.js (80KB minified, gzipped)
# - js/vendors-xxxxx.js (40KB minified, gzipped)
# - css/style-xxxxx.css (12KB minified, gzipped)
```

### Build Optimization

```bash
# Analyze bundle size
npm run build -- --analyze

# Profile build performance
npm run build -- --profile

# Generate source maps for debugging
npm run build -- --sourcemap
```

### Build Artifacts

```
dist/
├── index.html              # Main entry point
├── assets/
│   ├── js/
│   │   ├── main-xxxxx.js   # Application code
│   │   └── vendors-xxxxx.js # Node modules
│   └── css/
│       └── style-xxxxx.css # Compiled Tailwind CSS
└── manifest.json           # Vite manifest (optional)
```

### Build Caching Strategy

```
Vite automatically identifies stable vs dynamic chunks:

Stable (long cache, versioned URLs):
- vendors-xxxxx.js (npm packages, rarely change)
- style-xxxxx.css (CSS, versioned)

Dynamic (short cache, auto-invalidated):
- main-xxxxx.js (Application code, frequently updated)
- index.html (No cache, always fresh)
```

---

## Docker Deployment

### Single-Stage Dockerfile (Development)

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]
```

### Multi-Stage Dockerfile (Production)

```dockerfile
# Stage 1: Build
FROM node:20-alpine as builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=dependencies
COPY . .
RUN npm run build
RUN npm prune --production

# Stage 2: Runtime (nginx)
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1
```

### Docker Build & Push

```bash
# Build image
docker build -t rbac-dashboard:1.0.0 .
docker build -t rbac-dashboard:latest .

# Tag for registry
docker tag rbac-dashboard:1.0.0 docker.io/kushnir/rbac-dashboard:1.0.0
docker tag rbac-dashboard:latest docker.io/kushnir/rbac-dashboard:latest

# Push to registry
docker login docker.io
docker push docker.io/kushnir/rbac-dashboard:1.0.0
docker push docker.io/kushnir/rbac-dashboard:latest
```

### Docker Compose Integration

```yaml
version: '3.9'

services:
  rbac-api:
    build: ./services/rbac-api
    ports:
      - "3001:3001"
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/rbac
    depends_on:
      - db

  rbac-frontend:
    build: ./frontend
    ports:
      - "3000:80"
    environment:
      VITE_API_URL: http://rbac-api:3001
    depends_on:
      - rbac-api

  db:
    image: postgres:15-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: rbac
      POSTGRES_USER: rbac_user
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "5432:5432"

volumes:
  postgres_data:
```

### Docker Run Commands

```bash
# Development with hot reload
docker-compose up -d

# Production with fixed image
docker run -d \
  --name rbac-dashboard \
  -p 80:80 \
  -e API_URL=https://api.example.com \
  rbac-dashboard:1.0.0

# With volume mounts for logs
docker run -d \
  --name rbac-dashboard \
  -p 80:80 \
  -v /var/log/rbac:/var/log \
  rbac-dashboard:1.0.0
```

---

## Production Deployment

### Pre-Deployment Checklist

- [ ] All tests passing (`npm run test`)
- [ ] No TypeScript errors (`npm run type-check`)
- [ ] Environment variables configured
- [ ] API endpoint verified
- [ ] HTTPS certificate ready
- [ ] Database migrated & healthy
- [ ] Monitoring configured (Datadog, New Relic, etc)
- [ ] Backup strategy in place
- [ ] Rollback procedure documented

### Deployment Strategies

#### 1. Blue-Green Deployment

```
Current (Blue):
  Load Balancer → Port 3000 (Blue)
                → Port 3001 (Blue API)

Deploy Green:
  1. Build & test new version on Port 3002
  2. Verify: Health checks, smoke tests
  3. Switch: Load Balancer → Port 3002
  4. Monitor: Error rates, performance
  5. Rollback: If issues detected

Rollback:
  Load Balancer → Port 3000 (Blue)
  Keep Green running for comparison
```

#### 2. Canary Deployment

```
Traffic Split:
  Load Balancer:
    ├── 95% → Version 1.0.0 (Stable)
    └── 5% → Version 1.0.1 (Canary)

Monitor Canary:
  - Error rates
  - Latency
  - User complaints

After 1 hour:
  100% → Version 1.0.1
  Remove 1.0.0
```

#### 3. Rolling Deployment

```
Instance Pool:
  1. api-1 (old version)
  2. api-2 (old version)
  3. api-3 (old version)

Update:
  1. Deploy → api-1 (new)
  2. Remove api-1 from LB, test
  3. Add api-1 back, move to api-2
  4. Repeat for api-3

Benefits:
  - Zero downtime
  - Quick rollback (revert api-1)
  - Gradual detection of issues
```

### AWS ECS Deployment

```hcl
# Terraform
resource "aws_ecs_service" "rbac_frontend" {
  name            = "rbac-dashboard"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rbac_frontend.arn
  desired_count   = 3
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rbac_frontend.arn
    container_name   = "rbac-dashboard"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.rbac]
}

resource "aws_ecs_task_definition" "rbac_frontend" {
  family                   = "rbac-dashboard"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "rbac-dashboard"
      image     = "docker.io/kushnir/rbac-dashboard:${var.app_version}"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "VITE_API_URL"
          value = "https://api.example.com"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.rbac_frontend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

resource "aws_cloudwatch_log_group" "rbac_frontend" {
  name              = "/ecs/rbac-dashboard"
  retention_in_days = 7
}
```

### Kubernetes Deployment

```yaml
# Helm Chart: helm/rbac-dashboard/Chart.yaml
apiVersion: v2
name: rbac-dashboard
description: Enterprise RBAC Frontend
version: 1.0.0
appVersion: 1.0.0

---
# helm/rbac-dashboard/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "rbac-dashboard.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount | default 3 }}
  selector:
    matchLabels:
      app: rbac-dashboard
  template:
    metadata:
      labels:
        app: rbac-dashboard
        version: {{ .Chart.AppVersion }}
    spec:
      containers:
      - name: rbac-dashboard
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
        ports:
        - name: http
          containerPort: 3000
          protocol: TCP
        env:
        - name: VITE_API_URL
          value: {{ .Values.api.url }}
        - name: VITE_APP_ENV
          value: {{ .Values.environment | default "production" }}
        livenessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi

---
# Service
apiVersion: v1
kind: Service
metadata:
  name: rbac-dashboard
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  selector:
    app: rbac-dashboard

---
# HPA (Horizontal Pod Autoscaler)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: rbac-dashboard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rbac-dashboard
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Helm Deploy

```bash
# Add Helm repo
helm repo add kushnir https://charts.example.com
helm repo update

# Install or upgrade
helm upgrade --install rbac-dashboard kushnir/rbac-dashboard \
  --namespace rbac \
  --values values-prod.yaml \
  --set image.tag=1.0.0 \
  --set api.url=https://api.example.com

# Rollback
helm rollback rbac-dashboard 1

# Check status
helm status rbac-dashboard
```

---

## Environment Configuration

### Environment Variables

```bash
# .env.production
VITE_API_URL=https://api.example.com
VITE_APP_NAME=RBAC Dashboard
VITE_APP_VERSION=1.0.0
VITE_LOG_LEVEL=error
VITE_SENTRY_DSN=https://xxxxx@sentry.io/xxxxx
```

### Build-Time Variables

```typescript
// vite.config.ts
export default {
  define: {
    'import.meta.env.APP_VERSION': JSON.stringify(process.env.APP_VERSION || '1.0.0'),
    // MANDATE: Never default to localhost
    'import.meta.env.API_URL': JSON.stringify(process.env.VITE_API_URL || (
      process.env.NODE_ENV === 'production'
        ? 'https://api.kushnir.cloud'
        : 'http://rbac-api:3001'  // Container network
    )),
  },
}
```

### Runtime Configuration

```typescript
// src/config.ts
export const config = {
  // MANDATE: Use domain DNS or container networks, NEVER localhost
  apiUrl: import.meta.env.VITE_API_URL || (
    typeof window !== 'undefined' 
      ? `${window.location.origin}/api`
      : 'http://rbac-api:3001'
  ),
  appVersion: import.meta.env.VITE_APP_VERSION || 'dev',
  environment: import.meta.env.MODE,
  logLevel: import.meta.env.VITE_LOG_LEVEL || 'info',
}
```

---

## Troubleshooting

### Issue: "Cannot GET /" in browser

**Cause**: Vite/nginx not configured for SPA

**Fix**:

```nginx
# nginx.conf
location / {
  try_files $uri $uri/ /index.html;
}
```

### Issue: API requests fail with CORS error

**Cause**: Missing CORS headers from backend

**Fix**:

```typescript
// Backend (Express.js)
app.use(cors({
  origin: ['http://localhost:3000', 'https://example.com'],
  credentials: true,
}))
```

### Issue: 401 Unauthorized on protected routes

**Cause**: JWT token expired or missing

**Fix**:

```typescript
// Refresh token flow
const response = await refreshToken()
localStorage.setItem('auth_token', response.token)
retryOriginalRequest()
```

### Issue: Slow load times in production

**Cause**: Large bundle, missing compression

**Fix**:

```nginx
# nginx.conf
gzip on;
gzip_types text/plain text/css application/json application/javascript;
gzip_min_length 1000;
```

### Issue: Out of memory on build

**Cause**: Node heap too small

**Fix**:

```bash
NODE_OPTIONS=--max-old-space-size=4096 npm run build
```

---

## Monitoring & Logs

### Application Monitoring

```typescript
// Sentry error tracking
import * as Sentry from "@sentry/react"

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,
  tracesSampleRate: 0.1,
})
```

### Performance Monitoring

```typescript
// Web Vitals
import { getCLS, getFID, getFCP, getLCP, getTTFB } from 'web-vitals'

getCLS(console.log)
getFID(console.log)
getFCP(console.log)
getLCP(console.log)
getTTFB(console.log)
```

### Logging

```bash
# Docker logs
docker logs --follow rbac-dashboard

# Kubernetes logs
kubectl logs -f deployment/rbac-dashboard

# Log aggregation (ELK Stack)
filebeat → Elasticsearch ← Kibana
```

### Health Checks

```bash
# Simple health endpoint
curl http://localhost:3000/

# API connectivity
curl http://localhost:3000/api/health

# Database connectivity
curl http://localhost:3000/api/health/db
```

---

## Rollback Procedure

### Docker Rollback

```bash
# List image versions
docker image ls | grep rbac-dashboard

# Run previous version
docker stop rbac-dashboard
docker run -d --name rbac-dashboard-rollback \
  -p 80:80 \
  rbac-dashboard:1.0.0

# Verify and promote
curl http://localhost/
# If healthy:
docker rm rbac-dashboard
docker rename rbac-dashboard-rollback rbac-dashboard
```

### Kubernetes Rollback

```bash
# Check rollout history
kubectl rollout history deployment/rbac-dashboard

# Rollback to previous
kubectl rollout undo deployment/rbac-dashboard

# Rollback to specific revision
kubectl rollout undo deployment/rbac-dashboard --to-revision=2

# Check status
kubectl rollout status deployment/rbac-dashboard
```

### Helm Rollback

```bash
# List releases
helm history rbac-dashboard

# Rollback to previous
helm rollback rbac-dashboard

# Rollback to specific revision
helm rollback rbac-dashboard 1
```

---

## Performance Checklist

- [ ] Gzip compression enabled
- [ ] CSS/JS minified
- [ ] Cache headers configured (index.html: no-cache, assets: max-age=31536000)
- [ ] Image optimization (WebP, responsive sizes)
- [ ] Code splitting enabled
- [ ] Lazy loading implemented
- [ ] Bundle size < 200KB gzipped
- [ ] Lighthouse score > 80

## Security Checklist

- [ ] HTTPS enforced (redirect HTTP → HTTPS)
- [ ] CSP headers configured
- [ ] X-Frame-Options: DENY
- [ ] X-Content-Type-Options: nosniff
- [ ] HSTS enabled (3600+ seconds)
- [ ] Secrets not in code
- [ ] API authentication verified
- [ ] CORS properly configured

---

**Next Steps**: Deploy to staging environment, run smoke tests, then promote to production.

**Questions?** Contact the DevOps team or refer to RUNBOOKS.md
