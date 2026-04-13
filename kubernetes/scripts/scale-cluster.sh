#!/usr/bin/env bash

# kubernetes/scripts/scale-cluster.sh
# Manage Horizontal Pod Autoscaler (HPA) configuration
# Usage: ./scale-cluster.sh [enable|disable|status|configure] [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
NAMESPACE="code-server"
COMMAND="${1:-}"

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check if HPA exists
hpa_exists() {
    local deployment="$1"
    kubectl get hpa -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.scaleTargetRef.name=="'$deployment'")].metadata.name}' 2>/dev/null | grep -q . && return 0 || return 1
}

# Get HPA status
get_hpa_status() {
    local deployment="$1"
    
    if ! hpa_exists "$deployment"; then
        return
    fi
    
    local hpa_name=$(kubectl get hpa -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.scaleTargetRef.name=="'$deployment'")].metadata.name}')
    
    if [[ -n "$hpa_name" ]]; then
        echo "Deployment: $deployment"
        kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}' | xargs echo "  Min Replicas:"
        kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.spec.maxReplicas}' | xargs echo "  Max Replicas:"
        kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}' | xargs echo "  Current Replicas:"
        
        # Show metrics
        echo "  Metrics:"
        kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{range .spec.metrics[*]}{.type}{"\n"}{end}' | sed 's/^/    /'
        
        echo ""
    fi
}

# Enable HPA for deployment
enable_hpa() {
    local deployment="$1"
    
    log_info "Enabling HPA for deployment: $deployment"
    
    if ! kubectl get deployment "$deployment" -n "$NAMESPACE" &>/dev/null; then
        log_error "Deployment '$deployment' not found in namespace '$NAMESPACE'"
        return 1
    fi
    
    if hpa_exists "$deployment"; then
        log_warn "HPA already exists for deployment '$deployment'"
        return 0
    fi
    
    # Create HPA manifest based on deployment
    local min_replicas=3
    local max_replicas=10
    local cpu_threshold=70
    local memory_threshold=80
    
    # Adjust for embeddings (GPU-intensive)
    if [[ "$deployment" == "embeddings" ]]; then
        max_replicas=6
        cpu_threshold=65
        memory_threshold=75
    fi
    
    log_info "Creating HPA with: min=$min_replicas, max=$max_replicas, cpu=$cpu_threshold%, memory=$memory_threshold%"
    
    cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: $deployment-hpa
  namespace: $NAMESPACE
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $deployment
  minReplicas: $min_replicas
  maxReplicas: $max_replicas
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: $cpu_threshold
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: $memory_threshold
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
EOF
    
    log_success "HPA created for deployment '$deployment'"
}

# Disable HPA for deployment
disable_hpa() {
    local deployment="$1"
    
    log_info "Disabling HPA for deployment: $deployment"
    
    if ! hpa_exists "$deployment"; then
        log_warn "No HPA found for deployment '$deployment'"
        return 0
    fi
    
    local hpa_name=$(kubectl get hpa -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.scaleTargetRef.name=="'$deployment'")].metadata.name}')
    
    if [[ -n "$hpa_name" ]]; then
        kubectl delete hpa "$hpa_name" -n "$NAMESPACE"
        log_success "HPA '$hpa_name' deleted"
    fi
}

# Manual scaling (override HPA)
manual_scale() {
    local deployment="$1"
    local replicas="$2"
    
    log_info "Manual scaling: $deployment to $replicas replicas"
    
    if ! kubectl get deployment "$deployment" -n "$NAMESPACE" &>/dev/null; then
        log_error "Deployment '$deployment' not found"
        return 1
    fi
    
    # If HPA exists, pause it
    if hpa_exists "$deployment"; then
        log_warn "HPA active for '$deployment'. Disabling temporarily for manual scaling."
        disable_hpa "$deployment"
    fi
    
    kubectl scale deployment "$deployment" --replicas="$replicas" -n "$NAMESPACE"
    kubectl rollout status deployment/"$deployment" -n "$NAMESPACE" --timeout=300s
    
    log_success "Deployment '$deployment' scaled to $replicas replicas"
}

# Show status of all HPAs
show_status() {
    log_info "HPA Status for namespace: $NAMESPACE"
    echo ""
    
    if ! kubectl get hpa -n "$NAMESPACE" &>/dev/null; then
        log_info "No HorizontalPodAutoscalers found"
        return
    fi
    
    # Get all deployments in namespace
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    for deployment in $deployments; do
        get_hpa_status "$deployment"
    done
    
    # Show current replica counts
    log_info "Current Replica Counts:"
    kubectl get deployments -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.replicas}{"\t"}{.status.readyReplicas}{"\n"}{end}' | column -t -N "DEPLOYMENT,DESIRED,READY"
}

# Configure all HPAs
configure_all() {
    log_info "Configuring HPA for all deployments in namespace: $NAMESPACE"
    
    local deployments=("code-server" "agent-api" "embeddings" "prometheus" "grafana")
    
    for deployment in "${deployments[@]}"; do
        if kubectl get deployment "$deployment" -n "$NAMESPACE" &>/dev/null; then
            if hpa_exists "$deployment"; then
                log_warn "HPA already exists for '$deployment', skipping"
            else
                enable_hpa "$deployment"
            fi
        fi
    done
    
    log_success "HPA configuration complete"
    show_status
}

# Show help
show_help() {
    cat <<EOF
Usage: $0 [command] [options]

Commands:
  enable [deployment]      Enable HPA for specific deployment
  disable [deployment]     Disable HPA for specific deployment
  status                   Show HPA status for all deployments
  configure                Configure HPA for all deployments
  scale [deployment] N     Manually scale deployment to N replicas
  help                     Show this help message

Options:
  -n, --namespace NS       Kubernetes namespace (default: code-server)

Examples:
  $0 enable code-server
  $0 disable agent-api
  $0 status
  $0 configure
  $0 scale code-server 5
  $0 -n staging status

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Validate namespace
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Namespace '$NAMESPACE' not found"
    exit 1
fi

# Execute command
case "$COMMAND" in
    enable)
        if [[ -z "${2:-}" ]]; then
            log_error "Deployment name required"
            show_help
            exit 1
        fi
        enable_hpa "$2"
        ;;
    disable)
        if [[ -z "${2:-}" ]]; then
            log_error "Deployment name required"
            show_help
            exit 1
        fi
        disable_hpa "$2"
        ;;
    status)
        show_status
        ;;
    configure)
        configure_all
        ;;
    scale)
        if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
            log_error "Deployment and replica count required"
            show_help
            exit 1
        fi
        manual_scale "$2" "$3"
        ;;
    help|--help|-h|'')
        show_help
        exit 0
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
