# P0 #414: Code-Server & Loki Authentication Hardening
# ═════════════════════════════════════════════════════════════════════════════

## CRITICAL AUTHENTICATION & AUTHORIZATION REQUIREMENT

**Status**: ✅ PLANNING COMPLETE | ⏳ IMPLEMENTATION REQUIRED  
**Date**: April 15, 2026  
**Severity**: P0 (Critical - blocks production certification)  
**Impact**: Unauthorized access to code editor and logs

---

## Executive Summary

Both **code-server** and **Loki** currently lack proper authentication and authorization:

### Current State (Unacceptable for Production)
- ❌ code-server: Direct access (no auth gate)
- ❌ Loki: Direct access on port 3100 (no auth gate)
- ❌ No OAuth2/OIDC integration
- ❌ No RBAC (role-based access control)
- ❌ No JWT validation
- ❌ No API key authentication
- ❌ No rate limiting/DDoS protection
- ❌ No session management

### Target State (Production-Grade)
- ✅ code-server: OAuth2-proxy + OIDC (Google)
- ✅ Loki: OAuth2-proxy + OIDC + Grafana integration
- ✅ RBAC with policy-based access
- ✅ JWT token validation
- ✅ API key authentication for services
- ✅ Rate limiting per user/IP
- ✅ Session management with timeouts
- ✅ Audit logging for all authentication events

---

## Current Architecture Gaps

```
┌─────────────────────────────────────────────────────┐
│  CURRENT (INSECURE)                                 │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Internet → code-server:8080 (NO AUTH)              │
│             ↓                                       │
│             No session validation                   │
│             No OAuth2 gating                        │
│                                                      │
│  Internet → Loki:3100 (NO AUTH)                     │
│             ↓                                       │
│             Direct log access                       │
│             No RBAC                                 │
│                                                      │
│  Grafana → Loki (NO TLS, NO AUTH)                   │
│                                                      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  TARGET (SECURE)                                    │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Internet → Caddy (TLS)                             │
│             ↓ (HTTPS only, no HTTP)                │
│             ↓                                       │
│  Google OIDC Check → oauth2-proxy:4180              │
│             ↓ (Token validation)                    │
│             ↓                                       │
│  Valid Session → code-server:8080                   │
│  (Rate-limited, audited)                            │
│                                                      │
│  Internet → Caddy (TLS)                             │
│             ↓                                       │
│  Google OIDC Check → oauth2-proxy:4181              │
│             ↓                                       │
│  RBAC Policy Check → Loki:3100                      │
│  (admin/viewer/readonly roles)                      │
│             ↓                                       │
│             Rate-limited queries                    │
│             Audited log access                      │
│                                                      │
│  Grafana → oauth2-proxy:4181 (TLS + JWT)            │
│             ↓ (Internal API calls)                  │
│             ↓                                       │
│             Loki:3100 (API key auth)                │
│                                                      │
└─────────────────────────────────────────────────────┘
```

---

## Phase 1: Code-Server Authentication (THIS WEEK) 🔐

### 1.1 OAuth2-Proxy Configuration for code-server

**Objective**: Gate code-server access with Google OAuth2  
**Timeline**: 2 hours  
**Owner**: Infrastructure  

