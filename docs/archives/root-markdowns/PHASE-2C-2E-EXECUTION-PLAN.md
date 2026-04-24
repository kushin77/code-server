# PHASE 2C-2E EXECUTION PLAN - APRIL 22, 2026

**Status**: Ready for Execution  
**Target Duration**: 7-13 hours  
**Issue**: #1029 (P1)

## Executive Summary

This document outlines the step-by-step execution plan for Phase 2C (Deployment), Phase 2D (Observability), and Phase 2E (E2E Testing) to bring JWT service-to-service authentication to production.

**Key Deliverables**:
- ✅ GSM service account provisioning (5 secrets)
- ✅ Docker-compose deployment with JWT configuration
- ✅ JWT token acquisition and validation testing
- ✅ Service-to-service authentication verification
- ✅ Prometheus metrics and Grafana dashboards
- ✅ AlertManager rules for JWT operations
- ✅ Complete E2E test suite (auth flows, failover, integration)

---

## PHASE 2C: DEPLOYMENT (2-3 hours)

### Section C.1: GSM Service Account Provisioning (30 min)

**Objective**: Provision 5 secrets in Google Secret Manager for JWT operations

**Prerequisites**:
- GCP project `kushin77-ops` accessible
- gcloud CLI configured with appropriate credentials
- Service account with `secretmanager.admin` role

**Execution Steps**:

```bash
# Set environment
export GCP_PROJECT=kushin77-ops

# Dry-run first (SAFE - no modifications)
DRY_RUN=1 bash scripts/ops/provision-phase-2-service-accounts.sh

# Review output and expected secrets:
# ✓ ide-session-lb-secret
# ✓ code-server-jwt-subject
# ✓ code-server-jwt-audience
# ✓ session-broker-jwt-subject
# ✓ session-broker-jwt-audience

# Apply provisioning
bash scripts/ops/provision-phase-2-service-accounts.sh
```

**Verification**:
```bash
gcloud secrets list --project=kushin77-ops --filter="name:ide-session OR name:jwt"
# Expected: 5 secrets created with appropriate labels
```

**Success Criteria**:
- ✓ All 5 secrets created in GSM
- ✓ Each secret has correct format (string, not binary)
- ✓ Labels applied: phase=2, component=auth, environment=production
- ✓ Access IAM configured for service account

---

### Section C.2: Configuration Merge (20 min)

**Objective**: Load Phase 2 environment variables into runtime configuration

**Execution Steps**:

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Change to repo directory
cd /home/akushnir/code-server-enterprise

# Fetch all secrets from GSM
source scripts/fetch-gsm-secrets.sh

# Verify GSM secrets loaded
echo "IDE_SESSION_LB_SECRET length: ${#IDE_SESSION_LB_SECRET}"
echo "CODE_SERVER_JWT_SUBJECT: $CODE_SERVER_JWT_SUBJECT"
echo "SESSION_BROKER_JWT_SUBJECT: $SESSION_BROKER_JWT_SUBJECT"

# Load Phase 2 template variables
source .env.phase-2

# Verify all required JWT vars present
require_var IDE_SESSION_LB_SECRET
require_var CODE_SERVER_JWT_SUBJECT
require_var CODE_SERVER_JWT_AUDIENCE
require_var SESSION_BROKER_JWT_SUBJECT
require_var SESSION_BROKER_JWT_AUDIENCE
require_var JWT_ISSUER_URL
require_var JWT_AUDIENCE
require_var JWT_SUBJECT
require_var OIDC_ISSUER_URL
require_var OAUTH2_PROXY_CLIENT_ID
require_var OAUTH2_PROXY_CLIENT_SECRET
```

**Verification**:
```bash
# Check all vars loaded
env | grep -E "JWT|OIDC|SESSION" | sort
# Expected: 12+ JWT/OIDC/SESSION related vars
```

**Success Criteria**:
- ✓ All environment variables loaded
- ✓ No missing required vars
- ✓ All JWT secrets have correct format (hex, base64, or string)
- ✓ OIDC issuer URL is reachable from current host

---

### Section C.3: Service Deployment (45 min)

**Objective**: Deploy all services with JWT configuration

**Execution Steps**:

```bash
# On primary host (still SSH'd in)
cd /home/akushnir/code-server-enterprise

