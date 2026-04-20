# OAuth Login Failure Recovery Runbook

---

**Title**: OAuth Login Failure Recovery Runbook  
**Owner**: akushnir  
**Last Review**: 2026-04-20  
**Status**: active  
**Related Issues**: #954 (HA EPIC), #965 (Observability), #966 (This Runbook)

---

## Purpose

This runbook provides operators with a structured response plan for OAuth login failures on **kushnir.cloud**. The April 19, 2026 CSRF loop incident demonstrated the need for a formal recovery procedure beyond ad hoc configuration changes.

## Trigger Conditions

Use this runbook when any of the following occur:

1. **User reports**: "I cannot log in to kushnir.cloud"
2. **User reports**: Redirect loop at Google authentication (stuck on "choose account" screen)
3. **Alert fires**: `OAuth2ProxyUnauthorizedSpike` (401/403 rate > 5/min) from #965 observability
4. **Alert fires**: `AppsmithContainerUnhealthy` (healthcheck failing for 2+ minutes)
5. **Status page**: Cloudflare shows degraded origin health for kushnir.cloud

---

## Quick Verification Checklist

Before diving into detailed recovery steps, run these quick checks:

```bash
# Check 1: Portal availability
curl -I https://kushnir.cloud/healthz
# Expected: HTTP 200 OK

# Check 2: OAuth gateway
curl -I https://kushnir.cloud/oauth2/sign_in
# Expected: HTTP 302 redirect to accounts.google.com

# Check 3: Service status
docker-compose ps oauth2-proxy-portal appsmith session-broker redis

# Check 4: Recent errors in logs
docker-compose logs --tail 20 oauth2-proxy-portal | grep -i error
```

---

## Step 1: Triage (Target: 2 minutes)

**Goal**: Identify the failure point in the auth path (Cloudflare → Caddy → oauth2-proxy-portal → Appsmith).

### 1.1 Check Observability Dashboards

1. Open **Grafana**: https://192.168.168.31:3000 (credentials: admin/admin123)
2. Navigate to: **Portal & IDE OAuth Auth Path Observability** dashboard
3. Look for:
   - **Red/orange spikes** in "OAuth Error Rates" panel (401/403/5xx indicate auth failures)
   - **Component Health Status panel**: All components should show green (value = 1 = healthy)
   - **Redis Connected Clients**: Should be > 0 (indicates session store healthy)
   - **Active Sessions**: Track users currently logged in

### 1.2 Check AlertManager

1. Open **AlertManager**: https://192.168.168.31:9093
2. Check for **FIRING** alerts:
   - `OAuth2ProxyUnauthorizedSpike` → Users can't authenticate
   - `OAuth2ProxyHighErrorRate` → OAuth service returning errors
   - `AppsmithContainerUnhealthy` → Portal unavailable
   - `CaddyUpstream5xxSpike` → Upstream service failures
   - `SessionBrokerUnavailable` → Session routing broken
   - `RedisConnectedClientsDropped` → Session store down

### 1.3 Test Each Hop in Auth Chain

Run these curl commands to isolate the failure:

```bash
# Test 1: Cloudflare → Caddy → Health check
curl -I https://kushnir.cloud/healthz
# ✓ Expected: HTTP 200 OK
# ✗ If returns 502/503: Caddy upstream (oauth2-proxy-portal) is down

# Test 2: Caddy → oauth2-proxy-portal auth gateway
curl -I https://kushnir.cloud/oauth2/sign_in
# ✓ Expected: HTTP 302 redirect to https://accounts.google.com/...
# ✗ If returns 401: CSRF token validation failed
# ✗ If returns 502: Upstream appsmith is down

# Test 3: Check oauth2-proxy-portal service logs
docker logs --tail 50 oauth2-proxy-portal 2>&1 | grep -E "ERROR|WARN|msg="
# ✓ Expected: Normal auth flow logs (no ERROR lines)
# ✗ Red flags: "cookie_secret", "invalid request", "tls: handshake", "unauthorized client"

# Test 4: Check Appsmith service logs
docker logs --tail 50 appsmith 2>&1 | grep -E "ERROR|WARN|listening"
# ✓ Expected: "Starting Appsmith" → "listening on port 9000"
# ✗ Red flags: "ERROR", "connection refused", "port already in use"

# Test 5: Verify session broker
curl -s http://session-broker:5000/health | python3 -m json.tool
# ✓ Expected: {"status":"healthy","activeSessions":N}
# ✗ Red flags: Timeout or error response
```

