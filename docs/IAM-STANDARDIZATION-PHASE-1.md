# IAM Standardization — Phase 1 Design

**Status**: Design Ready - READY FOR IMPLEMENTATION  
**Priority**: P2 (#388)  
**Owner**: Security Team  
**Timeline**: May 1-5, 2026 (parallel track)  

---

## Objective

Standardize authentication and authorization across all services using:
- Single OAuth2 entry point
- Consistent RBAC framework
- Audit logging for all auth events
- Support for multiple identity providers (Google, GitHub, LDAP)

---

## OAuth2 Architecture

### Current State
- code-server: oauth2-proxy (Google OIDC)
- Prometheus: No auth
- Grafana: Local user database
- Loki: No auth
- Portal (Appsmith): TBD

**Problem**: Inconsistent auth across services, scattered credentials

### Target State (Phase 1)

```
┌─────────────────────────────────────────────────────────────┐
│  Internet / VPN Clients                                     │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTPS
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Caddy (TLS termination + reverse proxy)                    │
└────┬────────────┬────────────────┬────────────┬─────────────┘
     │            │                │            │
     │ /auth      │ /api           │ /dash      │ /logs
     │            │                │            │
┌────▼───────┐  ┌─▼──────────┐  ┌─▼──────┐  ┌─▼──────┐
│ oauth2-     │  │ code-      │  │Grafana │  │ Loki  │
│ proxy       │  │ server     │  │oauth2- │  │oauth2-│
│ :4180      │  │ :8080      │  │proxy   │  │proxy  │
└────────────┘  └────────────┘  │:4181  │  │:4182 │
                                 └───────┘  └──────┘
                                     │          │
                                     └──────────┘
                                          │
                                    PostgreSQL
                                    (session DB)
```

### OAuth2-proxy Configuration

```yaml
# Port: 4180 (main oauth2-proxy)
auth_email_domains:
  - example.com
  - gmail.com

oauth_provider: oidc
oidc_issuer_url: https://accounts.google.com
client_id: ${GOOGLE_CLIENT_ID}
client_secret: ${GOOGLE_CLIENT_SECRET}

# Cookie security
cookie_name: _oauth2_proxy
cookie_secure: true
cookie_httponly: true
cookie_samesite: Lax
cookie_secret: ${COOKIE_SECRET}
cookie_expire: 86400  # 24 hours (sliding)

# Session backend
session_store_type: redis
redis_connection_url: redis://redis:6379/0

# Rate limiting
ratelimit_enabled: true
ratelimit_rate: 10/m          # 10 req/min global
ratelimit_burst: 20
```

### Service-Specific oauth2-proxy Instances

```yaml
# oauth2-proxy for Grafana (port 4181)
oauth2-proxy-grafana:
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
  ports:
    - "4181:4180"
  environment:
    OAUTH2_PROXY_CLIENT_ID: ${GRAFANA_OAUTH_CLIENT_ID}
    OAUTH2_PROXY_REDIRECT_URL: https://grafana.example.com/oauth2/callback
    OAUTH2_PROXY_REDIS_CONNECTION_URL: redis://redis:6379/1  # DB 1
    OAUTH2_PROXY_SCOPE: "openid email profile"
    OAUTH2_PROXY_OIDC_ISSUER_URL: https://accounts.google.com
    OAUTH2_PROXY_RATELIMIT_RATE: 5/m    # Stricter for Grafana
  volumes:
    - ./config/oauth2-proxy-grafana.cfg:/etc/oauth2-proxy/oauth2-proxy.cfg:ro

# oauth2-proxy for Loki (port 4182)
oauth2-proxy-loki:
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
  ports:
    - "4182:4180"
  environment:
    OAUTH2_PROXY_CLIENT_ID: ${LOKI_OAUTH_CLIENT_ID}
    OAUTH2_PROXY_REDIRECT_URL: https://loki.example.com/oauth2/callback
    OAUTH2_PROXY_REDIS_CONNECTION_URL: redis://redis:6379/2  # DB 2
    OAUTH2_PROXY_RATELIMIT_RATE: 5/m
  volumes:
    - ./config/oauth2-proxy-loki.cfg:/etc/oauth2-proxy/oauth2-proxy.cfg:ro
```

---

## RBAC Framework

### Roles Definition

| Role | Scope | Permissions | Use Cases |
|------|-------|---|---|
| **admin** | All services | All operations | Operators, SREs, team lead |
| **viewer** | Most services | Read-only + limited writes | DevOps engineers, developers |
| **readonly** | Observability | Metrics only | On-call engineers |
| **developer** | code-server | Workspace access | Engineering team |
| **audit** | All | Read audit logs | Compliance auditors |

### RBAC Implementation

```yaml
# Grafana RBAC (via OAuth2-proxy headers)
oauth2_proxy:
  headers:
    X-Remote-User: ${oidc_subject}
    X-Remote-Email: ${oidc_email}
    X-Auth-Request-Groups: ${oidc_groups}

# Grafana role mapping (via provisioning)
provisioning/role-mappings.yaml:
  - email: "alice@example.com"
    grafana_role: Admin
  - email: "bob@example.com"
    grafana_role: Viewer
  - email: "team@example.com"
    grafana_role: Viewer
    folder_access:
      - name: "Dashboards"
        permission: View

# Loki label-based access control
loki:
  auth:
    require_auth: true
    allowed_users:
      - "admin"
      - "viewer"
    label_filters:
      viewer:
        - severity: "info|warn|error"          # Exclude debug
        - source: "-sensitive"                 # Exclude sensitive logs
      readonly:
        - source: "prometheus|alertmanager"    # Metrics only

# code-server OAuth2 scope
oauth2_proxy:
  client_scopes:
    - openid
    - email
    - profile
    - groups  # LDAP groups for team assignment
```

---

## Audit Logging

### Events to Log

1. **Authentication Events**:
   - Login success/failure
   - Logout
   - Token refresh
   - MFA challenge

2. **Authorization Events**:
   - Permission check (allow/deny)
   - Role change
   - Group membership change

3. **Session Events**:
   - Session creation
   - Session timeout
   - Session revocation

### Log Format

```json
{
  "timestamp": "2026-05-01T14:23:45.123Z",
  "event_type": "auth.login_success",
  "user_id": "<USER_ID>",
  "email": "alice@example.com",
  "provider": "google",
  "ip_address": "192.168.168.100",
  "user_agent": "Mozilla/5.0...",
  "groups": ["team-eng", "team-platform"],
  "mfa_verified": true,
  "session_id": "<SESSION_ID>",
  "duration_ms": 234
}
```

### Prometheus Metrics

```
oauth2_proxy_authentication_attempts_total{provider="google",result="success"} 1234
oauth2_proxy_authentication_attempts_total{provider="google",result="failure"} 45
oauth2_proxy_authorization_checks_total{service="grafana",result="allow"} 9876
oauth2_proxy_authorization_checks_total{service="grafana",result="deny"} 12
oauth2_proxy_session_active{provider="google"} 89
oauth2_proxy_session_refresh_total{result="success"} 567
oauth2_proxy_rate_limit_exceeded_total{service="loki"} 8
```

---

## Multi-Provider Support (Phase 2)

### Primary: Google OIDC
```yaml
oidc_issuer_url: https://accounts.google.com
oidc_client_id: ${GOOGLE_CLIENT_ID}
oidc_client_secret: ${GOOGLE_CLIENT_SECRET}
```

### Fallback 1: GitHub OAuth
```yaml
provider: github
client_id: ${GITHUB_CLIENT_ID}
client_secret: ${GITHUB_CLIENT_SECRET}
scope: "user:email read:org"
```

### Fallback 2: LDAP (Enterprise)
```yaml
ldap_url: ldaps://ldap.example.com:636
ldap_bind_dn: cn=admin,dc=example,dc=com
ldap_user_search_base: ou=users,dc=example,dc=com
ldap_group_search_base: ou=groups,dc=example,dc=com
```

---

## Implementation Phases

### Phase 1 (This Week: May 1-5)
- [x] Design oauth2-proxy architecture
- [ ] Configure Google OIDC
- [ ] Deploy oauth2-proxy for code-server
- [ ] Setup Redis session backend
- [ ] Define RBAC framework
- [ ] Create audit logging (Loki)
- [ ] Document procedures

### Phase 2 (Week 3: May 6-12)
- [ ] Deploy oauth2-proxy for Grafana
- [ ] Implement Grafana RBAC
- [ ] Deploy oauth2-proxy for Loki
- [ ] Implement Loki label-based filtering
- [ ] Team training

### Phase 3 (Week 4: May 13-19)
- [ ] Add GitHub OAuth fallback
- [ ] LDAP integration (optional)
- [ ] MFA support (TOTP)
- [ ] Session management UI

---

## Success Criteria

- [ ] All services behind oauth2-proxy
- [ ] RBAC enforced consistently across all services
- [ ] Audit logs complete and queryable
- [ ] <5% false positive rate for authorization checks
- [ ] <100ms auth latency (p99)
- [ ] Team fully trained (100%)
- [ ] Zero unplanned auth outages

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|---|---|---|
| Redis session loss | LOW | HIGH | RDB persistence + monitoring |
| OAuth2 provider outage | MEDIUM | MEDIUM | Graceful degradation + token caching |
| Rate limiting too strict | MEDIUM | MEDIUM | Tunable limits + monitoring |
| Group membership sync lag | MEDIUM | LOW | Cache invalidation on login |

---

**Status**: Design approved  
**Next**: Phase 1 implementation (May 1-5)  
**Owner**: Security Team
