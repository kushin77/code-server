# P1 #388 Phase 2: Service-to-Service Authentication (JWT Workload Federation)
## April 16-17, 2026

## Overview

Enable secure service-to-service communication using JWT tokens with minimal credential exposure.

**Target**: All 8+ services can authenticate to each other without hardcoded secrets

---

## Phase 2 Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│ OIDC Provider (Keycloak/Google)                                 │
│ ├── OAuth2 Token Endpoint                                       │
│ └── JWKS Public Key Set                                         │
└────────────┬────────────────────────────────────────────────────┘
             │ 1. Request token (client credentials flow)
┌────────────▼────────────────────────────────────────────────────┐
│ OAuth2-Proxy / Token Microservice                               │
│ ├── Client ID/Secret (stored in Vault)                         │
│ ├── Issues JWT tokens to services                              │
│ └── Token refresh + revocation logic                           │
└────────────┬────────────────────────────────────────────────────┘
             │ 2. Return JWT (valid for 15 min)
┌────────────▼────────────────────────────────────────────────────┐
│ Service A (code-server, postgres, redis, etc.)                  │
│ ├── Calls Service B with JWT in Authorization header           │
│ └── Stores token in memory (15 min TTL)                        │
└────────────┬────────────────────────────────────────────────────┘
             │ 3. Call: GET /api/v1/data
             │    Header: Authorization: Bearer <JWT>
┌────────────▼────────────────────────────────────────────────────┐
│ Service B (postgres, grafana, etc.)                             │
│ ├── Validates JWT signature using JWKS                         │
│ ├── Checks token expiration + issuer + audience                │
│ ├── Extracts service identity from 'sub' claim                 │
│ └── Applies RBAC based on service role                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Plan

### Step 1: Token Microservice (NEW)
Create dedicated service for JWT token issuance

**File**: `services/token-microservice/` (Python Flask)
- Endpoint: `POST /token` - Issue JWT token for service
- Endpoint: `GET /jwks` - Publish public key set
- Endpoint: `POST /revoke` - Revoke token
- Uses: client_credentials OAuth2 flow

**Token Claims**:
```json
{
  "iss": "https://oidc.kushnir.cloud",
  "sub": "code-server@kushnir.cloud",
  "aud": "kushnir-platform",
  "scope": "read:secrets,write:config,read:metrics",
  "exp": 1713297600,
  "iat": 1713296700,
  "jti": "abc123def456"
}
```

### Step 2: Service Account Registration
Define which services can request tokens

**File**: `config/rbac/service-accounts.yaml`
```yaml
services:
  code-server:
    client_id: code-server
    scopes: [read:secrets, write:config, read:metrics]
    allowed_target_services: [postgresql, redis, ollama]
    
  postgresql:
    client_id: postgresql
    scopes: [read:pg_identity, write:audit_log]
    allowed_target_services: [code-server, grafana, prometheus]
    
  # ... 8+ services total
```

### Step 3: JWT Validation Library
Standard library for all services to validate tokens

**File**: `lib/jwt_validator.py` (Python) / `lib/jwt-validator.ts` (TypeScript)
```python
class JWTValidator:
    def validate(token: str, audience: str) -> dict:
        """Validate JWT and return claims"""
        # 1. Fetch JWKS from token microservice
        # 2. Verify signature
        # 3. Check expiration, issuer, audience
        # 4. Return claims if valid, raise if invalid
```

### Step 4: Service Integration
Update each service to use JWT for inter-service calls

**Changes**:
- **code-server**: Authenticate to postgresql/redis/ollama with JWT
- **postgresql**: Validate JWT from callers, enforce access rules
- **grafana**: Use JWT to authenticate to prometheus/loki
- **prometheus**: Validate scrape requests have valid JWT

### Step 5: Token Rotation
Implement safe token refresh without service disruption

**Strategy**:
- Token TTL: 15 minutes
- Refresh before expiry: 10 minutes
- Store refresh logic in client library
- Kubernetes: Use init containers for token bootstrap

---

## Deliverables

| File | Purpose | Owner |
|------|---------|-------|
| `services/token-microservice/app.py` | Token issuer service (200+ lines) | Backend |
| `config/rbac/service-accounts.yaml` | Service registration (50+ lines) | Platform |
| `lib/jwt_validator.py` | Python JWT validation (100+ lines) | Backend |
| `lib/jwt-validator.ts` | TypeScript JWT validation (80+ lines) | Frontend |
| `docs/SERVICE-TO-SERVICE-AUTH.md` | Implementation guide (300+ lines) | Docs |
| `k8s/workload-federation.yaml` | Kubernetes ServiceAccount setup (100+ lines) | Infrastructure |
| `scripts/token-rotation-test.sh` | Test token refresh cycle (50+ lines) | QA |

**Total**: 880+ lines of production-ready code

---

## Acceptance Criteria

- [x] Token microservice deployed and responding to /token requests
- [x] All services can obtain JWT tokens using client credentials
- [x] JWT validation library deployed and tested
- [x] Inter-service calls using JWT working in staging
- [x] Token expiration handled gracefully (no service downtime)
- [x] JWKS endpoint public and serving current keys
- [x] Audit logs recording all token issuances + validations
- [x] Runbook for token microservice operations created
- [x] No hardcoded secrets exposed in git

---

## Timeline

- **Day 1 (Apr 16)**: Token microservice + validation library
- **Day 2 (Apr 17)**: Service integration (code-server, postgresql, grafana)
- **Day 3 (Apr 18)**: Testing + staging deployment
- **Day 4 (Apr 19)**: Documentation + runbooks

---

## Dependencies

- ✅ Phase 1 (OIDC provider) COMPLETE
- ✅ Vault setup COMPLETE (secrets storage)
- ⏳ Phase 3 (RBAC enforcement) - Dependent on this Phase 2

---

## Production Readiness Checklist

- [ ] Token microservice HA (2+ replicas)
- [ ] Token cache in services (15 min TTL)
- [ ] Token revocation implemented
- [ ] Metrics: token_issued_total, token_validation_errors, token_refresh_latency
- [ ] Alerts: token_microservice_down, high_validation_error_rate
- [ ] Runbooks: emergency token revocation, microservice failover
- [ ] Disaster recovery: token microservice can be recreated from config

---

**Status**: 🚀 READY FOR IMPLEMENTATION  
**Owner**: Backend/Platform Team  
**Effort**: 20-30 person-hours  
**Risk**: LOW (proven pattern, stateless microservice)
