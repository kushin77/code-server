# P1 #388 Phase 3: RBAC Enforcement at Service Boundaries - Implementation Guide

**Status**: Implementation in Progress  
**Phase**: 3 of 4  
**Effort**: 8-10 hours  
**Dependencies**: Phase 1 (OIDC + JWT schema) ✅, Phase 2 (K8s OIDC + mTLS + ServiceAccounts) ✅  
**Target Date**: April 23, 2026  

## Overview

Phase 3 enforces fine-grained role-based access control (RBAC) at service boundaries. This is the critical step that translates identity (Phase 1) and service-to-service auth (Phase 2) into actual policy enforcement.

### Phase 3 Scope

| Component | Responsibility | Status |
|-----------|-----------------|--------|
| **Caddyfile JWT Validation** | Validate JWT tokens from oauth2-proxy, extract claims, enforce per-endpoint RBAC | 🔄 In Progress |
| **Service Boundary Policy** | Define which services can call which APIs based on role + identity_type | 🔄 In Progress |
| **Audit Logging Integration** | Log all access decisions (allow/deny) to PostgreSQL + Prometheus | 🔄 In Progress |
| **Error Handling** | Return 403 Forbidden with audit reason, 401 Unauthorized for missing/invalid tokens | 🔄 In Progress |

## Architecture: Request Flow with Phase 3 RBAC

```
┌─────────────┐
│  External   │
│   Client    │
└──────┬──────┘
       │ HTTP Request
       ▼
┌──────────────────────────┐
│  oauth2-proxy            │
│  (Port 4180)             │
│  ✓ OAuth2/OIDC           │
│  ✓ Extract JWT + claims  │
└──────┬───────────────────┘
       │ X-Auth-Request-* headers
       ▼
┌──────────────────────────┐
│  Caddyfile               │
│  (Port 443/8080)         │
│  ✓ Route to service      │
│  ✓ JWT extraction        │  ← PHASE 3: Enforce here
│  ✓ RBAC validation       │
│  ✓ Audit logging         │
└──────┬───────────────────┘
       │
     ┌─┴─────────────────────────────────────┐
     │ Check: Does role have permission?     │
     │ (based on JWT claims + policy matrix) │
     └──────┬─────────────────┬──────────────┘
            │ Allow           │ Deny
            ▼                 ▼
      ┌──────────┐       ┌──────────┐
      │ Forward  │       │ 403      │
      │ to App   │       │ Forbidden│
      │ Service  │       │ (Log)    │
      └──────────┘       └──────────┘
            │                 │
            └─────────┬───────┘
                      ▼
             ┌────────────────┐
             │ Prometheus      │
             │ (Audit events)  │
             │ allow_count     │
             │ deny_count      │
             │ by_role        │
             └────────────────┘
```

## Phase 3 Implementation Steps

### Step 1: Caddyfile JWT Validation Module

**File**: `config/caddy/jwt-validator.caddyfile`

Caddyfile snippet that:
1. Extracts JWT from `Authorization: Bearer <token>` header
2. Validates JWT signature using OIDC public key
3. Extracts claims: `sub`, `role`, `identity_type`, `iss`
4. Passes claims to policy evaluator

**JWT Claims Expected** (from Phase 1):
```json
{
  "sub": "user123@company.com",
  "role": "admin|operator|viewer",
  "identity_type": "human|workload|automation",
  "iss": "https://oauth.company.com",
  "aud": "code-server",
  "exp": 1713916800,
  "iat": 1713913200
}
```

### Step 2: RBAC Policy Enforcer

**File**: `config/iam/rbac-policy-phase3.yaml`

Defines per-endpoint access control:

```yaml
policies:
  # Code-Server Portal
  /code-server:
    GET:
      allow_roles: [admin, operator, viewer]
      allow_identity_types: [human, workload]
    POST:
      allow_roles: [admin]
      allow_identity_types: [human]

  # Prometheus Metrics
  /prometheus/api/v1/query:
    GET:
      allow_roles: [admin, operator, viewer]
      allow_identity_types: [human, workload]
    POST:
      allow_roles: []
      allow_identity_types: []

  # Admin Functions (Restart, Deploy)
  /admin/restart:
    POST:
      allow_roles: [admin]
      allow_identity_types: [human]
  
  /admin/deploy:
    POST:
      allow_roles: [admin]
      allow_identity_types: [human]
```

### Step 3: Audit Logging Integration

**PostgreSQL Table** (from Phase 1, now used in Phase 3):

