# Workload Federation Implementation Guide (P1 #388)

## Overview

This document describes the implementation of workload federation for kushin77/code-server on-prem infrastructure. Workload federation replaces long-lived credentials with short-lived, token-based access for:

- GitHub Actions CI/CD workflows
- Kubernetes ServiceAccounts
- Backend microservices
- Observability systems (Prometheus, Loki, Jaeger)

**Status**: Phase 1-2 implementation complete. Ready for Kubernetes deployment.

---

## Architecture: Four Phases

### Phase 1: OIDC & RBAC Baseline (✅ IMPLEMENTED)

**Scope**: GitHub Actions OIDC claims validation, RBAC definitions, audit logging

**Files**:
- `config/github-actions-oidc.yaml` - OIDC claim validation rules
- `config/rbac-roles.yaml` - RBAC role definitions and mappings
- `config/audit-logging-oidc.yaml` - Audit event specifications
- `scripts/configure-workload-federation-phase1.sh` - Setup script

**What It Does**:
1. Validates GitHub Actions JWT tokens from `https://token.actions.githubusercontent.com`
2. Maps subject claims to roles: main/PR/release branches get different TTLs and permissions
3. Logs all token exchanges and permission checks for security audit

**Example Claim Validation**:
```yaml
Main branch claim: repo:kushin77/code-server:ref:refs/heads/main
→ Role: automation/operator (900s TTL, full CI/CD permissions)

PR claim: repo:kushin77/code-server:pull_request
→ Role: automation/viewer (300s TTL, read-only permissions)

Release claim: repo:kushin77/code-server:ref:refs/tags/v*
→ Role: automation/operator (600s TTL, full CI/CD permissions)
```

**Execution**:
```bash
cd /root/code-server-enterprise
./scripts/configure-workload-federation-phase1.sh
```

---

### Phase 2: Kubernetes ServiceAccounts & mTLS (✅ IMPLEMENTED)

**Scope**: Kubernetes-native workload federation, mTLS certificate infrastructure

**Files**:
- `config/iam/github-oidc.env.template` - GitHub OIDC environment variables
- `config/iam/k8s-oidc.env.template` - Kubernetes OIDC issuer configuration
- `config/iam/k8s-serviceaccounts.yaml` - ServiceAccount manifests (6 accounts)
- `config/iam/k8s-serviceaccount-roles.yaml` - ServiceAccount-to-role mappings
- `config/iam/mtls-config.yaml` - cert-manager certificate setup
- `config/iam/api-tokens-config.yaml` - API token management policy
- `config/iam/token-validation-service.yaml` - Token validation service deployment
- `scripts/configure-workload-federation-phase2.sh` - Setup script

**ServiceAccounts Created**:
| Namespace | Account | Role | Permissions |
|-----------|---------|------|-------------|
| prod | code-server | workload/viewer | code-server:execute, logs:write, metrics:export |
| prod | backstage | workload/operator | backstage:catalog, github:api, kubernetes:services |
| prod | appsmith | workload/operator | appsmith:workflows, deployments:execute, incidents:view |
| prod | ollama | workload/viewer | ollama:inference, metrics:export |
| monitoring | prometheus | workload/viewer | prometheus:scrape, kubernetes:pods |
| monitoring | loki | workload/viewer | loki:write, kubernetes:pods |

**Token Validation Service**:
- Validates OIDC tokens from Kubernetes ServiceAccounts
- Caches JWKS for 5 minutes to reduce issuer load
- Returns claims validated against known roles
- Exposes HTTP API on port 9000

**Execution**:
```bash
cd /root/code-server-enterprise
./scripts/configure-workload-federation-phase2.sh

# Deploy to Kubernetes
kubectl apply -f config/iam/k8s-serviceaccounts.yaml
kubectl apply -f config/iam/token-validation-service.yaml

# Install cert-manager (prerequisite)
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace

# Apply mTLS configuration
kubectl apply -f config/iam/mtls-config.yaml
```

---

### Phase 3: API Token Management (PLANNED)

**Scope**: Long-lived token issuance, rotation, revocation

**Implementation**:
- Token store: PostgreSQL with AES-256 encryption
- Token format: HMAC-SHA256 signed, base64url encoded
- Rotation policy: Monthly automated rotation with 7-day notification
- Revocation: Immediate, with 24-hour grace period for graceful shutdown

**Files** (to be created):
- `config/iam/token-management-policy.yaml` - Token lifecycle specification
- `scripts/configure-token-management-phase3.sh` - Setup and migration script
- `src/services/token-management/` - Go implementation

---

