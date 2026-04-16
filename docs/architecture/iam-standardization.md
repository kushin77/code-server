# P1 #388: IAM Identity & Workload Authentication Standardization

**Status**: Implementation Ready  
**Priority**: P1 BLOCKING  
**Date**: April 22, 2026  
**Owner**: Infrastructure Team  

---

## Executive Summary

Standardize identity management, role-based access control (RBAC), and workload authentication across all infrastructure. This unifies fragmented auth approaches (OAuth2, service accounts, K8s RBAC, API tokens) into a cohesive system.

---

## Problem Statement

Current state has multiple identity systems:
- **Human**: OAuth2 (Google, OIDC) via oauth2-proxy
- **Service**: Kubernetes service accounts (RBAC)
- **Workload**: API tokens (unsecured, unaudited)
- **Automation**: CI/CD secrets (scattered, immutable)

**Gaps**:
- No unified audit trail across all auth types
- Workload identities not federated to human identity
- No automatic credential rotation
- No workload account isolation (least privilege)
- Missing emergency access (break-glass) procedures

---

## Solution Architecture

### Three-Tier Identity Model

#### Tier 1: Human Identities (OAuth2 + MFA)
**Who**: Developers, operators, admins  
**Auth**: Google OIDC + TOTP MFA (mandatory for admins)  
**Token Lifetime**: 1 hour (session-based)  
**Revocation**: Immediate (session revocation)  
**Audit**: Full audit trail via Loki  

**Implementation**:
```yaml
OAuth2 Configuration:
- Provider: Google Workspace
- Redirect URI: https://{{ domain }}/oauth2/callback
- Scopes: openid, email, profile
- MFA: TOTP (via authenticator app)
- Session timeout: 1 hour
- Refresh token: 7 days (auto-refresh if active)

Allowed Users:
- Provisioned in allowed-emails.txt (via Terraform)
- Added to Google Workspace group (manual)
- RBAC role assigned (dev/admin/viewer)
```

**Role Matrix**:

| Role | Session | Audit | Code-Server | Infrastructure | Secrets |
|------|---------|-------|-------------|-----------------|---------|
| **viewer** | 1h | Read-only | View-only | Read-only | None |
| **developer** | 2h | Full | Full access | VCS, logs | Read app secrets |
| **admin** | 4h | Full | Full access | Full access | Read+write all |
| **break-glass** | 15m | Full | Full access | Full access | Full access (emergency only) |

---

#### Tier 2: Workload Identities (K8s + SPIFFE)
**Who**: Code-server, Loki, Prometheus, Kong, Ollama  
**Auth**: K8s ServiceAccount + SPIFFE/OIDC federation  
**Token Lifetime**: 1 hour (auto-renewed by kubelet)  
**Revocation**: Pod termination  
**Audit**: All API calls logged with workload identity  

**Implementation**:
```yaml
# Example: Code-server workload identity
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server
  namespace: production

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: code-server-role
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  resourceNames: ["app-config"]  # Least privilege: specific resource
  verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: code-server-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: code-server-role
subjects:
- kind: ServiceAccount
  name: code-server
  namespace: production
```

