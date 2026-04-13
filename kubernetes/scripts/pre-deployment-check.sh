#!/usr/bin/env bash

# kubernetes/scripts/pre-deployment-check.sh
# Pre-flight checks for Kubernetes deployment
# Usage: ./pre-deployment-check.sh [environment]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
KUBERNETES_DIR="$PROJECT_ROOT/kubernetes"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; ((CHECKS_PASSED++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((CHECKS_WARNING++)); }
log_error() { echo -e "${RED}[✗]${NC} $1"; ((CHECKS_FAILED++)); }

# Arguments
ENVIRONMENT="${1:-}"

if [[ -z "$ENVIRONMENT" ]]; then
    log_error "Usage: $0 [dev|staging|production]"
    exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT"
    exit 1
fi

log_info "=== Pre-Deployment Checks for $ENVIRONMENT ==="

# 1. Check kubectl availability
log_info "Checking kubectl installation..."
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | awk '{print $3}')
    log_success "kubectl found: $KUBECTL_VERSION"
else
    log_error "kubectl not found. Install kubectl first."
    exit 1
fi

# 2. Check cluster connection
log_info "Checking cluster connectivity..."
if kubectl cluster-info &>/dev/null; then
    CLUSTER_NAME=$(kubectl config current-context)
    log_success "Connected to cluster: $CLUSTER_NAME"
else
    log_error "Cannot connect to Kubernetes cluster. Check kubeconfig."
    exit 1
fi

# 3. Check API server availability
log_info "Checking API server availability..."
if kubectl get componentstatus &>/dev/null; then
    log_success "API server is available"
else
    log_error "API server is not responding"
    exit 1
fi

# 4. Check namespace
log_info "Checking 'code-server' namespace..."
if kubectl get namespace code-server &>/dev/null; then
    log_success "Namespace 'code-server' exists"
else
    log_warn "Namespace 'code-server' does not exist (will be created during deployment)"
fi

# 5. Check Metrics Server (required for HPA)
log_info "Checking Metrics Server (for HPA)..."
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    METRICS_VERSION=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F: '{print $2}')
    log_success "Metrics Server found: $METRICS_VERSION"
else
    log_warn "Metrics Server not found. HPA will not function. Install with:"
    log_warn "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

# 6. Check StorageClass
log_info "Checking StorageClass availability..."
if kubectl get storageclass &>/dev/null; then
    STORAGE_CLASS_COUNT=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
    log_success "Found $STORAGE_CLASS_COUNT StorageClass(es)"
else
    log_warn "No StorageClass found. PersistentVolumes may not be created automatically."
fi

# 7. Check node capacity
log_info "Checking node capacity..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")

if [[ $NODE_COUNT -gt 0 ]]; then
    log_success "Found $NODE_COUNT nodes ($READY_NODES Ready)"
    
    # Environment-specific node checks
    case "$ENVIRONMENT" in
        production)
            if [[ $NODE_COUNT -lt 3 ]]; then
                log_warn "Production recommended with 3+ nodes. Current: $NODE_COUNT"
            fi
            if [[ $READY_NODES -lt $NODE_COUNT ]]; then
                log_error "Not all nodes are Ready. Current: $READY_NODES/$NODE_COUNT"
            fi
            ;;
        staging)
            if [[ $NODE_COUNT -lt 2 ]]; then
                log_warn "Staging recommended with 2+ nodes. Current: $NODE_COUNT"
            fi
            ;;
    esac
else
    log_error "No nodes found in cluster"
fi

# 8. Check available resources
log_info "Checking available cluster resources..."
if kubectl top nodes &>/dev/null; then
    TOTAL_CPU=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.cpu}' | tr ' ' '+' | bc 2>/dev/null || echo "unknown")
    TOTAL_MEMORY=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.memory}' | tr -d 'Ki' | awk '{sum+=$1} END {print int(sum/1024/1024)}' | tr ' ' '+' | bc 2>/dev/null || echo "unknown")
    
    if [[ "$TOTAL_CPU" != "unknown" ]]; then
        log_success "Allocatable CPU: ${TOTAL_CPU}m"
    fi
    if [[ "$TOTAL_MEMORY" != "unknown" ]]; then
        log_success "Allocatable Memory: ${TOTAL_MEMORY}Gi"
    fi
else
    log_warn "Cannot retrieve node metrics (Metrics Server may not be ready)"
fi

# 9. Check kustomize
log_info "Checking kustomize installation..."
if command -v kustomize &> /dev/null; then
    KUSTOMIZE_VERSION=$(kustomize version 2>/dev/null | grep -oP 'kustomize/v\K[^,]+' || echo "unknown")
    log_success "kustomize found: v$KUSTOMIZE_VERSION"
else
    log_warn "kustomize not found. kubectl should have kustomize built-in."
fi

# 10. Validate manifests
log_info "Validating Kubernetes manifests..."
OVERLAY_PATH="$KUBERNETES_DIR/overlays/$ENVIRONMENT"

if [[ ! -d "$OVERLAY_PATH" ]]; then
    log_error "Overlay directory not found: $OVERLAY_PATH"
else
    if kustomize build "$OVERLAY_PATH" > /dev/null 2>&1; then
        MANIFEST_COUNT=$(kustomize build "$OVERLAY_PATH" | grep -c "^kind:" || echo "0")
        log_success "Manifests valid ($MANIFEST_COUNT resources)"
    else
        log_error "Manifest validation failed for $ENVIRONMENT"
    fi
fi

# 11. Check image availability (if registry accessible)
log_info "Checking image registry accessibility..."
if docker version &>/dev/null; then
    if docker pull alpine &>/dev/null; then
        log_success "Can reach Docker registries"
    else
        log_warn "Cannot pull images from Docker registries"
    fi
else
    log_warn "Docker not installed. Skipping registry check."
fi

# 12. Check for existing deployments
log_info "Checking for existing deployments..."
EXISTING_DEPLOYMENTS=$(kubectl get deployments -n code-server --no-headers 2>/dev/null | wc -l || echo "0")

if [[ $EXISTING_DEPLOYMENTS -gt 0 ]]; then
    log_warn "Found $EXISTING_DEPLOYMENTS existing deployment(s) in code-server namespace"
    log_warn "Deployment will update existing resources"
fi

# 13. Check RBAC permissions
log_info "Checking RBAC permissions..."
if kubectl auth can-i create deployments --namespace code-server &>/dev/null; then
    log_success "Have permission to create deployments"
else
    log_error "Insufficient permissions to create deployments in code-server namespace"
fi

# 14. Check for required configurations
log_info "Checking for application configurations..."
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    log_success "Environment configuration (.env) found"
else
    log_warn "Environment configuration (.env) not found. Will use defaults."
fi

# 15. Network policy check
log_info "Checking network policy support..."
if kubectl get networkpolicies -n kube-system &>/dev/null; then
    log_success "NetworkPolicy API available"
else
    log_warn "NetworkPolicy API not available. Network policies will not work."
fi

# Summary
echo ""
log_info "=== Pre-Deployment Check Summary ==="
echo -e "Passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Warnings: ${YELLOW}$CHECKS_WARNING${NC}"
echo -e "Failed: ${RED}$CHECKS_FAILED${NC}"

if [[ $CHECKS_FAILED -gt 0 ]]; then
    log_error "Pre-deployment checks failed. Please address errors before deploying."
    exit 1
elif [[ $CHECKS_WARNING -gt 0 ]]; then
    log_warn "Pre-deployment checks passed with $CHECKS_WARNING warning(s). Proceed with caution."
    exit 0
else
    log_success "All pre-deployment checks passed! Ready to deploy."
    exit 0
fi
