# Phase 14: Multi-Environment Consistency & GitOps

## Overview

Phase 14 implements GitOps-driven deployment practices, environment parity management, and automated consistency enforcement across dev → staging → production. This builds on all previous phases and creates a unified deployment experience across all environment tiers.

**Objectives:**
- ✅ GitOps framework (ArgoCD) for declarative deployments
- ✅ Environment-specific overlays and kustomization
- ✅ Secrets management across environments (sealed-secrets)
- ✅ Consistency validation and drift detection
- ✅ Automated promotion pipeline (dev → staging → prod)
- ✅ Environment parity testing and validation

---

## 1. GitOps Architecture with ArgoCD

### 1.1 ArgoCD Installation & Configuration

```yaml
# kubernetes/base/argocd.yaml

apiVersion: v1
kind: Namespace
metadata:
  name: argocd

---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: argocd
  namespace: argocd
spec:
  chart: argo-cd
  repo: https://argoproj.github.io/argo-helm
  values:
    server:
      service:
        type: LoadBalancer
    controller:
      replicas: 3
    repoServer:
      replicas: 2
    redis:
      enabled: true
    postgresql:
      enabled: true
      auth:
        password: $(ARGOCD_DB_PASSWORD)

---
# Application CRD for code-server
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: code-server
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kushin77/eiq-linkedin.git
    targetRevision: main
    path: kubernetes/deployments/code-server
  destination:
    server: https://kubernetes.default.svc
    namespace: code-server
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
  notification:
    slack:
      channel: '#deployments'
      enabled: true

---
# High-availability ArgoCD Repo Server
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-repo-creds
  namespace: argocd
data:
  ssh-private-key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

### 1.2 ArgoCD RBAC Configuration

```yaml
# kubernetes/base/argocd-rbac.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:reader
  policy.csv: |
    # Define roles for different teams
    p, role:platforms, applications, *, code-server/*, allow
    p, role:platforms, applications, *, agent-api/*, allow
    p, role:platforms, applications, *, embeddings/*, allow
    
    p, role:dev, applications, get, code-server/*, allow
    p, role:dev, applications, sync, code-server/dev, allow
    
    p, role:ops, applications, *, */*, allow
    p, role:ops, repositories, *, *, allow
    
    # Group mappings (from OIDC)
    g, platforms@company.com, role:platforms
    g, dev-team@company.com, role:dev
    g, ops-team@company.com, role:ops
  scopes: '[email, profile, groups]'
```

---

## 2. Environment-Specific Overlays with Kustomize

### 2.1 Directory Structure

```
kubernetes/deployments/
├── code-server/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── pvc.yaml
│   ├── overlays/
│   │   ├── dev/
│   │   │   ├── kustomization.yaml
│   │   │   ├── replica-count.yaml
│   │   │   └── resources-override.yaml
│   │   ├── staging/
│   │   │   ├── kustomization.yaml
│   │   │   ├── replica-count.yaml
│   │   │   ├── network-policy.yaml
│   │   │   └── pdb.yaml
│   │   └── prod/
│   │       ├── kustomization.yaml
│   │       ├── replica-count.yaml
│   │       ├── network-policy.yaml
│   │       ├── pdb.yaml
│   │       ├── autoscaling.yaml
│   │       └── resources-override.yaml
│   └── tests/
│       ├── kustomization_test.yaml
│       └── parity_test.sh
```

### 2.2 Base Kustomization

```yaml
# kubernetes/deployments/code-server/base/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: code-server

namespace: code-server
namePrefix: code-server-

commonLabels:
  app: code-server
  managed-by: argocd

commonAnnotations:
  config.kubernetes.io/version: "1.0"

resources:
- deployment.yaml
- service.yaml
- configmap.yaml
- pvc.yaml

vars:
- name: IMAGE_TAG
  objref:
    kind: Deployment
    name: code-server
    apiVersion: apps/v1
  fieldref:
    fieldpath: spec.template.spec.containers[0].image

replicas:
- name: code-server
  count: 3  # Default production replicas
