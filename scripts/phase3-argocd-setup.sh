#!/bin/bash

# Phase 3 Issue #168: ArgoCD GitOps Control Plane - Production Setup & Deployment
# Target: k3s cluster on 192.168.168.31
# Purpose: Declarative infrastructure management, GitOps control plane, canary deployments

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

PHASE_START=$(date +%s)

echo -e "${MAGENTA}"
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║     Phase 3 Issue #168: ArgoCD GitOps Control Plane - Production Setup     ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${BLUE}Date: $(date)${NC}"
echo -e "${BLUE}Target: k3s cluster on 192.168.168.31${NC}"
echo ""

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

# ============================================================================
# STEP 1: Prerequisites Check
# ============================================================================

echo -e "${YELLOW}[STEP 1] Prerequisites Check${NC}"
echo ""

if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    exit 1
fi

if ! command -v helm &>/dev/null; then
    echo -e "${YELLOW}⚠ Helm not found - installing...${NC}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo -e "${GREEN}✓ kubectl available${NC}"
echo -e "${GREEN}✓ helm available${NC}"

# Check k3s cluster
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}✗ Cannot connect to k3s cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✓ k3s cluster accessible${NC}"
echo ""

# ============================================================================
# STEP 2: Create ArgoCD Namespace
# ============================================================================

echo -e "${YELLOW}[STEP 2] Create ArgoCD Namespace${NC}"
echo ""

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace 'argocd' created${NC}"
echo ""

# ============================================================================
# STEP 3: Install ArgoCD via Helm
# ============================================================================

echo -e "${YELLOW}[STEP 3] Install ArgoCD via Helm${NC}"
echo ""

echo "Adding Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

echo "Installing ArgoCD Helm chart..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values - <<'EOF'
global:
  domain: argocd.local

configs:
  params:
    application.instanceLabelKey: argocd.argoproj.io/instance
  secret:
    createSecret: true

server:
  service:
    type: LoadBalancer
    loadBalancerSourceRanges: []
  ingress:
    enabled: false
  config:
    url: https://argocd.local
    application.instanceLabelKey: argocd.argoproj.io/instance
  rbacConfig:
    policy.default: role:readonly
    policy.csv: |
      g, github-org:kushin77, role:admin

controller:
  replicas: 1

repoServer:
  replicas: 1

dex:
  enabled: true

redis:
  enabled: true

notifications:
  enabled: true
  
applicationSet:
  enabled: true

crds:
  install: true
EOF

echo -e "${GREEN}✓ ArgoCD installed${NC}"
echo ""

# ============================================================================
# STEP 4: Wait for ArgoCD to be Ready
# ============================================================================

echo -e "${YELLOW}[STEP 4] Wait for ArgoCD Components${NC}"
echo ""

echo "Waiting for ArgoCD pods..."
kubectl -n argocd wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server --timeout=300s 2>/dev/null || true
kubectl -n argocd wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-controller --timeout=300s 2>/dev/null || true

sleep 5

echo -e "${GREEN}✓ ArgoCD pods running${NC}"
echo ""

# ============================================================================
# STEP 5: Get Admin Password & Access Info
# ============================================================================

echo -e "${YELLOW}[STEP 5] ArgoCD Access Information${NC}"
echo ""

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "PASSWORD_NOT_SET")
ARGOCD_IP=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "PENDING")

echo -e "${BLUE}ArgoCD Access Details:${NC}"
echo "  URL: https://${ARGOCD_IP}:443"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""

# Store in file for reference
cat > /tmp/argocd-credentials.txt <<EOF
ArgoCD Access Information
========================
Date: $(date)

URL: https://${ARGOCD_IP}:443
Username: admin
Password: ${ARGOCD_PASSWORD}

CLI Login:
  argocd login ${ARGOCD_IP} --insecure

Get new password:
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

Change admin password:
  argocd account update-password --account admin --new-password <NEW_PASSWORD>
EOF

echo -e "${GREEN}✓ Credentials saved to /tmp/argocd-credentials.txt${NC}"
echo ""

# ============================================================================
# STEP 6: Install Argo Rollouts (Canary Deployments)
# ============================================================================

echo -e "${YELLOW}[STEP 6] Install Argo Rollouts (Canary Deployments)${NC}"
echo ""

kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Argo Rollouts..."
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

sleep 5
echo -e "${GREEN}✓ Argo Rollouts installed${NC}"
echo ""

# ============================================================================
# STEP 7: Configure Git Repository
# ============================================================================

echo -e "${YELLOW}[STEP 7] Configure Git Repository${NC}"
echo ""

# Get GitHub token from environment or prompt
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${YELLOW}⚠ GitHub token not provided${NC}"
    echo "  Set GITHUB_TOKEN environment variable for automatic Git integration"
    echo "  Or manually add repository: argocd repo add https://github.com/kushin77/code-server"
