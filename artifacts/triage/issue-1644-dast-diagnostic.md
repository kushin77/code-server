## P1 #1644 Diagnostic Analysis & Remediation Plan

### Issue Summary
DAST security scanner unable to reach https://ide.kushnir.cloud/ - reports HTTP 404 or connection timeout. This is blocking production deployment.

### Root Cause Analysis

The :0 port suffix in the reported URL (`https://ide.kushnir.cloud/:0`) suggests a URL parsing anomaly in the ZAP scanner output, but the underlying issue is real: the endpoint is not responding correctly to HTTPS health checks.

**Likely Causes (in order of probability):**

1. **Caddy reverse proxy not running or crashed** - Most likely if recent deployment occurred
   - Symptom: Connection timeout or 502 from nginx
   - Check: `docker-compose ps caddy`

2. **oauth2-proxy backend unhealthy** - Caddy is up but oauth2-proxy has crashed
   - Symptom: HTTP 502/503
   - Check: `docker-compose ps oauth2-proxy`

3. **TLS certificate expired** - Less likely but possible if cert renewal failed
   - Symptom: TLS handshake failure in browser
   - Check: `openssl s_client -connect ide.kushnir.cloud:443`

4. **Health endpoint missing from Caddyfile** - Configuration regression
   - Symptom: HTTP 404 on /health endpoint
   - Check: Caddyfile for `@health path /health` and `respond @health`

5. **Load balancer/DNS routing misconfigured** - Network layer issue
   - Symptom: Connection times out when reaching ide.kushnir.cloud
   - Check: DNS resolution and HAProxy/Cloudflare routing

### Diagnostic Script

A comprehensive diagnostic script has been created: **scripts/ops/diagnose-dast-target-unreachable.sh**

**Usage (run on any accessible host with network access to ide.kushnir.cloud):**

```bash
bash scripts/ops/diagnose-dast-target-unreachable.sh
```

**What it tests:**
- DNS resolution of ide.kushnir.cloud
- Network connectivity on port 443
- TLS certificate validity
- HTTP health endpoint response codes
- Remote replica service status
- OAuth2-proxy health

### Immediate Actions

**Step 1: Run Diagnostic (on local machine or CI runner)**
```bash
bash scripts/ops/diagnose-dast-target-unreachable.sh
```

**Step 2: Identify failing test (refer to summary above)**

**Step 3: SSH to replica and investigate** (requires manual access)
```bash
ssh akushnir@192.168.168.42
cd code-server-enterprise

# Check what's running
docker-compose ps

# View Caddy logs
docker-compose logs --tail 100 caddy

# Check oauth2-proxy
docker-compose logs --tail 50 oauth2-proxy

# Verify Caddyfile has health endpoint
grep -A 3 "@health" Caddyfile
```

**Step 4: Restart services if needed**
```bash
# Restart Caddy
docker-compose restart caddy

# Restart full stack
docker-compose down
docker-compose up -d
```

**Step 5: Verify fix**
```bash
curl -k https://ide.kushnir.cloud/health
# Should return HTTP 200 with "OK"
```

### Blocking Dependencies

- **Issue #1636** (Passwordless sudo) - Enables automated remote diagnostics and fixes
- **Load balancer configuration** - Need access to verify HAProxy/Cloudflare routing
- **Network access to replicas** - Required for SSH-based remote investigation

### CI/CD Impact

DAST scan is part of the security gates pipeline and blocks:
- Issue #1467 (GO/NO-GO decision) - Currently shows GO but with DAST security issue noted
- Production deployment approval
- Any new PRs that trigger security scans

### Recommended Resolution

1. **Immediate** (next 1-2 hours): Run diagnostic script and identify root cause
2. **Short-term** (next 2-4 hours): Fix identified issue (restart Caddy, verify certs, etc.)
3. **Verification** (next 4-6 hours): Re-run DAST scan to confirm fix
4. **Documentation**: Document any configuration changes made

### Success Criteria

- DAST scan returns HTTP 200 for https://ide.kushnir.cloud/health
- No "target unreachable" or 404 errors in DAST report
- Security scan passes in CI pipeline
- Deployment gates clear for production

---

**Diagnostic Commit**: f6f7adb1  
**Script Location**: scripts/ops/diagnose-dast-target-unreachable.sh  
**Created**: April 23, 2026