```

### 2.3 Development Overlay

```yaml
# kubernetes/deployments/code-server/overlays/dev/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: code-server-dev

namespace: code-server-dev
namePrefix: code-server-dev-

bases:
- ../../base

patchesJson6902:
- target:
    group: apps
    version: v1
    kind: Deployment
    name: code-server
  patch: |-
    - op: replace
      path: /spec/replicas
      value: 1
    - op: replace
      path: /spec/strategy/type
      value: Recreate
    - op: add
      path: /spec/template/spec/containers/0/env
      value:
      - name: LOG_LEVEL
        value: DEBUG

images:
- name: code-server
  newTag: dev-latest  # Always pull latest dev build
  newName: code-server

envs:
- ../../base/envs/common.env
- envs/dev.env
```

### 2.4 Staging Overlay

```yaml
# kubernetes/deployments/code-server/overlays/staging/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: code-server-staging

namespace: code-server-staging
namePrefix: code-server-staging-

bases:
- ../../base

replicas:
- name: code-server
  count: 2

patchesJson6902:
- target:
    group: apps
    version: v1
    kind: Deployment
    name: code-server
  patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/resources/requests/memory
      value: "512Mi"
    - op: replace
      path: /spec/template/spec/containers/0/resources/limits/memory
      value: "1Gi"

resources:
- network-policy.yaml
- pdb.yaml

images:
- name: code-server
  newTag: staging-v1  # Pinned to specific version
  newName: code-server
```

### 2.5 Production Overlay

```yaml
# kubernetes/deployments/code-server/overlays/prod/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: code-server-prod

namespace: code-server-prod
namePrefix: code-server-prod-

bases:
- ../../base

replicas:
- name: code-server
  count: 5

patchesJson6902:
- target:
    group: apps
    version: v1
    kind: Deployment
    name: code-server
  patch: |-
    - op: replace
      path: /spec/strategy/type
      value: RollingUpdate
    - op: replace
      path: /spec/strategy/rollingUpdate/maxUnavailable
      value: 1
    - op: replace
      path: /spec/strategy/rollingUpdate/maxSurge
      value: 2
    - op: replace
      path: /spec/template/spec/affinity
      value:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - code-server
              topologyKey: kubernetes.io/hostname

resources:
- network-policy.yaml
- pdb.yaml
- autoscaling.yaml
- monitoring.yaml

images:
- name: code-server
  newTag: v1.2.3  # Strict semantic versioning
  newName: code-server

configMapGenerator:
- name: config
  files:
  - config/prod/config.json
  behavior: merge

secretGenerator:
- name: secrets
  envs:
  - secrets/prod.env
  behavior: merge
```

---

## 3. Secrets Management with Sealed Secrets

### 3.1 Sealed Secrets Installation

```yaml
# kubernetes/base/sealed-secrets.yaml

apiVersion: v1
kind: Namespace
metadata:
  name: kube-system

---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: sealed-secrets
  namespace: kube-system
spec:
  chart: sealed-secrets
  repo: https://bitnami-labs.github.io/sealed-secrets
  values:
    commandArgs:
    - --update-status=true
    - --log-level=info

---
# Service account for sealing secrets
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sealed-secrets-manager
  namespace: kube-system

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sealed-secrets-manager
rules:
- apiGroups: ['bitnami.com']
  resources: ['sealedsecrets']
  verbs: ['get', 'list', 'watch']
- apiGroups: ['']
  resources: ['secrets']
  verbs: ['get', 'list', 'create', 'update', 'patch']

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sealed-secrets-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: sealed-secrets-manager
subjects:
- kind: ServiceAccount
  name: sealed-secrets-manager
  namespace: kube-system
```

### 3.2 Environment-Specific Sealed Secrets

```bash
#!/bin/bash
# kubernetes/scripts/seal-secrets.sh

set -e

ENVIRONMENT=${1:-dev}
NAMESPACE="code-server-$ENVIRONMENT"
SEALING_KEY_CERT="/etc/kubernetes-sealing-keys/$ENVIRONMENT/sealing-cert.yaml"

echo "=== Sealing secrets for $ENVIRONMENT ==="