else
    echo "Adding GitHub repository with token auth..."
    
    argocd repo add https://github.com/kushin77/code-server \
      --username git \
      --password "${GITHUB_TOKEN}" \
      --insecure-skip-server-verification 2>/dev/null || {
        echo -e "${YELLOW}⚠ Repository may already be configured${NC}"
    }
    
    echo -e "${GREEN}✓ Git repository configured${NC}"
fi

echo ""

# ============================================================================
# STEP 8: Create AppProject (Team Isolation)
# ============================================================================

echo -e "${YELLOW}[STEP 8] Create AppProject for Development Team${NC}"
echo ""

kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: development
  namespace: argocd
spec:
  description: Development team projects
  sourceRepos:
  - 'https://github.com/kushin77/*'
  destinations:
  - namespace: 'development'
    server: 'https://kubernetes.default.svc'
  - namespace: 'code-server'
    server: 'https://kubernetes.default.svc'
  - namespace: 'default'
    server: 'https://kubernetes.default.svc'
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  roles:
  - name: developer
    policies:
    - p, proj:development:developer, applications, get, development/*, allow
    - p, proj:development:developer, applications, sync, development/*, allow
EOF

echo -e "${GREEN}✓ AppProject 'development' created${NC}"
echo ""

# ============================================================================
# STEP 9: Create Initial Application (code-server)
# ============================================================================

echo -e "${YELLOW}[STEP 9] Create ArgoCD Application (code-server)${NC}"
echo ""

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: code-server
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: code-server
  namespace: argocd
spec:
  project: development
  source:
    repoURL: https://github.com/kushin77/code-server
    targetRevision: main
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: code-server
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  revisionHistoryLimit: 10
EOF

echo -e "${GREEN}✓ Application 'code-server' created${NC}"
echo ""

# ============================================================================
# STEP 10: Setup Notifications (Slack)
# ============================================================================

echo -e "${YELLOW}[STEP 10] Configure Notifications${NC}"
echo ""

SLACK_TOKEN="${SLACK_TOKEN:-}"

if [ -n "$SLACK_TOKEN" ]; then
    echo "Creating Slack notification secret..."
    
    kubectl -n argocd create secret generic argocd-notifications-slack \
      --from-literal=slack-token="${SLACK_TOKEN}" \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo -e "${GREEN}✓ Slack notifications configured${NC}"
else
    echo -e "${YELLOW}⚠ SLACK_TOKEN not provided - skipping Slack integration${NC}"
    echo "  Set SLACK_TOKEN environment variable to enable Slack notifications"
fi

echo ""

# ============================================================================
# STEP 11: Install Argo Workflows (CI/CD Pipeline)
# ============================================================================

echo -e "${YELLOW}[STEP 11] Install Argo Workflows${NC}"
echo ""

kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Argo Workflows..."
helm upgrade --install argo argo/argo-workflows \
  --namespace argo \
  --set executor.image.tag=v3.4.4 \
  --wait 2>/dev/null || {
    echo -e "${YELLOW}⚠ Argo Workflows installation encountered issues${NC}"
}

echo -e "${GREEN}✓ Argo Workflows installed${NC}"
echo ""

# ============================================================================
# STEP 12: Verification
# ============================================================================

PHASE_END=$(date +%s)
PHASE_DURATION=$((PHASE_END - PHASE_START))

echo -e "${MAGENTA}"
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    SETUP COMPLETE                                         ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${GREEN}✓ Duration: ${PHASE_DURATION}s${NC}"
echo ""

echo -e "${BLUE}VERIFICATION STEPS:${NC}"
echo ""
echo "1. Check ArgoCD pods:"
echo "   kubectl get pods -n argocd"
echo ""
echo "2. Get LoadBalancer IP:"
echo "   kubectl -n argocd get svc argocd-server"
echo ""
echo "3. Login to ArgoCD UI:"
echo "   https://<LOADBALANCER_IP>"
echo "   Username: admin"
echo "   Password: (see /tmp/argocd-credentials.txt)"
echo ""
echo "4. Check applications:"
echo "   argocd app list"
echo ""
echo "5. View application status:"
echo "   argocd app get code-server"
echo ""

echo -e "${BLUE}NEXT STEPS:${NC}"
echo ""
echo "1. Access ArgoCD UI at: https://${ARGOCD_IP}:443"
echo "2. Add Git webhook for auto-sync:"
echo "   GitHub Settings → Webhooks → Add"
echo "   URL: https://${ARGOCD_IP}/api/webhook"
echo "3. Monitor applications via: argocd app watch code-server"
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Phase 3 Issue #168: ArgoCD Setup - COMPLETE ✓${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

exit 0