### Phase 4: Multi-Cluster Federation (PLANNED)

**Scope**: Cross-cluster workload identity synchronization

**Implementation**:
- Primary cluster (192.168.168.31): Single source of truth for OIDC issuer
- Replica cluster (192.168.168.42): Federated identity provider
- Sync mechanism: GitOps-driven, using Flux or ArgoCD

**Files** (to be created):
- `terraform/modules/multi-cluster-federation/` - Cluster-to-cluster routing
- `kubernetes/argocd-sync/` - Synchronization specifications

---

## API Token Management Pattern

Workload federation uses a unified token model for both short-lived and long-lived credentials:

### Token Generation

```
1. Service requests token from token-validation-service
   POST /tokens/exchange
   Headers: {
     "Authorization": "Bearer <kubernetes-sa-token>"
   }
   Body: {
     "service": "prometheus",
     "scope": "prometheus:scrape"
   }

2. Token validation service validates Kubernetes SA token
   - Fetches JWKS from Kubernetes API server
   - Validates signature and claims
   - Checks ServiceAccount-to-role mapping
   - Verifies requested scope is in role permissions

3. Service returns time-limited token
   {
     "access_token": "tok_base64url_encoded_token",
     "token_type": "Bearer",
     "expires_in": 3600,
     "scope": "prometheus:scrape"
   }

4. Service uses token in subsequent API calls
   GET /metrics
   Headers: {
     "Authorization": "Bearer tok_base64url_encoded_token"
   }
```

### Token Storage (Phase 3)

- **Short-lived tokens** (< 1 hour): In-memory cache only
- **Long-lived tokens** (> 1 day): PostgreSQL with encryption
- **Cache hierarchy**:
  1. Memory (5-minute TTL)
  2. Redis (1-hour TTL)
  3. PostgreSQL (source of truth, encrypted)

### Token Rotation

```yaml
# Rotation policy (config/iam/api-tokens-config.yaml)
rotation:
  schedule: "0 0 1 * *"         # 1st of month at 00:00 UTC
  notification_days_before: 7   # Email warning 7 days before
  grace_period_hours: 24        # Old token valid for 24h after rotation
  batch_size: 50                # Rotate 50 tokens per batch
  max_concurrent_rotations: 5   # Don't overwhelm issuer
```

### Token Revocation

```bash
# Immediate revocation (emergency)
curl -X DELETE https://token-validation-service/tokens/tok_xxx \
  -H "Authorization: Bearer <admin-token>"

# Graceful revocation (30-second grace period)
curl -X POST https://token-validation-service/tokens/tok_xxx/revoke \
  -H "Authorization: Bearer <admin-token>" \
  -d '{"grace_period_seconds": 30}'
```

---

## OIDC Integration Points

### GitHub Actions

**Issuer**: `https://token.actions.githubusercontent.com`

**Claim Format**:
```json
{
  "iss": "https://token.actions.githubusercontent.com",
  "aud": "kushin77/code-server",
  "sub": "repo:kushin77/code-server:ref:refs/heads/main",
  "repository_owner": "kushin77",
  "repository": "code-server",
  "ref": "refs/heads/main",
  "sha": "abc123...",
  "event_name": "push",
  "run_id": "123456789",
  "run_attempt": "1",
  "actor": "github-actions[bot]"
}
```

**Validation in config/github-actions-oidc.yaml**:
- Issuer must be `https://token.actions.githubusercontent.com`
- Audience must be `kushin77/code-server`
- Subject must match branch/tag pattern
- Repository owner must be `kushin77`

### Kubernetes ServiceAccounts

**Issuer**: `https://oidc.{deploy-host}.nip.io`

**Claim Format**:
```json
{
  "iss": "https://oidc.192.168.168.31.nip.io",
  "aud": "kubernetes.default.svc.cluster.local",
  "sub": "system:serviceaccount:prod:code-server",
  "kubernetes.io/serviceaccount/namespace": "prod",
  "kubernetes.io/serviceaccount/name": "code-server",
  "kubernetes.io/serviceaccount/secret.name": "code-server-token-abc123"
}
```

**Validation in config/iam/k8s-oidc.env.template**:
- Issuer must match cluster OIDC configuration
- Audience must be Kubernetes API server default service
- Subject must match ServiceAccount format

---

## Deployment Checklist

### Prerequisites
- [ ] Kubernetes 1.21+ (OIDC service account support)
- [ ] cert-manager v1.8+ (for certificate management)
- [ ] Helm 3.6+ (for package management)
- [ ] PostgreSQL 13+ (for token storage, Phase 3)
- [ ] Redis 6+ (for token caching, Phase 3)

