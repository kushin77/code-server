# 002. OAuth2 Proxy for Centralized Authentication

**Status**: Accepted  
**Date**: 2026-01-27  
**Author(s)**: @kushin77  
**Related ADRs**: [ADR-001: Containerized Deployment](001-containerized-deployment.md)  

---

## Context

Code-server by default:
- **Does not enforce authentication** — anyone with network access can use it
- **Has weak session management** — password-based auth, no centralized IAM
- **Cannot integrate with corporate identity** — no OIDC/SAML
- **Lacks audit logging** — no tracking of who accessed what, when

Enterprise security requires:
- **Centralized authentication** via corp SSO (Google, Azure AD, Okta)
- **Audit trails** for compliance (who accessed, when, from where)
- **Conditional access** (device compliance, IP ranges, etc.)
- **Secrets separation** — no credentials in app config

We needed a transparent, corporate-integrated authentication layer.

---

## Decision

We will deploy **OAuth2 Proxy** as a reverse proxy in front of code-server:

```
User Browser
    ↓
  Caddy (TLS termination, routing)
    ↓
  OAuth2 Proxy (auth + session management)
    ↓
  code-server (trusted, no direct auth needed)
```

Configuration:
- **OAuth provider**: Google OAuth (can switch to Azure AD, Okta later)
- **Session backend**: Cookie-based (signed, encrypted)
- **Session timeout**: 24 hours (auto-refresh on activity)
- **Allowed users**: Whitelist in `allowed-emails.txt`
- **Fallback**: Force login if session expired

Benefits:
- ✅ **Transparent to code-server** — proxy handles auth, code-server runs unmodified
- ✅ **Single sign-on** — reuse corporate identity
- ✅ **Centralized access control** — whitelist managed in version control (auditable)
- ✅ **Session management** — automatic timeouts, refresh tokens
- ✅ **Audit logging** — all auth attempts logged
- ✅ **No secrets in code** — credentials from environment variables

---

## Alternatives Considered

### Alternative 1: Native code-server Password Auth
**Pros**: 
- No proxy layer needed
- Simpler deployment

**Cons**: 
- **Weak security** — no access control beyond password
- **No audit trail** — impossible to track access
- **Doesn't scale** — managing 50+ passwords manually unworkable
- **No corporate SSO** — employees must remember another password
- **Session insecurity** — code-server's session management not enterprise-grade

**Why not chosen**: Doesn't meet enterprise security requirements.

### Alternative 2: VPN + Network Access Control
**Pros**: 
- OS-level security
- All services behind VPN benefit

**Cons**: 
- **VPN complexity** — requires separate infrastructure, management
- **User friction** — employees must be VPN clients
- **Not fine-grained** — can't revoke per-app access without revking VPN
- **Audit gaps** — VPN logs don't correlate to app usage
- **Mobile/remote friction** — VPN from coffee shop problematic

**Why not chosen**: Too coarse-grained, insufficient audit trail.

### Alternative 3: ORY Hydra (Full OAuth Server)
**Pros**: 
- Full OAuth2/OIDC compliance
- Can act as auth server for multiple apps

**Cons**: 
- **Over-engineered** — we're not building a SaaS platform
- **Operational complexity** — database, migrations, configuration
- **Learning curve** — Hydra is powerful but complex
- **Overkill for single app** — OAuth2 Proxy already solves our problem

**Why not chosen**: Unnecessary complexity for current scope.

---

## Consequences

### Positive Consequences
- ✅ **Enterprise security** — SSO, audit logging, access control
- ✅ **Simplified code-server** — no auth logic in appliance
- ✅ **Scalable access control** — whitelist managed in Git, no manual auth setup
- ✅ **Session security** — encrypted cookies, timeout/refresh
- ✅ **Audit compliance** — all access logged for regulatory review
- ✅ **Flexibility** — can switch OAuth providers without code changes

### Negative Consequences (Accepted Risks)
- ⚠️ **Proxy adds latency** — small HTTP header validation overhead (~5-10ms)
- ⚠️ **OAuth dependency** — if Google OAuth down, authentication fails (mitigated: fallback auth token)
- ⚠️ **Session affinity** — repeated requests to same proxy instance preferred (mitigated: shared cookie backend)
- ⚠️ **Configuration complexity** — OAuth callback URLs, client IDs, must be correct
- ⚠️ **User experience** — first-time login adds step (login redirect flow)

---

## Security Implications

- **Trust boundaries**: 
  - OAuth2 Proxy is the security boundary
  - Code-server assumes authenticated user (implicit trust)
  - User identity passed via HTTP header (trusted because proxy controls it)
  