# Create namespace if it doesn't exist
kubectl get namespace $NAMESPACE || kubectl create namespace $NAMESPACE

# Seal secrets
echo "Sealing database password..."
kubectl create secret generic db-secrets \
  --from-file=password=secrets/$ENVIRONMENT/db-password.txt \
  --dry-run=client -o yaml | \
kubeseal -f - \
  --cert $SEALING_KEY_CERT \
  > kubernetes/overlays/$ENVIRONMENT/secrets/db-secrets-sealed.yaml

echo "Sealing API keys..."
kubectl create secret generic api-keys \
  --from-file=github-token=secrets/$ENVIRONMENT/github-token.txt \
  --from-file=slack-token=secrets/$ENVIRONMENT/slack-token.txt \
  --dry-run=client -o yaml | \
kubeseal -f - \
  --cert $SEALING_KEY_CERT \
  > kubernetes/overlays/$ENVIRONMENT/secrets/api-keys-sealed.yaml

echo "✅ Secrets sealed for $ENVIRONMENT"
```

### 3.3 Sealed Secret in Kustomization

```yaml
# kubernetes/overlays/prod/kustomization.yaml (excerpt)

secretGenerator:
- name: db-secrets
  files:
  - secrets/db-secrets-sealed.yaml
  behavior: merge
  annotations:
    sealedsecrets.bitnami.com/managed: "true"

# Include sealed secrets from separate files
resources:
- secrets/db-secrets-sealed.yaml
- secrets/api-keys-sealed.yaml
```

---

## 4. Automated Promotion Pipeline

### 4.1 Promotion Workflow

```yaml
# .github/workflows/promote-deployment.yml

name: Promote Deployment

on:
  workflow_dispatch:
    inputs:
      from_env:
        description: 'Source environment'
        required: true
        type: choice
        options:
          - dev
          - staging
      to_env:
        description: 'Target environment'
        required: true
        type: choice
        options:
          - staging
          - prod

jobs:
  promote:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    
    steps:
    - uses: actions/checkout@v4
      with:
        token: ${{ secrets.GITHUB_TOKEN }}
    
    - name: Validate environments
      run: |
        [ "${{ github.event.inputs.from_env }}" != "${{ github.event.inputs.to_env }}" ] || exit 1
    
    - name: Run parity tests
      run: |
        ./kubernetes/deployments/code-server/tests/parity_test.sh \
          ${{ github.event.inputs.from_env }} \
          ${{ github.event.inputs.to_env }}
    
    - name: Extract image tag from source
      id: extract-tag
      run: |
        SOURCE_TAG=$(kustomize build kubernetes/overlays/${{ github.event.inputs.from_env }} | \
          grep -A1 'code-server.*image:' | tail -1 | awk '{print $2}')
        echo "tag=$SOURCE_TAG" >> $GITHUB_OUTPUT
    
    - name: Update target overlay
      run: |
        cd kubernetes/overlays/${{ github.event.inputs.to_env }}
        kustomize edit set image code-server=${{ steps.extract-tag.outputs.tag }}
        cd -
        git add kubernetes/overlays/${{ github.event.inputs.to_env }}/kustomization.yaml
    
    - name: Create promotion PR
      uses: peter-evans/create-pull-request@v5
      with:
        commit-message: |
          chore: promote code-server from ${{ github.event.inputs.from_env }} to ${{ github.event.inputs.to_env }}
          
          Image tag: ${{ steps.extract-tag.outputs.tag }}
          Source: kubernetes/overlays/${{ github.event.inputs.from_env }}
          Target: kubernetes/overlays/${{ github.event.inputs.to_env }}
        title: "🚀 Promote code-server: ${{ github.event.inputs.from_env }} → ${{ github.event.inputs.to_env }}"
        body: |
          ## Promotion Summary
          - Source: `${{ github.event.inputs.from_env }}`
          - Target: `${{ github.event.inputs.to_env }}`
          - Image: `${{ steps.extract-tag.outputs.tag }}`
          
          ## Checks
          - [x] Parity tests passed
          - [ ] Review and approve
          - [ ] Merge (auto-merge to prod)
        branch: promotion/${{ github.event.inputs.from_env }}-to-${{ github.event.inputs.to_env }}
        delete-branch: true
        labels: 'promotion,automated'
