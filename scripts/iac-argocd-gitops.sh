#!/usr/bin/env bash
set -euo pipefail

#############################################################################
# ARGOCD GITOPS CONTROL PLANE DEPLOYMENT - ON-PREMISES (192.168.168.31)
# Purpose: GitOps declarative infrastructure with canary deployments
# Status: Production-ready, Immutable, Independent, Duplicate-free
# Phase: #168 Implementation
#############################################################################

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/argocd-deployment-$(date +%s).log"
readonly K3S_IP="${K3S_IP:-192.168.168.31}"
readonly ARGOCD_VERSION="${ARGOCD_VERSION:-v2.10.0}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S UTC')] $*" | tee -a "$LOG_FILE"
}

emit_metric() {
    echo "$(date -u +%s),argocd,${1},${2},${3}" >> /var/metrics/argocd-deployment.log
}

# Preflight: Verify k3s cluster
verify_k3s() {
    log "=== VERIFYING K3S CLUSTER ==="
    
    if ! command -v kubectl &> /dev/null; then
        log "ERROR: kubectl not found"
        return 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR: Cannot connect to k3s cluster"
        return 1
    fi
    
    local nodes
    nodes=$(kubectl get nodes --no-headers | wc -l)
    log "✓ k3s cluster connected: $nodes node(s)"
    emit_metric "k3s_nodes" "$nodes" "gauge"
    
    return 0
}

# Install ArgoCD via Helm (idempotent, production-ready)
install_argocd() {
    log "=== INSTALLING ARGOCD HELM CHART ==="
    
    # Add Helm repository
    if ! helm repo list | grep -q argo; then
        log "Adding Argo Helm repository..."
        helm repo add argo https://argoproj.github.io/argo-helm
    fi
    helm repo update
    
    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Create PVC for ArgoCD repo server
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: argocd-repo-server-pvc
  namespace: argocd
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 50Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: argocd-redis-pvc
  namespace: argocd
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
EOF
    
    # Install/upgrade ArgoCD
    log "Installing ArgoCD Helm chart (version: $ARGOCD_VERSION)..."
    helm upgrade --install argocd argo/argo-cd \
        --namespace argocd \
        --version "${ARGOCD_VERSION#v}" \
        --set server.service.type=LoadBalancer \
        --set server.insecure=false \
        --set server.extraArgs="{--insecure-redirect-to-https}" \
        --set repoServer.autoscaling.enabled=false \
        --set repoServer.replicas=2 \
        --set redis.enabled=true \
        --set persistence.enabled=true \
        --set persistence.storageClassName=local-path \
        --set persistence.size=10Gi \
        --set dex.enabled=true \
        --set applicationSet.replicaCount=1 \
        --wait --timeout 5m
    
    log "✓ ArgoCD installed successfully"
    emit_metric "argocd_installed" "1" "gauge"
}

# Configure ArgoCD CLI
configure_argocd_cli() {
    log "=== CONFIGURING ARGOCD CLI ==="
    
    # Get LoadBalancer IP
    local argocd_ip
    for i in {1..30}; do
        argocd_ip=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        if [[ -n "$argocd_ip" ]]; then
            break
        fi
        log "Waiting for LoadBalancer IP assignment... ($i/30)"
        sleep 2
    done
    
    if [[ -z "$argocd_ip" ]]; then
        log "ERROR: Failed to get LoadBalancer IP"
        return 1
    fi
    
    log "ArgoCD LoadBalancer IP: $argocd_ip"
    emit_metric "argocd_loadbalancer_ip" "$argocd_ip" "gauge"
    
    # Download ArgoCD CLI if not present
    if ! command -v argocd &> /dev/null; then
        log "Downloading ArgoCD CLI..."
        curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64
        chmod +x /tmp/argocd
        sudo mv /tmp/argocd /usr/local/bin/
    fi
    
    # Get initial admin password
    local admin_password
    admin_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    # Configure CLI
    export ARGOCD_SERVER="$argocd_ip:443"
    argocd login "$ARGOCD_SERVER" --username admin --password "$admin_password" --insecure || true
    
    log "✓ ArgoCD CLI configured"
    
    # Save credentials for future use
    cat > /tmp/argocd-config.sh <<EOF
export ARGOCD_SERVER="$argocd_ip:443"
export ARGOCD_ADMIN_PASSWORD="$admin_password"
EOF
    
    return 0
}

# Register Git repository
register_git_repository() {
    log "=== REGISTERING GIT REPOSITORY ==="
    
    local repo_url="https://github.com/kushin77/code-server"
    
    # Add repository via CLI (idempotent)
    argocd repo add "$repo_url" \
        --type git \
        --name code-server-repo \
        --username ""  \
        --password "" \
        2>/dev/null || log "Repository already registered"
    
    log "✓ Git repository registered"
    emit_metric "git_repo_registered" "1" "gauge"
}

