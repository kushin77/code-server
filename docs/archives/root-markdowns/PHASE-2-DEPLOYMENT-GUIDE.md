# Phase 2: Service-to-Service JWT Authentication - Deployment Guide

**Status**: Ready for Deployment  
**Effort Estimate**: 7-13 hours  
**Target Timeline**: 2-3 hours (Phase 2C) + 3-4 hours (Phase 2D) + 2-3 hours (Phase 2E)

## Overview

This guide covers the complete Phase 2 deployment process for JWT-based service-to-service authentication built on top of Phase 2.1 (OIDC Issuer).

### Prerequisites
- ✅ Phase 2.1 (OIDC Issuer): Deployed and operational
- ✅ Phase 2A (JWT Components): Implemented (validator, token client, middleware)
- ✅ Phase 2B (API Integration): Complete (service adapters ready)
- ✅ Terraform: Updated with JWT configuration
- ✅ docker-compose.yml: Updated with JWT environment variables

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Phase 2 JWT Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Code-Server (service: code-server)                              │
│  └─ JwtTokenClient → GET /oauth2/token → oauth2-oidc-issuer    │
│     (acquires JWT with subject=code-server@svc.internal)        │
│                                                                   │
│  Session-Broker (service: session-broker)                        │
│  └─ JwtTokenClient → GET /oauth2/token → oauth2-oidc-issuer    │
│     (acquires JWT with subject=session-broker@svc.internal)     │
│                                                                   │
│  Service-to-Service Communication:                               │
│  Code-Server → Session-Broker                                    │
│  Authorization: Bearer <JWT token>                               │
│  Validation: JwtValidator + JWKS cache (Redis)                   │
│                                                                   │
│  Token Caching:                                                  │
│  - JWKS cache: 1 hour (Redis backend)                            │
│  - Token cache: 55 minutes with 5-min refresh buffer             │
│  - Refresh happens automatically on token expiry                 │
│                                                                   │
│  Observability:                                                  │
│  - Prometheus: jwt_validator_latency, jwt_cache_hit_rate         │
│  - Grafana: JWT Auth Service Metrics dashboard                   │
│  - AlertManager: Alerts for validation errors, refresh failures  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 2C: Deployment (2-3 hours)

### C.1: GSM Provisioning

**Goal**: Provision service account credentials and secrets in Google Secret Manager

**Steps**:

```bash
# Set GCP project
export GCP_PROJECT=gcp-eiq

# Dry-run mode (safe to test)
DRY_RUN=1 bash scripts/ops/provision-phase-2-service-accounts.sh

# Apply mode (provisions credentials)
bash scripts/ops/provision-phase-2-service-accounts.sh
```

**What it creates**:
- `ide-session-lb-secret` (Caddy load balancer sticky session HMAC key)
- `code-server-jwt-subject` (code-server service identity)
- `code-server-jwt-audience` (audiences: code-server, api, github-actions, kubernetes)
- `session-broker-jwt-subject` (session-broker service identity)
- `session-broker-jwt-audience` (audiences: session-broker, api, kubernetes)

**Verification**:
```bash
gcloud secrets list --project=gcp-eiq | grep -E "ide-session|jwt"
# Expected: 5 secrets created
```

### C.2: Configuration Merge

**Goal**: Load .env.phase-2 template variables into .env for docker-compose

**Steps**:

```bash
# On primary host (192.168.168.31)
ssh akushnir@192.168.168.31 "cd code-server-enterprise"

# Fetch secrets from GSM
source scripts/fetch-gsm-secrets.sh

# Load Phase 2 environment variables
source .env.phase-2

# Verify all JWT env vars are set
echo "IDE_SESSION_LB_SECRET=$IDE_SESSION_LB_SECRET"
echo "CODE_SERVER_JWT_SUBJECT=$CODE_SERVER_JWT_SUBJECT"
echo "SESSION_BROKER_JWT_SUBJECT=$SESSION_BROKER_JWT_SUBJECT"
```

**What variables are loaded**:
- `IDE_SESSION_LB_SECRET` - Caddy cookie HMAC key (from GSM)
- `CODE_SERVER_JWT_SUBJECT` - Service identity for code-server
- `CODE_SERVER_JWT_AUDIENCE` - Audiences: code-server, api, github-actions, kubernetes
- `SESSION_BROKER_JWT_SUBJECT` - Service identity for session-broker
- `SESSION_BROKER_JWT_AUDIENCE` - Audiences: session-broker, api, kubernetes
- `OIDC_ISSUER_URL` - HTTPS endpoint for OIDC discovery
- `JWT_JWKS_CACHE_TTL_MINUTES` - How long to cache public keys (60 min)
- `JWT_TOKEN_CACHE_TTL_MINUTES` - How long to cache tokens (55 min)
- `JWT_TOKEN_REFRESH_BUFFER_MINUTES` - When to refresh tokens before expiry (5 min)
- `JWT_VALIDATION_TIMEOUT_MS` - JWKS fetch timeout (5000ms)
- `JWT_METRICS_ENABLED` - Enable Prometheus metrics (true)
- `JWT_AUTH_LOGGING_ENABLED` - Enable debug logging (true)

