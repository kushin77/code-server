# Infrastructure Review & Recovery Plan
**Date**: April 21, 2026  
**Status**: CRITICAL SSL/TLS FAILURE DETECTED  
**Scope**: Primary (192.168.168.31) + Replica (192.168.168.42)

---

## 🔴 CRITICAL FINDING: SSL ERROR ON kushnir.cloud

### Symptoms
- Browser: `ERR_SSL_PROTOCOL_ERROR` when accessing `kushnir.cloud`
- Certificate: Invalid/untrusted
- Error: `TLSv1.3 (IN), TLS alert, internal error`
- Root: Caddy SSL/TLS configuration failure

### Root Cause Analysis

#### 1. **Caddyfile Drift** (PRIMARY ISSUE)
```
Current Caddyfile (71 lines):
├─ Enables auto-HTTPS with Let's Encrypt
├─ Uses environment variables: ${IDE_DOMAIN}, ${PORTAL_DOMAIN}, etc.
├─ References NON-EXISTENT services: session-broker:5000
├─ Configures complex multi-host failover upstreams
├─ Health checks failing → Caddy enters error state
└─ RESULT: Let's Encrypt cert generation fails → SSL error

Known-Good Caddyfile (100+ lines):
├─ Uses `:80` (HTTP only)
├─ auto_https off (Cloudflare Tunnel handles HTTPS)
├─ Simple proxying: only oauth2-proxy:4180
├─ Designed for on-prem infrastructure
└─ RESULT: Works reliably on-prem

Clean Caddyfile (8 lines):
├─ Minimal: ide.kushnir.cloud → oauth2-proxy:4180
├─ No environment variables, no ACME
└─ RESULT: Simplest, most stable approach
```

#### 2. **Backend Service Mismatch**
Current Caddyfile expects:
- ❌ `session-broker:5000` — NOT in docker-compose.yml
- ❌ Dual-host failover upstreams — NOT configured
- ❌ Sophisticated session management — NOT implemented

Actually available:
- ✅ `oauth2-proxy:4180` — Deployed and running (on primary)
- ✅ `code-server:8080` — Deployed and running
- ✅ Various monitoring services (Prometheus, Grafana, etc.)

#### 3. **Container Health Status**

**PRIMARY (192.168.168.31)** — OPERATIONAL ✅
```
caddy                        Up 17 minutes (healthy)
code-server                  Up 8 minutes (healthy)
oauth2-proxy                 (not visible, running through Caddy proxy)
postgres                     Up 17 minutes (healthy)
redis                        Up 17 minutes (healthy)
prometheus                   Up 17 minutes (healthy)
grafana                      Up 17 minutes (healthy)
```

**REPLICA (192.168.168.42)** — PARTIALLY DEGRADED ⚠️
```
redis-sentinel-arbiter       Restarting (1)
redis-sentinel-1             Restarting (1)
pgbouncer                    Restarting (1)
oauth2-proxy                 Up but UNHEALTHY
redis-exporter               Up but UNHEALTHY
code-server                  Up 9 minutes (healthy)
postgres                     Up 9 minutes (healthy)
```

#### 4. **Caddy Error Log Evidence**
```
HTTP request failed: lookup session-broker on 127.0.0.11:53: server misbehaving
HTTP request failed: lookup session-broker on 127.0.0.11:53: server misbehaving
[... repeating every 30 seconds ...]
```

Caddy continuously fails health checks → enters degraded state → returns TLS internal error.

---

## 🟡 REPLICA HOST ISSUES

### Services in Restart Loop
- `redis-sentinel-arbiter`: Restarting (1)
- `redis-sentinel-1`: Restarting (1)
- `pgbouncer`: Restarting (1)

### Unhealthy Services
- `oauth2-proxy`: UP but unhealthy
- `redis-exporter`: UP but unhealthy

### Diagnosis Needed
- Check docker logs for restart reason
- Verify network connectivity between services
- Check Redis configuration on replica

---

## 🟢 RECOVERY PLAN (IMMEDIATE)

### Phase 1: Stabilize Primary (10 minutes)