# Update docker-compose with current env vars
envsubst < docker-compose.tpl > docker-compose.yml

# Verify services defined
grep "^  [a-z-]*:$" docker-compose.yml | head -15
# Expected: code-server, session-broker, oauth2-oidc-issuer, etc.

# Bring up all services
docker-compose up -d

# Wait for health checks
sleep 10

# Verify service health
docker-compose ps
# Expected: All services running (Up or health check in progress)
```

**Health Check Details**:

```bash
# Check each service individually
docker-compose logs code-server | tail -20
docker-compose logs oauth2-oidc-issuer | tail -20
docker-compose logs session-broker | tail -20
docker-compose logs jwt-validator | tail -20
docker-compose logs prometheus | tail -10
docker-compose logs grafana | tail -10
docker-compose logs alertmanager | tail -10
```

**Success Criteria**:
- ✓ All 9+ services running with status "Up"
- ✓ Health checks passing (no "unhealthy" status)
- ✓ No error messages in service logs
- ✓ OIDC issuer responding to health checks
- ✓ JWT validator cache initialized with redis

---

### Section C.4: Token Acquisition Test (30 min)

**Objective**: Acquire JWT from oauth2-oidc-issuer and verify token structure

**Execution Steps**:

```bash
# Acquire JWT token
TOKEN=$(curl -s -X POST \
  http://localhost:6969/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$OIDC_CLIENT_ID&client_secret=$OIDC_CLIENT_SECRET&audience=$CODE_SERVER_JWT_AUDIENCE" \
  | jq -r '.access_token')

echo "Token acquired: ${TOKEN:0:50}..."

# Decode and verify token structure
echo "$TOKEN" | jq -R 'split(".") | .[0:2] | map(@base64d | fromjson)' | jq .

# Expected header:
# {
#   "alg": "RS256",
#   "typ": "JWT",
#   "kid": "<key-id>"
# }

# Expected payload:
# {
#   "aud": "code-server",
#   "sub": "code-server@svc.internal",
#   "iss": "https://oauth2-oidc-issuer.svc.internal",
#   "iat": <current-unix-time>,
#   "exp": <current-unix-time + 3600>
# }
```

**Verification**:
```bash
# Validate claims
PAYLOAD=$(echo "$TOKEN" | jq -R 'split(".") | .[1] | @base64d | fromjson')

echo "Issuer: $(echo $PAYLOAD | jq '.iss')"
echo "Subject: $(echo $PAYLOAD | jq '.sub')"
echo "Audience: $(echo $PAYLOAD | jq '.aud')"
echo "Issued At: $(echo $PAYLOAD | jq '.iat')"
echo "Expires At: $(echo $PAYLOAD | jq '.exp')"
```

**Success Criteria**:
- ✓ HTTP 200 response from /oauth2/token
- ✓ Token has valid JWT structure (3 base64-separated parts)
- ✓ Header: alg=RS256, typ=JWT, kid present
- ✓ Payload: sub, aud, iss, iat, exp all present
- ✓ aud matches CODE_SERVER_JWT_AUDIENCE
- ✓ sub matches CODE_SERVER_JWT_SUBJECT
- ✓ iss matches JWT_ISSUER_URL
- ✓ exp is 3600 seconds (1 hour) in the future

---

### Section C.5: Service-to-Service Test (30 min)

**Objective**: Verify bearer token acceptance for service-to-service calls

**Execution Steps**:

```bash
# Acquire token for code-server service
TOKEN=$(curl -s -X POST \
  http://localhost:6969/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$CODE_SERVER_CLIENT_ID&client_secret=$CODE_SERVER_CLIENT_SECRET&audience=$SESSION_BROKER_JWT_AUDIENCE" \
  | jq -r '.access_token')

# Call session-broker with bearer token
curl -s -X GET \
  http://localhost:7777/health \
  -H "Authorization: Bearer $TOKEN" \
  | jq .

# Expected: HTTP 200 with health check response
# Response body:
# {
#   "status": "healthy",
#   "service": "session-broker",
#   "version": "1.0.0",
#   "timestamp": "2026-04-22T...",
#   "jwt_validated": true
# }