**Interpret Results**:

| Test | Pass ✓ | Fail ✗ | Next Step |
|------|--------|--------|-----------|
| Test 1 (/healthz) | 200 | 502/503 | Check Caddy config, restart oauth2-proxy-portal (Step 3) |
| Test 2 (/oauth2/sign_in) | 302 to Google | 401/403 | CSRF Loop Recovery (Step 2) |
| Test 2 (/oauth2/sign_in) | 302 to Google | 502 | Restart Appsmith (Step 4) |
| Test 3 (oauth2-proxy-portal logs) | Normal flow | ERROR lines | Restart oauth2-proxy-portal (Step 3) |
| Test 4 (Appsmith logs) | "listening on port 9000" | ERROR lines | Restart Appsmith (Step 4) |
| Test 5 (session broker) | 200 OK | Timeout | Failover to replica (Step 6) |

---

## Step 2: CSRF Loop Recovery (Target: 5 minutes)

**Trigger**: Users report being stuck on Google's "choose account" screen, or redirect loops between kushnir.cloud and Google.

**Root Cause**: Stale CSRF/session cookies causing oauth2-proxy to reject the request as "unauthorized".

### 2.1 Direct User to Cookie Reset Endpoint

Instruct affected users to visit **in an incognito/private window**:

```
https://kushnir.cloud/auth/reset
```

**What this does**:
- Clears stale oauth2-proxy cookies (`oauth2_proxy_*`)
- Clears session affinity cookie (`ide_session_lb`)
- Redirects to fresh login flow

**Expected user experience**:
1. Click `/auth/reset` link
2. Redirect to https://kushnir.cloud/sign_in
3. Normal OAuth flow: choose account → grant permissions → Appsmith portal loads

### 2.2 If `/auth/reset` Itself Loops

If the `/auth/reset` endpoint also loops:

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Verify CSRF configuration on oauth2-proxy-portal
docker-compose exec -e OAUTH2_PROXY_COOKIE_SAMESITE oauth2-proxy-portal env | grep OAUTH2_PROXY_COOKIE_SAMESITE
# ✓ Expected: OAUTH2_PROXY_COOKIE_SAMESITE=none

docker-compose exec oauth2-proxy-portal env | grep OAUTH2_PROXY_CSRF_TRUSTED_HOSTS
# ✓ Expected: OAUTH2_PROXY_CSRF_TRUSTED_HOSTS=kushnir.cloud,ide.kushnir.cloud

# If variables missing or wrong, update and restart:
cat >> .env <<EOF
OAUTH2_PROXY_COOKIE_SAMESITE=none
OAUTH2_PROXY_CSRF_TRUSTED_HOSTS=kushnir.cloud,ide.kushnir.cloud
EOF

docker-compose restart oauth2-proxy-portal
sleep 10

# Verify fix
curl -I https://kushnir.cloud/healthz
# ✓ Expected: HTTP 200
```

### 2.3 Direct User to Manual Cookie Clearing (Last Resort)

If `/auth/reset` is still unavailable:

**Chrome/Edge/Firefox**:
1. Press `F12` to open DevTools
2. Navigate to: **Application** tab → **Cookies** → `kushnir.cloud`
3. Delete **all** cookies for `kushnir.cloud`
4. Also delete for `ide.kushnir.cloud`
5. Close DevTools, restart browser, try login again

**Safari**:
1. Preferences → Privacy → Manage Website Data
2. Search "kushnir.cloud" → Click "Remove"
3. Restart Safari, try login again

---

## Step 3: Restart oauth2-proxy-portal (Target: 2 minutes)

**Trigger**: `oauth2-proxy-portal` logs show repeated "unauthorized" or CSRF errors, OR `/healthz` returns 502/503.

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Check status
docker-compose ps oauth2-proxy-portal
# ✓ Expected: Status = Up (X seconds)
# ✗ If Exited/Restarting: Service is failing

# Graceful restart
docker-compose restart oauth2-proxy-portal

# Wait for startup
sleep 10

# Verify recovery
curl -I https://kushnir.cloud/healthz
# ✓ Expected: HTTP 200 OK

# If still unhealthy, inspect logs
docker-compose logs oauth2-proxy-portal | tail -100
```