**Step 1**: Revert Caddyfile to Known-Good Configuration
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Backup current broken config
cp Caddyfile Caddyfile.broken-$(date +%s)

# Restore known-good (on-prem + Cloudflare)
cp Caddyfile.known-good Caddyfile

# Alternative: Use clean minimal config (if .known-good has issues)
# cp Caddyfile.clean Caddyfile

# Verify syntax
docker run --rm -v ${PWD}/Caddyfile:/etc/caddy/Caddyfile caddy:2.7.6 caddy validate
```

**Step 2**: Update Environment Variables in docker-compose
```yaml
# Ensure these are set:
environment:
  - DOMAIN=kushnir.cloud
  - IDE_DOMAIN=ide.kushnir.cloud
  - PORTAL_DOMAIN=kushnir.cloud
  - ACME_EMAIL=ops@kushnir.cloud
```

**Step 3**: Restart Caddy Container
```bash
docker-compose restart caddy

# Wait 10s for startup
sleep 10

# Verify health
docker ps | grep caddy  # Should show "healthy"

# Check logs
docker logs caddy --tail 20  # Should show successful ACME or error
```

**Step 4**: Verify SSL Certificate
```bash
# If using Cloudflare Tunnel (on-prem):
curl -vvv http://192.168.168.31  # Should work (HTTP only behind tunnel)

# If using Let's Encrypt:
curl -vvv https://192.168.168.31  # Should show valid cert

# Test OAuth flow
curl -vvv https://ide.kushnir.cloud/oauth2/ping  # Should respond 200
```

### Phase 2: Diagnose Replica Issues (15 minutes)

**Step 1**: SSH to Replica
```bash
ssh akushnir@192.168.168.42
cd code-server-enterprise
```

**Step 2**: Check Restart Loops
```bash
# Identify why services are restarting
docker logs redis-sentinel-arbiter --tail 50
docker logs redis-sentinel-1 --tail 50
docker logs pgbouncer --tail 50

# Check Redis network connectivity
docker exec redis redis-cli ping  # Should respond PONG

# Check PostgreSQL
docker exec postgres pg_isready -h localhost -U codeserver
```

**Step 3**: Fix Unhealthy Services
```bash
# OAuth2-proxy unhealthy: check config + restart
docker logs oauth2-proxy --tail 50
docker-compose restart oauth2-proxy

# Redis-exporter unhealthy: verify Redis is accessible
docker logs redis-exporter --tail 50
docker-compose restart redis-exporter
```

### Phase 3: Load Balancer & Failover Validation (20 minutes)

**Architecture Expected**:
```
kushnir.cloud (173.77.179.148 — Cloudflare edge)
    ↓
Cloudflare Tunnel or VPN
    ↓
192.168.168.31 (Primary — Caddy LB + OAuth2-proxy + code-server)
192.168.168.42 (Replica — Failover standby)
```

**Test Cases**:
```bash
# 1. DNS resolution
nslookup kushnir.cloud  # Should resolve to Cloudflare IP

# 2. HTTP/HTTPS to primary
curl -v https://ide.kushnir.cloud/health
curl -v https://kushnir.cloud/health

# 3. OAuth flow
curl -v "https://ide.kushnir.cloud/oauth2/ping"

# 4. Code-server accessibility (after auth)
# Manual test: open browser, login with QA account

# 5. Failover simulation (if HAProxy/DNS failover configured)
# Stop primary, verify traffic routes to replica
```

---

## 📊 CURRENT PRODUCTION STATE

### Architecture: On-Prem + Cloudflare

```
┌─────────────────────────┐
│  kushnir.cloud          │
│  (DNS: 173.77.179.148)  │ ← External DNS
└──────────┬──────────────┘
           │
    ┌──────┴────────┐
    │               │
    ▼ Cloudflare    ▼ VPN
    │ Tunnel        │
    │               │
    ├──────────────────────────┐
    │ 192.168.168.31 (Primary) │ (OPERATIONAL ✅)
    │  ├─ Caddy 2.7.6         │
    │  ├─ oauth2-proxy 7.5.1  │
    │  ├─ code-server 4.115.0 │
    │  ├─ postgres 15         │
    │  ├─ redis 7             │
    │  ├─ prometheus 2.49.1   │
    │  └─ grafana 10.4.1      │
    └──────────────────────────┘
    
    ┌──────────────────────────┐
    │ 192.168.168.42 (Replica) │ (DEGRADED ⚠️)
    │  ├─ Services: Mixed      │
    │  └─ Some restarting      │
    └──────────────────────────┘
