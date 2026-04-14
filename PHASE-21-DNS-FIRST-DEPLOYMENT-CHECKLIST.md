# PHASE 21+ DEPLOYMENT CHECKLIST: DNS-First Architecture

## ✅ COMPLETED: Configuration Files

All configuration files have been updated to support DNS-first, environment-driven access:

### 1. **Caddyfile** — DNS-First Reverse Proxy
- ✅ Uses `{$DOMAIN}` environment variable placeholder
- ✅ All service routes reference container DNS (e.g., `code-server:8080`)
- ✅ No hardcoded IPs or localhost
- ✅ Conditional HTTPS: auto_https off for nip.io, on for kushnir.cloud
- ✅ Location: `/Caddyfile` (mounted in docker-compose)

### 2. **config/caddy/Caddyfile** — Terraform Template
- ✅ Updated to match main Caddyfile
- ✅ Used by Terraform for code generation
- ✅ Location: `config/caddy/Caddyfile` (for terraform generation)

### 3. **docker-compose.tpl** — Template for docker-compose.yml
- ✅ Added DOMAIN environment variable: `${external_domain}`
- ✅ Added ACME_EMAIL environment variable: `${acme_email}`
- ✅ Mounts updated Caddyfile correctly
- ✅ All services on enterprise network (Docker DNS enabled)

### 4. **docker-compose.yml** — Current Deployment
- ✅ DOMAIN environment variable (uses default 192.168.168.31.nip.io)
- ✅ ACME_EMAIL environment variable (uses default ops@kushnir.cloud)
- ✅ Caddy service updated with new environment variables

### 5. **variables.tf** — Terraform Configuration
- ✅ New variable: `external_domain` (default: 192.168.168.31.nip.io)
- ✅ New variable: `acme_email` (default: ops@kushnir.cloud)
- ✅ Ready for production override via terraform.tfvars

### 6. **main.tf** — Terraform Locals
- ✅ `docker_compose_vars` includes `external_domain` variable
- ✅ `docker_compose_vars` includes `acme_email` variable
- ✅ Variables passed to docker-compose template correctly

### 7. **code-server-config.yaml** — IDE Configuration
- ✅ Updated `proxy-domain` list with wildcard patterns
- ✅ Includes `*.nip.io` for dynamic DNS
- ✅ Includes `${DOMAIN}` environment variable
- ✅ Includes `192.168.*.*` subnet for on-prem networks

## 📋 NEXT STEPS FOR DEPLOYMENT

### For On-Premises (192.168.168.31)

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Navigate to code-server-enterprise directory
cd code-server-enterprise

# Pull latest changes
git pull origin main

# Set environment variables for THIS deployment
export DOMAIN=192.168.168.31.nip.io
export ACME_EMAIL=""  # Empty = no HTTPS for nip.io

# Terraform: Regenerate docker-compose.yml with new variables
terraform apply -auto-approve

# Docker: Redeploy containers
docker compose up -d --remove-orphans

# Verify all services are healthy
docker compose ps  # Should show all containers as "healthy"
docker compose logs caddy | grep -i "listening"  # Verify Caddy started

# Test endpoints:
curl http://192.168.168.31.nip.io/healthz           # Should return OK
curl http://code-server.192.168.168.31.nip.io/      # Should return HTML
curl http://prometheus.192.168.168.31.nip.io/api/v1/targets  # Should return JSON
```

### For Production (kushnir.cloud)

```bash
# SSH to host (or local dev machine with docker context set)
ssh akushnir@192.168.168.31  # Or production IP

# Navigate to repo
cd code-server-enterprise

# Set production environment
export DOMAIN=kushnir.cloud
export ACME_EMAIL=ops@kushnir.cloud

# Terraform apply
terraform apply -auto-approve

# Verify DNS is configured (Cloudflare)
# Make sure A record points to this host IP
dig kushnir.cloud +short  # Should show correct IP

# Docker deploy
docker compose up -d --remove-orphans

# Verify HTTPS cert generation
docker compose logs caddy | grep -i "certificate"

# Test endpoints with HTTPS
curl https://kushnir.cloud/healthz
curl https://code-server.kushnir.cloud/
curl https://prometheus.kushnir.cloud/api/v1/targets
```

## 🔍 VERIFICATION CHECKLIST

Run these commands to verify DNS-first architecture is working:

```bash
# 1. Check Caddyfile syntax
docker exec caddy caddy validate