```sql
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id TEXT NOT NULL,
  role TEXT NOT NULL,
  identity_type TEXT NOT NULL,
  method TEXT NOT NULL,
  path TEXT NOT NULL,
  action TEXT NOT NULL,  -- 'allow' | 'deny'
  reason TEXT,           -- Why was it allowed/denied
  status_code INT,
  ip_address INET,
  user_agent TEXT,
  CONSTRAINT immutable CHECK (timestamp <= NOW())
);

CREATE INDEX idx_audit_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_user_role ON audit_logs(user_id, role);
```

### Step 4: Prometheus Metrics

**Metrics to emit**:

```
# Counter: RBAC decisions by role and action
rbac_decision_total{role="admin", action="allow", endpoint="/admin/deploy"} 1
rbac_decision_total{role="viewer", action="deny", endpoint="/admin/deploy", reason="insufficient_role"} 1

# Histogram: Policy evaluation latency (must be <10ms)
rbac_policy_eval_seconds{endpoint="/code-server", status="allow"}

# Gauge: Current active authenticated users by role
rbac_active_sessions{role="admin"} 3
rbac_active_sessions{role="operator"} 12
rbac_active_sessions{role="viewer"} 45
```

### Step 5: Error Handling & Responses

**403 Forbidden Response**:
```json
{
  "error": "Forbidden",
  "message": "Your role (viewer) does not have permission for this action (POST /admin/deploy)",
  "required_role": "admin",
  "your_role": "viewer",
  "audit_id": "audit-12345678",
  "timestamp": "2026-04-23T14:35:00Z"
}
```

**401 Unauthorized Response**:
```json
{
  "error": "Unauthorized",
  "message": "Missing or invalid JWT token",
  "audit_id": "audit-87654321",
  "timestamp": "2026-04-23T14:35:00Z"
}
```

## Implementation Checklist

### 1. JWT Validation in Caddyfile
- [ ] Add `jwt-validator` module to Caddyfile
- [ ] Extract JWT from Authorization header
- [ ] Validate JWT signature using OIDC public key
- [ ] Extract claims into Caddy variables
- [ ] Pass to policy evaluator

### 2. Policy Enforcement
- [ ] Define RBAC policy matrix in `config/iam/rbac-policy-phase3.yaml`
- [ ] Implement policy lookup function (role + endpoint → allow/deny)
- [ ] Return 403 for denied requests
- [ ] Log decision to audit_logs table

### 3. Prometheus Integration
- [ ] Export RBAC decision metrics to Prometheus
- [ ] Create Grafana dashboard: "RBAC Decisions by Role"
- [ ] Create Grafana dashboard: "Policy Enforcement Latency"
- [ ] Add alerts: "High deny rate" (>5% denial rate)

### 4. Testing & Validation
- [ ] Unit tests: Policy evaluator (role matrix)
- [ ] Integration tests: JWT extraction + policy enforcement
- [ ] Performance tests: Policy eval <10ms p99
- [ ] Chaos test: Deny all requests → verify 403 responses

### 5. Documentation & Runbooks
- [ ] Create `docs/runbooks/rbac-enforcement.md`
- [ ] Troubleshooting: "User getting 403 — how to debug"
- [ ] Runbook: "Add new role"
- [ ] Runbook: "Audit RBAC denials"

## Dependencies & Blockers

**Must Complete Before Phase 3**:
- ✅ Phase 1: OIDC + JWT claims schema
- ✅ Phase 2: K8s ServiceAccount federation + mTLS

**Will Enable**:
- Phase 4: Compliance automation (uses audit logs from Phase 3)

## Success Criteria

✅ JWT tokens are validated at service boundary  
✅ RBAC policy enforced per endpoint + method  
✅ 403 Forbidden returned for denied requests  
✅ All access decisions logged to PostgreSQL  
✅ Prometheus metrics show allow/deny distribution  
✅ Policy evaluation latency <10ms p99  
✅ Zero unplanned access (security tests pass)  

## Timeline

- **Hour 1-2**: Implement Caddyfile JWT validator
- **Hour 2-3**: Implement RBAC policy enforcer
- **Hour 4-5**: Audit logging integration
- **Hour 6-7**: Prometheus metrics + Grafana dashboards
- **Hour 8**: Testing & validation
- **Hour 9-10**: Documentation & runbooks

## Next Phase (Phase 4)

After Phase 3 RBAC enforcement is live, Phase 4 will:
- Automate compliance evidence collection (use audit logs)
- Generate SOC2/ISO27001/GDPR compliance reports
- Implement break-glass procedures (emergency admin access)
- Create audit retention policies (7-year minimum)

---

**Owner**: Infrastructure Team  
**Created**: April 23, 2026  
**Status**: Ready for Implementation