```

### Component Status Table

| Component | Version | Port | Primary | Replica | Status |
|-----------|---------|------|---------|---------|--------|
| Caddy | 2.7.6 | 80/443 | ✅ | ❌ | SSL BROKEN |
| oauth2-proxy | 7.5.1 | 4180 | ✅ | ⚠️ UNHEALTHY | AUTH GATE |
| code-server | 4.115.0 | 8080 | ✅ | ✅ | IDE OK |
| postgres | 15 | 5432 | ✅ | ✅ | DATABASE OK |
| redis | 7 | 6379 | ✅ | ✅ | CACHE OK |
| prometheus | 2.49.1 | 9090 | ✅ | ⏸️ | MONITORING |
| grafana | 10.4.1 | 3000 | ✅ | ⏸️ | DASHBOARDS |
| Sentinel | - | 26379 | ⏸️ | ⚠️ RESTART LOOP | FAILOVER |

---

## 🔧 RECOMMENDED ACTIONS

### IMMEDIATE (Next 30 minutes)
- [ ] **CRITICAL**: Fix Caddyfile SSL by reverting to known-good
- [ ] Restart Caddy on primary
- [ ] Verify kushnir.cloud HTTPS connectivity
- [ ] Test OAuth login flow

### SHORT TERM (Today)
- [ ] Diagnose replica restart loops
- [ ] Fix unhealthy services on replica
- [ ] Test failover from primary to replica
- [ ] Validate DNS resolution for backup hosts

### MEDIUM TERM (This week)
- [ ] Implement session-broker service (planned Phase 2)
- [ ] Set up dual-host failover properly
- [ ] Configure HAProxy load balancer if needed
- [ ] Document final architecture decisions

### LONG TERM (Governance)
- [ ] Eliminate hardcoded IPs (use DNS names)
- [ ] Implement GitOps for infrastructure reconciliation
- [ ] Add comprehensive health monitoring + alerting
- [ ] Automate rollback on configuration failures

---

## 📋 VERIFICATION CHECKLIST

After applying fixes:

```bash
# ✅ SSL/TLS Working
curl -vvv https://kushnir.cloud 2>&1 | grep "certificate verify ok"

# ✅ OAuth Responding
curl -s https://ide.kushnir.cloud/oauth2/ping | grep -q "OK"

# ✅ Code-server Accessible
curl -s https://code-server.kushnir.cloud/healthz | grep -q "OK"

# ✅ All Services Healthy
ssh akushnir@192.168.168.31 "docker ps | grep -E 'healthy|unhealthy'"

# ✅ Replica Services Stable
ssh akushnir@192.168.168.42 "docker ps | grep -E 'Restarting|unhealthy' | wc -l"

# ✅ DNS Resolution
nslookup kushnir.cloud 8.8.8.8 | grep -q "173.77.179.148"

# ✅ Certificate Valid
openssl s_client -connect kushnir.cloud:443 -showcerts 2>/dev/null | grep "verify ok"
```

---

## 📚 SUPPORTING FILES

- **Caddyfile**: Current (broken) configuration
- **Caddyfile.known-good**: Previous working on-prem config
- **Caddyfile.clean**: Minimal fallback config
- **docker-compose.yml**: Authoritative service definitions
- **P0-SECURITY-REMEDIATION-PLAN.md**: Critical fixes pending

---

## 👤 Next Session Handoff

**For next engineer**:
1. Execute Phase 1 (Caddyfile revert) — **URGENT**
2. Verify kushnir.cloud HTTPS works
3. Execute Phase 2 (diagnose replica)
4. Run verification checklist
5. Document final state

**Blockers**: None (all tools + context provided)
