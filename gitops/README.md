# GitOps with ArgoCD - Phase 9 Implementation

## Overview

Phase 9 implements declarative application deployment using ArgoCD and GitOps principles.

**Core Concept**: Git is the single source of truth. All infrastructure and application changes are declaratively defined in Git and automatically synced to Kubernetes clusters.

## Architecture

### Components

1. **ArgoCD Server**
   - Web UI for managing applications
   - API for programmatic access
   - Webhook receiver for Git events
   - Deployed in `argocd` namespace

2. **Application Controller**
   - Monitors Git repositories
   - Detects drift between git and cluster state
   - Automatically reconciles state based on policy
   - Handles sync, prune, and self-healing

3. **Master Control Loop**
   - Continuous reconciliation (~30 second intervals)
   - State comparison algorithm
   - Automated remediation

## Key Features

### Declarative Application Management

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: code-server-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kushin77/code-server
    targetRevision: main
    path: kustomize/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: code-server
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### ApplicationSet for Multi-Cluster Deployments

Generate applications dynamically from clusters, directories, or lists:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: code-server-multi-cluster
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          type: production
  template:
    # Application template for each cluster
```

### Continuous Drift Detection & Remediation

- Monitors git repository for changes
- Detects manual changes in cluster (drift)
- Auto-syncs to desired state
- Prunes resources no longer in git
- Optional self-healing

## Deployment Model

### Push vs Pull

**Traditional Push** (CI/CD):
```
Code Change → Pipeline → kubectl apply → Cluster
```

**GitOps Pull** (ArgoCD):
```
Code Change → Git Repo → ArgoCD monitors → kubectl apply → Cluster
```

### Benefits of Pull Model

1. **No credential exposure in pipeline** - ArgoCD runs inside cluster
2. **Automatic rollback** - Just revert git commit
3. **Audit trail** - All changes in git history
4. **Cluster convergence** - Continuous reconciliation
5. **Multi-cluster easy** - Same repo → multiple clusters

## Implementation

### Installation

```bash
# 1. Install ArgoCD in cluster
kubectl apply -f gitops/argocd-installation.yaml

# 2. Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s

# 3. Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# 4. Port-forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:80

# 5. Access UI at http://localhost:8080 (admin/ <password>)
```

### Register Repository

```bash
# 1. Go to Settings → Repositories → Connect Repo

# 2. Select connection method (HTTPS with personal token or SSH)

# 3. Enter:
#    - Repository URL: https://github.com/kushin77/code-server
#    - Authentication: Token or SSH key
#    - TLS: Skip certificate if needed

# 4. Test connection

# 5. Save
```

### Create Application

```bash
# 1. Go to Applications → New App

# 2. Fill in:
#    - Application Name: code-server-app
#    - Project: default
#    - Sync Policy: Automatic, Prune, Self Heal

# 3. Source:
#    - Repository: select registered repo
#    - Revision: main
#    - Path: kustomize/overlays/production

# 4. Destination:
#    - Cluster: https://kubernetes.default.svc
#    - Namespace: code-server

# 5. Create

# Or apply YAML:
kubectl apply -f gitops/argocd-applications.yaml
```

### Create ApplicationSet

```bash
# Deploy ApplicationSet for multi-cluster:
kubectl apply -f gitops/applicationsets.yaml

# This will automatically generate Applications for:
# - Each cluster matching selector labels
# - Each environment × cluster combination
# - Each directory in Git repo structure
```

## Repository Structure

```
code-server/
├── kustomize/
│   ├── base/
│   │   ├── code-server/
│   │   │   ├── kustomization.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── configmap.yaml
│   │   ├── monitoring/
│   │   └── ingress/
│   └── overlays/
│       ├── production/
│       │   ├── kustomization.yaml
│       │   └── patches/
│       ├── staging/
│       │   ├── kustomization.yaml
│       │   └── patches/
│       └── development/
│           ├── kustomization.yaml
│           └── patches/
└── gitops/
    ├── argocd-applications.yaml
    ├── applicationsets.yaml
    └── README.md
```

## Sync Policies

### Automated Sync
```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources not in git
    selfHeal: true   # Fix drift automatically
    allowEmpty: false # Don't allow empty sync
```

### Manual Sync
```yaml
syncPolicy:
  syncOptions:
  - CreateNamespace=true
  - ServerSideDiff=true
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

### Progressive Delivery (Canary/Blue-Green)
Pair with Phase 15 deployment orchestration for:
- Canary deployments (10% → 25% → 50% → 100%)
- Blue-green instant switchover
- Automatic rollback on errors

## RBAC Configuration

### Default Roles

1. **role:readonly** - View applications
2. **role:developer** - Create/update applications
3. **role:admin** - Full access (create, update, delete)

### Custom RBAC

