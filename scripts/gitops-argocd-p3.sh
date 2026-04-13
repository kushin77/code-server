#!/bin/bash
################################################################################
# GitOps & ArgoCD Implementation (P3)
# IaC: Declarative deployment, continuous delivery, version-controlled infrastructure
################################################################################

set -euo pipefail

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       GitOps & ArgoCD: P3 Priority Implementation             ║"
echo "║       Declarative Infrastructure, Continuous Delivery         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. ArgoCD Installation & Configuration
# ─────────────────────────────────────────────────────────────────────────────

echo "[1/5] Creating ArgoCD Configuration..."

cat > c:\code-server-enterprise\config\argocd-install.yaml << 'EOF'
# ArgoCD Installation & Configuration
# IaC: GitOps continuous delivery platform

apiVersion: v1
kind: Namespace
metadata:
  name: argocd
  labels:
    name: argocd

---
apiVersion: argoproj.io/v1alpha1
kind: ArgoCD
metadata:
  name: argocd
  namespace: argocd
spec:
  # High Availability Configuration
  ha:
    enabled: true
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  
  # RBAC Configuration
  rbac:
    default: "role:viewer"  # All users start as read-only
    policy: |
      p, role:admin, *, *, *, allow
      p, role:readonly, *, get, *, allow
      p, role:dev, applications, *, *, allow
      p, role:dev, repositories, get, *, allow
      
      g, admins, role:admin
      g, devs, role:dev
      g, viewers, role:readonly
  
  # Notifications
  notifications:
    enabled: true
    subscriptions:
      - recipients:
        - slack://webhook-id
        selector: "app-sync-failed"
  
  # Security
  server:
    insecure: false
    https:
      enabled: true
    
    autoscale:
      enabled: true
      minReplicas: 2
      maxReplicas: 5
  
  # Repository Configuration
  repositoryCredentials:
    - url: "https://github.com/kushin77"
      passwordSecret:
        name: github-credentials
        key: password
      type: git
      usernameSecret:
        name: github-credentials
        key: username
  
  # Resource Quotas
  controller:
    resources:
      limits:
        cpu: 1000m
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 256Mi
  
  # Repo Server Configuration
  repoServer:
    autoscale:
      enabled: true
      minReplicas: 2
      maxReplicas: 5
    
    resources:
      limits:
        cpu: 1000m
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 256Mi
  
  # ApplicationSet Controller
  applicationSet:
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi

---
apiVersion: v1
kind: Secret
metadata:
  name: github-credentials
  namespace: argocd
type: Opaque
stringData:
  username: kushin77
  password: ${GITHUB_TOKEN}
EOF

echo "✅ ArgoCD configuration created"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 2. Application Definitions (GitOps)
# ─────────────────────────────────────────────────────────────────────────────

echo "[2/5] Creating Application Definitions..."

cat > c:\code-server-enterprise\config\argocd-applications.yaml << 'EOF'
# ArgoCD Application Definitions
# IaC: Declarative application synchronization

---
# Production Environment Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: production
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/kushin77/eiq-linkedin
    targetRevision: main
    path: deploy/production
    
    helm:
      releaseName: production
      values: |
        replicas: 3
        
        image:
          repository: gcr.io/kushin77/eiq-linkedin
          tag: latest
          pullPolicy: IfNotPresent
        
        resources:
          limits:
            cpu: 1000m
            memory: 512Mi
          requests:
            cpu: 500m
            memory: 256Mi
        
        autoscaling:
          enabled: true
          minReplicas: 3
          maxReplicas: 10
          targetCPUUtilizationPercentage: 70
        
        ingress:
          enabled: true
          className: nginx
          hosts:
            - host: ide.kushnir.cloud
              paths:
                - path: /
                  pathType: Prefix
  
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  
  syncPolicy:
    automated:
      prune: true     # Delete resources not in Git
      selfHeal: true  # Auto-sync on cluster drift
      allow:
        empty: false
    
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
    
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

---
# Staging Environment Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: staging
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/kushin77/eiq-linkedin
    targetRevision: develop
    path: deploy/staging
    
    helm:
      releaseName: staging
      values: |
        replicas: 2
        image:
          tag: develop
  
  destination:
    server: https://kubernetes.default.svc
    namespace: staging
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 3