#### Docker Compose Service
```yaml
# docker-compose.yml - code-server auth proxy

oauth2-proxy-code-server:
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
  container_name: oauth2-proxy-code-server
  ports:
    - "4180:4180"
  environment:
    OAUTH2_PROXY_PROVIDER: "google"
    OAUTH2_PROXY_CLIENT_ID: "${GOOGLE_OAUTH2_CLIENT_ID}"
    OAUTH2_PROXY_CLIENT_SECRET: "${GOOGLE_OAUTH2_CLIENT_SECRET}"
    OAUTH2_PROXY_COOKIE_SECRET: "${OAUTH2_PROXY_COOKIE_SECRET}"  # 16-byte hex
    OAUTH2_PROXY_REDIRECT_URL: "https://code-server.code-server-enterprise.local:8080/oauth2/callback"
    
    # Security hardening
    OAUTH2_PROXY_COOKIE_SECURE: "true"           # HTTPS only
    OAUTH2_PROXY_COOKIE_HTTPONLY: "true"         # Block JS access
    OAUTH2_PROXY_COOKIE_SAMESITE: "Lax"          # CSRF protection
    OAUTH2_PROXY_COOKIE_REFRESH: "1h"            # Auto-refresh tokens
    OAUTH2_PROXY_COOKIE_EXPIRE: "24h"            # Session timeout
    OAUTH2_PROXY_SESSION_STORE_TYPE: "redis"    # Session persistence
    OAUTH2_PROXY_SESSION_REDIS_CONNECTION_URL: "redis://redis:6379"
    
    # Allowed users (whitelist)
    OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE: "/config/allowed-emails.txt"
    
    # Rate limiting
    OAUTH2_PROXY_RATE_LIMIT: "10"                # 10 requests per second
    OAUTH2_PROXY_RATE_LIMIT_BURST: "20"          # Burst up to 20
    
    # Logging
    OAUTH2_PROXY_STANDARD_LOGGING: "true"
    OAUTH2_PROXY_REQUEST_LOGGING: "true"
    OAUTH2_PROXY_LOG_LEVEL: "info"
    
    # OIDC settings
    OAUTH2_PROXY_SCOPE: "openid email profile"
    OAUTH2_PROXY_GROUPS_CLAIM: "groups"
    OAUTH2_PROXY_OIDC_ISSUER_URL: "https://accounts.google.com"
    
  volumes:
    - ./config/allowed-emails.txt:/config/allowed-emails.txt:ro
  networks:
    - code-server-network
  depends_on:
    - redis
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4180/ping"]
    interval: 10s
    timeout: 5s
    retries: 3

# Update code-server to only listen on localhost
code-server:
  image: codercom/code-server:4.115.0
  container_name: code-server
  ports:
    - "127.0.0.1:8080:8080"  # ← Only localhost, not public!
  environment:
    PASSWORD: "${CODE_SERVER_PASSWORD}"
    SUDO_PASSWORD: "${CODE_SERVER_SUDO_PASSWORD}"
    CODE_SERVER_BIND_ADDR: "0.0.0.0:8080"
  networks:
    - code-server-network
  # ... rest of config
```

#### Caddy Configuration
```caddyfile
# Caddyfile - code-server endpoint

code-server.code-server-enterprise.local {
  # Redirect HTTP → HTTPS
  http:// {
    redir https://{host}{uri} permanent
  }

  # TLS certificate
  tls /etc/caddy/certs/code-server.crt /etc/caddy/certs/code-server.key

  # Route through oauth2-proxy
  reverse_proxy localhost:4180 {
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
    
    # Session handling
    header_up Cookie {http.request.header.Cookie}
  }

  # Logging
  log {
    output file /var/log/caddy/code-server.log {
      roll_size 10mb
      roll_keep 10
      roll_keep_for 720h
    }
    format json {
      time_format iso8601
      level_format "⚠️ {level}"
    }
  }
}
```

### 1.2 Allowed Users Configuration

**File**: `allowed-emails.txt`
```
# Whitelist of users allowed to access code-server
# One email per line

kushnir.alex@gmail.com
admin@code-server-enterprise.local
dev-team@code-server-enterprise.local
```

### 1.3 Session Management (Redis)

```bash
# Test Redis session storage
redis-cli -h redis -p 6379

# Check active sessions
> KEYS "oauth2-proxy_*"
> TTL "oauth2-proxy_<session-id>"

# Monitor session creation
> MONITOR

# Clear old sessions
> FLUSHDB ASYNC  # ⚠️ Careful! Only on test systems
```

### 1.4 Validation Checks

```bash
# 1. Verify OAuth2-proxy is running
docker-compose ps oauth2-proxy-code-server

# 2. Test health check
curl -v http://localhost:4180/ping

# 3. Test callback endpoint
curl -v -L "http://localhost:4180/oauth2/callback?code=test&state=test"

# 4. Test code-server direct access is blocked
curl -v http://localhost:8080/ 
# Should return 502 (no auth header)

# 5. Monitor logs
docker-compose logs -f oauth2-proxy-code-server

# 6. Verify session storage
redis-cli -h redis KEYS "oauth2-proxy_*" | wc -l
# Should show active sessions
```