```yaml
policy.csv: |
  p, role:team-a, applications, *, team-a/*, allow
  p, role:team-a, repositories, get, *, allow
  g, developers, role:team-a
  p, role:deploy, applications, sync, */*, allow
  p, role:deploy, applications, get, */*, allow
  g, deployer, role:deploy
```

## Secret Management Integration

### Sealed Secrets
```bash
# 1. Install sealed-secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# 2. Create sealed secret
echo -n "my-secret" | 
  kubectl create secret generic my-secret \
  --dry-run=client \
  --from-file=/dev/stdin \
  -o yaml | \
  kubeseal -f - > sealed-secret.yaml

# 3. Commit sealed-secret.yaml to git
# 4. ArgoCD applies sealed secret (controller decrypts)
```

### External Secrets Operator
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: github-secrets
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: github-token
spec:
  secretStoreRef:
    name: github-secrets
    kind: SecretStore
  target:
    name: github-secret
  data:
  - secretKey: token
    remoteRef:
      key: github-pat-production
```

## Monitoring & Alerting

### Prometheus Metrics

ArgoCD exposes Prometheus metrics:
- `argocd_reconcile_duration_seconds` - Sync duration
- `argocd_git_request_duration_seconds` - Git operations
- `argocd_app_sync_total` - Sync attempts
- `argocd_app_health_status` - Application health

### Alert Examples

```yaml
- alert: ArgoCDAppOutOfSync
  expr: argocd_app_sync_status{sync_status="OutOfSync"} > 0
  for: 5m
  annotations:
    summary: "Application out of sync"

- alert: ArgoCDAppUnhealthy
  expr: argocd_app_health_status{health_status!="Healthy"} > 0
  for: 5m
  annotations:
    summary: "Application unhealthy"

- alert: ArgoCDSyncFailure
  expr: rate(argocd_app_sync_total{phase="Failed"}[5m]) > 0
  annotations:
    summary: "ArgoCD sync failures detected"
```

## Drift Detection & Remediation

### Manual Drift Detection

```bash
# Check if app is out of sync
argocd app get code-server-app | grep "Sync Status"

# Compare git vs cluster
argocd app diff code-server-app

# List changed resources
argocd app resources code-server-app
```

### Automatic Remediation

```bash
# Enable auto-sync
argocd app set code-server-app \
  --auto-prune \
  --self-heal

# Trigger manual sync
argocd app sync code-server-app

# Force sync (discard local changes)
argocd app sync code-server-app --force
```

## Integration with Phase 15

**Deploy Orchestration** + **GitOps**:

1. **Phase 15** manages deployment strategy (canary, blue-green)
2. **Phase 9** provides git-based state management
3. Combined workflow:
   - Phase 15 detects the optimal deployment strategy
   - Phase 9 pulls from git repo (source of truth)
   - Application controller syncs state
   - Phase 15 monitors health and rollback

## Troubleshooting

### Application stuck "OutOfSync"

```bash
# Check sync status
argocc app get code-server-app --refresh

# View recent events
kubectl get events -n argocd \
  --field-selector involvedObject.name=code-server-app

# Check logs
kubectl logs -n argocd deployment/argocd-server
```

### Webhook not triggering

```bash
# GitHub Settings → Webhooks → Recent Deliveries

# Check ArgoCD webhook logs
kubectl logs -n argocd -l app=argocd-server | grep webhook

# Manual trigger (test)
curl -X POST https://argocd.example.com/api/webhook
```

### Secret not decrypting

```bash
# Verify sealed-secrets controller running
kubectl get deploy -n kube-system sealed-secrets-controller

# Check secret encryption key
kubectl get secret -n kube-system sealed-secrets-key

# Reseal if needed
kubeseal -f sealed-secret.yaml > new-sealed-secret.yaml
```

## Best Practices

1. **Structure repositories logically**
   - Separate base from overlays
   - One repo per team
   - Clear directory naming

2. **Use ApplicationSets for scale**
   - Multi-cluster deployments
   - Auto-generate from templates
   - Reduce manual YAML creation

3. **Implement RBAC properly**
   - Separate roles per team
   - Limit access by namespace
   - Use OIDC for SSO

4. **Monitor continuously**
   - Set up health monitoring
   - Alert on out-of-sync
   - Track sync duration metrics

5. **Test before production**
   - Validation environments
   - Policy as Code (OPA/Conftest)
   - Test ApplicationSets in staging

6. **Secure secrets properly**
   - Never commit secrets to git
   - Use sealed-secrets or external-secrets
   - Rotate keys regularly

---

**Status**: Ready for Implementation  
**Integration**: Phase 9 (GitOps) + Phase 15 (Deployment) = Complete GitOps Stack  
**Last Updated**: 2024-01-27  
**Version**: 1.0.0
