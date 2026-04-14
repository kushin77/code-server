# oauth2-proxy Configuration Status

**Date**: April 14, 2026
**Status**: ⚠️ RESTART LOOP (Non-blocking - code-server accessible on port 8080)
**Priority**: P3 (Enhancement - not blocking core functionality)
**Owner**: @kushin77 (DevOps)

---

## Current State

### Container Status
```
NAME           STATUS                              PORTS
oauth2-proxy   Restarting (1) Less than a second   4180/tcp
```

### Root Cause
```
[main.go:54] invalid configuration:
  missing setting: cookie-secret
  provider missing setting: client-id
  missing setting: client-secret or client-secret-file
```

**Issue**: Container exits (code 1) because required Google OAuth credentials are not configured

### Impact Assessment

**Affected**: oauth2-proxy authentication layer
**Not Affected**:
- ✅ code-server application (accessible on http://192.168.168.31:8080)
- ✅ Caddy reverse proxy
- ✅ Ollama service
- ✅ Monitoring stack (Prometheus, Grafana, AlertManager)

**Workaround**: Access code-server DIRECTLY on port 8080 (bypasses oauth2-proxy)
- Works: `http://192.168.168.31:8080`
- Intended: `https://ide.kushnir.cloud` → Caddy → oauth2-proxy → code-server

---

## Configuration Requirements

### Missing Credentials (All EMPTY)

| Setting | Current | Required |
|---------|---------|----------|
| OAUTH2_PROXY_CLIENT_ID | `` | Google OAuth Client ID |
| OAUTH2_PROXY_CLIENT_SECRET | `` | Google OAuth Client Secret |
| OAUTH2_PROXY_COOKIE_SECRET | `` | Random 32+ byte key for session encryption |
| OAUTH2_PROXY_EMAIL_DOMAINS | `` | Domain whitelist (e.g., `kushnir.cloud`) |
| OAUTH2_PROXY_REDIRECT_URL | `https:///oauth2/callback` | `https://ide.kushnir.cloud/oauth2/callback` |

### Sources
1. **Google OAuth**: GCP Console → OAuth 2.0 Credentials
2. **Secrets**: Vault `nexusshield-prod/prod-portal-google-oauth-client-id`
3. **Cookie Secret**: `openssl rand -base64 32`

---

## Resolution Options

### Option 1: Defer (Current - Non-Blocking) ✅
**Status**: IMPLEMENTED
**Impact**: None - code-server accessible
**Timeline**: After Phase 3 governance (post-April 28)

```bash
# Workaround: Use direct port 8080
http://192.168.168.31:8080
```

### Option 2: Disable oauth2-proxy (Quick Fix)
**Impact**: Remove authentication layer
**Timeline**: ~15 minutes

```yaml
# In docker-compose.yml
oauth2-proxy:
  profiles: ["disabled"]  # Don't start
```

### Option 3: Configure with Valid Credentials (Proper Fix)
**Impact**: Full OAuth integration restored
**Timeline**: ~2 hours (including GCP setup)

```bash
# Steps:
1. Extract credentials from Vault (or GCP Console)
2. Update docker-compose.yml with credential envs
3. Update .env with OAUTH2_PROXY_* settings
4. Restart: docker-compose up -d oauth2-proxy
5. Verify: curl http://localhost:4180/ping
```

---

## Recommended Path Forward

### Short-term (Now - April 14)
- ✅ Document issue and workaround
- ✅ Ensure core functionality accessible
- ✅ No action required on oauth2-proxy

### Medium-term (After Phase 3 - April 28+)
- [ ] Extract OAuth credentials from Vault
- [ ] Implement proper credential management (Vault integration)
- [ ] Configure oauth2-proxy with credentials
- [ ] Test full OAuth flow
- [ ] Update CONTRIBUTING.md with OAuth setup

### Long-term (Phase 4+)
- [ ] Integrate OAuth2-Proxy with Argo Workflow
- [ ] Implement RBAC (Role-Based Access Control) via OAuth scopes
- [ ] Add team/org-level authentication

---

## How to Access code-server Now

### Working: Direct Port 8080
```bash
# Browser
http://192.168.168.31:8080

# SSH with port forwarding
ssh -L 8080:127.0.0.1:8080 akushnir@192.168.168.31

# curl
curl http://192.168.168.31:8080/api/health
```

### Not Working: Via HTTPS (needs oauth2-proxy)
```bash
❌ https://ide.kushnir.cloud  # Requires oauth2-proxy auth
✅ http://192.168.168.31:8080  # Direct access (workaround)
```

---

## Container Logs

```
[2026/04/14 15:25:44] [main.go:54] invalid configuration:
  missing setting: cookie-secret
  provider missing setting: client-id
  missing setting: client-secret or client-secret-file
```

**Resolution**: oauth2-proxy container will restart until credentials are provided.

---

## Files Affected

- `docker-compose.yml` - oauth2-proxy service definition
- `.env` - OAUTH2_PROXY_* environment variables
- `oauth2-proxy.cfg` - Configuration file (if mounted)

---

## Tracking

| Item | Status | Owner | Due |
|------|--------|-------|-----|
| Document issue | ✅ | @kushin77 | Apr 14 |
| Ensure core access | ✅ | @kushin77 | Apr 14 |
| Extract credentials | ⏳ | TBD | Post-Apr 28 |
| Implement fix | ⏳ | TBD | May 5 |
| Test OAuth flow | ⏳ | TBD | May 12 |

---

## See Also

- [ADR-003: Zero-Touch OAuth Integration](./ADR-003-OAUTH-INTEGRATION.md)
- [CONTRIBUTING.md - OAuth Setup](./CONTRIBUTING.md#oauth2-proxy-setup)
- [Google OAuth 2.0 Setup Guide](./OAUTH2-INTEGRATION-SUMMARY.md)

---

**Decision**: Non-blocking issue. Defer until Phase 4 (post-governance implementation).
**Next Review**: April 28, 2026 (Phase 3 completion)