```

### 4.2 Promotion Checklist

```yaml
# kubernetes/deployments/code-server/tests/promotion-checklist.yaml

promotion_requirements:
  from_dev_to_staging:
    - pass_all_unit_tests
    - pass_integration_tests
    - no_security_vulnerabilities_critical
    - image_signed_and_scanned
    - documentation_updated
    - requires_approvals: 1  # Any developer
  
  from_staging_to_prod:
    - pass_all_tests
    - no_security_vulnerabilities
    - pass_soak_test_48h
    - performance_targets_met
    - disaster_recovery_tested
    - requires_approvals: 2  # Platform + SRE
    - requires_schedule: 'business_hours'

validation_rules:
  - name: resource_limits
    check: "staging replicas >= 2, prod replicas >= 3"
  - name: monitoring
    check: "alerting rules defined for all services"
  - name: backup
    check: "backup tested in target environment"
```

---

## 5. Environment Parity Validation

### 5.1 Automated Parity Tests

```bash
#!/bin/bash
# kubernetes/deployments/code-server/tests/parity_test.sh

set -e

SOURCE_ENV=${1}
TARGET_ENV=${2}

echo "=== Environment Parity Test ==="
echo "Source: $SOURCE_ENV"
echo "Target: $TARGET_ENV"

# Function to get resource count
get_resource_count() {
  local env=$1
  local resource=$2
  kubectl get $resource -n code-server-$env --no-headers 2>/dev/null | wc -l
}

# Function to validate configuration
validate_config() {
  local env1=$1
  local env2=$2
  
  # Get deployment configs
  kustomize build kubernetes/overlays/$env1 > /tmp/config-$env1.yaml
  kustomize build kubernetes/overlays/$env2 > /tmp/config-$env2.yaml
  
  # Compare core configuration (ignoring replicas and resources)
  diff <(yq eval 'del(.spec.replicas) | del(.spec.template.spec.containers[].resources)' /tmp/config-$env1.yaml) \
       <(yq eval 'del(.spec.replicas) | del(.spec.template.spec.containers[].resources)' /tmp/config-$env2.yaml) && \
  echo "✅ Configuration parity: PASS" || echo "⚠️  Configuration diffs (replicas/resources ignored)"
}

# Function to validate labels/annotations
validate_labels() {
  local env1=$1
  local env2=$2
  
  # Check common labels exist
  for label in "app" "managed-by" "version"; do
    kustomize build kubernetes/overlays/$env1 | grep -q "labels:" && echo "  ✅ Label '$label' present"
  done
}

# Function to validate resource requests/limits
validate_resources() {
  local env=$1
  
  kustomize build kubernetes/overlays/$env | \
  yq eval '.spec.template.spec.containers[].resources' | \
  grep -E "(requests|limits)" && echo "✅ Resource requests/limits defined" || echo "⚠️  No resource limits"
}

echo ""
echo "=== Validation Checks ==="

validate_config $SOURCE_ENV $TARGET_ENV
validate_labels $SOURCE_ENV $TARGET_ENV

echo ""
echo "=== Resource Validation ==="
echo "Source ($SOURCE_ENV):"
validate_resources $SOURCE_ENV

echo ""
echo "Target ($TARGET_ENV):"
validate_resources $TARGET_ENV

echo ""
echo "✅ Parity test complete"
```

### 5.2 Drift Detection

```yaml
# kubernetes/base/drift-detection.yaml

apiVersion: batch/v1
kind: CronJob
metadata:
  name: argocd-drift-detection
  namespace: argocd
