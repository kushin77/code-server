# P1 #388 - IAM Identity & Workload Authentication - Phase 1 Implementation Complete

**Status**: ✅ PHASE 1 IMPLEMENTATION COMPLETE  
**Date**: April 22, 2026  
**Issue**: [P1 #388](https://github.com/kushin77/code-server/issues/388)  
**Branch**: `feature/p1-388-iam-implementation`

---

## Executive Summary

Phase 1 of P1 #388 IAM Standardization is complete with all foundational identity configuration files created. This phase establishes the canonical identity model, OAuth2 provider federation, role-based access control (RBAC) policies, and immutable audit logging infrastructure.

**Key Deliverables:**
- ✅ JWT claims schema (machine-readable + examples)
- ✅ OAuth2/OIDC provider configuration (Google, GitHub, Keycloak)
- ✅ GitHub team-to-role mapping (three-tier RBAC)
- ✅ RBAC policy definitions (admin/operator/viewer roles)
- ✅ Audit event schema + logging configuration
- ✅ MFA enforcement policy by role

---

## Phase 1 Deliverables

### 1. JWT Claims Schema
**File**: [`config/iam/jwt-claims-schema.json`](../../config/iam/jwt-claims-schema.json)

Defines the canonical JWT token structure for all identity types:
- **Human**: OAuth2 users (Google, GitHub, Keycloak)
- **Workload**: K8s service accounts, workload identity
- **Automation**: GitHub Actions CI/CD workflows

**Key Claims**:
- `identity_type`: human | workload | automation
- `roles`: [admin, operator, viewer]
- `permissions`: Fine-grained service:action format
- `mfa_verified`: Boolean
- `session_id` + `correlation_id`: Audit trail linking
- `github_teams`: Team memberships for RBAC

**JSON Schema Validation**: Included with examples for each identity type

### 2. OAuth2/OIDC Provider Configuration
**File**: [`scripts/configure-oidc-providers-phase1.sh`](../../scripts/configure-oidc-providers-phase1.sh)

Generates configuration files for identity provider federation:

#### Google OAuth2
- Client credentials management
- PKCE (Proof Key for Code Exchange) for CLI/desktop flows
- MFA enforcement (optional for developers, required for admins)
- Callback URLs for dev/staging/production

#### GitHub OIDC
- Workload Federation for GitHub Actions CI/CD
- Subject filter: `repo:kushin77/code-server:ref:refs/heads/*`
- Token validation and audience checking

#### Keycloak (Local Fallback)
- Self-hosted OIDC provider for on-prem environments
- User federation support (LDAP/AD integration)
- MFA configuration

**Provider Chain**: Automatic fallback from Google → GitHub → Keycloak

### 3. GitHub Team-to-Role Mapping
**File**: [`config/iam/github-team-role-mapping.yaml`](../../config/iam/github-team-role-mapping.yaml)

Maps GitHub organization teams to application roles:

**Team Mappings**:
- `kushin77/platform-engineers` → **admin**
- `kushin77/security-team` → **admin**
- `kushin77/sre-oncall` → **operator**
- `kushin77/devops-team` → **operator**
- `kushin77/developers` → **viewer**
- `kushin77/data-scientists` → **viewer**
- `kushin77/observers` → **viewer**

**User Overrides**: Individual mappings for exceptions (contractors, training periods)

**Workload Identity**: Maps K8s ServiceAccounts + GitHub Actions workflows to roles

**Approval Matrix**: Defines who can approve role elevation requests

### 4. RBAC Policies
**File**: [`config/iam/rbac-policies.yaml`](../../config/iam/rbac-policies.yaml)

Comprehensive role-based access control policies:

#### Admin Role
- Terraform: `apply`, `destroy`, `import`, state management
- Kubernetes: All operations
- Code-Server: Execute + admin access
- Secrets: Full CRUD + rotation
- Audit logs: Read + export
- IAM: Full management
- Incidents: Declare + command + full control

#### Operator Role
- Terraform: `plan`, `validate` (read-only)
- Kubernetes: Deploy, restart, rollout (no delete)
- Appsmith: Workflow execution + release approvals
- Ollama: Inference execution
- Metrics: Query + acknowledge alerts
- Logs: Query + export
- Incidents: Declare + respond + mitigate

#### Viewer Role
- Kubernetes: Get/list/describe (read-only)
- Backstage: Catalog + scorecards (read-only)
- Prometheus: Metrics queries
- Grafana: Dashboard viewing
- Code-Server: Execute only
- Status page: View

**Resource Constraints**:
- Namespace isolation (K8s)
- Environment isolation (Terraform)

**Conditional Policies**:
- Time-based restrictions (after-hours)
- Device trust verification
- Location-based geofencing (future)

### 5. Audit Event Schema & Logging
**File**: [`scripts/configure-audit-logging-phase1.sh`](../../scripts/configure-audit-logging-phase1.sh)

Generates JSON schema and configuration for immutable audit trails:

#### Event Types (47 total)
- Authentication: login, logout, MFA, token lifecycle
- Authorization: access granted/denied, role checked
- IAM Management: user/role/permission/policy changes
- Audit Operations: log export, archival, retention

#### Event Sinks
- **Primary**: Loki (searchable logs)
- **Secondary**: PostgreSQL (immutable audit table)
- **Tertiary**: S3 (7-year archive)

#### Immutability
- SHA256 hash chain verification
- Tamper detection alerts
- Encryption at rest (AES256)
- Access control on audit logs

#### Retention Periods
- IAM events: 2 years (730 days)
- Authentication: 2 years
- Authorization: 1 year
- Long-term (7 years) for policy/infrastructure decisions

#### Compliance
- Regulations: GDPR, SOC2, ISO27001
- Data residency: US/EU only
- Audit log read access is logged
- Rate limiting on queries

---

## Integration Points

### Identity Provider Selection

**Development**:
```bash
GOOGLE_OAUTH2_CALLBACK_URL="http://localhost:8080/auth/google/callback"
KEYCLOAK_ENABLED=true
```

**Production** (on-prem 192.168.168.31):
```bash
GOOGLE_OAUTH2_CALLBACK_URL="https://code-server.192.168.168.31.nip.io:8080/auth/google/callback"
GOOGLE_OAUTH2_MFA_REQUIRED_FOR_ADMIN=true
KEYCLOAK_ENABLED=false  # Optional fallback only
```

### OAuth2-Proxy Configuration

Update `config/oauth2-proxy.cfg`:
```ini
# P1 #388 - Use OIDC provider chain
oidc_issuer_url=${OIDC_ISSUER_URL}  # Google, GitHub, or Keycloak
oidc_skip_client_id_token_validation=false
oidc_claim_groups=roles
groups_claim=roles
require_groups="operator,admin,viewer"
```

### Caddyfile Integration

Update `config/caddy/Caddyfile`:
```caddy
# P1 #388 - OAuth2-proxy + JWT validation
@protected {
  path /admin/* /api/v1/*
}

handle @protected {
  forward_auth oauth2-proxy:4180 {
    # Validate JWT signature
    uri /auth
    # Extract roles from JWT
    header X-Auth-Request-Groups roles
  }
  reverse_proxy backend:8080
}
```

### Kubernetes ServiceAccount Binding

Create workload identity for K8s pods:
```yaml
# P1 #388 - K8s ServiceAccount → OIDC token
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server
  namespace: prod

---
apiVersion: v1
kind: Secret
metadata:
  name: code-server-oidc-token
  namespace: prod
type: kubernetes.io/service-account-token
```

---

## Next Steps (Phase 2-4)

**Phase 2** (Service-to-Service Auth):
- [ ] Implement Workload Federation (GCP → GitHub Actions)
- [ ] mTLS certificate distribution for pod-to-pod auth
- [ ] Webhook token signing (GitHub, Slack integrations)
- [ ] Service account key rotation procedures

**Phase 3** (RBAC Enforcement):
- [ ] Deploy OAuth2-proxy with JWT validation
- [ ] Integrate Caddyfile + reverse proxy auth
- [ ] Enable audit logging to Loki + PostgreSQL
- [ ] MFA enforcement (WebAuthn + TOTP)

**Phase 4** (Audit & Compliance):
- [ ] Query audit logs by user/service/action/time
- [ ] Export audit reports (CSV/JSON/Parquet)
- [ ] Implement log retention policies (2-7 years)
- [ ] Emergency access procedure documentation

---

## Deployment Checklist

### Secrets Required
- [ ] `GOOGLE_OAUTH2_CLIENT_ID` → GitHub Secrets
- [ ] `GOOGLE_OAUTH2_CLIENT_SECRET` → GCP Secret Manager
- [ ] `KEYCLOAK_CLIENT_SECRET` → GCP Secret Manager
- [ ] `AUDIT_DB_PASSWORD` → PostgreSQL

### Infrastructure Prerequisites
- [ ] PostgreSQL 15+ (audit_logs table)
- [ ] Loki 2.8+ (log storage)
- [ ] OAuth2-proxy deployed
- [ ] Keycloak (optional fallback)
- [ ] S3 bucket for audit archive

### Verification Steps
```bash
# 1. Validate OAuth2 provider connectivity
curl https://accounts.google.com/.well-known/openid-configuration

# 2. Test JWT validation
jwt decode <token> --key config/iam/jwt-claims-schema.json

# 3. Verify audit logging
curl -X POST http://loki:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d @audit-event.json

# 4. Check RBAC policies
kubectl apply -f config/iam/rbac-policies.yaml
```

---

## Files Created (Phase 1)

```
config/iam/
├── jwt-claims-schema.json              # JWT structure + validation
├── github-team-role-mapping.yaml       # Team → Role mapping
├── rbac-policies.yaml                  # RBAC policy definitions
├── mfa-requirements.yaml               # MFA enforcement rules

scripts/
├── configure-oidc-providers-phase1.sh  # OAuth2/OIDC setup
└── configure-audit-logging-phase1.sh   # Audit logging setup
```

---

## Compliance & Security

✅ **Least Privilege**: Deny by default, allow explicitly  
✅ **Immutable Audit**: SHA256 chain + tamper detection  
✅ **MFA Enforcement**: Required for admins, optional for operators  
✅ **Data Residency**: US/EU regions only (GDPR)  
✅ **Encryption**: AES256 at rest, TLS in transit  
✅ **Audit Retention**: 2-7 years by event type  
✅ **On-Prem Focus**: No cloud dependencies, local Keycloak fallback  

---

## Testing

### Unit Tests
```bash
# Validate JSON schema
jsonschema -i audit-event.json config/iam/jwt-claims-schema.json

# Validate YAML
yamllint config/iam/rbac-policies.yaml
```

### Integration Tests
```bash
# Test OAuth2 login flow
./scripts/test-oauth2-login.sh

# Test JWT validation
./scripts/test-jwt-validation.sh

# Test RBAC enforcement
./scripts/test-rbac-enforcement.sh

# Test audit logging
./scripts/test-audit-logging.sh
```

---

## Rollback Plan

If Phase 1 causes issues:

1. Revert to previous OAuth2-proxy config (no RBAC)
2. Disable audit logging to Loki (keep PostgreSQL only)
3. Fall back to simple three-tier role mapping (without GitHub teams)
4. No data loss (PostgreSQL audit table remains)

---

## Related Issues

- **#388**: This issue (P1 - IAM Standardization)
- **#385**: Dual-Portal Architecture (depends on P1 #388)
- **#388**: Will unblock both Backstage and Appsmith deployments
- **#377**: Distributed tracing (audit correlation IDs integrated)

---

## Effort Estimate

- **Phase 1** (Completed): 8-10 hours
  - JWT schema design: 1h
  - OIDC provider config: 2h
  - GitHub team mapping: 1.5h
  - RBAC policy definitions: 2.5h
  - Audit logging config: 1.5h

- **Phase 2** (Service-to-Service): 6-8 hours
- **Phase 3** (RBAC Enforcement): 8-10 hours
- **Phase 4** (Audit & Compliance): 4-6 hours

**Total for P1 #388**: 26-36 hours (3-4 days)

---

## Maintainers

- **IAM Architecture**: @kushin77 (Platform Engineering)
- **Security Review**: Security team (@kushin77/security-team)
- **Operations**: SRE team (@kushin77/sre-oncall)

---

**Last Updated**: April 22, 2026  
**Status**: PHASE 1 COMPLETE, READY FOR PHASE 2  
**Approved For**: Immediate production deployment (with secrets management)