# Test with invalid token (should fail)
curl -s -w "\nStatus: %{http_code}\n" -X GET \
  http://localhost:7777/health \
  -H "Authorization: Bearer invalid-token" \
  | tail -5

# Expected: HTTP 401 Unauthorized
```

**Verification**:
```bash
# Check JWT validation metrics in prometheus
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=jwt_validator_validation_total{status="success"}' \
  | jq '.data.result'

# Check service logs for validation events
docker-compose logs session-broker | grep -i "jwt" | tail -10
```

**Success Criteria**:
- ✓ Valid bearer token accepted (HTTP 200)
- ✓ session-broker health endpoint returns JWT validation result
- ✓ Invalid/expired tokens rejected (HTTP 401)
- ✓ JWT validator metrics recorded
- ✓ Service logs show successful validation

---

## PHASE 2D: OBSERVABILITY (3-4 hours)

### Section D.1: JWT Metrics Collection (45 min)

**Objective**: Configure Prometheus to scrape JWT validator metrics

**Execution Steps**:

```bash
# On primary host, edit prometheus.yml
ssh akushnir@192.168.168.31

cd /home/akushnir/code-server-enterprise

# Add JWT validator job to prometheus.yml
cat >> prometheus.yml << 'EOF'

  - job_name: 'jwt-validator'
    static_configs:
      - targets: ['localhost:8081']
    scrape_interval: 15s
    metrics_path: '/metrics'
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'jwt-validator:8081'
      - source_labels: [__scheme__]
        target_label: scheme
        replacement: 'http'

EOF

# Reload Prometheus
curl -s -X POST http://localhost:9090/-/reload

# Verify metrics are collected
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=jwt_validator_latency_ms' \
  | jq '.data.result | length'

# Expected: 1+ metrics returned
```

**Expected Metrics**:
```
jwt_validator_validation_total{status="success|failure"}
jwt_validator_latency_ms{p50|p95|p99}
jwt_cache_hit_rate{cache="jwks|token"}
jwt_token_refresh_count{service="code-server|session-broker"}
jwt_issuer_reachability{status="up|down"}
```

**Success Criteria**:
- ✓ Prometheus scrape job configured
- ✓ jwt_validator metrics endpoint responds with 200
- ✓ At least 5 different metric types collected
- ✓ Histogram buckets populated with latency data
- ✓ Cache hit/miss counters incrementing

---

### Section D.2: Grafana Dashboard (75 min)

**Objective**: Create "JWT Auth Service Metrics" dashboard with 6 visualization panels

**Execution Steps**:

```bash
# Access Grafana
# URL: http://192.168.168.31:3000
# Username: admin
# Password: (check docker-compose.yml or .env)

# Create new dashboard: "JWT Auth Service Metrics"

# Panel 1: JWT Validation Success Rate (Gauge)
# Query: 100 * rate(jwt_validator_validation_total{status="success"}[5m]) / (rate(jwt_validator_validation_total{status="success"}[5m]) + rate(jwt_validator_validation_total{status="failure"}[5m]))
# Threshold: Green >95%, Yellow 85-95%, Red <85%

# Panel 2: Validator Latency P95 (Graph)
# Query: histogram_quantile(0.95, jwt_validator_latency_ms)
# Threshold: Yellow >50ms, Red >100ms

# Panel 3: JWKS Cache Hit Rate (Gauge)
# Query: 100 * rate(jwt_cache_hit_rate{cache="jwks"}[5m])
# Threshold: Green >90%, Yellow 70-90%, Red <70%

# Panel 4: Token Refresh Rate (Bar Chart)
# Query: rate(jwt_token_refresh_count[5m]) by (service)
# Services: code-server, session-broker

# Panel 5: OIDC Issuer Reachability (Status Panel)
# Query: jwt_issuer_reachability{status="up"}
# Show: Red if metric=0, Green if metric=1

# Panel 6: JWT Validation Errors by Type (Pie Chart)
# Query: sum(rate(jwt_validator_validation_total{status="failure"}[5m])) by (error_type)
# Error types: expired, invalid_signature, missing_kid, issuer_mismatch

