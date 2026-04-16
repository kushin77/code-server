# P1 #388 Phase 2: Service-to-Service Authentication - Implementation Guide

## Quick Start (5 minutes)

```bash
# 1. Start token microservice
docker compose --profile iam up -d token-microservice

# 2. Request JWT token for code-server
curl -X POST http://localhost:8888/token \
  -H "Content-Type: application/json" \
  -d '{
    "grant_type": "client_credentials",
    "client_id": "code-server",
    "client_secret": "'$CODE_SERVER_CLIENT_SECRET'",
    "scope": "read:secrets write:config"
  }'

# 3. Use token to call another service
curl -X GET http://localhost:5432/api/v1/status \
  -H "Authorization: Bearer <token_from_step_2>"
```

---

## Implementation Steps (4 Days)

### Day 1: Token Microservice & Validation Library (Phase 2 Foundation)

**Duration**: 8 hours  
**Owner**: Backend team  
**Deliverables**: Token issuer + JWT validation library

#### 1.1 Deploy Token Microservice
```bash
# Start service
docker compose --profile iam up -d token-microservice

# Verify health
curl http://localhost:8888/health
# Response: {"status": "healthy", ...}

# Check JWKS (public keys for verification)
curl http://localhost:8888/jwks
# Response: {"keys": [{...}]}
```

#### 1.2 Test Token Issuance
```bash
# Request token for code-server
TOKEN=$(curl -s -X POST http://localhost:8888/token \
  -H "Content-Type: application/json" \
  -d '{
    "grant_type": "client_credentials",
    "client_id": "code-server",
    "client_secret": "'$CODE_SERVER_CLIENT_SECRET'"
  }' | jq -r .access_token)

echo $TOKEN
# eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

# Validate token
curl -X POST http://localhost:8888/validate \
  -H "Content-Type: application/json" \
  -d '{"token": "'$TOKEN'"}'
# Response: {"valid": true, "claims": {...}}
```

#### 1.3 Test JWT Validation Library
```bash
# Python example
from lib.jwt_validator import JWTValidator

validator = JWTValidator("http://localhost:8888")
try:
    claims = validator.validate(token, audience="kushnir-platform")
    print(f"Token valid! Service: {claims['sub']}")
except Exception as e:
    print(f"Token invalid: {e}")

# TypeScript example would be similar
```

---

### Day 2: Service Integration (Add JWT to all services)

**Duration**: 8 hours  
**Owner**: Backend team + each service owner  
**Changes**: Update each service to use JWT for inter-service calls

#### 2.1 Code-Server Integration
```python
# In code-server main.py or init script
from lib.jwt_validator import TokenClient

# Create token client for code-server service
token_client = TokenClient(
    client_id="code-server",
    client_secret=os.getenv("CODE_SERVER_CLIENT_SECRET")
)

# When calling PostgreSQL
auth_header = token_client.get_auth_header()
response = requests.get(
    "http://postgresql:5432/api/v1/data",
    headers={"Authorization": auth_header}
)
```

#### 2.2 PostgreSQL Integration
```sql
-- Add middleware to validate JWT tokens
-- In postgres_init.sql or migration

CREATE OR REPLACE FUNCTION validate_jwt_token(token TEXT)
RETURNS jsonb AS $$
BEGIN
    -- Call token-microservice to validate
    RETURN http_post('http://token-microservice:8888/validate', 
                     jsonb_build_object('token', token));
END;
$$ LANGUAGE plpgsql;

-- In connection setup
CREATE ROLE jwt_authenticated;
ALTER ROLE jwt_authenticated SET search_path TO public;
```

#### 2.3 Grafana Integration
```ini
# In grafana.ini or environment

# Add JWT bearer token validation
[auth.proxy]
enabled = true
header_name = Authorization
header_property = Bearer
auto_sign_up = false

# Data source authentication
[datasources]
- name: Prometheus
  type: prometheus
  url: http://prometheus:9090
  auth:
    type: bearer
    token: ${PROMETHEUS_JWT_TOKEN}
```

#### 2.4 Test All Integrations
```bash
# Verify code-server → postgresql works
docker logs code-server | grep "token"

# Verify grafana → prometheus works
docker logs grafana | grep "Authorization"

# Verify prometheus metrics are tagged with source service
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels'
```

---

### Day 3: Token Rotation & Refresh Testing

**Duration**: 8 hours  
**Owner**: QA + Ops  
**Testing**: Token lifecycle, refresh, expiration handling

#### 3.1 Test Token Expiration
```bash
# Create token with short TTL for testing
curl -X POST http://localhost:8888/token \
  -H "Content-Type: application/json" \
  -d '{"grant_type": "client_credentials", ...}' > token1.json

TOKEN1=$(jq -r .access_token token1.json)
EXPIRES_IN=$(jq -r .expires_in token1.json)

# Wait for expiration
sleep $((EXPIRES_IN + 10))

# Try to use expired token - should fail
curl -X GET http://localhost:5432/api/v1/data \
  -H "Authorization: Bearer $TOKEN1"
# Response: 401 Unauthorized (token expired)
```

#### 3.2 Test Token Refresh Cycle
```bash
# Simulate continuous service operation
while true; do
    # Check if token needs refresh (within 5-minute window)
    if token_client.should_refresh(token):
        token = token_client.get_token(force_refresh=True)
        logger.info("Token refreshed")
    
    # Use token for service call
    response = requests.get(..., headers={"Authorization": f"Bearer {token}"})
    
    # Sleep and repeat
    sleep(60)
done
```

