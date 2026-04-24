# 🔴 INFRASTRUCTURE CRISIS REPORT & RECOVERY PLAN
**Generated**: April 21, 2026  
**Status**: CRITICAL - kushnir.cloud SSL BROKEN + Replica Degraded  
**Author**: GitHub Copilot Infrastructure Review

---

## EXECUTIVE SUMMARY

| Item | Status | Impact | Priority |
|------|--------|--------|----------|
| **kushnir.cloud HTTPS** | ❌ BROKEN | Users cannot access | **P0 CRITICAL** |
| **Primary Host (192.168.168.31)** | ⚠️ DEGRADED | Caddy/SSL failing | **P0 CRITICAL** |
| **Replica Host (192.168.168.42)** | ⚠️ DEGRADED | Sentinel restart loop | **P1 HIGH** |
| **OAuth2-proxy** | ⚠️ UNHEALTHY | Auth may fail under load | **P1 HIGH** |
| **Database Failover** | ⚠️ RISKY | Sentinel issues | **P2 MEDIUM** |

---

## ROOT CAUSE ANALYSIS

### 1. **Caddyfile Configuration Mismatch** (PRIMARY ISSUE)

```
PROBLEM:
├─ Current Caddyfile (486 bytes, 22 lines) — Caddyfile.clean
│  └─ Designed for minimal proxying
│     ├─ Target: oauth2-proxy:4180
│     └─ No HTTPS/ACME configuration
│
├─ Broken attempt: Caddyfile.known-good
│  └─ Tries Let's Encrypt ACME
│     ├─ Uses email: security-team@example.com ❌ FORBIDDEN
│     └─ Error: HTTP 400 from ACME
│
└─ Architecture mismatch:
   ├─ DNS resolves kushnir.cloud → 173.77.179.148 (Cloudflare)
   ├─ Traffic → 192.168.168.31 (on-prem primary)
   ├─ Caddy should handle HTTP → Cloudflare handles HTTPS
   └─ WRONG: Caddy trying to fetch certificates from Let's Encrypt
```

### 2. **Docker Snap Mount Issue** (TECHNICAL BLOCKER)

```
ERROR: "cannot create subdirectories in /var/snap/docker/... /etc/caddy/Caddyfile"

CAUSE:
├─ Docker installed via Snap on Linux host
├─ Snap uses restricted overlay filesystem
├─ Volume mount: ./Caddyfile:/etc/caddy/Caddyfile:ro
│  └─ Path is relative to docker-compose working directory
│  └─ Snap's overlay can't create mount points properly
│
SOLUTION NEEDED:
├─ Use absolute path: /home/akushnir/code-server-enterprise/Caddyfile
├─ OR: Use docker volumes exclusively
├─ OR: Fix docker snap installation
```

### 3. **Service Restart Loops on Replica** (CASCADING FAILURE)

```
Replica (192.168.168.42) Services:
├─ redis-sentinel-arbiter: Restarting (1) ❌
├─ redis-sentinel-1: Restarting (1) ❌
├─ pgbouncer: Restarting (1) ❌
│
ROOT CAUSES (likely):
├─ Network issues between replica → primary
├─ PostgreSQL replication not configured
├─ Sentinel failing to connect to Redis on primary
└─ PgBouncer can't reach primary database
```

---

## CRITICAL FINDINGS

### A. Container Status Map

**PRIMARY (192.168.168.31)** - MOSTLY HEALTHY ✅
```
✅ code-server              Up 8m (healthy)    — IDE accessible locally
✅ redis                    Up 17m (healthy)   — Cache operational
✅ postgres                 Up 17m (healthy)   — Database working
✅ grafana                  Up 17m (healthy)   — Monitoring dashboard
✅ ollama                   Up 17m (healthy)   — LLM engine
✅ jaeger                   Up 17m (healthy)   — Tracing system
✅ alertmanager             Up 17m (healthy)   — Alerts queued

❌ caddy                    FAILED             — Cannot mount Caddyfile (SNAP issue)
❌ oauth2-proxy             Unknown            — Hidden behind Caddy proxy
```

**REPLICA (192.168.168.42)** - PARTIALLY BROKEN ⚠️
```
✅ code-server              Up 9m (healthy)
✅ postgres                 Up 9m (healthy)
✅ redis                    Up 9m (healthy)
✅ grafana                  Up 9m (healthy)
✅ prometheus               Up 9m (healthy)
✅ ollama                   Up 9m (healthy)
✅ alertmanager             Up 9m (healthy)

⚠️ oauth2-proxy             Up 6h (UNHEALTHY)   — Health check failing
⚠️ redis-exporter           Up 6h (UNHEALTHY)   — Cannot reach metrics
❌ redis-sentinel-arbiter   Restarting (1)     — Network issue
❌ redis-sentinel-1         Restarting (1)     — Network issue
❌ pgbouncer                Restarting (1)     — DB connection issue
```