# Save dashboard
# Filename: jwt-auth-service-metrics.json
# Tags: jwt, auth, performance
```

**Dashboard Export** (for version control):
```bash
# Export dashboard JSON via API
curl -s http://192.168.168.31:3000/api/dashboards/uid/jwt-auth-service-metrics \
  -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
  | jq '.dashboard' > dashboards/jwt-auth-service-metrics.json

# Store in repo
git add dashboards/jwt-auth-service-metrics.json
git commit -m "Dashboard: JWT Auth Service Metrics"
```

**Success Criteria**:
- ✓ Dashboard created and accessible
- ✓ All 6 panels rendering data
- ✓ Threshold colors functioning (green/yellow/red)
- ✓ Time range selector working (1h, 6h, 24h, 7d)
- ✓ Dashboard exported to JSON for version control

---

### Section D.3: AlertManager Configuration (45 min)

**Objective**: Configure AlertManager rules for JWT operations

**Execution Steps**:

```bash
# On primary host
ssh akushnir@192.168.168.31

cd /home/akushnir/code-server-enterprise

# Add JWT alert rules to prometheus-rules.yml
cat >> prometheus-rules.yml << 'EOF'

groups:
  - name: jwt-auth
    interval: 30s
    rules:
      - alert: HighJWTValidationErrorRate
        expr: |
          (rate(jwt_validator_validation_total{status="failure"}[5m]) 
          / 
          (rate(jwt_validator_validation_total{status="success"}[5m]) + rate(jwt_validator_validation_total{status="failure"}[5m])))
          > 0.05
        for: 5m
        annotations:
          summary: "JWT validation error rate > 5%"
          description: "Service {{ $labels.service }} has high JWT validation failure rate: {{ $value | humanizePercentage }}"
      
      - alert: JWTValidatorLatencyHigh
        expr: histogram_quantile(0.95, jwt_validator_latency_ms) > 100
        for: 5m
        annotations:
          summary: "JWT validator P95 latency > 100ms"
          description: "JWT validation latency high: {{ $value }}ms"
      
      - alert: JWTCacheLowHitRate
        expr: rate(jwt_cache_hit_rate{cache="jwks"}[5m]) < 0.7
        for: 10m
        annotations:
          summary: "JWKS cache hit rate < 70%"
          description: "Cache efficiency low: {{ $value | humanizePercentage }}"
      
      - alert: OIDCIssuerUnreachable
        expr: jwt_issuer_reachability{status="up"} == 0
        for: 2m
        annotations:
          summary: "OIDC issuer unreachable"
          description: "Cannot reach OIDC issuer at {{ $labels.issuer_url }}"
      
      - alert: TokenRefreshFailures
        expr: rate(jwt_token_refresh_count{status="failure"}[5m]) > 0
        for: 5m
        annotations:
          summary: "JWT token refresh failures detected"
          description: "Service {{ $labels.service }} failed to refresh token: {{ $value }}/sec"

EOF

# Reload Prometheus rules
curl -s -X POST http://localhost:9090/-/reload

# Verify rules loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="jwt-auth") | .rules | length'

# Expected: 5 rules loaded
```

**Notification Configuration** (if using external alerting):
```yaml
# In AlertManager config
receivers:
  - name: 'jwt-alerts'
    slack_configs:
      - api_url: $SLACK_WEBHOOK_URL
        channel: '#infrastructure-alerts'
        title: 'JWT Auth Alert'
        text: '{{ .GroupLabels.alertname }}: {{ .CommonAnnotations.summary }}'
        send_resolved: true

route:
  group_by: ['alertname']
  routes:
    - match:
        group: 'jwt-auth'
      receiver: 'jwt-alerts'
      continue: true
```

**Success Criteria**:
- ✓ All 5 JWT alert rules loaded in Prometheus
- ✓ Alert rules evaluate without errors
- ✓ AlertManager webhooks configured (if external notifications desired)
- ✓ Test alert triggered and notification sent
- ✓ Alert thresholds calibrated for your environment

---

## PHASE 2E: E2E TESTING (2-3 hours)

### Section E.1: Auth Flow Tests (40 min)

**Objective**: Test complete JWT token lifecycle (acquisition, validation, expiration, refresh)

**Test Scenarios**:

```bash
# Run test suite
cd /home/akushnir/code-server-enterprise
bash scripts/ci/run-jwt-e2e-tests.sh --phase=2e --test=auth-flow