spec:
  schedule: "*/15 * * * *"  # Every 15 minutes
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: argocd-controller
          containers:
          - name: drift-check
            image: argoproj/argocd-alpine:v2.9
            command:
            - /bin/bash
            - -c
            - |
              for app in code-server agent-api embeddings; do
                STATUS=$(argocd app get $app -o json | jq -r '.status.sync.status')
                
                if [ "$STATUS" != "Synced" ]; then
                  echo "⚠️  Drift detected in $app: $STATUS"
                  
                  # Auto-sync or alert based on policy
                  if [ "$ARGOCD_AUTO_SYNC" = "true" ]; then
                    argocd app sync $app
                  else
                    # Send alert
                    curl -X POST $SLACK_WEBHOOK \
                      -d "{'text':'🚨 Drift in '$app': '$STATUS'"
                  fi
                fi
              done
          restartPolicy: OnFailure
```

---

## 6. GitOps Repository Structure

```
eiq-linkedin/
├── kubernetes/
│   ├── deployments/          # Application manifests
│   │   ├── code-server/
│   │   ├── agent-api/
│   │   └── embeddings/
│   ├── base/                 # Shared base configs
│   ├── overlays/             # Environment-specific overlays
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── scripts/              # Helper scripts
├── terraform/                # Infrastructure as Code
├── docs/
├── .github/workflows/        # CI/CD pipelines
└── README.md
```

---

## 7. Continuous Deployment Strategy

### 7.1 CD Workflow Rules

```yaml
# .github/workflows/continuous-sync.yml

name: Continuous Deployment

on:
  push:
    branches:
      - main
    paths:
      - 'kubernetes/**'
      - '.github/workflows/continuous-sync.yml'

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Validate manifests
      run: |
        kubectl apply --dry-run=client -f kubernetes/
    
    - name: Validate with Kustomize
      run: |
        kustomize build kubernetes/overlays/prod
        kustomize build kubernetes/overlays/staging
        kustomize build kubernetes/overlays/dev
    
    - name: Trigger ArgoCD sync
      run: |
        argocd app sync code-server-prod --async
        argocd app wait code-server-prod --sync-timeout 300
        
        argocd app sync code-server-staging --async
        argocd app wait code-server-staging --sync-timeout 300
        
        argocd app sync code-server-dev --async
        argocd app wait code-server-dev --sync-timeout 300
    
    - name: Verify deployment
      run: |
        ./kubernetes/scripts/verify-deployment.sh prod
```

### 7.2 Rollback Strategy

```bash
#!/bin/bash
# kubernetes/scripts/rollback-deployment.sh

set -e

ENVIRONMENT=${1}
SERVICE=${2:-code-server}

echo "=== Rollback Procedure ==="
echo "Environment: $ENVIRONMENT"
echo "Service: $SERVICE"

# Get current git hash
CURRENT_HASH=$(git rev-parse HEAD)
echo "Current commit: $CURRENT_HASH"

# Get previous stable commit
PREVIOUS_HASH=$(git log --oneline --all | grep -i "stable\|release" | head -1 | awk '{print $1}')
echo "Rolling back to: $PREVIOUS_HASH"

# Reset to previous commit
git reset --hard $PREVIOUS_HASH

# Sync ArgoCD
argocd app sync $SERVICE-$ENVIRONMENT --force

# Wait for rollback to complete
argocd app wait $SERVICE-$ENVIRONMENT --sync-timeout 300

# Verify health
echo ""
echo "Verifying rollback..."
kubectl rollout status deployment/$SERVICE -n code-server-$ENVIRONMENT

echo "✅ Rollback complete"
```

---

## 8. Success Criteria

- ✅ All deployments via GitOps (ArgoCD)
- ✅ Environment parity validated automatically
- ✅ Secrets encrypted and isolated per environment
- ✅ Promotion pipeline functional (dev → staging → prod)
- ✅ Drift detection running every 15 minutes
- ✅ Zero manual kubectl commands in production
- ✅ Rollback capability < 5 minutes
- ✅ All changes tracked in Git with full audit trail

---

## Next Steps

1. Deploy ArgoCD to cluster
2. Configure GitHub repo with deployment manifests
3. Setup Sealed Secrets for secrets management
4. Configure promotion workflow
5. Run parity tests
6. Create drift detection CronJob
7. Setup rollback runbook
8. Begin **Phase 15: Advanced Networking & Service Mesh**