---

## Phase 2: Loki Authentication & RBAC (THIS WEEK) 🔐

### 2.1 OAuth2-Proxy for Loki

**Objective**: Gate Loki queries with authentication and RBAC  
**Timeline**: 2 hours  
**Owner**: Infrastructure  

#### Docker Compose Service
```yaml
# docker-compose.yml - Loki auth proxy

oauth2-proxy-loki:
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
  container_name: oauth2-proxy-loki
  ports:
    - "4181:4181"
  environment:
    OAUTH2_PROXY_PROVIDER: "google"
    OAUTH2_PROXY_CLIENT_ID: "${GOOGLE_OAUTH2_CLIENT_ID}"
    OAUTH2_PROXY_CLIENT_SECRET: "${GOOGLE_OAUTH2_CLIENT_SECRET}"
    OAUTH2_PROXY_COOKIE_SECRET: "${OAUTH2_PROXY_COOKIE_SECRET}"
    OAUTH2_PROXY_REDIRECT_URL: "https://logs.code-server-enterprise.local/oauth2/callback"
    
    # Security settings (same as code-server)
    OAUTH2_PROXY_COOKIE_SECURE: "true"
    OAUTH2_PROXY_COOKIE_HTTPONLY: "true"
    OAUTH2_PROXY_COOKIE_SAMESITE: "Lax"
    OAUTH2_PROXY_SESSION_STORE_TYPE: "redis"
    OAUTH2_PROXY_SESSION_REDIS_CONNECTION_URL: "redis://redis:6379/1"
    
    # RBAC: Allowed groups
    OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE: "/config/loki-access.txt"
    OAUTH2_PROXY_GROUPS_CLAIM: "roles"
    
    # Rate limiting (stricter for log queries)
    OAUTH2_PROXY_RATE_LIMIT: "5"
    OAUTH2_PROXY_RATE_LIMIT_BURST: "10"
    
  volumes:
    - ./config/loki-access.txt:/config/loki-access.txt:ro
  networks:
    - code-server-network
  depends_on:
    - redis
    - loki
```

### 2.2 Loki RBAC Configuration

**File**: `loki-access.txt`
```
# Loki access control list
# Format: email,role
# Roles: admin (all labels), viewer (non-sensitive), readonly (metrics only)

kushnir.alex@gmail.com,admin
admin@code-server-enterprise.local,admin
prometheus@code-server-enterprise.local,readonly
grafana@code-server-enterprise.local,viewer
dev-team@code-server-enterprise.local,viewer
```

### 2.3 Loki-Level Access Control

**File**: `config/loki-rbac.yaml`
```yaml
# Loki role-based access control

roles:
  admin:
    permissions:
      - logs:read
      - logs:write
      - logs:delete
      - stats:read
      - alerts:manage
    label_restrictions: []  # Can see all labels
    
  viewer:
    permissions:
      - logs:read
      - stats:read
    label_restrictions:
      - source=~"(code-server|caddy|oauth2-proxy|prometheus|grafana)"  # Can only see these
      - exclude_patterns: ["password", "secret", "token"]  # Hide sensitive data
      
  readonly:
    permissions:
      - logs:read
    label_restrictions:
      - source=~"(prometheus|alertmanager)"  # Can only see metrics
      - exclude_patterns: ["*"]  # Hide all custom logs

# Query rate limiting per role
rate_limits:
  admin:
    queries_per_minute: 1000
    bytes_per_second: 100000
  viewer:
    queries_per_minute: 100
    bytes_per_second: 10000
  readonly:
    queries_per_minute: 50
    bytes_per_second: 5000
```

### 2.4 Caddy Configuration for Loki

```caddyfile
# Caddyfile - Loki endpoint

logs.code-server-enterprise.local {
  # Redirect HTTP → HTTPS
  http:// {
    redir https://{host}{uri} permanent
  }

  # TLS
  tls /etc/caddy/certs/loki.crt /etc/caddy/certs/loki.key

  # Route through oauth2-proxy
  reverse_proxy localhost:4181 {
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }

  # Logging
  log {
    output file /var/log/caddy/loki.log {
      roll_size 10mb
      roll_keep 10
      roll_keep_for 720h
    }
  }
}
```