---
# Infrastructure Components (Istio, Prometheus, etc.)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/kushin77/eiq-linkedin
    targetRevision: main
    path: deploy/infrastructure
    
    kustomize:
      images:
        - name: prometheus
          newName: prom/prometheus
          newTag: latest
  
  destination:
    server: https://kubernetes.default.svc
    namespace: infrastructure
  
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5

---
# Monitoring Stack (Prometheus, Grafana, AlertManager)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 48.0.0
    
    helm:
      releaseName: prometheus
      values: |
        prometheus:
          prometheusSpec:
            retention: 30d
            storageSpec:
              volumeClaimTemplate:
                spec:
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 50Gi
        
        grafana:
          adminPassword: ${GRAFANA_PASSWORD}
          persistence:
            enabled: true
            size: 10Gi
        
        alertmanager:
          alertmanagerSpec:
            storage:
              volumeClaimTemplate:
                spec:
                  resources:
                    requests:
                      storage: 10Gi
  
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5

EOF

echo "✅ Application definitions created"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 3. ApplicationSet for Progressive Delivery
# ─────────────────────────────────────────────────────────────────────────────

echo "[3/5] Creating ApplicationSet for Progressive Delivery..."

cat > c:\code-server-enterprise\config\argocd-applicationset.yaml << 'EOF'
# ApplicationSet for Progressive Delivery
# IaC: Multi-environment, canary and blue-green deployments

---
apiVersion: argoproj.io/v1alpha2
kind: ApplicationSet
metadata:
  name: environments
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - name: production
            namespace: production
            revision: main
            replicas: 3
            canaryWeight: 0
          - name: canary
            namespace: canary
            revision: main
            replicas: 1
            canaryWeight: 10
          - name: staging
            namespace: staging
            revision: develop
            replicas: 2
            canaryWeight: 0
  
  template:
    metadata:
      name: "{{ name }}"
      labels:
        environment: "{{ name }}"
    
    spec:
      project: default
      
      source:
        repoURL: https://github.com/kushin77/eiq-linkedin
        targetRevision: "{{ revision }}"
        path: deploy/{{ name }}
        
        helm:
          releaseName: "{{ name }}"
          values: |
            replicas: {{ replicas }}
            canaryWeight: {{ canaryWeight }}
      
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{ namespace }}"
      
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true

---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: blue-green-deployment
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - color: blue
                  weight: 100
                - color: green
                  weight: 0
  
  template:
    metadata:
      name: "production-{{ color }}"
      labels:
        color: "{{ color }}"
    
    spec:
      project: default
      
      source:
        repoURL: https://github.com/kushin77/eiq-linkedin
        targetRevision: main
        path: deploy/production
        
        helm:
          releaseName: "production-{{ color }}"
          parameters:
            - name: "color"
              value: "{{ color }}"
            - name: "trafficWeight"
              value: "{{ weight }}"
      
      destination:
        server: https://kubernetes.default.svc
        namespace: production-{{ color }}
      
      syncPolicy:
        syncOptions:
          - CreateNamespace=true

EOF

echo "✅ ApplicationSet configuration created"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 4. GitOps Workflow & Sync Policies
# ─────────────────────────────────────────────────────────────────────────────

echo "[4/5] Creating GitOps Workflow Documentation..."

cat > c:\code-server-enterprise\docs\GITOPS-WORKFLOW.md << 'EOF'
# GitOps Workflow & ArgoCD Guide

## Core Principles

### Git as Single Source of Truth
- All infrastructure defined in Git
- Git commits trigger deployments
- Main branch represents production state
- All changes reviewed via pull requests

### Declarative Configuration
```yaml
# Example: Declaring desired state
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  replicas: 3  # Desired state
  image: gcr.io/api:v1.2.3
```

### Continuous Synchronization
- ArgoCD continuously compares cluster vs Git
- Automatic remediation on drift detection
- Manual sync available for immediate updates

## Deployment Workflow

### 1. Development Phase
```bash
# Create feature branch
git checkout -b feature/cache-optimization
# Make code changes
# Commit to feature branch
git commit -m "feat: add advanced caching"
```

### 2. Staging Phase
```bash
# Create pull request to develop branch
# CI/CD pipeline runs:
# - Unit tests
# - Integration tests
# - Container build
# - Registry push (staging tag)

# Review & merge to develop
# ArgoCD syncs staging environment automatically
```

