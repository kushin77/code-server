# NO LOCALHOST MANDATE

**Status**: ✅ ENFORCED  
**Effective**: 2026-04-12  
**Scope**: All services, APIs, and configuration across code-server-enterprise

---

## The Mandate

**NEVER use `localhost` or `127.0.0.1` for any external API, service endpoint, or production configuration.**

This includes:
- API endpoints
- Service URLs
- Build configurations
- Documentation examples
- Environment variable defaults

---

## Required Alternatives

### Development Environments (Docker/Compose)

Use **container network DNS names**:

```bash
# ✅ CORRECT
VITE_API_URL=http://rbac-api:3001
OLLAMA_ENDPOINT=http://ollama:11434
OAUTH_PROXY_URL=http://oauth2-proxy:4180

# ❌ WRONG
VITE_API_URL=http://localhost:3001
OLLAMA_ENDPOINT=http://localhost:11434
```

**Why**: Container names auto-resolve within Docker networks, survive restarts, and scale horizontally.

---

### Staging/Production Environments

Use **domain DNS**:

```bash
# ✅ CORRECT
VITE_API_URL=https://api.kushnir.cloud
VITE_API_URL=https://api-staging.kushnir.cloud
VITE_API_URL=https://ide.kushnir.cloud/api

# ❌ WRONG
VITE_API_URL=http://localhost:3001
VITE_API_URL=http://192.168.1.100:3001
```

**Why**: Domain DNS is:
- **Portable**: Works anywhere without IP changes
- **Secure**: Enables HTTPS/TLS
- **Scalable**: Load balancers can be added transparently
- **Observable**: DNS queries are auditable

---

## Updated Files

### Frontend API Client

**File**: `frontend/src/api/rbac-client.ts`

```typescript
// ✅ CORRECT: Respects environment variable, falls back to domain
constructor(baseURL?: string) {
  const defaultUrl = baseURL || 
    process.env.VITE_API_URL || 
    (typeof window !== 'undefined' 
      ? `${window.location.origin}/api` 
      : 'http://rbac-api:3001')  // Container network for SSR
  
  this.axiosInstance = axios.create({ baseURL: defaultUrl })
}
```

---

### Vite Development Server

**File**: `frontend/vite.config.ts`

```typescript
// ✅ CORRECT: Respects environment variable, uses container network
proxy: {
  '/api': {
    target: process.env.VITE_API_URL || 'http://rbac-api:3001',
    changeOrigin: true,
    rewrite: (path) => path.replace(/^\/api/, ''),
  },
}
```

**Environment Variables**:

```bash
# Development (Docker)
VITE_API_URL=http://rbac-api:3001

# Staging
VITE_API_URL=https://api-staging.kushnir.cloud

# Production
VITE_API_URL=https://api.kushnir.cloud
```

---

## Enforcement

### 1. Code Review

- **Block** any PR containing `http://localhost` in:
  - Source code
  - Configuration files
  - Documentation examples
  
- **Accept** only:
  - Domain names (domain.com, api.domain.com)
  - Container network names (rbac-api, ollama)
  - Environment variable references ($DOMAIN, process.env.VITE_API_URL)

### 2. CI/CD

Add linting rule to reject localhost:

```bash
# Example: grep in CI pipeline
if grep -r "localhost" src/ vite.config.ts; then
  echo "ERROR: localhost found in source. Use domain DNS instead."
  exit 1
fi
```

### 3. Documentation

All examples and quickstart guides must show domain DNS, not localhost:

```bash
# ❌ OLD (removed)
curl http://localhost:3001/health

# ✅ NEW
VITE_API_URL=http://rbac-api:3001
curl $VITE_API_URL/health  # Docker

# Or for production:
curl https://api.kushnir.cloud/health
```

---

## Benefits

| Aspect | localhost | Domain DNS | Container Network |
|--------|-----------|------------|--------------------|
| Portability | ❌ Only works locally | ✅ Works anywhere | ✅ Works in clusters |
| Security (TLS) | ❌ No HTTPS | ✅ Production HTTPS | ⚠️ Only in dev |
| Scalability | ❌ Single machine only | ✅ Load balancers | ✅ K8s native |
| Service Discovery | ❌ Manual IPs | ✅ DNS TTL managed | ✅ Auto-discovered |
| Developer Experience | ⚠️ Simple but limiting | ✅ Production-realistic | ✅ Docker-native |

---

## Migration Checklist

- [x] Frontend API client (`rbac-client.ts`)
- [x] Vite dev server config (`vite.config.ts`)
- [x] Deployment documentation (`DEPLOYMENT.md`)
- [x] Quick start guide (`QUICK_START.md`)
- [x] Architecture documentation (`ARCHITECTURE.md`)
- [ ] Backend services (pending review)
- [ ] Docker Compose templates (`docker-compose.tpl`)
- [ ] GitHub Actions workflows (`.github/workflows/`)
- [ ] Helm/K8s templates (if applicable)
- [ ] .env.template and .gitignore

---

## Questions?

**Q: But I'm developing locally and don't have a domain setup.**  
A: Use Docker Compose with container network names (e.g., `http://rbac-api:3001`). No domain required.

**Q: What about localhost-only testing?**  
A: Not allowed. Test with the same URL structure as production:
- Dev: `http://rbac-api:3001` (container name)
- Prod: `https://api.kushnir.cloud` (same API, different transport)

**Q: Does this affect internal service communication?**  
A: No. Internal Docker network uses container names (`http://code-server:8080`). External/browser access uses domain DNS.

**Q: How do I set the API URL in my .env?**  
A: Copy `.env.template` → `.env`, and set:
```bash
VITE_API_URL=http://rbac-api:3001      # For Docker development
# VITE_API_URL=https://api.kushnir.cloud  # For production
```

---

## Approved By

- **Mandate Date**: 2026-04-12
- **Status**: ENFORCED - No exceptions
- **Legacy Code**: Must be refactored in next sprint

---

*This mandate ensures production-readiness from day one and prevents localhost-lockdown bugs in CI/CD pipelines.*