---

## Phase 3: Grafana-to-Loki Integration (THIS WEEK) 🔐

### 3.1 Grafana Service Account for Loki

```bash
# 1. Create API key in Grafana
# UI: Configuration → API Keys → New API Key
# Name: "loki-datasource"
# Role: "Editor"
# Expiration: 90 days

# 2. Store in Vault
vault kv put kv/grafana/loki-api-key \
  api_token="eyJrIjoiT0tTOC..." \
  created_at="2026-04-15T00:00:00Z" \
  expires_at="2026-07-14T00:00:00Z"

# 3. Configure Loki datasource in Grafana
```

**Grafana Loki Datasource Configuration**:
```yaml
# grafana-datasources.yaml

apiVersion: 1
datasources:
  - name: Loki
    type: loki
    url: https://logs.code-server-enterprise.local
    access: proxy
    basicAuth: false
    
    # OAuth2 via api key
    secureJsonData:
      httpHeaderValue1: "Bearer eyJrIjoiT0tTOC..."  # From Vault
    
    jsonData:
      httpHeaderName1: "Authorization"
      tlsSkipVerify: false
      tlsCertFile: "/etc/grafana/certs/loki-ca.crt"
      
    # Logging limits
    maxQueryTime: "1h"
    maxConcurrentRequests: 10
```

### 3.2 Loki Service Account for Prometheus

```bash
# Create API key for Prometheus to write logs
vault kv put kv/loki/prometheus-push-key \
  api_token="$(openssl rand -hex 32)" \
  created_at="2026-04-15T00:00:00Z"
```

---

## Phase 4: Audit Logging (COMPLIANCE) 📊

### 4.1 Authentication Events to Loki

```yaml
# promtail-auth.yaml - Ship auth events to Loki

scrape_configs:
  - job_name: code-server-auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: code-server_auth
          service: code-server
    pipeline_stages:
      - json:
          expressions:
            timestamp: .timestamp
            email: .email
            action: .action
            result: .result
            ip: .client_ip
      - match:
          selector: '{job="code-server_auth"}'
          stages:
            - timestamp:
                format: "2006-01-02T15:04:05Z07:00"
            - labels:
                action:
                result:
                ip:

  - job_name: loki-auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: loki_auth
          service: loki
    pipeline_stages:
      - json:
          expressions:
            timestamp: .timestamp
            user: .user
            query: .query
            status_code: .status_code
            duration_ms: .duration_ms
```

### 4.2 Prometheus Metrics for Authentication

```yaml
# prometheus.yml - Auth metrics

scrape_configs:
  - job_name: "oauth2-proxy"
    static_configs:
      - targets: ["localhost:4180", "localhost:4181"]
    metrics_path: "/metrics"
```

**Key Metrics to Monitor**:
```
oauth2_proxy_authentication_attempts_total{email="..."}
oauth2_proxy_authentication_failures_total{email="...", reason="..."}
oauth2_proxy_session_refresh_total
oauth2_proxy_session_cookie_expires
oauth2_proxy_rate_limit_exceeded_total
```

---

## Phase 5: Testing & Validation (THIS WEEK) ✅

### 5.1 Test Matrix

| Test | Expected Result | Status |
|------|-----------------|--------|
| No auth → code-server (direct) | 502/403 | ⏳ TODO |
| No auth → Loki (direct) | 502/403 | ⏳ TODO |
| Invalid OAuth token → code-server | Redirect to Google | ⏳ TODO |
| Valid OAuth token → code-server | Access granted + session | ⏳ TODO |
| Expired session → code-server | Re-authenticate | ⏳ TODO |
| Viewer role → Loki | Can read non-sensitive logs | ⏳ TODO |
| Readonly role → Loki | Can read metrics only | ⏳ TODO |
| Admin role → Loki | Full access | ⏳ TODO |
| Rate limit → Query Loki | 429 (Too Many Requests) | ⏳ TODO |
| TLS certificate invalid | SSL error | ⏳ TODO |

### 5.2 Test Commands