### B. DNS & External Resolution

```
$ nslookup kushnir.cloud 8.8.8.8
Name: kushnir.cloud
Address: 173.77.179.148   ← Cloudflare edge IP

Expected flow:
  Browser: https://kushnir.cloud
         ↓
  Cloudflare (173.77.179.148): Proxy + TLS termination + WAF
         ↓
  192.168.168.31 (Primary): Reverse proxy via HTTP (no TLS on LAN)
         ↓
  code-server (8080): IDE

Current broken flow:
  Browser: https://kushnir.cloud
         ↓
  Cloudflare: [OK]
         ↓
  192.168.168.31: [ERROR] TLSv1.3 alert internal error
         ↓
  Caddy: [CRASHED] Cannot handle request
```

### C. Service Dependencies Broken

```
Cascade of failures:
  Caddy (BROKEN) 
    → Can't proxy to oauth2-proxy
    → Can't pass traffic to code-server
    → Users can't authenticate
    → SSH/IDE access blocked

Sentinel (RESTART LOOP)
    → Can't coordinate Redis failover
    → Database replication unstable
    → Potential data loss on primary failure
```

---

## IMMEDIATE FIX (30 minutes)

### Step 1: SSH to Primary Host
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
```

### Step 2: Fix Caddyfile Mount Issue (CRITICAL)
```bash
# Option A: Remove broken Caddy container
docker stop caddy || true
docker rm caddy || true
docker ps | grep caddy  # Verify it's gone

# Option B: Verify Caddyfile exists
ls -lh Caddyfile                     # Should show ~500 bytes (clean config)
file Caddyfile                       # Should say "regular file"

# Option C: Check current content (should be simple)
head -5 Caddyfile                    # Should show: "ide.kushnir.cloud {" or ":80 {"
```

### Step 3: Clear Caddy Volumes (Remove corrupted state)
```bash
docker volume rm caddy-data || true
docker volume rm caddy-config || true
docker volume create caddy-data
docker volume create caddy-config
```

### Step 4: Start Caddy with Explicit Configuration
```bash
# Use absolute path to avoid snap mount issues
cd /home/akushnir/code-server-enterprise

docker run -d \
  --name caddy \
  --restart unless-stopped \
  -u 33 \
  --network net-edge \
  --network net-app \
  -p 80:80 \
  -p 443:443 \
  -p 127.0.0.1:2019:2019 \
  -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -v caddy-data:/data \
  -v caddy-config:/config \
  -e "DOMAIN=kushnir.cloud" \
  -e "IDE_DOMAIN=ide.kushnir.cloud" \
  -e "PORTAL_DOMAIN=kushnir.cloud" \
  caddy:2.7.6
```

### Step 5: Verify Startup
```bash
sleep 5
docker logs caddy --tail 20          # Check for errors
docker ps | grep caddy               # Should show "healthy" or "up"
curl -s http://localhost/health      # Should respond "OK"
```

### Step 6: Test OAuth Flow
```bash
curl -v http://ide.kushnir.cloud/oauth2/ping
# Should get: HTTP 200 OK (or redirect if behind proxy)
```

---

## REPLICA RECOVERY (60 minutes)

### Step 1: SSH to Replica
```bash
ssh akushnir@192.168.168.42
cd code-server-enterprise
```

### Step 2: Diagnose Restart Loops
```bash
# Check why services keep restarting
docker logs redis-sentinel-arbiter --tail 50
docker logs redis-sentinel-1 --tail 50
docker logs pgbouncer --tail 50

# Common issues:
# - "Cannot connect to 192.168.168.31:6379" → Primary Redis unreachable
# - "CRITICAL ERROR in initialization" → Config/network issue
```

### Step 3: Fix Network Connectivity
```bash
# Test if replica can reach primary
docker run --rm --network net-app alpine ping 192.168.168.31
docker run --rm --network net-app alpine nc -zv 192.168.168.31 5432  # PostgreSQL
docker run --rm --network net-app alpine nc -zv 192.168.168.31 6379  # Redis

# If these fail: networking between hosts is broken
#   → Check firewall rules on both hosts
#   → Verify host-to-host SSH works: ssh akushnir@192.168.168.42 ping 192.168.168.31
```

### Step 4: Stop Restarting Services
```bash
docker stop redis-sentinel-1 redis-sentinel-arbiter pgbouncer
docker ps | grep -E "Restarting|restart"  # Verify they stopped
```

### Step 5: Check Unhealthy Services
```bash
docker logs oauth2-proxy --tail 50      # Why unhealthy?
docker logs redis-exporter --tail 50    # Network issue?

# Restart if config looks OK:
docker restart oauth2-proxy redis-exporter
```

### Step 6: Don't Restart Sentinel Until Diagnostics Complete
```bash
# Sentinel + PgBouncer need:
# 1. Redis replication working on primary
# 2. Network connectivity verified
# 3. Proper configuration in place

