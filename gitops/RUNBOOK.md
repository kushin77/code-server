# Phase 9 GitOps - Operational Runbook

## Overview

This runbook provides step-by-step operations for Phase 9 (GitOps) implementation using ArgoCD.

## Table of Contents

1. [Installation](#installation)
2. [Initial Configuration](#initial-configuration)
3. [Application Management](#application-management)
4. [Multi-Cluster Deployment](#multi-cluster-deployment)
5. [Troubleshooting](#troubleshooting)
6. [Disaster Recovery](#disaster-recovery)

---

## Installation

### Prerequisites

- Kubernetes 1.20+
- kubectl configured
- Helm 3.x installed
- Terraform 1.5.0+ (optional, for IaC)

### Step 1: Install ArgoCD

#### Option A: Using Terraform (Recommended)

```bash
# 1. Configure variables
export TF_VAR_cluster_name=prod-cluster
export TF_VAR_github_repo_url=https://github.com/kushin77/code-server

# 2. Initialize Terraform
terraform init

# 3. Plan deployment
terraform plan -out=tfplan

# 4. Apply
terraform apply tfplan

# 5. Get ArgoCD URL
terraform output argocd_server_url
```

#### Option B: Using Helm Directly

```bash
# 1. Add Helm repository
helm repo add argocd https://argoproj.github.io/argo-helm
helm repo update

# 2. Create namespace
kubectl create namespace argocd

# 3. Install ArgoCD
helm install argocd argocd/argo-cd \
  --namespace argocd \
  --version 5.46.0 \
  --set server.replicas=2 \
  --set server.ingress.enabled=false

# 4. Wait for deployment
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s
```

### Step 2: Access ArgoCD

```bash
# Get initial admin password
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# Port-forward to local machine
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Access UI
# http://localhost:8080
# Username: admin
# Password: (from above)
```

### Step 3: Change Initial Password

```bash
# Via ArgoCD CLI
argocd login localhost:8080 \
  --username admin \
  --password $ADMIN_PASSWORD

argocd account update-password \
  --account admin \
  --current-password $ADMIN_PASSWORD \
  --new-password <new-password>
```

---

## Initial Configuration

### Register Git Repository

```bash
# Via CLI
argocd repo add https://github.com/kushin77/code-server \
  --username <github-username> \
  --password <github-token> \
  --type git

# Or via UI:
# 1. Go to Settings → Repositories
# 2. Click Connect Repo
# 3. Select HTTPS
# 4. Enter URL and credentials
# 5. Test Connection
# 6. Save
```

### Configure RBAC

```bash
# Create RBAC ConfigMap
kubectl create configmap argocd-rbac-cm \
  --from-file=policy.csv=rbac-policy.csv \
  -n argocd --dry-run=client -o yaml | kubectl apply -f -

# Verify RBAC
kubectl describe configmap argocd-rbac-cm -n argocd
```

### Enable OIDC (GitHub)

```bash
# 1. Create GitHub OAuth App
# Go to Settings → Developer settings → OAuth Apps
# Create OAuth App with:
# - Homepage URL: https://argocd.example.com
# - Callback URL: https://argocd.example.com/api/dex/callback

# 2. Create secret
kubectl create secret generic oidc-github \
  --from-literal=clientID=<client-id> \
  --from-literal=clientSecret=<client-secret> \
  -n argocd

# 3. Update ArgoCD config
kubectl patch configmap argocd-cm -n argocd -p '{
  "data": {
    "oidc.config": "name: GitHub\n
      issuer: https://github.com\n
      clientID: <client-id>\n
      clientSecret: <client-secret>\n
      requestedScopes:\n
        - openid\n
        - profile\n
        - email"
  }
}'
```

---

## Application Management

### Create Application

#### Option 1: YAML Manifests

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
    syncOptions:
    - CreateNamespace=true
```

Apply:
```bash
kubectl apply -f gitops/argocd-applications.yaml
```

#### Option 2: ArgoCD CLI

```bash
argocd app create code-server-app \
  --repo https://github.com/kushin77/code-server \
  --revision main \
  --path kustomize/overlays/production \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace code-server
```

### Monitor Application Status

```bash
# Get app status
argocd app get code-server-app

# Watch real-time status
argocd app get code-server-app --refresh --watch

# Get detailed diff
argocd app diff code-server-app

# Get application logs
argocd app logs code-server-app --follow

# Get resource status
argocd app resources code-server-app

# Describe application
kubectl describe application code-server-app -n argocd
```

### Sync Application

```bash
# Manual sync
argocd app sync code-server-app

# Force full sync
argocd app sync code-server-app --force

# Sync specific resource
argocd app sync code-server-app \
  --resource apps/Deployment/code-server/code-server

# Sync with prune
argocd app sync code-server-app --prune

# Wait for sync completion
argocd app wait code-server-app --sync
```

### Update Application

```bash
# Change target revision (branch)
argocd app set code-server-app \
  --revision staging

# Change source path
argocd app set code-server-app \
  --path kustomize/overlays/staging

# Enable auto-sync
argocd app set code-server-app \
  --auto-prune \
  --self-heal

# Disable auto-sync
argocd app set code-server-app \
  --sync-policy=none
```

### Delete Application

```bash
# Soft delete (keep resources in cluster)
kubectl delete application code-server-app -n argocd

# Hard delete (remove resources from cluster)
kubectl delete application code-server-app -n argocd \
  --cascade=foreground
```

---

## Multi-Cluster Deployment

### Register Cluster

```bash
# 1. Get cluster credentials
kubectl config get-context

# 2. Register in ArgoCD (CLI)
argocd cluster add <cluster-context>

# Or manually:
argocd cluster add kubernetes-admin@cloud \
  --name prod-us-east \
  --label environment=production,region=us-east

# 3. Verify registration
argocd cluster list

# 4. Label cluster for ApplicationSets
kubectl label node -l kubernetes.io/hostname= \
  argocd.argoproj.io/cluster-type=multi-region
```

### Create ApplicationSet for Multi-Cluster

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-cluster-apps
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          environment: production
  template:
    metadata:
      name: '{{name}}-code-server'
    spec:
      project: default
      source:
        repoURL: https://github.com/kushin77/code-server
        path: kustomize/overlays/production
      destination:
        server: '{{server}}'
        namespace: code-server
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

Apply:
```bash
kubectl apply -f gitops/applicationsets.yaml

# Monitor generation
kubectl get applicationsets -n argocd

# Watch applications being created
kubectl get applications -n argocd -w
```

### Manage Clusters from CLI

```bash
# List all clusters
argocd cluster list

# Get cluster details
argocd cluster get prod-us-east

# Get cluster API server
argocd cluster get prod-us-east -f json | jq .server

# Remove cluster
argocd cluster rm prod-us-east
```

---

## Drift Detection & Remediation

### Manual Drift Detection

```bash
# Check if out of sync
argocd app get code-server-app | grep "Sync Status"

# Compare git vs cluster
argocd app diff code-server-app

# Show resource differences
kubectl diff -f kustomize/overlays/production
```

### Automatic Drift Detection

Enable auto-sync for continuous drift detection:

```bash
argocd app set code-server-app \
  --auto-prune \
  --self-heal
```

### Remediate Drift

```bash
# Option 1: Sync (pull git state to cluster)
argocd app sync code-server-app

# Option 2: Force sync (discard local changes)
argocd app sync code-server-app --force

# Option 3: Prune (remove resources not in git)
argocd app sync code-server-app --prune

# Option 4: Check and prune
argocd app sync code-server-app --dry-run
```

---

## Troubleshooting

### Application stuck "OutOfSync"

```bash
# 1. Check recent errors
kubectl get events -n argocd --field-selector involvedObject.name=code-server-app

# 2. View server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100

# 3. Try manual refresh and sync
argocd app get code-server-app --refresh
argocd app sync code-server-app --force

# 4. Check git connectivity
argocd repo list
argocd repo get-details https://github.com/kushin77/code-server
```

### Webhook not triggering sync

```bash
# 1. Check webhook secret
kubectl get secret -n argocd github-webhook-secret

# 2. Set webhook in GitHub
# Settings → Webhooks → Add webhook
# Payload URL: https://argocd.example.com/api/webhook
# Secret: (from secret above)

# 3. Test manually
curl -X POST https://argocd.example.com/api/webhook \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature: sha1=..." \
  -d '{...}'

# 4. Check logs
kubectl logs -n argocd -l app=argocd-server | grep webhook
```

### Health check failures

```bash
# 1. View health status details
argocd app get code-server-app
# Look at: HealthStatus, LastHealthProbeTime

# 2. Check pod health
kubectl get pods -n code-server
kubectl describe pod -n code-server <pod-name>

# 3. View pod logs
kubectl logs -n code-server <pod-name>

# 4. Restart pod if needed
kubectl rollout restart deployment/code-server -n code-server
```

### Network issues

```bash
# 1. Check ArgoCD pod status
kubectl get pods -n argocd
kubectl describe pod -n argocd argocd-server-<hash>

# 2. Test cluster API connectivity
curl -k https://kubernetes.default:443/api/v1/namespaces

# 3. Verify NetworkPolicy not blocking
kubectl get networkpolicy -n argocd
kubectl describe networkpolicy -n argocd argocd-network-policy

# 4. Check DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup github.com

# 5. Test git clone
kubectl run -it --rm debug --image=alpine/git --restart=Never -- \
  git clone https://github.com/kushin77/code-server /tmp/test
```

---

## Disaster Recovery

### Backup ArgoCD Configuration

```bash
# Backup all Applications and ApplicationSets
kubectl get applications -A -o yaml > argocd-backup.yaml
kubectl get applicationsets -A -o yaml >> argocd-backup.yaml

# Backup ConfigMaps
kubectl get configmap -n argocd -o yaml > argocd-config-backup.yaml

# Backup Secrets (caution: contains sensitive data)
kubectl get secrets -n argocd -o yaml > argocd-secrets-backup.yaml.enc
# Store encrypted backup!
```

### Restore ArgoCD Configuration

```bash
# 1. Restore Applications
kubectl apply -f argocd-backup.yaml

# 2. Restore ConfigMaps
kubectl apply -f argocd-config-backup.yaml

# 3. Verify restoration
kubectl get applications -A
argocd app list
```

### Recover from Failed Sync

```bash
# 1. Identify failed resources
kubectl get events -n argocd --sort-by=.metadata.creationTimestamp

# 2. Manually fix in cluster (if needed)
kubectl edit deployment code-server -n code-server

# 3. Let ArgoCD re-sync to git state
argocd app sync code-server-app --force

# 4. Or revert to git commit
git revert <commit-hash>
# ArgoCD will detect and sync automatically
```

### Recreate in-sync-lost scenarios

```bash
# If Application resource is deleted:
kubectl apply -f gitops/argocd-applications.yaml

# If cluster state diverged significantly:
# 1. Option A: Delete and recreate
argocd app delete code-server-app
kubectl apply -f gitops/argocd-applications.yaml

# 2. Option B: Force sync
argocd app sync code-server-app --force --prune
```

---

## Integration with Phase 15 (Deployment)

Phase 9 (GitOps) + Phase 15 (Deployment) = Complete GitOps Stack

### Canary Deployment with ArgoCD

1. **Git commit** triggers webhook
2. **ArgoCD detects** change
3. **Phase 15 Canary Engine** gradually rolls out (10% → 50% → 100%)
4. **Health monitoring** validates at each step
5. **Auto-remediation** rolls back on failure

### SLO-Driven Sync with Deployment

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: slo-driven-app
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 5  # Phase 15 determines retry policy
  # Phase 15 monitors SLOs and gates deployment
```

---

**Last Updated**: 2024-01-27  
**Version**: 1.0.0  
**Audience**: DevOps, Platform Engineers, SREs