**Common failure patterns** in oauth2-proxy-portal logs:

| Log Pattern | Cause | Resolution |
|-------------|-------|------------|
| `cookie_secret must be 16, 24, or 32 bytes but is N bytes` | Wrong OAUTH2_PROXY_COOKIE_SECRET format in .env | Rotate secret via GSM, check .env.schema.json |
| `invalid request` | Client provided invalid OAuth credentials or malformed request | Check CLIENT_ID, CLIENT_SECRET in .env |
| `tls: handshake failure` | TLS certificate issue with upstream (Google, Appsmith) | Check Caddy cert renewal, verify Appsmith is listening |
| `unauthorized` | CSRF validation failed or token expired | User cookies stale (Step 2) or clock skew |

---

## Step 4: Restart Appsmith (Target: 3 minutes, includes 120s startup time)

**Trigger**: oauth2-proxy-portal is healthy, but Appsmith portal is not reachable. Alert: `AppsmithContainerUnhealthy`.

**Important**: Appsmith can take **up to 180 seconds** to fully start. Do not interrupt the startup process.

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Check current status
docker-compose ps appsmith
# ✓ Expected: Status = Up
# ✗ If Exited/Unhealthy: Service is failing

# Restart Appsmith
docker-compose restart appsmith

# Monitor startup (watch for startup completion)
docker-compose logs -f appsmith
# ✓ Look for: "Starting Appsmith Server", "listening on port 9000"
# ✗ Red flags: "ERROR", "Exception", "failed to start"
# Press Ctrl+C to exit after you see "listening on port 9000"

# After ~120-180 seconds, verify health endpoint:
docker-compose exec appsmith curl -s http://localhost:9000/api/v1/health | python3 -m json.tool
# ✓ Expected:
# {
#   "version": "...",
#   "isHealthy": true
# }

# If health check still fails after 3 minutes:
# Verify Appsmith data volume (NAS mount) is healthy
docker-compose exec appsmith ls -la /appsmith-data/
# ✓ Expected: Directories: apps/, config/, db/
# ✗ If missing: Volume mount failed (check NAS connectivity)
```

**Appsmith Startup Phases**:

1. **Phase 1 (0-30s)**: Container starts, database initialization
   - Look for: `Starting Appsmith Server`
2. **Phase 2 (30-90s)**: Application context loading
   - Look for: `Loading plugins`, `initializing`
3. **Phase 3 (90-120s)**: Server fully online
   - Look for: `listening on port 9000`
4. **Phase 4 (120s+)**: Ready for requests
   - `/api/v1/health` returns `{"isHealthy": true}`

---

## Step 5: Full Portal Profile Redeploy (Target: 5-10 minutes)

**Trigger**: Individual service restarts (Steps 3-4) do not resolve the issue. You need to redeploy the entire portal stack.

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# First, simulate the redeploy (no changes applied)
DRY_RUN=1 bash scripts/ops/redeploy-portal.sh
# Review the output to see what would be redeployed

# If dry-run looks good, apply the actual redeploy
DRY_RUN=0 bash scripts/ops/redeploy-portal.sh

# Monitor the redeploy in real time
docker-compose logs -f oauth2-proxy-portal appsmith
# Wait until you see both services are healthy

# After redeploy, run happy-path test (if available)
# Requires Playwright and valid QA credentials
if [ -f scripts/ci/run-kushnir-cloud-appsmith-login-e2e.sh ]; then
  PORTAL_BASE_URL=https://kushnir.cloud bash scripts/ci/run-kushnir-cloud-appsmith-login-e2e.sh
else
  echo "E2E test script not available; manual verification required"
fi
```

**What redeploy-portal.sh does**:

1. Creates backup of Appsmith state (API export)
2. Pulls latest Docker images from registry
3. Stops old containers gracefully
4. Starts new containers with `docker-compose --profile portal up -d`
5. Waits for health checks to pass (30s timeout per service)
6. Verifies no data was lost (row count checks in PostgreSQL)
7. Reports success/failure

**After redeploy, verify**:

```bash
# Test the auth path again
curl -I https://kushnir.cloud/healthz     # Should be 200
curl -I https://kushnir.cloud/oauth2/sign_in  # Should be 302 to Google

# Check Grafana dashboard
# https://192.168.168.31:3000 → Portal & IDE OAuth Auth Path Observability
# All components should show green (healthy = 1)
```

