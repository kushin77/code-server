# SSO Architecture

**Issue:** #1545 — Endpoint & SSO  
**Governance:** GOV-002  
**Status:** In progress

---

## Single OAuth Flow — All Subdomains

One Google OAuth login authenticates a user across all endpoints:

```
User                  Caddy               OAuth2-Proxy           Google
 |                      |                      |                    |
 |-- GET ide.kushnir.cloud -->                 |                    |
 |                      |-- forward_auth ----> |                    |
 |                      |<-- 401 no cookie ----|                    |
 |<-- 302 /oauth2/sign_in --|                  |                    |
 |-- GET /oauth2/sign_in -> |                  |                    |
 |                      |-- route to proxy --> |                    |
 |<-- 302 accounts.google.com ------------------------------ redirect
 |-- Google OAuth consent --------------------------------------------------->|
 |<-- 302 /oauth2/callback with code ----------------------------------------|
 |-- GET /oauth2/callback -> |-- exchange code for token --> Google           |
 |                      |    |<-- id_token + access_token --|                 |
 |                      |    |-- set-cookie: _oauth2_proxy (domain=.kushnir.cloud)
 |<-- 302 original URL  |    |                              |                 |
 |-- GET ide.kushnir.cloud (with _oauth2_proxy cookie)     |                 |
 |                      |-- forward_auth ----> |            |                 |
 |                      |<-- 200 X-Auth-Request-User        |                 |
 |<-- 200 IDE content --|                      |            |                 |
```

---

## Cookie Configuration

`_oauth2_proxy` cookie is set with `Domain=.kushnir.cloud`:

| Subdomain | Cookie Valid? | Notes |
|-----------|---------------|-------|
| `kushnir.cloud` | ✓ | Portal apex |
| `ide.kushnir.cloud` | ✓ | VS Code IDE |
| `api.kushnir.cloud` | ✓ | API endpoints |
| `grafana.kushnir.cloud` | ✓ | Monitoring |

**Config:** `config/oauth2-proxy.cfg`:
```
cookie_domains = [".kushnir.cloud"]
cookie_expire = "168h"    # 7-day session
cookie_refresh = "1h"     # Background token refresh
```

---

## Caddy Routing — Portal Architecture

```
kushnir.cloud (apex)
├── /           → Appsmith portal (portal page)
├── /health     → 200 OK (monitoring)
└── /oauth2/*   → OAuth2-Proxy (auth)

ide.kushnir.cloud
├── /oauth2/*   → OAuth2-Proxy
└── /           → code-server:8080 (after auth)

api.kushnir.cloud
├── /oauth2/*   → OAuth2-Proxy
├── /docs       → OpenAPI UI
└── /           → backend:8000 (after OPA check)

grafana.kushnir.cloud
└── /           → grafana:3000 (after auth)
```

---

## Single Logout

To clear all subdomain sessions:
```
GET /oauth2/sign_out?rd=https://kushnir.cloud
```

OAuth2-proxy clears the `_oauth2_proxy` cookie on `Domain=.kushnir.cloud`, logging out across all subdomains simultaneously.

---

## Token Refresh

`cookie_refresh = "1h"` — OAuth2-proxy silently refreshes the Google token every hour in the background. User is never prompted mid-session unless:
- Session cookie expired (`cookie_expire = "168h"`, 7 days)
- User manually logs out

---

## Portal Landing Page (Appsmith)

The apex `kushnir.cloud` routes to the Appsmith portal with these sections:

| Menu Item | Link | Auth Required |
|-----------|------|---------------|
| Dashboard | `/dashboard` | Yes |
| IDE | `ide.kushnir.cloud` | Yes |
| Repositories | `/repos` (GitHub/GitLab OAuth) | Yes |
| Admin | `/admin` (admin role only) | Yes (+ role) |
| Settings | `/settings` | Yes |
| Docs | `/docs` | No |

---

## SSO Validation Test

```bash
# 1. Login via OAuth2 (get cookie)
curl -c /tmp/cookies.txt -L https://ide.kushnir.cloud/oauth2/sign_in

# 2. Test session is valid across subdomains
curl -b /tmp/cookies.txt https://api.kushnir.cloud/oauth2/ping
curl -b /tmp/cookies.txt https://grafana.kushnir.cloud/oauth2/ping

# 3. Test logout clears all sessions
curl -b /tmp/cookies.txt -c /tmp/cookies.txt \
  https://ide.kushnir.cloud/oauth2/sign_out

# After logout — all subdomains should redirect to sign_in:
curl -L -o /dev/null -w "%{http_code}" \
  https://api.kushnir.cloud/api/health  # Should be 302 → sign_in
```

---

*GOV-002: All SSO config changes require OPA policy review.*