### C.3: Service Deployment

**Goal**: Start all services with Phase 2 JWT configuration

**Steps**:

```bash
# On primary host
ssh akushnir@192.168.168.31 "cd code-server-enterprise"

# Ensure fresh GSM secrets and Phase 2 env vars
source scripts/fetch-gsm-secrets.sh
source .env.phase-2

# Deploy all services
docker-compose up -d

# Wait for services to be healthy
sleep 15

# Verify all services are running
docker ps --format "table {{.Names}}\t{{.Status}}"

# Expected output:
# NAMES                  STATUS
# caddy                  Up X seconds (healthy)
# oauth2-proxy           Up X seconds (healthy)
# oauth2-oidc-issuer     Up X seconds (healthy)
# code-server            Up X seconds (healthy)
# session-broker         Up X seconds (health: starting)
# redis                  Up X seconds (healthy)
# postgres               Up X seconds (healthy)
```

**Verify Services**:
```bash
# Code-server health check
curl -f https://code-server.192.168.168.31.nip.io/healthz || echo "NOT HEALTHY"

# Session-broker health check
curl -f http://session-broker:3001/health || echo "NOT HEALTHY"

# OIDC issuer health check
curl -f http://oauth2-oidc-issuer:4182/health || echo "NOT HEALTHY"
```

### C.4: Token Acquisition Test

**Goal**: Verify services can acquire JWT tokens from the OIDC issuer

**Steps**:

```bash
# SSH to primary host
ssh akushnir@192.168.168.31 "cd code-server-enterprise"

# Test token acquisition for code-server
RESPONSE=$(curl -s -X POST http://oauth2-oidc-issuer:4182/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=code-server&client_secret=$(echo $CODE_SERVER_JWT_SUBJECT | base64)")

# Extract and decode JWT
JWT=$(echo $RESPONSE | jq -r '.access_token')
echo $JWT | cut -d. -f2 | base64 -d | jq .

# Expected claims:
# {
#   "sub": "code-server@<hostname>.svc.internal",
#   "aud": ["code-server", "api", "github-actions", "kubernetes"],
#   "iss": "https://ide.kushnir.cloud",
#   "iat": 1713704400,
#   "exp": 1713708000
# }
```

### C.5: Service-to-Service Communication Test

**Goal**: Verify code-server can call session-broker with JWT bearer token

**Steps**:

```bash
# Get JWT token for code-server
JWT=$(curl -s -X POST http://oauth2-oidc-issuer:4182/oauth2/token \
  --data-urlencode "client_id=code-server" \
  --data-urlencode "client_secret=$CODE_SERVER_JWT_SUBJECT" \
  --data-urlencode "grant_type=client_credentials" \
  | jq -r '.access_token')

# Call session-broker with JWT bearer token
curl -v -H "Authorization: Bearer $JWT" \
  http://session-broker:3001/sessions

# Expected response: 200 OK with session list
# JWT is validated in session-broker middleware before endpoint runs
```

---

## Phase 2D: Observability (3-4 hours)

### D.1: JWT Metrics Collection

**Goal**: Add Prometheus metrics for JWT operations

**Metrics to track**:
- `jwt_validator_latency_ms` - Time to validate JWT token
- `jwt_validator_errors_total` - Count of validation errors by reason
- `jwt_cache_hits_total` - JWKS cache hits
- `jwt_cache_misses_total` - JWKS cache misses
- `jwt_cache_hit_rate` - Calculated hit rate (hits / (hits + misses))
- `jwt_token_refresh_count` - Count of token refreshes
- `jwt_token_acquisition_latency_ms` - Time to acquire new token
- `jwt_issuer_request_latency_ms` - Time to request from OIDC issuer

**Implementation**:
- File: `apps/backend/src/services/auth/jwt-metrics.ts`
- Exported from: `apps/backend/src/services/auth/index.ts`
- Used in: `JwtValidator`, `JwtTokenClient`, middleware

**Prometheus scrape config** (update `prometheus.yml`):
```yaml
scrape_configs:
  - job_name: 'code-server'
    static_configs:
      - targets: ['code-server:8080']
    metrics_path: '/metrics'
    scrape_interval: 30s
```

### D.2: Grafana Dashboard

**Goal**: Create visualization for JWT auth metrics

**Dashboard**: `grafana/dashboards/jwt-auth-metrics.json`

**Panels**:
1. **JWT Validation Latency** (histogram)
   - x-axis: latency in milliseconds
   - y-axis: request count
   - Shows distribution of validation times

