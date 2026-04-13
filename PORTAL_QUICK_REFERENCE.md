# Multi-Portal Deployment Quick Reference

## 🚀 Quick Start (5 Minutes)

### 1. Configure
```bash
cp .env.example .env
# Edit .env with your values
```

### 2. Build
```bash
docker-compose build rbac-api caddy code-server
```

### 3. Deploy
```bash
docker-compose up -d
```

### 4. Verify
```bash
curl https://{DOMAIN}/auth/.well-known/openid-configuration
```

## 📋 Service Status Check

```bash
# View all services
docker-compose ps

# Follow logs for specific service
docker-compose logs -f rbac-api
docker-compose logs -f caddy
docker-compose logs -f appsmith
docker-compose logs -f backstage

# Check service health
docker-compose exec rbac-api curl http://rbac-api:3001/healthz
docker-compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

## 🔐 OAuth Testing

### Test 1: Discovery Endpoint
```bash
# Get OAuth2/OIDC configuration
curl https://{DOMAIN}/auth/.well-known/openid-configuration | jq .
```

Expected keys: `issuer`, `authorization_endpoint`, `token_endpoint`, `userinfo_endpoint`

### Test 2: Login
```bash
# Direct API login
curl -X POST https://{DOMAIN}/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "password123",
    "org_slug": "acme-corp"
  }' | jq .
```

Expected: `access_token`, `refresh_token`, `mfa_required`

### Test 3: Token Validation
```bash
# Get token first (replace ACCESS_TOKEN from Test 2)
curl https://{DOMAIN}/auth/userinfo \
  -H "Authorization: Bearer ACCESS_TOKEN" | jq .
```

Expected: `{"sub": "...", "email": "admin@example.com", "roles": ["admin"]}`

## 🌐 Portal Access

| Portal | URL | Purpose | Auth |
|--------|-----|---------|------|
| IDE | `https://{DOMAIN}` | Code-server | Google OAuth |
| Admin | `https://{DOMAIN}/appsmith` | Low-code | JWT from RBAC API |
| Developer | `https://{DOMAIN}/backstage` | Catalog | JWT from RBAC API |
| API | `https://{DOMAIN}/api` | REST endpoints | JWT Bearer |

## 📁 Key Files

| File | Purpose |
|------|---------|
| `backend/src/index.ts` | Main RBAC API server |
| `backend/src/oauth.ts` | OAuth2/OIDC endpoints |
| `docker-compose.yml` | Service orchestration |
| `Caddyfile` | Reverse proxy routing |
| `appsmith/appsmith.yaml` | Admin portal config |
| `backstage/app-config.yaml` | Developer portal config |
| `PORTAL_DEPLOYMENT.md` | Full deployment guide |

## 🔧 Common Operations

### Reset Everything
```bash
# Stop services
docker-compose down -v

# Remove volumes (PostgreSQL data)
docker volume rm coder-data ollama-data caddy-data caddy-config appsmith-stacks

# Start fresh
docker-compose up -d
```

### View Service Logs
```bash
# Real-time logs
docker-compose logs -f rbac-api

# Last 100 lines
docker-compose logs --tail=100 rbac-api

# Specific timestamp
docker-compose logs rbac-api --since 2024-01-01T00:00:00
```

### Access Database
```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U postgres

# List databases
\l

# Connect to appsmith database
\c appsmith

# List tables
\dt
```

### Rebuild Service
```bash
# Rebuild specific image
docker-compose build --no-cache rbac-api

# Deploy updated service
docker-compose up -d rbac-api
```

## ⚠️ Troubleshooting

### OAuth routes not found (404 on /auth/*)
```bash
# Check oauth.ts is imported
grep "import oauthRoutes" backend/src/index.ts

# Check routes are registered
grep "app.use.*oauth" backend/src/index.ts

# Rebuild container
docker-compose build --no-cache rbac-api
docker-compose up -d rbac-api
```