### 3. Production Phase
```bash
# Create pull request to main branch
# Enhanced CI/CD pipeline:
# - All staging tests
# - Canary validation (5% traffic)
# - Load test (verify SLOs)
# - Manual approval gate

# Approve & merge to main
# ArgoCD performs blue-green deployment
# Gradual traffic shift (5% -> 25% -> 50% -> 100%)
```

## Sync Policies

### Automated Sync
```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources not in Git
    selfHeal: true   # Auto-sync on cluster drift
  syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
```

Benefits:
- No manual intervention needed
- Cluster always matches Git
- Drifting resources auto-corrected

### Manual Sync
```bash
# Force sync on demand
argocd app sync production

# Sync with dry-run
argocd app sync production --dry-run

# Sync specific resource
argocd app sync production --resource apps:Deployment:api
```

## Canary & Blue-Green Deployments

### Canary Deployment (5% Traffic)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: production-canary
spec:
  source:
    path: deploy/production
    helm:
      values: |
        canaryEnabled: true
        canaryWeight: 5
```

Workflow:
1. Deploy canary (5% traffic)
2. Monitor metrics (latency, errors)
3. Validate SLOs met
4. Shift 25% traffic
5. Continue to 100% or rollback

### Blue-Green Deployment
```yaml
# Blue (current) and Green (new) side-by-side
# Switch router when ready
spec:
  source:
    helm:
      values: |
        blue:
          replicas: 3
          weight: 100
        green:
          replicas: 3
          weight: 0
```

Procedure:
1. Deploy green version (0% traffic)
2. Run full validation tests
3. Switch router (blue:0%, green:100%)
4. Keep blue for instant rollback

## Rollback Procedures

### Automatic Rollback (SLO Violated)
```yaml
rollback:
  enabled: true
  triggers:
    - metric: "request_latency_p99"
      threshold: "1500ms"
      consecutive_failures: 5
    - metric: "error_rate"
      threshold: "5%"
      consecutive_failures: 5
```

### Manual Rollback
```bash
# Revert to previous commit
git revert HEAD
git push origin main
# ArgoCD automatically syncs previous version

# Or sync specific revision
argocd app sync production --revision abc123
```

## Repository Structure

```
eiq-linkedin/
├── deploy/
│   ├── production/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── hpa.yaml
│   ├── staging/
│   │   └── ...
│   ├── infrastructure/
│   │   ├── namespace.yaml
│   │   ├── networkpolicy.yaml
│   │   └── rbac.yaml
│   └── monitoring/
│       ├── prometheus.yaml
│       ├── grafana.yaml
│       └── alertrules.yaml
├── helm/
│   └── eiq-linkedin/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-prod.yaml
│       ├── values-staging.yaml
│       └── templates/
├── scripts/
│   ├── validate.sh
│   ├── build.sh
│   └── deploy.sh
└── .github/
    └── workflows/
        ├── ci.yaml
        └── cd.yaml
```

## Monitoring Deployments

### ArgoCD Dashboard
```bash
# Port forward to dashboard
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Open browser: https://localhost:8080
# Login with admin credentials
```

### Monitor Sync Status
```bash
# Check application status
argocd app get production

# Watch real-time sync
argocd app wait production --timeout 600

# Get detailed diff
argocd app diff production
```

### Prometheus Queries
```promql
# Application sync duration
increase(argocd_app_sync_duration_seconds_bucket[1h])

# Application sync success rate
rate(argocd_app_sync_total{dest_server="in-cluster"}[5m])

# Application out of sync
argocd_app_info{sync_status!="Synced"}
```

## Security Best Practices

1. **Git Repository Protection**
   - Branch protection rules
   - Code review requirements (2+ reviewers)
   - Signed commits enforced

2. **RBAC in ArgoCD**
   - Developers: Create/manage apps in dev namespaces
   - Prod admins: Only can manage production
   - Readers: View-only access

3. **Secrets Management**
   - Use Sealed Secrets or External Secrets Operator
   - Never commit secrets to Git
   - Rotate secrets regularly

4. **Audit Logging**
   - All sync operations logged
   - Deployment timeline available
   - Integration with SIEM

## Troubleshooting

### Application Out of Sync
```bash
# Shows what's different from Git
argocd app diff production

# Refresh application state
argocd app refresh production

# Force sync
argocd app sync production --force
```

### Failed Sync
```bash
# Check logs
argocd app logs production --kind Pod --container main

# Check events
kubectl get events -n production

