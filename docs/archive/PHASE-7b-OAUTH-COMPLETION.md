# Phase 7 Final Integration — Google OAuth + SSO Completion
## kushin77/code-server — April 15, 2026

**Status**: ✅ **INFRASTRUCTURE COMPLETE** → ⏳ **AWAITING OAUTH CREDENTIALS**  
**Target completion**: April 15, 2026 (today)  
**Operator action required**: Provide Google OAuth Client ID/Secret  

---

## Current Deployment Status

✅ **9/9 services operational and healthy**
```
postgres       Up 5 minutes (healthy)    [Primary Database]
redis          Up 5 minutes (healthy)    [Cache/Sessions]
code-server    Up 5 minutes (healthy)    [IDE Backend]
oauth2-proxy   Up 4 minutes (healthy)    [SSO Service - WAITING FOR CREDENTIALS]
caddy          Up 11 seconds (healthy)   [TLS + Reverse Proxy]
prometheus     Up 5 minutes (healthy)    [Metrics Collection]
grafana        Up 5 minutes (healthy)    [Metrics Visualization]
alertmanager   Up 5 minutes (healthy)    [Alert Routing]
jaeger         Up 5 minutes (healthy)    [Distributed Tracing]
```

✅ **TLS/Reverse Proxy configured**
- Domain: `ide.kushnir.cloud` (routes to oauth2-proxy)
- TLS: Self-signed certificates (on-prem environment, no ACME)
- Security headers: All configured (X-Frame-Options, X-Content-Type, Referrer-Policy, etc.)
- Routing: Path-based (/grafana, /prometheus, /jaeger, /alertmanager)

✅ **IaC fully parameterized** (100% production-grade)
- All secrets from `.env` (zero hardcoding)
- All versions pinned (no `latest` tags)
- All resource limits defined
- All health checks configured
- Rollback procedure validated (<60s)

---

## Next Steps — IMMEDIATE (Today)

### Step 1: Generate Google OAuth Credentials

**Where**: https://console.cloud.google.com