```bash
# 1. Test oauth2-proxy health
curl -v http://localhost:4180/ping
curl -v http://localhost:4181/ping

# 2. Test code-server direct access is blocked
curl -v http://localhost:8080/
# Expected: Connection refused or 502

# 3. Test through oauth2-proxy (requires valid Google account)
curl -v -L "https://code-server.code-server-enterprise.local" \
  --insecure  # For testing only, use proper cert in production

# 4. Test session cookie
curl -v -b "oauth2proxy_csrf=test" \
  "https://code-server.code-server-enterprise.local/oauth2/auth"

# 5. Monitor Redis sessions
redis-cli -h redis KEYS "oauth2-proxy_*" | wc -l

# 6. Test Loki access logs
curl -v "https://logs.code-server-enterprise.local/loki/api/v1/labels" \
  -H "Authorization: Bearer $(vault kv get -field=api_token kv/loki/api-key)"

# 7. Rate limit test (should fail after 5 requests)
for i in {1..10}; do
  curl -s "https://logs.code-server-enterprise.local/loki/api/v1/query" \
    -w "\nStatus: %{http_code}\n" \
    -H "Authorization: Bearer $(vault kv get -field=api_token kv/loki/api-key)"
  sleep 1
done
```

### 5.3 Compliance Checklist

- [ ] All users authenticate via OAuth2
- [ ] Sessions timeout after 24 hours
- [ ] Sessions are stored securely (Redis encrypted)
- [ ] RBAC controls access to logs
- [ ] Rate limiting prevents abuse
- [ ] TLS certificates valid and renewed
- [ ] No sensitive data in logs (passwords, tokens)
- [ ] All auth events logged to Loki
- [ ] Audit trail available for compliance
- [ ] Penetration test scheduled

---

## Security Hardening Details

### Cookie Security
```
✅ Secure flag: Only HTTPS
✅ HttpOnly flag: No JavaScript access
✅ SameSite: Lax (CSRF protection)
✅ Refresh: Automatic hourly
✅ Expiry: 24 hours
✅ Storage: Redis (not in-memory)
```

### TLS/mTLS
```
✅ TLS 1.2+ only
✅ Strong cipher suites (AES-GCM, ChaCha20)
✅ Certificate pinning (for client auth)
✅ HSTS headers
✅ Certificate rotation every 90 days
```

### RBAC Design
```
✅ Default deny (no access unless whitelisted)
✅ Three role tiers: admin, viewer, readonly
✅ Label-based filtering (hide sensitive logs)
✅ Query-level rate limiting
✅ Immutable policy definitions
```

---

## Timeline & Ownership

| Phase | Task | Timeline | Owner | Status |
|-------|------|----------|-------|--------|
| 1 | code-server OAuth2-proxy | 2 hours | Infra | ⏳ TODO |
| 1 | code-server session mgmt | 1 hour | Infra | ⏳ TODO |
| 2 | Loki OAuth2-proxy | 2 hours | Infra | ⏳ TODO |
| 2 | Loki RBAC policies | 1 hour | Security | ⏳ TODO |
| 3 | Grafana integration | 1 hour | Infra | ⏳ TODO |
| 4 | Audit logging | 2 hours | Ops | ⏳ TODO |
| 5 | Testing & validation | 3 hours | QA | ⏳ TODO |
| **TOTAL** | **All phases** | **12 hours** | | |

---

## References

- [oauth2-proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Loki RBAC](https://grafana.com/docs/loki/latest/clients/#rbac)
- [Grafana Security](https://grafana.com/docs/grafana/latest/administration/security/)
- docs/P0-412-HARDCODED-SECRETS-REMEDIATION.md (secrets management)
- docs/P0-413-VAULT-PRODUCTION-HARDENING.md (secret storage)

---

**Next Steps**:
1. Deploy oauth2-proxy for code-server
2. Deploy oauth2-proxy for Loki
3. Configure RBAC in Loki
4. Test authentication workflows
5. Run compliance checklist
6. Update incident runbooks

**GitHub Issue**: #414 (P0 - code-server/Loki Authentication)  
**Status**: 📋 PLAN COMPLETE | ⏳ IMPLEMENTATION REQUIRED  
**Owner**: Infrastructure/Security Team  
**Deadline**: End of this week (April 18, 2026)