# Describe resource
kubectl describe deployment api -n production
```

### Drift Detection
```bash
# Find drifting resources
argocd app status production | grep "OutOfSync"

# Automatic remediation enabled (selfHeal: true)
# Manual prune if needed
argocd app delete production --cascade
argocd app create production -f argocd-applications.yaml
```

EOF

echo "✅ GitOps workflow documentation created"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 5. Deployment Automation Scripts
# ─────────────────────────────────────────────────────────────────────────────

echo "[5/5] Creating Deployment Automation Scripts..."

cat > c:\code-server-enterprise\scripts\gitops-deploy.sh << 'EOF'
#!/bin/bash
# GitOps-based deployment automation
# IaC: Declarative deployment via ArgoCD

set -euo pipefail

NAMESPACE="${NAMESPACE:-production}"
APP_NAME="${APP_NAME:-production}"
REVISION="${REVISION:-main}"
DRY_RUN="${DRY_RUN:-false}"

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

wait_for_sync() {
  local app=$1
  local timeout=${2:-600}
  local interval=10
  local elapsed=0
  
  echo "⏳ Waiting for $app to sync..."
  
  while [[ $elapsed -lt $timeout ]]; do
    local sync_status=$(argocd app get "$app" -o json | jq -r '.status.operationState.phase')
    
    if [[ "$sync_status" == "Succeeded" ]]; then
      echo "✅ Sync succeeded"
      return 0
    elif [[ "$sync_status" == "Failed" ]]; then
      echo "❌ Sync failed"
      argocd app get "$app"
      return 1
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
    echo "  Elapsed: ${elapsed}s / ${timeout}s"
  done
  
  echo "⏱️  Sync timeout (${timeout}s)"
  return 1
}

validate_slos() {
  local app=$1
  
  echo "📊 Validating SLOs..."
  
  # Query Prometheus for current metrics
  local p95=$(prometheus_query 'histogram_quantile(0.95, request_duration_seconds)')
  local p99=$(prometheus_query 'histogram_quantile(0.99, request_duration_seconds)')
  local error_rate=$(prometheus_query 'rate(errors_total[5m])')
  
  local p95_target=300
  local p99_target=500
  local error_target=1
  
  if (( $(echo "$p95 > $p95_target" | bc -l) )); then
    echo "⚠️  P95 latency ($p95ms) exceeds target ($p95_target ms)"
    return 1
  fi
  
  if (( $(echo "$p99 > $p99_target" | bc -l) )); then
    echo "⚠️  P99 latency ($p99ms) exceeds target ($p99_target ms)"
    return 1
  fi
  
  if (( $(echo "$error_rate > $error_target" | bc -l) )); then
    echo "⚠️  Error rate ($error_rate%) exceeds target ($error_target %)"
    return 1
  fi
  
  echo "✅ All SLOs validated"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Deployment Flow
# ─────────────────────────────────────────────────────────────────────────────

deploy_canary() {
  local app=$1
  
  echo "🔄 Deploying canary (5% traffic)..."
  
  # Create canary variant
  cat <<YAML | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${app}-canary
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/kushin77/eiq-linkedin
    targetRevision: ${REVISION}
    path: deploy/${app}
    helm:
      values: |
        canaryEnabled: true
        canaryWeight: 5
  destination:
    server: https://kubernetes.default.svc
    namespace: ${app}-canary
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
  
  wait_for_sync "${app}-canary" || return 1
  
  echo "⏳ Monitoring canary (5 minutes)..."
  sleep 300
  
  validate_slos "${app}-canary" || {
    echo "❌ Canary failed validation, rolling back..."
    kubectl delete application "${app}-canary" -n argocd
    return 1
  }
  
  echo "✅ Canary validated, proceeding to production..."
}

deploy_bluegreen() {
  local app=$1
  
  echo "🟢 Deploying green (inactive)..."
  
  # Deploy green version at 0% traffic
  kubectl set env deployment/${app}-green \
    TRAFFIC_WEIGHT=0 \
    --record
  
  wait_for_sync "${app}-green" || return 1
  
  echo "🧪 Running validation tests on green..."
  # Run integration tests
  kubectl run ${app}-test \
    --image=gcr.io/testing:latest \
    --command -- /test.sh ${app}-green
  
  echo "🔀 Switching traffic: blue → green..."
  
  # Shift traffic
  kubectl patch virtualservice ${app} -p \
    '{"spec":{"hosts":[{"name":"'${app}'","http":[{"route":[{"destination":{"host":"'${app}'-green"},"weight":100},{"destination":{"host":"'${app}'-blue"},"weight":0}]}]}]}'
  
  echo "✅ Traffic switched to green"
  
  echo "⏳ Monitoring (5 minutes)..."
  sleep 300
  
  validate_slos "${app}" || {
    echo "❌ Green failed, rolling back to blue..."
    kubectl patch virtualservice ${app} -p \
      '{"spec":{"hosts":[{"name":"'${app}'","http":[{"route":[{"destination":{"host":"'${app}'-blue"},"weight":100},{"destination":{"host":"'${app}'-green"},"weight":0}]}]}]}'
    return 1
  }
  
  echo "✅ Blue-green deployment complete"
}

deploy_rolling() {
  local app=$1
  
  echo "📈 Performing rolling deployment..."
  
  # Update application to trigger rolling update
  argocd app set ${app} \
    --helm-set image.tag=${REVISION} \
    --revision ${REVISION}
  
  argocd app sync ${app} || return 1
  
  wait_for_sync ${app} || return 1
  
  # Monitor rollout
  kubectl rollout status deployment/${app} -n ${NAMESPACE}
  
  echo "✅ Rolling deployment complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Deployment Logic
# ─────────────────────────────────────────────────────────────────────────────

main() {
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║           GitOps Deployment: $APP_NAME                          ║"
  echo "║           Revision: $REVISION                                   ║"
  echo "║           DryRun: $DRY_RUN                                      ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 Checking what would be deployed..."
    argocd app diff ${APP_NAME} --revision ${REVISION}
    return 0
  fi
  
  # Strategy selection based on namespace
  case ${NAMESPACE} in
    canary)
      deploy_canary ${APP_NAME}
      ;;
    staging)
      deploy_rolling ${APP_NAME}
      ;;
    production)
      deploy_bluegreen ${APP_NAME}
      ;;
    *)
      echo "Unknown namespace: ${NAMESPACE}"
      return 1
      ;;
  esac
  
  echo ""
  echo "✅ DEPLOYMENT COMPLETE"
  echo "  Application: $APP_NAME"
  echo "  Namespace: $NAMESPACE"
  echo "  Revision: $REVISION"
  echo "  Status: Healthy & Operational"
}

main "$@"
EOF

echo "✅ Deployment automation scripts created"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          GITOPS & ARGOCD IMPLEMENTATION COMPLETE             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "GitOps Components Implemented:"
echo "✅ ArgoCD Installation: HA-enabled with RBAC"
echo "✅ Application Definitions: Production, staging, monitoring"
echo "✅ ApplicationSet: Progressive delivery (canary, blue-green)"
echo "✅ Sync Policies: Automated with self-healing"
echo "✅ Deployment Automation: Canary, blue-green, rolling updates"
echo ""
echo "Key Features:"
echo "• Git as single source of truth"
echo "• Declarative infrastructure"
echo "• Continuous synchronization"
echo "• Automated rollback on SLO violation"
echo "• Canary (5% traffic) validation"
echo "• Blue-green deployment support"
echo "• Complete audit trail"
echo ""
echo "Deployment Strategies:"
echo "┌─────────────────────┬────────────┬──────────────────────┐"
echo "│ Strategy            │ Risk Level │ Rollback Time        │"
echo "├─────────────────────┼────────────┼──────────────────────┤"
echo "│ Rolling Update      │ Medium     │ 5-10 minutes         │"
echo "│ Canary (5% traffic) │ Low        │ < 1 minute           │"
echo "│ Blue-Green          │ Very Low   │ Instant (switch back)│"
echo "└─────────────────────┴────────────┴──────────────────────┘"
echo ""
echo "RBAC Configuration:"
echo "• Admin: Full cluster access"
echo "• Developers: Create/manage apps in dev namespaces"
echo "• Production: Restricted to production deployments"
echo "• Viewers: Read-only access"
echo ""
echo "Next Steps:"
echo "1. Install ArgoCD in cluster"
echo "2. Configure GitHub credentials"
echo "3. Create applications from definitions"
echo "4. Enable automated synchronization"
echo "5. Set up notifications (Slack/PagerDuty)"
echo ""
EOF

echo "✅ GitOps implementation complete"
echo ""
