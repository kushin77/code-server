#!/usr/bin/env bash

# kubernetes/scripts/deploy.sh
# Deploy code-server infrastructure to target environment
# Usage: ./deploy.sh [dev|staging|production]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
KUBERNETES_DIR="$PROJECT_ROOT/kubernetes"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Arguments
ENVIRONMENT="${1:-}"

# Validate arguments
if [[ -z "$ENVIRONMENT" ]]; then
    log_error "Usage: $0 [dev|staging|production]"
    exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT (must be dev, staging, or production)"
    exit 1
fi

# Validate tools
check_tools() {
    local tools=("kubectl" "kustomize")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool not found. Please install it first."
            exit 1
        fi
    done
    log_success "All required tools found"
}

# Validate cluster connectivity
check_cluster_connection() {
    log_info "Checking Kubernetes cluster connection..."
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check kubeconfig."
        exit 1
    fi
    
    log_success "Connected to cluster: $(kubectl config current-context)"
}

# Check if metrics server is installed (required for HPA)
check_metrics_server() {
    log_info "Checking Metrics Server installation..."
    
    if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        log_success "Metrics Server found in kube-system namespace"
    else
        log_warn "Metrics Server not found. HPA may not work properly."
        log_info "Install with: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
}

# Build manifests with kustomize
build_manifests() {
    log_info "Building Kubernetes manifests for $ENVIRONMENT..."
    
    local overlay_path="$KUBERNETES_DIR/overlays/$ENVIRONMENT"
    
    if [[ ! -d "$overlay_path" ]]; then
        log_error "Overlay directory not found: $overlay_path"
        exit 1
    fi
    
    log_info "Using overlay: $overlay_path"
    
    # Test build (dry-run)
    if ! kustomize build "$overlay_path" > /dev/null; then
        log_error "Kustomize build failed for $ENVIRONMENT overlay"
        exit 1
    fi
    
    log_success "Manifests built successfully"
}

# Create namespace if it doesn't exist
create_namespace() {
    log_info "Ensuring namespace 'code-server' exists..."
    
    if kubectl get namespace code-server &>/dev/null; then
        log_success "Namespace 'code-server' already exists"
    else
        log_info "Creating namespace 'code-server'..."
        kubectl create namespace code-server
        kubectl label namespace code-server app=code-server environment="$ENVIRONMENT"
        log_success "Namespace created"
    fi
}

# Pre-deployment checks
pre_deployment_checks() {
    log_info "Running pre-deployment checks for $ENVIRONMENT..."
    
    # Check cluster capacity (for production)
    if [[ "$ENVIRONMENT" == "production" ]]; then
        log_info "Checking node capacity..."
        local node_count=$(kubectl get nodes --no-headers | wc -l)
        
        if [[ $node_count -lt 3 ]]; then
            log_warn "Production environment recommended to have 3+ nodes for HA. Found: $node_count"
        fi
    fi
    
    # Check for sufficient storage
    log_info "Checking storage class availability..."
    if ! kubectl get storageclass &>/dev/null; then
        log_warn "No storage classes found. PersistentVolumes may not be created."
    fi
    
    log_success "Pre-deployment checks passed"
}

# Apply manifests
apply_manifests() {
    log_info "Applying Kubernetes manifests to $ENVIRONMENT environment..."
    
    local overlay_path="$KUBERNETES_DIR/overlays/$ENVIRONMENT"
    
    # Apply with confirmation for production
    if [[ "$ENVIRONMENT" == "production" ]]; then
        log_warn "This will deploy to PRODUCTION environment"
        read -p "Are you sure you want to continue? (yes/no): " -r CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    log_info "Applying manifests..."
    kubectl apply -k "$overlay_path"
    
    log_success "Manifests applied successfully"
}

# Wait for rollout
wait_for_rollout() {
    log_info "Waiting for deployments to roll out..."
    
    local deployments=("code-server" "agent-api" "embeddings" "prometheus" "grafana")
    local timeout=300  # 5 minutes
    
    for deployment in "${deployments[@]}"; do
        log_info "  Waiting for $deployment..."
        
        if kubectl rollout status deployment/"$deployment" -n code-server --timeout="${timeout}s"; then
            log_success "  $deployment deployment complete"
        else
            log_warn "  $deployment rollout timeout or failed"
        fi
    done
    
    log_success "Deployment rollout complete"
}

# Print deployment summary
print_summary() {
    log_info "=== Deployment Summary ==="
    log_info "Environment: $ENVIRONMENT"
    
    echo ""
    log_info "Deployed Pods:"
    kubectl get pods -n code-server --no-headers | awk '{print "  -", $1, "(" $3 ")"}'
    
    echo ""
    log_info "Services:"
    kubectl get svc -n code-server --no-headers | awk '{print "  -", $1, "(" $3 ")"}'
    
    echo ""
    log_info "PersistentVolumeClaims:"
    kubectl get pvc -n code-server --no-headers 2>/dev/null || log_info "  (none)"
    
    echo ""
    log_info "HPA Status:"
    kubectl get hpa -n code-server --no-headers 2>/dev/null || log_info "  (none configured)"
    
    echo ""
    log_info "Next steps:"
    case "$ENVIRONMENT" in
        dev)
            log_info "  Port-forward to code-server: kubectl port-forward -n code-server svc/code-server 8080:8443"
            log_info "  Port-forward to Grafana: kubectl port-forward -n code-server svc/grafana 3000:3000"
            ;;
        staging)
            log_info "  Check staging ingress: kubectl get ingress -n code-server"
            log_info "  Verify services: kubectl get svc -n code-server"
            ;;
        production)
            log_info "  Monitor deployments: kubectl rollout status deployment/code-server -n code-server"
            log_info "  Check HPA: kubectl get hpa -n code-server"
            log_info "  View logs: kubectl logs -f -n code-server deployment/code-server"
            ;;
    esac
}

# Main execution
main() {
    log_info "Starting deployment to $ENVIRONMENT environment..."
    
    check_tools
    check_cluster_connection
    check_metrics_server
    build_manifests
    create_namespace
    pre_deployment_checks
    apply_manifests
    wait_for_rollout
    print_summary
    
    log_success "Deployment complete!"
}

# Run main
main "$@"