**SPIFFE Identity**:
- **Format**: `spiffe://{{ domain }}/ns/production/sa/code-server`
- **Cert Lifetime**: 1 hour (auto-rotated by Cert-Manager)
- **Verification**: Mutual TLS (code-server and Kong verify each other's SPIFFE identity)

---

#### Tier 3: Automation Identities (CI/CD + GCP Service Accounts)
**Who**: GitHub Actions, Terraform, deployment scripts  
**Auth**: Short-lived tokens via OIDC federation  
**Token Lifetime**: 15 minutes (GitHub Actions → GCP OIDC token)  
**Revocation**: Auto-revoked after use  
**Audit**: All actions logged with automation account  

**Implementation**:
```yaml
# GitHub Actions OIDC → GCP Service Account Federation

# 1. Create GCP service account
gcloud iam service-accounts create github-actions \
  --display-name="GitHub Actions CI/CD"

# 2. Create Workload Identity Pool + Provider
gcloud iam workload-identity-pools create "github-pool" \
  --project="${GCP_PROJECT}" \
  --location="global" \
  --display-name="GitHub Actions"

gcloud iam workload-identity-providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --project="${GCP_PROJECT}"

# 3. Grant permissions
gcloud iam service-accounts add-iam-policy-binding \
  "github-actions@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${GCP_PROJECT}/locations/global/workloadIdentityPools/github-pool/attribute.repository/kushin77/code-server"

# 4. Grant actual permissions (e.g., terraform apply)
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:github-actions@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"
```

**Permissions Matrix**:
- **Terraform apply**: Compute.instanceAdmin.v1, Monitoring.admin
- **Deploy images**: Artifact Registry writer
- **Modify secrets**: Secret Manager admin (limited to prod-* secrets)

---

### Cross-Tier Integration

#### User → Workload Token Exchange
When a developer logs in via OAuth2, they get a session token valid for accessing workload APIs:

```
User (OAuth2) → Code-server API
  1. Browser sends OAuth2 token to Code-server
  2. Code-server extracts user identity
  3. Code-server calls Kong API Gateway (mTLS with SPIFFE)
  4. Kong verifies Code-server identity (SPIFFE cert)
  5. Kong grants access if user role permits
  6. Request routed to upstream service
```

#### Workload → Human Audit Binding
Every action is audited with both identities:

```json
{
  "timestamp": "2026-04-22T14:30:00Z",
  "human_identity": "alice@kushnir.cloud",
  "human_role": "admin",
  "workload_identity": "spiffe://kushnir.cloud/ns/production/sa/code-server",
  "action": "WRITE /api/workspace/file.ts",
  "resource": "/mnt/workspace/file.ts",
  "result": "allowed",
  "audit_log_id": "audit-20260422-1430-xyz123"
}
```

---

## Implementation Plan

### Phase 1: Foundation (Week 1)
- ✅ [x] OAuth2 + MFA configuration (code-server, oauth2-proxy)
- ✅ [x] K8s ServiceAccount + RBAC (all services)
- [ ] GitHub Actions OIDC → GCP federation
- [ ] Audit logging infrastructure (Loki)
- [ ] Break-glass account setup

### Phase 2: Integration (Week 2)
- [ ] mTLS between services (Kong → all upstreams)
- [ ] SPIFFE certificate deployment
- [ ] Cross-tier audit binding
- [ ] Token lifecycle automation

### Phase 3: Hardening (Week 3)
- [ ] Rate limiting per workload identity
- [ ] Automatic credential rotation
- [ ] Emergency access procedures
- [ ] Incident response playbooks

### Phase 4: Validation (Week 4)
- [ ] SOC 2 compliance verification
- [ ] Penetration testing
- [ ] Runbook documentation
- [ ] Team training

---

## Deliverables

### Documentation
- [ ] `docs/IAM-ARCHITECTURE.md` — Complete identity architecture
- [ ] `docs/RBAC-MATRIX.md` — Role definitions and permissions
- [ ] `docs/WORKLOAD-IDENTITY.md` — Service account provisioning guide
- [ ] `docs/INCIDENT-RESPONSE.md` — Emergency access and incident response
- [ ] `docs/AUDIT-SCHEMA.md` — Audit log schema and retention policy

### Terraform/IaC
- [ ] `terraform/iam.tf` — IAM policies and service accounts
- [ ] `terraform/rbac.tf` — K8s RBAC configuration
- [ ] `terraform/audit.tf` — Audit logging configuration
- [ ] `terraform/users.tf` — User and team provisioning (already exists)

### Configuration Files
- [ ] `config/_base-config.env` — OAuth2 and MFA settings
- [ ] `config/rbac-policies.yaml` — K8s RBAC definitions
- [ ] `config/audit-schema.json` — Audit log schema

### Scripts
- [ ] `scripts/provision-workload-identity.sh` — Workload identity setup
- [ ] `scripts/rotate-credentials.sh` — Credential rotation automation
- [ ] `scripts/emergency-access.sh` — Break-glass account procedures

### Tests
- [ ] Unit tests: RBAC enforcement
- [ ] Integration tests: Cross-tier token exchange
- [ ] E2E tests: Full auth flow (user → workload → resource)
- [ ] Security tests: Unauthorized access rejection

---

## Success Criteria

✅ **Authentication**:
- [ ] 100% of human users via OAuth2 + MFA
- [ ] 100% of workloads via K8s ServiceAccount + SPIFFE
- [ ] 100% of automation via GCP OIDC federation

✅ **Authorization**:
- [ ] All API calls respect RBAC rules
- [ ] Least privilege enforced (no wildcard permissions)
- [ ] Rate limiting per identity (1000 req/min default, 10 for auth endpoints)

✅ **Audit**:
- [ ] 100% of authenticated actions logged
- [ ] Audit logs immutable (S3 WORM)
- [ ] Audit logs queryable in Loki

✅ **Incidents**:
- [ ] Unauthorized access attempts logged and alerted
- [ ] Break-glass account usable in <5 minutes
- [ ] Incident response runbook tested and documented

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| OAuth2 provider outage | Medium | High | Fallback to local service accounts (temporary) |
| Certificate expiry | Low | Critical | Cert-manager auto-rotation + alerting |
| Credential leak | Low | Critical | Immediate token revocation, incident response |
| Performance degradation | Medium | Medium | Cache tokens, connection pooling |

---

## Estimated Effort

- **Phase 1**: 8-12 hours (foundation, deployment)
- **Phase 2**: 8-10 hours (integration, testing)
- **Phase 3**: 6-8 hours (hardening, security validation)
- **Phase 4**: 4-6 hours (compliance, documentation)

**Total**: 26-36 hours (3-4 days, parallel execution possible)

---

## Dependencies

- ✅ OAuth2 infrastructure (code-server, oauth2-proxy)
- ✅ Kubernetes cluster (local or GKE)
- ✅ GCP project (gcp-eiq)
- ✅ Cert-manager (for SPIFFE certificates)
- ✅ Loki (for audit logging)
- ✅ Prometheus (for monitoring)

---

## References

- SPIFFE/OIDC: https://spiffe.io/docs/latest/
- K8s RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- OAuth2 Best Practices: https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics
- SOC 2 Type II: https://www.aicpa.org/soc2

---

**Created**: April 22, 2026  
**Status**: READY FOR IMPLEMENTATION  
**Owner**: @kushin77  
**Next Step**: Approve plan → Assign Phase 1 implementation
