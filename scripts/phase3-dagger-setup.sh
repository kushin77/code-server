#!/bin/bash
# Phase 3 Issue #169 - Dagger CI/CD Engine Deployment
# Language-agnostic container build pipeline for kushin77/code-server
# Integrates with k3s, Harbor, ArgoCD for complete GitOps workflow

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DAGGER_VERSION=${DAGGER_VERSION:-"0.9.11"}
NAMESPACE=${NAMESPACE:-"dagger"}
HARBOR_URL=${HARBOR_URL:-"192.168.168.31:8443"}
HARBOR_PROJECT=${HARBOR_PROJECT:-"code-server"}
GITHUB_TOKEN=${GITHUB_TOKEN:-""}
SLACK_WEBHOOK=${SLACK_WEBHOOK:-""}

print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    print_header "Prerequisites Check"
    
    local errors=0
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found - install k3s first (Issue #164)"
        ((errors++))
    else
        print_success "kubectl available"
    fi
    
    # Check k3s cluster
    if ! kubectl cluster-info &> /dev/null 2>&1; then
        print_error "k3s cluster not accessible"
        ((errors++))
    else
        print_success "k3s cluster accessible"
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker not installed"
        ((errors++))
    else
        print_success "Docker available"
    fi
    
    # Check git
    if ! command -v git &> /dev/null; then
        print_error "Git not installed"
        ((errors++))
    else
        print_success "Git available"
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Prerequisites check failed: $errors missing components"
        return 1
    fi
    
    print_success "All prerequisites met"
}

# ============================================================================
# Dagger Installation
# ============================================================================

install_dagger() {
    print_header "Dagger Installation"
    
    if command -v dagger &> /dev/null; then
        local current_version=$(dagger version 2>/dev/null || echo "unknown")
        print_info "Dagger already installed: $current_version"
        return 0
    fi
    
    print_step "Downloading Dagger $DAGGER_VERSION..."
    
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    if [ "$arch" == "x86_64" ]; then
        arch="amd64"
    elif [ "$arch" == "aarch64" ]; then
        arch="arm64"
    fi
    
    local url="https://github.com/dagger/dagger/releases/download/v${DAGGER_VERSION}/dagger_v${DAGGER_VERSION}_${os}_${arch}.tar.gz"
    
    if ! curl -sL "$url" | tar xz -C /tmp; then
        print_error "Failed to download Dagger"
        return 1
    fi
    
    if ! sudo mv /tmp/dagger /usr/local/bin/dagger || ! sudo chmod +x /usr/local/bin/dagger; then
        print_error "Failed to install Dagger binary"
        return 1
    fi
    
    # Verify installation
    if ! dagger version &> /dev/null; then
        print_error "Dagger installation verification failed"
        return 1
    fi
    
    print_success "Dagger $DAGGER_VERSION installed"
}

# ============================================================================
# Namespace & RBAC Setup
# ============================================================================