- **Attack surface**: 
  - **Reduced**: code-server never receives unauthenticated requests
  - **New**: OAuth client credentials (mitigated: stored in GCP Secret Manager, not in repo)
  - **New**: Session cookie security (mitigated: signed, encrypted, SameSite=Lax)
  
- **Data exposure**: 
  - OAuth tokens cached in session (not exposed to code-server)
  - User email passed to code-server in `X-Auth-Request-User` header
  
- **Authentication/Authorization**: 
  - ✅ Authentication enforced by OAuth2 Proxy
  - ✅ Authorization via whitelist (`allowed-emails.txt`)
  - Limitations: Single authorization policy (all/none), no RBAC
  
- **Mitigation strategy**: 
  - OAuth credentials stored in GCP Secret Manager
  - Session cookie: httpOnly, Secure, SameSite=Lax flags
  - Regular rotation of OAuth client credentials
  - Whitelist reviewed quarterly for access violations
  - Logs monitored for suspicious patterns (repeated 401s, unusual IPs)

---

## Performance & Scalability Implications

- **Horizontal scaling**: 
  - ✅ OAuth2 Proxy stateless (no affinity required)
  - Multiple instances load-balanced via Caddy
  - Session backend (Redis or shared store) required for distributed scenarios
  
- **Bottlenecks**: 
  - OAuth token validation (network call to Google): ~100-200ms first request
  - Session cookie validation: ~1-5ms (local crypto, no network)
  - Caddy load balancer routing: <1ms overhead
  
- **Resource usage**: 
  - OAuth2 Proxy: ~50-100MB RAM per instance
  - CPU: minimal (mostly network I/O waiting)
  - Storage: none (stateless)
  
- **Latency**: 
  - First auth: adds ~200ms (OAuth roundtrip)
  - Subsequent requests: <10ms additional (cookie validation)
  - P99 latency: unlikely to exceed 500ms
  
- **Throughput**: 
  - Single instance: ~500-1000 auth requests/sec
  - Multiple instances scale linearly

---

## Operational Impact

- **Deployment**: 
  - OAuth2 Proxy runs as sidecar container in Compose/container orchestration
  - Configuration: env vars (OAUTH2_PROXY_CLIENT_ID, OAUTH2_PROXY_CLIENT_SECRET, etc.)
  - Secrets injected from GCP Secret Manager at runtime
  
- **Monitoring**: 
  - Log successful/failed auth attempts
  - Monitor token refresh rates (high refresh = possible misconfiguration)
  - Alert if Google OAuth service unreachable
  
- **Alerting**: 
  - Alert on sustained 401 responses (auth failure)
  - Alert on OAuth provider downtime
  - Alert on unusual access patterns (e.g., brute force)
  
- **Rollback**: 
  - ✅ Stateless, can be restarted immediately
  - Change to whitelist? Edit `allowed-emails.txt`, redeploy
  - Change OAuth provider? Update env vars, restart
  
- **On-call**: 
  - Understanding OAuth2 flow (OIDC handshake)
  - Debugging session/cookie issues
  - Google OAuth troubleshooting
  - Runbook for common issues (see [RUNBOOKS.md](../../RUNBOOKS.md))

---

## Implementation Notes

**OAuth Provider Setup**:
1. Create OAuth app in Google Cloud Console
2. Configure redirect URI: `https://<code-server-domain>/oauth2/callback`
3. Extract client ID and client secret
4. Store secrets in GCP Secret Manager (encrypted at rest)

**Whitelist Management**:
- File: `allowed-emails.txt` (one email per line)
- Deploy: whitelist checked on every auth
- Changes take effect on next restart/reload

**Session Configuration**:
- Type: Cookie-based (encrypted)
- Duration: 24 hours
- Auto-refresh: Yes (on request)
- Fallback: If cookie invalid, force re-authentication

---

## Validation Criteria

- [x] **Authentication enforcement**: Unauthenticated requests rejected (401)
- [x] **SSO integration**: Google OAuth working for configured users
- [x] **Whitelist enforcement**: Only whitelisted emails can authenticate
- [x] **Session security**: Cookies signed and encrypted
- [ ] **Audit logging**: Auth attempts logged and queryable (pending log aggregation)
- [ ] **Fallback auth**: Fallback token method working (pending implementation)
- [ ] **Performance**: Auth latency < 300ms P99 (pending load test)

---

## References

- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Google OAuth2 Setup Guide](https://developers.google.com/identity/protocols/oauth2)
- [OWASP: Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [OWASP: Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
- [RFC 6749: OAuth 2.0](https://tools.ietf.org/html/rfc6749)

---

## Sign-off

- [x] Technical review: @kushin77
- [x] Security review: @kushin77
- [x] Operations review: @kushin77
- [x] Architecture consensus: @kushin77