# 2. Verify environment variables loaded
docker exec caddy env | grep -E "DOMAIN|ACME"
# Expected: DOMAIN=192.168.168.31.nip.io, ACME_EMAIL=ops@kushnir.cloud

# 3. Test external DNS resolution
nslookup 192.168.168.31.nip.io        # Should return 192.168.168.31
nslookup code-server.192.168.168.31.nip.io  # Should return 192.168.168.31

# 4. Test Caddy reverse proxy routes
curl -v http://192.168.168.31.nip.io/healthz
curl -v http://code-server.192.168.168.31.nip.io/

# 5. Verify service-to-service DNS
docker exec caddy nslookup code-server   # Should resolve in enterprise network
docker exec caddy nslookup prometheus    # Should resolve
docker exec code-server nslookup prometheus  # Should resolve

# 6. Check health of all services
docker compose ps  # All containers should show "healthy"
docker compose exec code-server curl http://localhost:8080/healthz
docker compose exec prometheus curl http://localhost:9090/-/healthy
docker compose exec grafana curl http://localhost:3000/api/health

# 7. Verify no hardcoded IPs in configs
grep -r "127.0.0.1" config/  # Should be empty
grep -r "localhost" config/  # Should be empty (except comments)
grep -r "192.168.168.31" Caddyfile  # Should only be in defaults, not hardcoded
```

## 📊 ARCHITECTURE VERIFICATION

```
Expected DNS Resolution Chain:

User Browser
    ↓
DNS Query: code-server.192.168.168.31.nip.io
    ↓
nip.io returns: 192.168.168.31
    ↓
Caddy on 192.168.168.31:80 receives request
    ↓
Caddy resolves "code-server:8080" via Docker DNS
    ↓
Docker DNS returns: 172.28.0.2 (code-server container IP)
    ↓
Caddy forwards to 172.28.0.2:8080 (code-server service)
    ↓
Response returns to browser with 200 OK
```

## ⚠️ TROUBLESHOOTING

### Issue: "Address already in use" for port 80/443

**Cause:** Previous Caddy container didn't shut down properly

**Fix:**
```bash
docker compose down --remove-orphans
docker volume prune  # Optional: clean up stale volumes
docker compose up -d
```

### Issue: nip.io DNS not resolving

**Cause:** DNS resolver not configured for external wildcard domains

**Fix:**
```bash
# Test nip.io resolution directly
nslookup 1.2.3.4.nip.io
# If fails, try with different resolver:
nslookup 1.2.3.4.nip.io 8.8.8.8  # Google DNS
```

### Issue: HTTPS certificate not generating

**Cause:** ACME_EMAIL not set or Let's Encrypt not reachable

**Check:**
```bash
docker compose logs caddy | grep -i "acme"
docker compose exec caddy curl https://acme-v02.api.letsencrypt.org/directory
```

### Issue: Service-to-service DNS not resolving

**Cause:** Containers not on same network or network DNS not enabled

**Fix:**
```bash
# Verify network
docker network ls
docker network inspect enterprise

# Verify containers on same network
docker compose ps  # All should show "enterprise" network

# Check Docker DNS
docker exec caddy cat /etc/resolv.conf  # Should have Docker's embedded DNS
```

## 🚀 SUCCESS CRITERIA

- [x] Caddyfile uses environment variables (no hardcoded IPs)
- [x] docker-compose.yml includes DOMAIN + ACME_EMAIL
- [x] Terraform templates updated with new variables
- [x] code-server-config.yaml proxy-domain list comprehensive
- [x] All services reference container DNS names
- [x] No localhost or hardcoded IPs in active configs
- [ ] Deployed to 192.168.168.31 with nip.io (next step)
- [ ] Health checks all passing
- [ ] External DNS access working (code-server.192.168.168.31.nip.io)
- [ ] Service-to-service DNS working (internal container communication)

## 📚 RELATED DOCUMENTS

- `DNS-FIRST-ARCHITECTURE-PHASE-21.md` — Full architecture documentation
- `DNS-IMPLEMENTATION-GUIDE.md` — Legacy Phase 18-20 DNS changes
- `ARCHITECTURE.md` — Overall system design
- `Caddyfile` — Actual reverse proxy configuration