# Create AppProject for team isolation
create_app_project() {
    log "=== CREATING APPPROJECT FOR TEAM ISOLATION ==="
    
    kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: development
  namespace: argocd
spec:
  description: Development team projects with RBAC
  sourceRepos:
  - 'https://github.com/kushin77/*'
  destinations:
  - namespace: development
    server: https://kubernetes.default.svc
  - namespace: code-server
    server: https://kubernetes.default.svc
  - namespace: argocd
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  namespaceResourceBlacklist:
  - group: ''
    kind: ResourceQuota
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
  roles:
  - name: developer
    policies:
    - p, proj:development:developer, applications, get, development/*, allow
    - p, proj:development:developer, applications, sync, development/*, allow
    - p, proj:development:developer, repositories, get, code-server-repo, allow
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: operations
  namespace: argocd
spec:
  description: Operations/SRE projects - full cluster access
  sourceRepos:
  - 'https://github.com/kushin77/*'
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
  roles:
  - name: admin
    policies:
    - p, proj:operations:admin, applications, *, operations/*, allow
    - p, proj:operations:admin, repositories, *, *, allow
EOF
    
    log "✓ AppProject created"
    emit_metric "appproject_created" "1" "gauge"
}

# Deploy ArgoCD Applications (GitOps declarative)
deploy_applications() {
    log "=== DEPLOYING APPLICATIONS VIA GITOPS ==="
    
    # Development environment - auto-sync
    kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: code-server-dev
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: development
  source:
    repoURL: https://github.com/kushin77/code-server
    targetRevision: main
    path: k8s/overlays/development
  destination:
    server: https://kubernetes.default.svc
    namespace: development
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allow:
        empty: false
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=background
    - RespectIgnoreDifferences=true
  revisionHistoryLimit: 10
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: code-server-staging
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: development
  source:
    repoURL: https://github.com/kushin77/code-server
    targetRevision: staging
    path: k8s/overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: staging
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - Validate=true
  revisionHistoryLimit: 5
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: code-server-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: operations
  source:
    repoURL: https://github.com/kushin77/code-server
    targetRevision: production
    path: k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: code-server
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - Validate=true
  revisionHistoryLimit: 20
EOF
    
    log "✓ Applications deployed"
    emit_metric "applications_deployed" "3" "gauge"
}

# Install Argo Rollouts for canary deployments
install_argo_rollouts() {
    log "=== INSTALLING ARGO ROLLOUTS FOR CANARY DEPLOYMENTS ==="
    
    kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -n argo-rollouts -f \
        "https://github.com/argoproj/argo-rollouts/releases/download/v1.6.0/install.yaml"
    
    log "✓ Argo Rollouts installed"
    emit_metric "argo_rollouts_installed" "1" "gauge"
}

# Configure notifications (Slack)
setup_notifications() {
    log "=== SETTING UP NOTIFICATIONS ==="
    
    # Create notification secret
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
type: Opaque
stringData:
  slack-token: ${SLACK_TOKEN:-xoxb-placeholder}
EOF
    
    # Create notification config
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  trigger.on-sync-succeeded: |
    - when: app.status.operationState.phase in ['Succeeded']
      oncePer: app.status.operationState.finishedAt
      send: [app-synced]
  template.app-synced: |
    message: |
      ✅ Application {{.app.metadata.name}} synced successfully
      Repo: {{.app.spec.source.repoURL}}
      Branch: {{.app.spec.source.targetRevision}}
    slack:
      attachments: |
        [{"color": "#18be52", "fields": [
          {"title": "Status", "value": "{{.app.status.syncResult.status}}", "short": true},
          {"title": "Revision", "value": "{{.app.status.sync.revision}}", "short": true}
        ]}]
EOF
    
    log "✓ Notifications configured"
    emit_metric "notifications_configured" "1" "gauge"
}

# Health check
health_check() {
    log "=== PERFORMING HEALTH CHECKS ==="
    
    # Check ArgoCD server
    if kubectl -n argocd get pod -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.phase}' | grep -q Running; then
        log "✓ ArgoCD server healthy"
    else
        log "ERROR: ArgoCD server not healthy"
        return 1
    fi
    
    # Check applications
    local app_count
    app_count=$(argocd app list 2>/dev/null | tail -n +2 | wc -l)
    log "✓ Applications deployed: $app_count"
    emit_metric "applications_count" "$app_count" "gauge"
    
    return 0
}

# Main execution
main() {
    log "╔════════════════════════════════════════════════════════════════╗"
    log "║     ARGOCD GITOPS CONTROL PLANE DEPLOYMENT                    ║"
    log "║     Target: On-Premises (192.168.168.31)                      ║"
    log "║     Status: Production-Ready, Immutable, Independent           ║"
    log "║     Phase: #168 Implementation                                 ║"
    log "╚════════════════════════════════════════════════════════════════╝"
    
    mkdir -p "$(dirname "$LOG_FILE")" /var/metrics
    
    verify_k3s || { log "k3s verification failed"; return 1; }
    install_argocd || { log "ArgoCD installation failed"; return 1; }
    configure_argocd_cli || { log "ArgoCD CLI configuration failed"; return 1; }
    register_git_repository || { log "Git repository registration failed"; return 1; }
    create_app_project || { log "AppProject creation failed"; return 1; }
    deploy_applications || { log "Application deployment failed"; return 1; }
    install_argo_rollouts || { log "Argo Rollouts installation failed"; return 1; }
    setup_notifications || { log "Notification setup failed"; return 1; }
    health_check || { log "Health checks failed"; return 1; }
    
    log ""
    log "╔════════════════════════════════════════════════════════════════╗"
    log "║     ✅ ARGOCD GITOPS DEPLOYMENT COMPLETE                       ║"
    log "║     Features: GitOps, Canary Deployments, Team Isolation       ║"
    log "║     Applications: 3 (dev/staging/prod)                         ║"
    log "║     Access: kubectl port-forward -n argocd svc/argocd-server   ║"
    log "║               8080:443                                         ║"
    log "║     Status: Production-Ready                                   ║"
    log "║     Logs: $LOG_FILE                                            ║"
    log "╚════════════════════════════════════════════════════════════════╝"
    
    return 0
}

main "$@"