### Phase 1: OIDC & RBAC
- [ ] Run `./scripts/configure-workload-federation-phase1.sh`
- [ ] Review generated YAML in `config/`
- [ ] Add GitHub Actions workflow with OIDC token exchange
- [ ] Test GitHub Actions deployment with new OIDC token

### Phase 2: Kubernetes
- [ ] Run `./scripts/configure-workload-federation-phase2.sh`
- [ ] Install cert-manager: `helm install cert-manager jetstack/cert-manager ...`
- [ ] Apply ServiceAccounts: `kubectl apply -f config/iam/k8s-serviceaccounts.yaml`
- [ ] Apply token validation service: `kubectl apply -f config/iam/token-validation-service.yaml`
- [ ] Apply mTLS: `kubectl apply -f config/iam/mtls-config.yaml`
- [ ] Verify ServiceAccounts: `kubectl get sa -n prod`
- [ ] Verify token validation service: `kubectl get pods -n code-server-iam`

### Phase 3: Token Management (Future)
- [ ] Configure PostgreSQL token store
- [ ] Deploy token management service
- [ ] Migrate existing long-lived tokens
- [ ] Test token rotation

### Phase 4: Multi-Cluster (Future)
- [ ] Configure replica cluster OIDC
- [ ] Deploy cluster federation mesh
- [ ] Test cross-cluster workload identity

---

## Security Considerations

### Token Lifetime

| Token Type | Issuer | TTL | Refresh | Use Case |
|-----------|--------|-----|---------|----------|
| GitHub Actions (main) | GitHub Actions | 900s | No | CI/CD deployments |
| GitHub Actions (PR) | GitHub Actions | 300s | No | PR validation/preview |
| GitHub Actions (release) | GitHub Actions | 600s | No | Release deployments |
| Kubernetes SA | API server | 3600s | Automatic | Service-to-service |
| API token (long-lived) | Token-validation-service | 30 days | Manual | External integrations |

### Audit Logging

All token exchanges and API access are logged to `config/audit-logging-oidc.yaml`:

```yaml
Events logged:
  - Token exchange (subject, issuer, audience, outcome)
  - Token validation (service, scope, decision)
  - Permission checks (subject, action, resource, decision)
  - Token rotation/revocation (token_id, reason)

Retention:
  - Hot (queryable): 30 days
  - Warm (compressed): 90 days
  - Cold (archived): 1 year

Alerts:
  - > 5 failed exchanges/min → block subject
  - > 10 unauthorized attempts/min → alert security team
```

### Secrets Management

- **Encryption**: AES-256-GCM for token storage (Phase 3)
- **Key rotation**: Monthly automated rotation
- **Access control**: Kubernetes RBAC restricts token store access
- **No plaintext**: Tokens never logged in plaintext (first 8 chars only)

---

## Troubleshooting

### GitHub Actions OIDC Not Working

```bash
# Check issuer reachability
curl https://token.actions.githubusercontent.com/.well-known/openid-configuration

# Verify claim validation rules
grep "GITHUB_OIDC" config/github-actions-oidc.yaml

# Test token validation locally
./scripts/configure-workload-federation-phase1.sh
```

### Kubernetes ServiceAccount Token Issues

```bash
# Verify ServiceAccount exists
kubectl get sa -n prod code-server

# Check token mount
kubectl describe sa code-server -n prod

# Test token validation service
kubectl port-forward -n code-server-iam svc/token-validation-service 9000:9000
curl http://localhost:9000/health
```

### mTLS Certificate Errors

```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Verify certificate was created
kubectl get certificate -n code-server-iam

# Check certificate status
kubectl describe certificate code-server-ca -n code-server-iam
```

---

## Related Documentation

- [RBAC Enforcement Guide](RBAC_ENFORCEMENT_GUIDE.md)
- [Kubernetes Architecture](../ARCHITECTURE.md)
- [Security Policy](../SECURITY_POLICY.md)
- [GitHub Actions Workflows](.github/workflows/)

---

## References

- [Kubernetes Service Account Tokens](https://kubernetes.io/docs/concepts/configuration/secret/#service-account-token-secrets)
- [OpenID Connect Discovery](https://openid.net/specs/openid-connect-discovery-1_0.html)
- [GitHub Actions OIDC Token Claims](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [cert-manager Documentation](https://cert-manager.io/docs/)

---

**Last Updated**: April 2026  
**Phase**: 1-2 Complete, Phase 3-4 Planned  
**Status**: ✅ Ready for PR Review and Merge