---

## Step 6: Failover to Replica (Target: 5 minutes)

**Trigger**: Steps 1-5 do not resolve the issue AND you suspect primary host (.31) is degraded beyond recovery.

### 6.1 Promote Replica to Primary

```bash
# SSH to primary host
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Dry-run failover (show what would happen, no changes)
DRY_RUN=1 bash scripts/ops/failover-promote.sh
# Read the output carefully

# If confident, execute failover
DRY_RUN=0 bash scripts/ops/failover-promote.sh
```

**What failover-promote.sh does**:

1. Verifies primary is unreachable (curl timeout)
2. Verifies replica health (SSH connectivity, Docker daemon)
3. Checks PostgreSQL replication lag (must be < 60 seconds)
4. Promotes replica to primary role
5. Updates Cloudflare to route traffic to replica
6. Verifies new primary health

### 6.2 Verify Replica is Now Serving kushnir.cloud

```bash
# From your local machine:
curl -I https://kushnir.cloud/healthz
# ✓ Expected: HTTP 200 (from .42 now, not .31)

# Check Cloudflare health
# https://dash.cloudflare.com → kushnir.cloud → Analytics → Origin Health
# ✓ Expected: Origin .42 = HEALTHY, Origin .31 = DOWN

# Verify OAuth works on new primary
open https://kushnir.cloud/sign_in
# ✓ Expected: Normal redirect to Google OAuth

# Check Grafana dashboard (may be on new primary)
open https://192.168.168.31:3000  # OR https://192.168.168.42:3000
# Navigate to: Portal & IDE OAuth Auth Path Observability
# ✓ Expected: All components healthy
```

---

## Step 7: Escalation and Incident Declaration

**Trigger**: Failover to replica does not resolve the login failure after 30+ minutes of troubleshooting.

### 7.1 Declare P0 Incident

```bash
gh issue create --repo kushin77/code-server \
  --title "P0 INCIDENT: OAuth login unavailable (runbook #966 exhausted)" \
  --label P0,incident,oauth-auth \
  --body "$(cat <<'EOF'
## Incident Declaration

Runbook #966 OAuth Login Failure Recovery exhausted all steps without resolving login failure.

### Steps Completed
- [x] Step 1: Triage (dashboard, AlertManager, curl tests)
- [x] Step 2: CSRF loop recovery (/auth/reset, trusted hosts)
- [x] Step 3: Restart oauth2-proxy-portal
- [x] Step 4: Restart Appsmith
- [x] Step 5: Full portal redeploy
- [x] Step 6: Failover to replica

### Current State
- Primary: 192.168.168.31 [Status: unhealthy/degraded]
- Replica: 192.168.168.42 [Status: promoted, attempting to serve]
- Users: Cannot access https://kushnir.cloud

### Required
- Manual investigation on both hosts
- Possible database/volume restore from backup
- Post-mortem analysis

### Severity
P0 - Production outage (all users blocked)

### Assigned
@kushnir (on-call)
EOF
)"
```

### 7.2 Notify On-Call

PagerDuty should already have triggered when AlertManager fired critical alerts. If not:
- Page on-call engineer directly
- Declare incident in #incidents Slack channel
- Escalate to team lead if on-call is unresponsive

### 7.3 Preserve Evidence for Post-Mortem

```bash
# Collect all logs and system state
mkdir -p /tmp/incident-2026-04-20
cd /tmp/incident-2026-04-20

# Logs from both hosts
ssh akushnir@192.168.168.31 "docker-compose logs oauth2-proxy-portal" > oauth2-proxy-portal-31.log
ssh akushnir@192.168.168.31 "docker-compose logs appsmith" > appsmith-31.log
ssh akushnir@192.168.168.31 "docker-compose logs caddy" > caddy-31.log
ssh akushnir@192.168.168.31 "docker-compose logs redis redis-sentinel-1" > redis-31.log

# System state
ssh akushnir@192.168.168.31 "docker-compose ps" > docker-compose-ps-31.log
ssh akushnir@192.168.168.31 "env | grep -E OAUTH2|APPSMITH|REDIS" > env-31.log

# Prometheus metrics at time of incident
curl -s 'http://192.168.168.31:9090/api/v1/query?query=rate(oauth2_proxy_requests_total[5m])' > prometheus-oauth2-rate.json

# AlertManager state
curl -s 'http://192.168.168.31:9093/api/v1/alerts' > alertmanager-alerts.json

# Package all evidence
tar -czf incident-evidence-2026-04-20.tar.gz *.log *.json
# Attach to incident GitHub issue
```