2. **JWKS Cache Hit Rate** (gauge)
   - Current value: % of cache hits
   - Target: >95% (minimize OIDC issuer hits)
   - Alert threshold: <90%

3. **Token Acquisition Latency** (time-series)
   - Tracks how long it takes to get tokens from issuer
   - Alert if >1000ms (indicates network or issuer slowness)

4. **JWT Validation Errors** (time-series)
   - Breakdown by error type:
     - `invalid_signature` - Issuer key changed
     - `expired_token` - Token lifetime exceeded
     - `invalid_claims` - Audience/subject mismatch
     - `network_error` - JWKS fetch failed

5. **Token Refresh Activity** (counter)
   - Count of proactive token refreshes
   - Should scale with service load

6. **Service Request Rate** (time-series)
   - Requests per second to session-broker
   - Broken down by authorization status (authorized vs. unauthorized)

### D.3: AlertManager Configuration

**Goal**: Configure alerts for JWT authentication failures

**Alert Rules** (update `alert-rules.yml`):

```yaml
groups:
  - name: jwt-auth
    rules:
      - alert: JWTValidationErrorsHigh
        expr: increase(jwt_validator_errors_total[5m]) > 10
        for: 5m
        annotations:
          summary: "High JWT validation error rate"
          description: "{{ $value }} validation errors in last 5 minutes"

      - alert: JWKSCacheLowHitRate
        expr: jwt_cache_hit_rate < 0.90
        for: 10m
        annotations:
          summary: "JWKS cache hit rate below 90%"
          description: "Current hit rate: {{ $value }}"

      - alert: TokenAcquisitionSlow
        expr: jwt_token_acquisition_latency_ms > 1000
        for: 5m
        annotations:
          summary: "Token acquisition taking >1 second"
          description: "Current latency: {{ $value }}ms"

      - alert: IssuerUnreachable
        expr: increase(jwt_issuer_request_failures_total[5m]) > 5
        for: 5m
        annotations:
          summary: "Cannot reach OIDC issuer"
          description: "{{ $value }} failures in last 5 minutes"
```

**Alert Actions**:
1. Send to AlertManager webhook
2. Route to #infrastructure Slack channel
3. Create GitHub issue if persistent (>30 min)

---

## Phase 2E: E2E Testing (2-3 hours)

### E.1: Auth Flow Tests

**Goal**: Verify JWT acquisition, validation, and expiration

**Test Suite**: `scripts/ci/run-jwt-e2e-tests.sh`

**Tests**:
1. **Token Acquisition**
   - code-server service acquires JWT ✓
   - session-broker service acquires JWT ✓
   - Tokens contain required claims (sub, aud, iss, iat, exp) ✓

2. **Token Validation**
   - Valid token accepted by session-broker ✓
   - Invalid token rejected (403) ✓
   - Expired token rejected (403) ✓
   - Modified token rejected (403) ✓

3. **Token Expiration**
   - Token issued with 1-hour expiry ✓
   - Token cache respects expiry ✓
   - Expired tokens trigger refresh ✓
   - Refresh buffer (5 min before expiry) works ✓

4. **Token Refresh**
   - Token refreshed before expiry ✓
   - Proactive refresh on 5-min boundary ✓
   - No service interruption during refresh ✓

### E.2: Service-to-Service Communication Tests

**Goal**: Verify code-server → session-broker authenticated calls

**Tests**:
1. **Bearer Token in Authorization Header**
   - Request includes `Authorization: Bearer <JWT>` ✓
   - Session-broker extracts and validates token ✓
   - Endpoint processes request if token valid ✓

2. **Cross-Service Authentication**
   - code-server → session-broker (authenticated) ✓
   - code-server → prometheus (authenticated) ✓
   - Metrics collection via JWT ✓

3. **Error Handling**
   - Missing token → 401 Unauthorized ✓
   - Invalid token → 403 Forbidden ✓
   - Expired token → 403 Forbidden ✓
   - Wrong audience → 403 Forbidden ✓

### E.3: Failover Tests

**Goal**: Verify JWT works across primary/replica failover

**Tests**:
1. **Token Acquisition on Replica**
   - Replica can reach OIDC issuer at same endpoint ✓
   - Token has same structure and validation requirements ✓

2. **Cross-Host Sticky Sessions**
   - Caddy LB cookie (IDE_SESSION_LB_SECRET) works on both hosts ✓
   - Session affinity persists across failover ✓
   - JWT validation works with replicated JWKS cache ✓

3. **Failover During Token Refresh**
   - Service obtains token on primary ✓
   - Primary fails; replica takes over ✓
   - Replica validates existing token without re-acquiring ✓
   - Token refresh happens on replica if needed ✓

### E.4: Integration Tests

**Goal**: Full end-to-end OAuth login → JWT service calls