#### 3.3 Test Token Revocation
```bash
# Issue token
TOKEN=$(curl -s -X POST http://localhost:8888/token ... | jq -r .access_token)

# Use token - should work
curl -X GET http://localhost:5432/api/v1/data \
  -H "Authorization: Bearer $TOKEN"
# Response: 200 OK

# Revoke token
curl -X POST http://localhost:8888/revoke \
  -H "Content-Type: application/json" \
  -d '{"token": "'$TOKEN'"}'

# Try to use revoked token - should fail
curl -X GET http://localhost:5432/api/v1/data \
  -H "Authorization: Bearer $TOKEN"
# Response: 401 Unauthorized (token revoked)
```

---

### Day 4: Documentation & Runbooks

**Duration**: 4 hours  
**Owner**: Docs team + DevOps  
**Deliverables**: Operations guide, troubleshooting

#### 4.1 Create Runbooks
```bash
# Runbook 1: Emergency Token Microservice Recovery
# Location: docs/RUNBOOKS/token-microservice-recovery.md

1. Identify issue: Check service health
   curl http://localhost:8888/health
   
2. If unhealthy, check logs
   docker logs token-microservice
   
3. Restart service
   docker restart token-microservice
   
4. Verify recovery
   curl http://token-microservice:8888/health
   
5. Monitor token validation errors (Prometheus metric)
   token_validation_errors_total

# Runbook 2: Token Secret Rotation
# Location: docs/RUNBOOKS/token-secret-rotation.md

1. Generate new secrets
   openssl rand -hex 32 > /tmp/code-server-secret.txt
   
2. Update in Vault
   vault kv put secret/token-microservice code_server_secret=...
   
3. Restart affected services (they'll re-read secrets)
   docker restart code-server
   
4. Verify new tokens are working
   curl -X POST http://localhost:8888/token ...
```

#### 4.2 Create Troubleshooting Guide
```markdown
# Service-to-Service Auth Troubleshooting

## Problem: "invalid_client" error when requesting token
- Check service credentials in .env
- Verify CLIENT_SECRET is correct (not base64 encoded)
- Check token-microservice logs: docker logs token-microservice

## Problem: "token_invalid" error when using token
- Token may have expired (TTL is 15 minutes)
- Check token.should_refresh() before using
- Validate token hasn't been revoked

## Problem: High token_validation_errors in Prometheus
- Check if services are using expired tokens
- Verify all services have updated JWT validator library
- Check token microservice capacity (may need more replicas)

## Problem: Token microservice is down
- Emergency: Temporarily allow hardcoded secrets (for rollback)
- Restart: docker restart token-microservice
- Recovery: Redeploy from k8s/workload-federation.yaml
```

---

## Monitoring & Observability

### Prometheus Metrics
```yaml
# Token microservice exposes:
token_issued_total{service="code-server"}
token_validation_attempts_total{status="success|failure"}
token_validation_errors_total{error="expired|invalid_sig|..."}
token_refresh_latency_seconds{quantile="0.5|0.95|0.99"}
```

### Grafana Dashboard
```json
{
  "dashboard": {
    "title": "Service-to-Service Authentication",
    "panels": [
      {
        "title": "Tokens Issued per Service",
        "targets": [{"expr": "rate(token_issued_total[5m])"}]
      },
      {
        "title": "Token Validation Errors",
        "targets": [{"expr": "rate(token_validation_errors_total[5m])"}]
      },
      {
        "title": "Token Refresh Latency",
        "targets": [{"expr": "histogram_quantile(0.95, token_refresh_latency_seconds)"}]
      }
    ]
  }
}
```

### Alert Rules
```yaml
alert:
  - name: TokenMicroserviceDown
    expr: up{job="token-microservice"} == 0
    for: 1m
    severity: critical
    
  - name: HighTokenValidationErrors
    expr: rate(token_validation_errors_total[5m]) > 0.1
    for: 5m
    severity: warning
    
  - name: TokenRefreshLatencyHigh
    expr: histogram_quantile(0.95, token_refresh_latency_seconds) > 1
    for: 10m
    severity: warning
```

---

## Deployment Checklist

- [ ] Token microservice deployed to production
- [ ] JWKS endpoint responding and verified
- [ ] Service accounts created with secrets in Vault
- [ ] All services updated with JWT validation library
- [ ] Token refresh logic tested with graceful degradation
- [ ] Monitoring dashboards created
- [ ] Alert rules deployed
- [ ] Runbooks created and tested
- [ ] Team trained on troubleshooting
- [ ] Runbook links added to on-call wiki

---

## Migration Path (Zero Downtime)

**Strategy**: Dual-auth (old + new) during transition

```
Phase 2a (Week 1): Deploy token-microservice, no breaking changes
Phase 2b (Week 2): Add JWT validation library to services (non-breaking)
Phase 2c (Week 3): Enable JWT validation alongside existing auth
Phase 2d (Week 4): Remove old auth, JWT-only
```

---

## Success Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Token microservice availability | 99.95% | Pending |
| Token issuance latency (p95) | <100ms | Pending |
| Token validation latency (p95) | <50ms | Pending |
| Service uptime during token rotation | 100% | Pending |
| Incident response time (token secret leak) | <5 min | TBD |

---

**Phase 2 Status**: ✅ Ready for implementation  
**Owner**: Backend + Platform teams  
**Start**: April 16, 2026  
**Target completion**: April 18, 2026