# Test 1: Token Acquisition
# - Acquire JWT from /oauth2/token
# - Verify HTTP 200
# - Verify JWT structure (3 parts)
# - Verify claims present (sub, aud, iss, iat, exp)
# Expected: PASS

# Test 2: Token Validation
# - Use acquired JWT in Authorization header
# - Call /health endpoint
# - Verify HTTP 200 and jwt_validated=true
# Expected: PASS

# Test 3: Token Expiration
# - Mock token expiration (set exp claim to past time)
# - Call service with expired token
# - Verify HTTP 401 Unauthorized
# - Verify error message "token expired"
# Expected: PASS

# Test 4: Token Refresh
# - Acquire token
# - Wait 55 minutes (or mock time advancement)
# - Verify token is automatically refreshed
# - Verify service calls continue working
# Expected: PASS (or skipped if time-dependent)

# Test Results Report
# Location: artifacts/triage/jwt-auth-flow-tests-{TIMESTAMP}.json
```

**Success Criteria**:
- ✓ Token acquisition: HTTP 200, valid JWT format
- ✓ Token validation: Bearer token accepted, jwt_validated=true
- ✓ Expired tokens: Rejected with HTTP 401
- ✓ Token refresh: Automatic refresh working (for long-running sessions)
- ✓ All 4 test scenarios passing

---

### Section E.2: Service-to-Service Tests (40 min)

**Objective**: Test bearer token acceptance and cross-service authentication

**Test Scenarios**:

```bash
# Run test suite
bash scripts/ci/run-jwt-e2e-tests.sh --phase=2e --test=s2s

# Test 1: Bearer Token Format
# - Include Authorization: Bearer <token> header
# - Call /session-broker/health
# - Verify HTTP 200 and jwt_validated=true
# Expected: PASS

# Test 2: Token Validation in Transit
# - Acquire token for code-server service
# - Call session-broker with token
# - Verify JWKS cache used for validation
# - Verify no calls to OIDC issuer for JWKS
# Expected: PASS

# Test 3: Missing Bearer Token
# - Call protected endpoint without Authorization header
# - Verify HTTP 401 Unauthorized
# - Verify error message "missing bearer token"
# Expected: PASS

# Test 4: Invalid Bearer Token Format
# - Use malformed Authorization header (e.g., "Authorization: Invalid token123")
# - Verify HTTP 401 Unauthorized
# Expected: PASS

# Test 5: Mismatched Audience
# - Acquire token for audience="api"
# - Call endpoint expecting audience="session-broker"
# - Verify HTTP 401 Unauthorized
# - Verify error message "audience mismatch"
# Expected: PASS

# Test 6: Cross-Service Call Chain
# - code-server calls session-broker with JWT
# - session-broker calls jwt-validator with JWKS cache
# - All services validate successfully
# - No repeated OIDC issuer calls (cache hit)
# Expected: PASS

# Test Results Report
# Location: artifacts/triage/jwt-s2s-tests-{TIMESTAMP}.json
```

**Success Criteria**:
- ✓ Bearer token accepted in Authorization header
- ✓ JWKS cache utilized (no repeated issuer calls)
- ✓ Missing/invalid tokens rejected (HTTP 401)
- ✓ Audience validation enforced
- ✓ Cross-service call chains working
- ✓ All 6 test scenarios passing

---

### Section E.3: Failover Tests (40 min)

**Objective**: Test JWT operations during failover scenarios

**Test Scenarios**:

```bash
# Run test suite
bash scripts/ci/run-jwt-e2e-tests.sh --phase=2e --test=failover

# Prerequisites:
# - Primary host: 192.168.168.31 (healthy)
# - Replica host: 192.168.168.42 (running, synced)
# - Load balancer: Routing to primary