setup_namespace_rbac() {
    print_header "Namespace & RBAC Setup"
    
    print_step "Creating namespace: $NAMESPACE"
    
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace created"
    
    print_step "Creating RBAC for Dagger..."
    
    # Service account for Dagger
    kubectl create serviceaccount dagger -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # ClusterRole for Dagger CI/CD operations
    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: dagger-ci-role
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["create", "get", "list", "watch", "delete"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "get", "list", "watch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "patch"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "create"]
  - apiGroups: ["argoproj.io"]
    resources: ["applications"]
    verbs: ["get", "list", "create", "patch"]
EOF
    
    # Bind role to service account
    kubectl create clusterrolebinding dagger-ci-binding \
        --clusterrole=dagger-ci-role \
        --serviceaccount="$NAMESPACE:dagger" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "RBAC configured"
}

# ============================================================================
# Harbor Integration
# ============================================================================

setup_harbor_integration() {
    print_header "Harbor Registry Integration"
    
    if [ -z "$HARBOR_URL" ]; then
        print_info "Skipping Harbor setup (HARBOR_URL not set)"
        return 0
    fi
    
    print_step "Creating Harbor credentials secret..."
    
    # Read Harbor credentials or use defaults for testing
    local harbor_user="${HARBOR_USER:-admin}"
    local harbor_pass="${HARBOR_PASS:-Harbor12345}"
    
    kubectl create secret docker-registry harbor-registry \
        --docker-server="$HARBOR_URL" \
        --docker-username="$harbor_user" \
        --docker-password="$harbor_pass" \
        --docker-email="ci@kushnir.cloud" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Harbor integration configured"
}

# ============================================================================
# GitHub & Notifications Integration
# ============================================================================

setup_integrations() {
    print_header "GitHub & Notifications Integration"
    
    if [ -z "$GITHUB_TOKEN" ]; then
        print_info "GitHub token not set (GITHUB_TOKEN) - status checks disabled"
    else
        print_step "Setting up GitHub integration..."
        kubectl create secret generic github-token \
            --from-literal=token="$GITHUB_TOKEN" \
            -n "$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
        print_success "GitHub integration configured"
    fi
    
    if [ -z "$SLACK_WEBHOOK" ]; then
        print_info "Slack webhook not set (SLACK_WEBHOOK) - notifications disabled"
    else
        print_step "Setting up Slack notifications..."
        kubectl create secret generic slack-webhook \
            --from-literal=webhook="$SLACK_WEBHOOK" \
            -n "$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
        print_success "Slack integration configured"
    fi
}

# ============================================================================
# ConfigMap for Pipeline Configuration
# ============================================================================

setup_configmap() {
    print_header "Pipeline Configuration"
    
    print_step "Creating Dagger pipeline configuration..."
    
    kubectl create configmap dagger-config \
        --from-literal=harbor-url="$HARBOR_URL" \
        --from-literal=harbor-project="$HARBOR_PROJECT" \
        --from-literal=github-org="kushin77" \
        --from-literal=github-repo="code-server" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "ConfigMap created"
}

# ============================================================================
# Workflow Template Setup
# ============================================================================

setup_workflow_templates() {
    print_header "Workflow Templates Setup"
    
    print_step "Creating Dagger workflow templates..."
    
    # Create workflow directory
    mkdir -p ~/.dagger/workflows
    
    # Create base workflow template
    cat > ~/.dagger/workflows/base.yaml <<'EOF'
# Dagger Base Workflow Template
# Provides: build, test, push to registry, deploy via ArgoCD

version: "1.0"
name: "code-server-cicd"
description: "Multi-stage CI/CD pipeline for code-server"

stages:
  - name: "build"
    description: "Build Docker image"
    steps:
      - name: "checkout"
        image: "alpine/git:latest"
        commands:
          - "git clone https://github.com/kushin77/code-server.git /workspace"
          - "cd /workspace && git checkout ${GIT_REF}"
      
      - name: "build-image"
        image: "docker:latest"
        commands:
          - "docker build -t code-server:${VERSION} ."
          - "docker tag code-server:${VERSION} ${HARBOR_URL}/${HARBOR_PROJECT}/code-server:${VERSION}"
  
  - name: "test"
    description: "Run comprehensive tests"
    steps:
      - name: "unit-tests"
        image: "code-server:${VERSION}"
        commands:
          - "npm test -- --coverage"
      
      - name: "integration-tests"
        image: "code-server:${VERSION}"
        commands:
          - "npm run test:integration"
  
  - name: "push"
    description: "Push image to Harbor registry"
    steps:
      - name: "push-image"
        image: "docker:latest"
        commands:
          - "docker push ${HARBOR_URL}/${HARBOR_PROJECT}/code-server:${VERSION}"
  
  - name: "deploy"
    description: "Deploy via ArgoCD"
    steps:
      - name: "update-values"
        image: "alpine/git:latest"
        commands:
          - "git clone https://github.com/kushin77/code-server.git /deploy"
          - "cd /deploy && sed -i 's|image:.*|image: ${HARBOR_URL}/${HARBOR_PROJECT}/code-server:${VERSION}|' deploy/values.yaml"
          - "git add deploy/values.yaml && git commit -m 'Update image to ${VERSION}' && git push"
      
      - name: "argocd-sync"
        image: "argoproj/argocd:latest"
        commands:
          - "argocd app sync code-server --insecure"
          - "argocd app wait code-server --timeout 300s"

env:
  VERSION: "${GIT_COMMIT_SHA:0:8}"
  GIT_REF: "main"
  HARBOR_URL: "192.168.168.31:8443"
  HARBOR_PROJECT: "code-server"
EOF
    
    print_success "Workflow templates created"
}

# ============================================================================
# Health Check
# ============================================================================

health_check() {
    print_header "Health Check"
    
    local errors=0
    
    print_step "Verifying Dagger installation..."
    if dagger version &> /dev/null; then
        print_success "Dagger CLI operational"
    else
        print_error "Dagger CLI not responding"
        ((errors++))
    fi
    
    print_step "Verifying k3s access..."
    if kubectl get nodes &> /dev/null; then
        print_success "k3s cluster accessible"
    else
        print_error "Cannot access k3s cluster"
        ((errors++))
    fi
    
    print_step "Verifying namespace..."
    if kubectl get ns "$NAMESPACE" &> /dev/null; then
        print_success "Namespace $NAMESPACE exists"
    else
        print_error "Namespace $NAMESPACE not found"
        ((errors++))
    fi
    
    print_step "Verifying RBAC..."
    if kubectl get clusterrole dagger-ci-role &> /dev/null; then
        print_success "RBAC roles configured"
    else
        print_error "RBAC not properly configured"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        print_success "All health checks passed"
        return 0
    else
        print_error "Health check failed: $errors issues found"
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    print_header "Phase 3 Issue #169: Dagger CI/CD Engine Setup"
    
    local start_time=$(date +%s)
    
    check_prerequisites || exit 1
    install_dagger || exit 1
    setup_namespace_rbac || exit 1
    setup_harbor_integration || exit 1
    setup_integrations || exit 1
    setup_configmap || exit 1
    setup_workflow_templates || exit 1
    health_check || exit 1
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header "✅ Dagger Setup Complete"
    print_success "Total deployment time: ${duration}s"
    print_info "Next: Deploy ArgoCD (Issue #168) to enable GitOps"
    print_info "Then: Run workflows with: dagger run ./workflows/base.yaml"
}

main "$@"
