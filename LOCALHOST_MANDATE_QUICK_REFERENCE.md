# NO LOCALHOST MANDATE - QUICK REFERENCE

## The Rule

🚫 **NEVER use `localhost` or `127.0.0.1` in any configuration, code, or documentation**

✅ **ALWAYS use domain DNS or container network names**

---

## Quick Setup

### Step 1: Set Environment Variables

```bash
# Copy .env.template
cp .env.template .env

# Set API URL (for Docker development)
echo 'VITE_API_URL=http://rbac-api:3001' >> .env
echo 'OLLAMA_ENDPOINT=http://ollama:11434' >> .env
```

### Step 2: Start Services

```bash
docker compose up -d
```

### Step 3: Access

- **IDE**: https://ide.kushnir.cloud (or your domain)
- **API**: http://rbac-api:3001 (internal; proxied through domain externally)
- **Ollama**: http://ollama:11434 (internal Docker network)

---

## Development vs Production

| Environment | API URL | Ollama URL |
|-------------|---------|-----------|
| **Development** | `http://rbac-api:3001` | `http://ollama:11434` |
| **Staging** | `https://api-staging.kushnir.cloud` | `https://ollama-staging.kushnir.cloud` |
| **Production** | `https://api.kushnir.cloud` | `https://ollama.kushnir.cloud` |

---

## Code Patterns

### ✅ Correct

```typescript
// Frontend
const endpoint = process.env.VITE_API_URL || 'http://rbac-api:3001'

// Backend
const endpoint = process.env.OLLAMA_ENDPOINT || 'http://ollama:11434'

// Docker
healthcheck:
  test: ["CMD", "curl", "-f", "http://code-server:8080/healthz"]
```

### ❌ Wrong

```typescript
// ❌ Never hardcode localhost
const endpoint = 'http://localhost:3001'

// ❌ Never hardcode IPs
const endpoint = 'http://127.0.0.1:3001'

// ❌ Never use localhost in health checks
test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
```

---

## Environment Variables

### Frontend (.env.local)
```bash
# Development (Docker)
VITE_API_URL=http://rbac-api:3001

# Production
VITE_API_URL=https://api.kushnir.cloud
```

### System
```bash
# Development
export OLLAMA_ENDPOINT=http://ollama:11434

# Production
export OLLAMA_ENDPOINT=https://ollama.kushnir.cloud
```

---

## Docker Container Network

All containers communicate via container names:

```
code-server:8080
ollama:11434
oauth2-proxy:4180
caddy:80
```

Example (inside Docker):
```bash
curl http://ollama:11434/api/tags
curl http://code-server:8080/healthz
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Cannot connect to API" | Check `VITE_API_URL` is set and exported |
| "localhost refused" error | Use container network name instead (e.g., `rbac-api`) |
| Health check failing | Verify using container network DNS in docker-compose |
| CORS errors | Ensure API URL matches frontend domain in production |

---

## Reference Documents

- **Full Mandate**: `NO_LOCALHOST_MANDATE.md`
- **Implementation Details**: `LOCALHOST_MANDATE_ENFORCEMENT.md`
- **Verification Report**: `LOCALHOST_MANDATE_VERIFICATION.md`
- **Architecture**: `frontend/ARCHITECTURE.md`

---

## Quick Checks

```bash
# ✅ Verify environment variable
echo $VITE_API_URL  # Should NOT contain 'localhost'

# ✅ Test health check
docker compose exec code-server curl http://code-server:8080/healthz

# ✅ Verify browser DevTools
# Network tab should show requests to:
# - http://rbac-api:3001 (development)
# - https://api.kushnir.cloud (production)
# NOT http://localhost:3001
```

---

**Remember**: If you see `localhost` in code or config, it's a mistake. Use domain DNS or container networks instead.

**Questions?** See `NO_LOCALHOST_MANDATE.md`