### 7.4 Rollback & Recovery Options

If all automatic recovery fails:

**Option A: Revert Recent Changes**

```bash
# If recent deployment caused regression:
git log --oneline --since="2 hours ago"  # Check recent commits
git revert <commit-hash>  # Revert the offending change
docker-compose restart oauth2-proxy-portal appsmith
```

**Option B: Rotate Credentials**

```bash
# If CSRF secret or OAuth credentials are suspect:
bash scripts/ops/secret-rotation.sh  # Rotate all GSM secrets
docker-compose restart oauth2-proxy-portal
```

**Option C: Database Restore from Backup**

```bash
# If data corruption is suspected:
DRY_RUN=0 bash scripts/ops/restore-appsmith.sh --backup-file=<latest-backup>
docker-compose restart appsmith
```

---

## Decision Tree / Flowchart

```
OAuth Login Failure Reported
│
├─→ Can users reach https://kushnir.cloud/healthz? (200 OK)
│   ├─ NO  → Go to Step 1.1: Check dashboards/logs
│   │       Likely: Caddy down OR oauth2-proxy-portal down
│   │       Action: Check Grafana, restart oauth2-proxy-portal (Step 3)
│   └─ YES → Continue
│
├─→ Can users reach https://kushnir.cloud/oauth2/sign_in? (302 to Google)
│   ├─ NO (401/403)  → Step 2: CSRF Loop Recovery
│   │                 User sends: /auth/reset
│   ├─ NO (502/503)  → Step 4: Restart Appsmith
│   │                 Appsmith likely down
│   └─ YES (302)     → Continue
│
├─→ Do users see redirect loop at Google auth screen?
│   ├─ YES → Step 2: CSRF Loop Recovery
│   │        Stale cookies or trusted-host misconfiguration
│   └─ NO  → Continue
│
├─→ Check Grafana Component Health panel:
│   ├─ oauth2-proxy-portal = RED (0) → Step 3: Restart oauth2-proxy-portal
│   ├─ Appsmith = RED (0)             → Step 4: Restart Appsmith
│   ├─ session-broker = RED (0)       → Step 4 + Step 6: Check Redis/failover
│   ├─ Redis = RED (0)                → Step 6: Failover to replica
│   └─ All GREEN (1)                  → Continue
│
└─→ If still unresolved:
    ├─ Step 5: Full Portal Redeploy
    └─ Step 6: Failover to Replica
    └─ Step 7: Escalation (P0 incident)
```

---

## Verification Checklist

After completing recovery steps, verify with this checklist:

- [ ] `curl -I https://kushnir.cloud/healthz` returns `HTTP 200 OK`
- [ ] `curl -I https://kushnir.cloud/oauth2/sign_in` returns `HTTP 302 Location: ...google...`
- [ ] OAuth flow completes: users can choose Google account → grant permissions → access Appsmith
- [ ] No redirect loops between kushnir.cloud and Google OAuth
- [ ] Grafana Portal dashboard shows all components healthy (green)
- [ ] AlertManager shows no FIRING auth-path alerts
- [ ] Session persistence: users logged in on .31 can continue on .42 after failover

---

## Related References

- **Related Issues**: #954 (HA EPIC), #965 (Observability), #966 (This Runbook)
- **HA Topology Contract**: [docs/architecture/ha-topology-contract.md](../architecture/ha-topology-contract.md)
- **Grafana Dashboard**: Portal & IDE OAuth Auth Path Observability (http://grafana:3000)
- **AlertManager**: http://alertmanager:9093
- **Observability Metrics**: [#965](https://github.com/kushin77/code-server/issues/965)

---

## Revision History

| Date | Author | Version | Changes |
|------|--------|---------|---------|
| 2026-04-20 | akushnir | 1.1 | Comprehensive 7-step runbook with decision tree and detailed troubleshooting |

---

**Status**: Active  
**Last Updated**: 2026-04-20  
**Owner**: akushnir