# Test 1: Token Acquisition on Replica
# - Failover to replica (or query replica directly)
# - Acquire JWT from replica /oauth2/token
# - Verify HTTP 200 and valid JWT
# Expected: PASS

# Test 2: Cross-Host Sticky Sessions
# - code-server acquires token on primary
# - Load balancer routes to replica
# - Verify JWT still validates on replica
# - Verify JWKS cache synced between hosts (Redis)
# Expected: PASS

# Test 3: Failover During Token Refresh
# - Trigger token refresh on primary
# - Simultaneously failover to replica
# - Verify token continues to validate
# - Verify no "authentication lost" errors
# Expected: PASS

# Test 4: OIDC Issuer Failover
# - OIDC issuer primary becomes unavailable
# - Replica OIDC issuer handles token requests
# - Verify code-server can still acquire tokens
# Expected: PASS (if dual OIDC setup; skip if single)

# Test 5: Cache Consistency During Failover
# - Populate JWKS cache on primary (Redis)
# - Failover to replica
# - Verify replica has same cache (Redis replicated)
# - Verify no "cache miss" spikes after failover
# Expected: PASS

# Test Results Report
# Location: artifacts/triage/jwt-failover-tests-{TIMESTAMP}.json
```

**Manual Failover Simulation** (if automation not available):
```bash
# On primary host
docker-compose stop oauth2-oidc-issuer

# Wait 30 seconds

# Try to acquire token
curl -s -X POST http://localhost:6969/oauth2/token \
  -d "grant_type=client_credentials&..." | jq .

# Expected: Should use cached token or fail gracefully

# On replica host
# Query replica jwt-validator to test cross-host validation

# Restore primary
docker-compose start oauth2-oidc-issuer
```

**Success Criteria**:
- ✓ Token acquisition works on replica
- ✓ Sticky sessions maintained across failover
- ✓ No authentication loss during failover
- ✓ Cache consistency between hosts
- ✓ Graceful degradation if OIDC issuer unavailable
- ✓ All 5 test scenarios passing

---

### Section E.4: Integration Tests (40 min)

**Objective**: Test complete authentication flow from OAuth login through service calls

**Test Scenarios**:

```bash
# Run test suite
bash scripts/ci/run-jwt-e2e-tests.sh --phase=2e --test=integration

# Test 1: OAuth Login → JWT Acquisition → Code-Server Access
# - User logs in via oauth2-proxy (OAuth/OIDC with Google)
# - Session established with Caddy
# - code-server exchanges OAuth token for JWT (client credentials)
# - code-server uses JWT to call session-broker
# - User session created and active
# Expected: PASS

# Test 2: JWT Refresh During Long-Running Session
# - User logged in for 55+ minutes
# - code-server token approaching expiration
# - Automatic token refresh triggered
# - User continues using IDE without interruption
# Expected: PASS

# Test 3: Concurrent Service Calls with JWT
# - Multiple code-server instances acquiring tokens
# - Concurrent calls to session-broker
# - Verify JWKS cache hit rate (should be high)
# - Verify no token collisions or race conditions
# Expected: PASS

# Test 4: JWT Metrics in Integration Flow
# - User OAuth login, JWT acquisition, service call
# - Verify Prometheus metrics recorded
# - Check Grafana dashboard updates in real-time
# - Verify alert thresholds not exceeded
# Expected: PASS

# Test 5: Error Handling in Integration Flow
# - JWT token refresh fails (mock OIDC issuer error)
# - User receives graceful error (not 5xx)
# - Alert triggered in AlertManager
# - Session broker logs failure event
# Expected: PASS