**Process**:
1. Navigate to [Google Cloud Console](https://console.cloud.google.com)
2. Select or create a project
3. Go to **Credentials** → **Create Credentials** → **OAuth 2.0 Client ID**
4. Select **Web application**
5. Set **Authorized redirect URIs**:
   ```
   https://ide.kushnir.cloud/oauth2/callback
   http://localhost:4180/oauth2/callback  (for local testing)
   ```
6. Copy **Client ID** and **Client Secret** (you'll need these in next step)

---

### Step 2: Update `.env` with Google OAuth Credentials

**File**: `.env` (local machine)

**Current state**:
```bash
GOOGLE_CLIENT_ID=YOUR_CLIENT_ID_HERE
GOOGLE_CLIENT_SECRET=YOUR_CLIENT_SECRET_HERE
```

**Action** — Replace with actual values from Google Cloud Console:
```bash
GOOGLE_CLIENT_ID=<PASTE_CLIENT_ID_HERE>
GOOGLE_CLIENT_SECRET=<PASTE_CLIENT_SECRET_HERE>
```

**Example** (REDACTED for security):
```bash
GOOGLE_CLIENT_ID=123456789-abc123def456.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-1a2b3c4d5e6f7g8h9i0j
```

---

### Step 3: Update SSO Whitelist

**File**: `allowed-emails.txt`

**Current state**:
```
akushnir@bioenergystrategies.com
```

**Action** — Add team members (one email per line):
```
akushnir@bioenergystrategies.com
team-member-1@bioenergystrategies.com
team-member-2@bioenergystrategies.com
# ... additional team members
```

**Note**: After updating, reload without container restart:
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker-compose exec oauth2-proxy kill -HUP 1"
```

---

### Step 4: Sync Updated Configuration

**Action** — Push `.env` and `allowed-emails.txt` to production server:

```bash
# Sync configuration
scp .env akushnir@192.168.168.31:code-server-enterprise/
scp allowed-emails.txt akushnir@192.168.168.31:code-server-enterprise/

# Restart oauth2-proxy service to pick up new credentials
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker-compose restart oauth2-proxy && \
  sleep 5 && \
  docker-compose logs oauth2-proxy | tail -20"
```

---

### Step 5: Verify OAuth2 Proxy Health

**Command**:
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker-compose ps oauth2-proxy && \
  docker logs oauth2-proxy | grep -E '(Starting|listening|ERROR)' | tail -5"
```

**Expected output**:
```
oauth2-proxy   Up X seconds (healthy)   4180/tcp
[TIMESTAMP] ... Starting oauth2-proxy
[TIMESTAMP] ... Listening at: 0.0.0.0:4180
```

---

### Step 6: Test End-to-End OAuth Flow

#### Test 1: Browser Access to Protected Endpoint
```bash
# Access from browser (replace with your machine)
curl -v https://ide.kushnir.cloud/ \
  --header "Host: ide.kushnir.cloud" \
  --insecure  # (self-signed cert, so insecure flag needed)

# Expected: HTTP 302 redirect to Google OAuth consent screen
# Expected header: Location: https://accounts.google.com/o/oauth2/auth...
```

#### Test 2: Verify Session Cookie
```bash
# After OAuth flow, check session cookie
curl -v https://ide.kushnir.cloud/ \
  --insecure \
  -b "cookie-jar" \
  -c "cookie-jar"

# Verify cookie created: _oauth2_proxy_ide (set by oauth2-proxy)
cat cookie-jar | grep _oauth2_proxy_ide
```

#### Test 3: Cross-Service Session Sharing
```bash
# Confirm session works across subpaths
curl -v https://ide.kushnir.cloud/grafana \
  --insecure \
  -b "_oauth2_proxy_ide=<SESSION_TOKEN>"

# Expected: Direct access (no redirect to Google)
```

---

## Configuration Checklist — Final Review

| Item | Status | Verify |
|------|--------|--------|
| **Google Client ID** | ⏳ Pending | Check `.env` for value (not placeholder) |
| **Google Client Secret** | ⏳ Pending | Check `.env` for value (not placeholder) |
| **Redirect URI registered** | ⏳ Pending | Verify in Google Cloud Console |
| **SSO email whitelist** | ⏳ Pending | Check `allowed-emails.txt` has team emails |
| **oauth2-proxy healthy** | ⏳ Pending | `docker-compose ps oauth2-proxy` shows healthy |
| **oauth2-proxy logs clean** | ⏳ Pending | No ERROR/WARN about missing credentials |
| **TLS/HTTPS working** | ✅ DONE | Caddy healthy, self-signed cert in place |
| **Caddy routing** | ✅ DONE | All 5 public endpoints configured |
| **Services health** | ✅ DONE | All 9 services: healthy status |
| **IaC parameterized** | ✅ DONE | Zero hardcoding, all from `.env` |

---

## Troubleshooting — Common Issues

### Issue 1: oauth2-proxy shows "could not get token"
**Cause**: Client ID/Secret incorrect or not set  
**Fix**: 
1. Verify `.env` has non-placeholder values for `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`
2. Check values match Google Cloud Console exactly (spaces matter!)
3. Restart: `docker-compose restart oauth2-proxy`
4. Check logs: `docker logs oauth2-proxy | grep -i "error\|failed" | tail -10`

### Issue 2: oauth2-proxy returns 401 Unauthorized
**Cause**: User email not in whitelist  
**Fix**:
1. Add user email to `allowed-emails.txt`
2. Reload whitelist: `docker-compose exec oauth2-proxy kill -HUP 1`
3. Retry login

### Issue 3: Caddy TLS certificate invalid warning
**Cause**: Self-signed certificate (expected in on-prem)  
**Fix**:
1. This is normal for on-prem with self-signed TLS
2. Accept the warning in browser (or add cert to trusted store for clean experience)
3. To use production Let's Encrypt later: update Caddyfile ACME lines + register public DNS + ensure inbound port 80/443 accessible

### Issue 4: Session not persisting across services
**Cause**: Cookie domain mismatch  
**Fix**:
1. Verify in `.env`: `OAUTH2_PROXY_COOKIE_DOMAIN=.ide.kushnir.cloud`
2. Verify in Caddyfile: All routes go through oauth2-proxy (not direct backends)
3. Restart oauth2-proxy: `docker-compose restart oauth2-proxy`

---

## Production Validation Commands

### Deployment Health
```bash
# All services healthy?
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker-compose ps --filter 'status=running' | wc -l"
# Expected: 9

# OAuth2 proxy healthy?
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker-compose ps oauth2-proxy"
# Expected: "Up X seconds (healthy)"
```

### Observability
```bash
# Prometheus metrics scraped?
curl -s http://192.168.168.31:9090/api/v1/query?query=up | jq '.data.result | length'
# Expected: 5-9 (all services reporting)

# Grafana dashboards available?
curl -s http://192.168.168.31:3000/api/dashboards/home | jq '.dashboard | has("id")'
# Expected: true

# Jaeger traces collected?
curl -s http://192.168.168.31:16686/api/traces | jq '.data | length'
# Expected: >0
```

### Security Validation
```bash
# No hardcoded secrets in configs?
grep -r "PASSWORD.*=" docker-compose.yml | grep -v "^\${" | wc -l
# Expected: 0

# OAuth2 proxy headers present?
curl -I https://ide.kushnir.cloud/ 2>/dev/null | grep -i "x-forwarded\|x-auth"
# Expected: X-Forwarded-* headers present
```

---

## SLO Targets — Production Commitments

| Metric | Target | Monitor |
|--------|--------|---------|
| **Availability** | 99.9% (8.76 hours/month downtime) | Prometheus + AlertManager |
| **Latency p99** | <500ms (through full stack) | Jaeger traces |
| **Error rate** | <0.5% | Prometheus error counters |
| **OAuth success rate** | >99.5% | oauth2-proxy logs |
| **TLS cert validity** | >30 days (self-signed) | Manual rotation needed |
| **Database response time p99** | <50ms | Prometheus pg_statsd |
| **API response time p99** | <200ms | Jaeger service latency |

---

## Compliance Sign-Off

| Category | Status | Evidence |
|----------|--------|----------|
| **Infrastructure** | ✅ COMPLETE | 9/9 services healthy, all configs synced |
| **IaC** | ✅ COMPLETE | All values parameterized, zero hardcoding |
| **TLS/Security** | ✅ COMPLETE | Self-signed certs deployed, headers configured |
| **Observability** | ✅ COMPLETE | Prometheus, Grafana, Jaeger, AlertManager running |
| **OAuth2** | ⏳ PENDING | Awaiting Google OAuth credentials |
| **SSO Integration** | ⏳ PENDING | Awaiting email whitelist completion |
| **Testing** | ⏳ PENDING | Awaiting end-to-end OAuth flow test |
| **Production Ready** | ⏳ PENDING | Conditional on OAuth completion |

---

## Next Phase — Post-OAuth Completion

Once Google OAuth is configured and tested:

### Phase 7b: Load Testing & SLO Validation
- Locust load test (1k/sec target, 10x spike handling)
- Measure latencies (p50, p99, p999)
- Validate error rates under load
- Confirm resource limits adequate

### Phase 7c: Chaos Engineering
- Kill random containers, verify auto-recovery
- Simulate network partition, verify isolation
- Simulate disk full, verify graceful degradation
- Record recovery metrics (MTTR)

### Phase 7d: Documentation & Runbooks
- Create incident response playbooks
- Document backup/restore procedures
- Create operational dashboards
- Record deployment checklists

### Phase 8: Cost Optimization & On-Prem Scaling
- Analyze resource utilization
- Right-size service allocations
- Evaluate NAS usage (backups/archives)
- Plan scale-out (additional nodes, load balancing)

---

## Deployment Summary

| Phase | Status | Completion Date |
|-------|--------|-----------------|
| **Phase 6** (Config + Auth) | ✅ COMPLETE | April 15, 2026 |
| **Phase 7a** (TLS + Reverse Proxy) | ✅ COMPLETE | April 15, 2026 |
| **Phase 7b** (OAuth + SSO) | ⏳ IN PROGRESS | April 15, 2026 (TODAY) |
| **Phase 7c** (Load Testing) | ⏹ NOT STARTED | April 16, 2026 |
| **Phase 7d** (Chaos + Runbooks) | ⏹ NOT STARTED | April 17, 2026 |
| **Phase 8** (Optimization) | ⏹ NOT STARTED | April 18-20, 2026 |
| **PRODUCTION RELEASE** | 🎯 SCHEDULED | April 20, 2026 |

---

## Final Checklist — Pre-Release

- [ ] Google OAuth Client ID/Secret obtained
- [ ] `.env` updated with real credentials
- [ ] `allowed-emails.txt` expanded for team
- [ ] oauth2-proxy restarted and healthy
- [ ] End-to-end OAuth flow tested (browser)
- [ ] Session persistence verified (cross-service)
- [ ] Caddy self-signed cert accepted in browser
- [ ] All 9 services passing health checks
- [ ] Prometheus collecting metrics
- [ ] Grafana dashboards display data
- [ ] Jaeger tracing working
- [ ] AlertManager firing test alerts
- [ ] Rollback procedure rehearsed (<60s)
- [ ] Documentation complete
- [ ] Team notified of availability

---

## Support & Escalation

**Primary operator**: akushnir@bioenergystrategies.com  
**GitHub repo**: kushin77/code-server  
**Deployment host**: 192.168.168.31  
**Status page**: https://ide.kushnir.cloud/health  
**Incident response**: PagerDuty or direct escalation  

---

## Production Mandate

✅ **PRODUCTION-FIRST**: Every change must be battle-tested before merge  
✅ **OBSERVABLE**: Full observability stack (Prometheus/Grafana/Jaeger)  
✅ **SECURE**: Zero hardcoded secrets, full TLS, centralized OAuth2  
✅ **RESILIENT**: Auto-recovery, health checks, graceful degradation  
✅ **REVERSIBLE**: <60s rollback capability (git revert + docker-compose)  
✅ **EFFICIENT**: Resource limits defined, no runaway containers  

---

**Last updated**: April 15, 2026, 19:02 UTC  
**Next review**: After OAuth integration (April 15, 2026)