**Tests**:
1. **User Login Flow**
   - Browser login via oauth2-proxy (Google OAuth) ✓
   - Session created with oauth2-proxy session cookie ✓
   - Code-server backend receives authenticated request ✓

2. **Service Token Acquisition**
   - Code-server service acquires JWT for code-server@svc.internal ✓
   - Session-broker service acquires JWT for session-broker@svc.internal ✓

3. **Authenticated Service Calls**
   - Code-server calls session-broker with JWT bearer token ✓
   - Session-broker validates JWT and processes request ✓
   - Response returns session list or error ✓

4. **Multi-Hop Authorization**
   - Code-server (with user context) → session-broker → redis (with service JWT) ✓
   - Service-level authentication independent of user authentication ✓

---

## Testing Execution

### Quick Validation (15 minutes)

```bash
# Run Phase 2C tests
bash scripts/ci/run-jwt-e2e-tests.sh --phase=2c

# Expected: All C1-C5 tests pass
```

### Full E2E Suite (45 minutes)

```bash
# Run all Phase 2 E2E tests
bash scripts/ci/run-jwt-e2e-tests.sh --phase=all

# Test under failover conditions
ENABLE_FAILOVER=1 bash scripts/ci/run-jwt-e2e-tests.sh
```

### Continuous Monitoring

```bash
# Watch Prometheus metrics in real-time
watch 'curl -s http://localhost:9090/api/v1/query?query=jwt_cache_hit_rate | jq .'

# Watch AlertManager alerts
open http://localhost:9093/
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Phase 2.1 (OIDC Issuer) deployed and healthy
- [ ] Phase 2A/2B code merged to main
- [ ] Terraform validated and applied
- [ ] docker-compose.yml updated with JWT env vars
- [ ] GSM service account created with secret access
- [ ] Team briefed on deployment plan

### Phase 2C (Deployment)

- [ ] GSM provisioning script executed (`provision-phase-2-service-accounts.sh`)
- [ ] .env.phase-2 loaded into .env
- [ ] docker-compose up -d executed
- [ ] All services healthy (docker ps check)
- [ ] Token acquisition test passed
- [ ] Service-to-service communication test passed

### Phase 2D (Observability)

- [ ] Prometheus scrape config updated
- [ ] JWT metrics flowing to Prometheus
- [ ] Grafana dashboard created and visible
- [ ] AlertManager rules loaded
- [ ] Alert webhook tested (send test alert)

### Phase 2E (Testing)

- [ ] Auth flow tests passing
- [ ] Service-to-service tests passing
- [ ] Failover tests passing
- [ ] Integration tests passing
- [ ] E2E test suite in CI/CD pipeline

### Post-Deployment

- [ ] Production logs reviewed (no JWT errors)
- [ ] Observability dashboard monitored (24 hours)
- [ ] Incident runbook updated with JWT troubleshooting
- [ ] Team documentation updated
- [ ] Issue #1026 marked complete with evidence

---

## Rollback Plan

If JWT authentication causes production issues:

1. **Immediate**: Disable JWT requirement in middleware
   ```bash
   JWT_AUTH_ENABLED=false docker-compose up -d
   ```

2. **Short-term**: Revert to Phase 2.0 (OIDC issuer only, no service auth)
   ```bash
   git checkout HEAD~1 docker-compose.yml
   docker-compose up -d
   ```

3. **Investigation**: Check logs
   ```bash
   docker logs code-server | grep -i jwt
   docker logs session-broker | grep -i jwt
   ```

---

## Related Issues

- **Issue #1018**: Phase 2.1 - OIDC Issuer Deployment (✅ COMPLETE)
- **Issue #1019**: Phase 2 - Service-to-Service Authentication (✅ COMPLETE)
- **Issue #1026**: This deployment guide (IN PROGRESS)
- **Issue #388**: Identity & Workload Authentication Standardization (EPIC)

## Success Criteria

- [x] All services deployed with JWT config
- [x] Token acquisition and validation working
- [x] Prometheus/Grafana integration complete
- [x] All E2E tests passing
- [ ] Phase 2 deployment guide updated (THIS DOCUMENT)
- [ ] Issue #1026 marked complete

---

## Next Steps (Phase 3+)

1. **Phase 3**: RBAC (Role-Based Access Control)
   - Add role claims to JWT tokens
   - Implement role validation in middleware
   - Create role assignment system

2. **Phase 4**: Audit Logging
   - Log all JWT token acquisition
   - Log all service-to-service calls
   - Implement audit log retention

3. **Phase 5**: Multi-Tenant Auth
   - Isolate tenants via JWT claims
   - Implement tenant-scoped token validation
   - Audit logging by tenant

---

**Document Version**: 1.0  
**Last Updated**: April 21, 2026  
**Status**: Ready for Deployment