# Test Results Report
# Location: artifacts/triage/jwt-integration-tests-{TIMESTAMP}.json
```

**Success Criteria**:
- ✓ Complete OAuth → JWT → service call flow working
- ✓ Token refresh transparent to end user
- ✓ High JWKS cache hit rate (>90%)
- ✓ Metrics and alerts functioning
- ✓ Graceful error handling
- ✓ All 5 test scenarios passing

---

## DEFINITION OF DONE

✅ **Phase 2C Complete**:
- [ ] GSM service accounts provisioned (5 secrets)
- [ ] docker-compose deployment successful
- [ ] All 9 services healthy and running
- [ ] Token acquisition tested and verified
- [ ] Service-to-service authentication working

✅ **Phase 2D Complete**:
- [ ] Prometheus JWT metrics collection active
- [ ] Grafana dashboard "JWT Auth Service Metrics" created
- [ ] All 6 dashboard panels rendering data
- [ ] AlertManager rules configured (5 alerts)
- [ ] Notification system tested (if external)

✅ **Phase 2E Complete**:
- [ ] Auth flow tests: 4/4 scenarios passing
- [ ] Service-to-service tests: 6/6 scenarios passing
- [ ] Failover tests: 5/5 scenarios passing
- [ ] Integration tests: 5/5 scenarios passing
- [ ] All test reports generated and archived

✅ **Production Ready**:
- [ ] Phase 2 deployment guide updated and verified
- [ ] Runbook created for operational procedures
- [ ] Alerting configured and tested
- [ ] Failover procedures validated
- [ ] Issue #1029 closure verified

---

## EXECUTION COMMANDS

### Quick Start (Dry-Run):
```bash
cd /home/akushnir/code-server-enterprise
DRY_RUN=1 bash EXECUTE-PHASE-2-DEPLOYMENT.sh
```

### Execute Phase 2C Only:
```bash
PHASE=2c DRY_RUN=0 bash EXECUTE-PHASE-2-DEPLOYMENT.sh
```

### Execute All Phases (2C-2E):
```bash
PHASE=all DRY_RUN=0 bash EXECUTE-PHASE-2-DEPLOYMENT.sh
```

### Manual SSH Deployment:
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  source scripts/fetch-gsm-secrets.sh && \
  source .env.phase-2 && \
  docker-compose up -d"
```

---

## TIMELINE ESTIMATE

| Phase | Component | Duration | Status |
|-------|-----------|----------|--------|
| 2C | GSM Provisioning | 30 min | Ready |
| 2C | Config Merge | 20 min | Ready |
| 2C | Service Deployment | 45 min | Ready |
| 2C | Token Acquisition | 30 min | Ready |
| 2C | S2S Test | 30 min | Ready |
| **2C Total** | | **2-3 hrs** | **Ready** |
| 2D | Metrics Collection | 45 min | Ready |
| 2D | Grafana Dashboard | 75 min | Ready |
| 2D | AlertManager Rules | 45 min | Ready |
| **2D Total** | | **3-4 hrs** | **Ready** |
| 2E | Auth Flow Tests | 40 min | Ready |
| 2E | S2S Tests | 40 min | Ready |
| 2E | Failover Tests | 40 min | Ready |
| 2E | Integration Tests | 40 min | Ready |
| **2E Total** | | **2-3 hrs** | **Ready** |
| **GRAND TOTAL** | | **7-13 hrs** | **Ready** |

---

## RISK MITIGATION

| Risk | Impact | Mitigation |
|------|--------|-----------|
| GSM secret format mismatch | Deployment fails | Pre-validate secret format in dry-run |
| OIDC issuer unreachable | Token acquisition fails | Verify OIDC issuer health before Phase 2C.4 |
| JWT cache desynchronization | Failover issues | Use Redis replication, verify cache sync |
| Load balancer session affinity | Cross-host failures | Test sticky sessions in Phase 2E.3 |
| Metrics cardinality explosion | Prometheus OOM | Limit label combinations for service/audience |
| Alert fatigue | Operations burden | Calibrate thresholds in Phase 2D.3 with baseline metrics |

---

## DOCUMENTATION REFERENCES

- **Deployment Guide**: `PHASE-2-DEPLOYMENT-GUIDE.md` (571 lines)
- **Test Scripts**: `scripts/ci/run-jwt-e2e-tests.sh`
- **Provisioning Script**: `scripts/ops/provision-phase-2-service-accounts.sh`
- **Execution Script**: `EXECUTE-PHASE-2-DEPLOYMENT.sh` (this file)
- **Issue Tracking**: GitHub Issue #1029 (P1)

---

**Last Updated**: April 22, 2026  
**Status**: Ready for Execution  
**Estimated Start**: Immediately upon approval  
**Target Completion**: Within 24 hours (7-13 hours active work)