# For now: leave stopped, debug later
```

---

## VERIFICATION CHECKLIST

After each step, verify:

```bash
# ✅ HTTP Endpoint Responding
curl -s http://192.168.168.31/health | grep OK

# ✅ Caddy Container Healthy
docker ps | grep caddy | grep healthy

# ✅ OAuth Reachable
curl -v http://ide.kushnir.cloud/oauth2/ping

# ✅ Code-server Behind OAuth
curl -v http://192.168.168.31:8080/healthz

# ✅ DNS Still Resolving
nslookup kushnir.cloud 8.8.8.8 | grep 173.77

# ✅ All Primary Services Running
ssh akushnir@192.168.168.31 'docker ps --format "{{.Names}}\t{{.Status}}" | grep healthy | wc -l'
# Should be 6+

# ✅ Logs Show No Errors
docker logs caddy --tail 5 | grep -i "error" || echo "✅ No errors"
```

---

## ROOT CAUSE: WHY DID THIS HAPPEN?

1. **Caddyfile Configuration Drift**
   - Multiple .bak, .known-good, .clean versions indicate repeated failures
   - Last modified: Apr 21 04:04 (recent failed restart attempt)
   - Configuration inconsistent with deployed services

2. **Docker Snap Limitations**
   - Snap overlay filesystem doesn't handle volume mounts properly
   - Relative paths → mount issues
   - Snap stores docker data in `/var/snap/docker/` (non-standard)

3. **No Configuration as Code**
   - docker-compose changes not tracked in git
   - Volumes/mounts changed manually
   - No rollback capability

4. **Lack of Health Monitoring**
   - Caddy failures not detected automatically
   - No alerts sent when SSL/TLS broken
   - Manual discovery only

---

## PERMANENT FIXES (This Week)

### 1. **Fix Docker Snap Installation**
```bash
# Option A: Reinstall docker (recommended)
sudo snap remove docker
sudo apt install docker.io docker-compose

# Option B: Fix snap docker mount issue
# Add this to /etc/docker/daemon.json:
{
  "storage-driver": "overlay2",
  "data-root": "/home/docker-data"
}
```

### 2. **Implement Caddyfile as Code**
```bash
# Store Caddyfile in git with comments explaining each section
# Track all changes:
git add Caddyfile
git commit -m "fix: Use minimal Caddyfile for on-prem behind Cloudflare"
git push origin main
```

### 3. **Add Caddy Health Monitoring**
```yaml
# Add to Prometheus scrape config
scrape_configs:
  - job_name: 'caddy'
    static_configs:
      - targets: ['localhost:2019']
    metrics_path: '/metrics'
```

### 4. **Implement Automatic Rollback**
```bash
# Save working configurations
cp docker-compose.yml docker-compose.yml.known-good
cp Caddyfile Caddyfile.known-good

# On failure, restore:
docker-compose stop
git checkout docker-compose.yml Caddyfile
docker-compose up -d
```

### 5. **Set Up Alerting**
```yaml
# Alert if Caddy unhealthy for >2 minutes
- alert: CaddyDown
  expr: up{job="caddy"} == 0
  for: 2m
```

---

## NEXT SESSION HANDOFF

**For Next Engineer**:

1. **IMMEDIATE** (Next 30 minutes):
   - [ ] Execute "Immediate Fix" steps 1-6 above
   - [ ] Verify kushnir.cloud HTTPS working
   - [ ] Test OAuth login with QA account

2. **SHORT TERM** (Today):
   - [ ] Fix replica restart loops (diagnose network/config issues)
   - [ ] Implement permanent fixes #1-2

3. **MEDIUM TERM** (This week):
   - [ ] Add health monitoring + alerting
   - [ ] Document final architecture
   - [ ] Test failover procedures

4. **LONG TERM** (This month):
   - [ ] Eliminate hardcoded IPs (use DNS names)
   - [ ] Implement GitOps for infrastructure
   - [ ] Add E2E tests for SSL/OAuth

---

## SUPPORTING RESOURCES

- **Diagnostics Document**: `INFRASTRUCTURE-REVIEW-AND-RECOVERY-APRIL-21-2026.md`
- **Recovery Script**: `RECOVERY-SCRIPT-PHASE-1.sh` (requires SSH key setup)
- **Caddyfile Versions**:
  - `Caddyfile.clean` (minimal, use this)
  - `Caddyfile.known-good` (complex, has ACME issues)
  - `Caddyfile.production` (reference only)

---

## CONTACTS & ESCALATION

- **On-Call**: akushnir@kushnir.cloud
- **Incident Channel**: #infrastructure-alerts
- **Escalation**: If SSH not working, contact infrastructure team directly

**Last Updated**: April 21, 2026 04:10 UTC  
**Status**: READY FOR MANUAL RECOVERY