### Caddy not routing to backend
```bash
# Validate Caddyfile
docker-compose exec caddy caddy validate --config /etc/caddy/Caddyfile

# Check routing rules
docker-compose exec caddy cat /etc/caddy/Caddyfile

# View Caddy logs
docker-compose logs caddy
```

### PostgreSQL connection failed
```bash
# Check database exists
docker-compose exec postgres psql -U postgres -l

# Check initialization script ran
docker-compose logs postgres | grep "init-postgres"

# Reinitialize (removes data)
docker volume rm code-server-enterprise_appsmith-stacks
docker-compose up postgres -d
```

### Service won't start
```bash
# Check port conflicts
lsof -i :3001  # RBAC API
lsof -i :80    # HTTP
lsof -i :443   # HTTPS

# Check disk space
df -h

# Check Docker logs
docker logs rbac-api
docker logs caddy
docker logs appsmith
docker logs backstage

# Increase Docker memory if needed
# (Docker Desktop → Settings → Resources)
```

## 🧪 Integration Testing

### Test Appsmith Authentication
```bash
# 1. Login to RBAC API and get token
TOKEN=$(curl -s -X POST https://{DOMAIN}/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "password123",
    "org_slug": "acme-corp"
  }' | jq -r '.access_token')

echo $TOKEN

# 2. Access Appsmith
# https://{DOMAIN}/appsmith
# Enter JWT token when prompted
```

### Test Backstage Catalog
```bash
# 1. Check catalog is loaded
curl https://{DOMAIN}/backstage/api/catalog/entities | jq .

# 2. View in UI
# https://{DOMAIN}/backstage/catalog
```

### Test code-server IDE
```bash
# 1. Navigate to https://{DOMAIN}
# 2. Sign in with Google OAuth
# 3. Verify Copilot extension is active
# 4. Check terminal access works
```

## 📊 Monitoring

### Check All Services Healthy
```bash
# View status
docker-compose ps

# All services should show "healthy" or "running"
```

### Monitor Resource Usage
```bash
# Real-time stats
docker stats

# Specific service
docker stats rbac-api caddy postgres appsmith backstage
```

### Check Component Health
```bash
# RBAC API
curl -s http://rbac-api:3001/healthz

# Caddy (shows active connections)
curl -s http://caddy:2019/config

# PostgreSQL
docker-compose exec postgres pg_isready
```

## 🔐 Production Checklist

Before deploying to production:

- [ ] Change JWT_SECRET (generate new)
- [ ] Update GOOGLE_CLIENT_ID/SECRET
- [ ] Update DOMAIN to production domain
- [ ] Change CODE_SERVER_PASSWORD
- [ ] Configure GITHUB_TOKEN for Backstage
- [ ] Enable MFA for admin accounts
- [ ] Update SSL certificates (Let's Encrypt auto-renewal)
- [ ] Setup database backups
- [ ] Configure log aggregation
- [ ] Enable audit logging (ENABLE_AUDIT_LOGGING=true)
- [ ] Test failover procedures
- [ ] Load test under expected traffic
- [ ] Security audit of OAuth endpoints

## 📞 Support

| Issue | Resolution |
|-------|-----------|
| OAuth endpoints 404 | Rebuild rbac-api: `docker-compose build --no-cache rbac-api` |
| Database not initialized | Check logs: `docker-compose logs postgres` |
| TLS certificate issues | Check Caddy logs: `docker-compose logs caddy` |
| Service memory issues | Increase Docker memory limits in docker-compose.yml |
| Port already in use | Change port mappings or kill conflicting process |

## 📚 Documentation

For detailed information, see:
- **Deployment Guide**: `PORTAL_DEPLOYMENT.md`
- **Integration Summary**: `INTEGRATION_SUMMARY.md`
- **Architecture**: `ARCHITECTURE.md`
- **README**: `README.md`

---

**Status**: ✅ Ready to Deploy
**Version**: 1.0
**Last Updated**: 2024-01-27
