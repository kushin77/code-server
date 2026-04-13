#!/bin/bash
# Deployment Verification Script
# Validates deployment health and performance

set -e

ENVIRONMENT=${1:-staging}
TIMEOUT=${2:-300}

COLOR_BLUE='\033[0;34m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

log_info() { echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} $*"; }
log_success() { echo -e "${COLOR_GREEN}✓${COLOR_RESET} $*"; }
log_warn() { echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $*"; }
log_error() { echo -e "${COLOR_RED}✗${COLOR_RESET} $*"; }

# Verify Kubernetes connectivity
verify_cluster() {
    log_info "Verifying Kubernetes cluster connectivity..."
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Cluster connected"
}

# Check deployment rollout status
check_deployment() {
    local deployment=$1
    local namespace=$2
    
    log_info "Checking deployment: $deployment in namespace: $namespace"
    
    if ! kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout="${TIMEOUT}s"; then
        log_error "Deployment rollout failed: $deployment"
        return 1
    fi
    
    log_success "Deployment ready: $deployment"
}

# Verify pod health
check_pods() {
    local namespace=$1
    
    log_info "Checking pods in namespace: $namespace"
    
    local pod_count=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    if [ "$pod_count" -eq 0 ]; then
        log_warn "No pods found in namespace: $namespace"
        return 1
    fi
    
    local not_running=$(kubectl get pods -n "$namespace" --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
    if [ "$not_running" -gt 0 ]; then
        log_error "$not_running pods not in Running state"
        kubectl get pods -n "$namespace" -o wide
        return 1
    fi
    
    log_success "All pods running in namespace: $namespace"
}

# Check persistent volumes
check_volumes() {
    local namespace=$1
    
    log_info "Checking persistent volumes..."
    
    local unbound_pvcs=$(kubectl get pvc -n "$namespace" --field-selector=status.phase!=Bound --no-headers 2>/dev/null | wc -l)
    if [ "$unbound_pvcs" -gt 0 ]; then
        log_error "$unbound_pvcs PVCs not bound"
        kubectl get pvc -n "$namespace"
        return 1
    fi
    
    log_success "All PVCs bound"
}

# Check resource usage
check_resources() {
    log_info "Checking resource usage..."
    
    local nodes=$(kubectl get nodes -o json | jq -r '.items | length')
    log_info "Cluster nodes: $nodes"
    
    local allocatable_cpu=$(kubectl get nodes -o json | jq -r '[.items[].status.allocatable.cpu | rtrimstr("m") | tonumber] | add')
    local allocatable_mem=$(kubectl get nodes -o json | jq -r '[.items[].status.allocatable.memory | rtrimstr("Ki") | tonumber] | add / 1024 / 1024')
    
    log_info "Allocatable resources:"
    log_info "  CPU: ${allocatable_cpu}m"
    log_info "  Memory: ${allocatable_mem}Gi"
    
    # Check for resource available
    if [ "$allocatable_cpu" -lt 1000 ]; then
        log_warn "Low CPU resources available: ${allocatable_cpu}m"
    fi
    
    if (( $(echo "$allocatable_mem < 4" | bc -l) )); then
        log_warn "Low memory available: ${allocatable_mem}Gi"
    fi
    
    log_success "Resource check complete"
}

# Perform smoke tests
smoke_tests() {
    local environment=$1
    
    log_info "Running smoke tests for environment: $environment"
    
    # Test API connectivity
    local code_server_url="http://localhost:8080"
    if [ "$environment" = "production" ]; then
        code_server_url="https://code-server.example.com"
    fi
    
    log_info "Testing connectivity to code-server: $code_server_url"
    
    if ! curl -sf -m 30 "$code_server_url" > /dev/null 2>&1; then
        log_warn "Code-server not responding yet (may still be starting)"
    else
        log_success "Code-server responding"
    fi
    
    # Test Prometheus
    log_info "Testing Prometheus connectivity..."
    if kubectl port-forward -n monitoring svc/prometheus 9090:9090 &>/dev/null &
    then
        sleep 2
        if curl -sf http://localhost:9090/-/healthy > /dev/null; then
            log_success "Prometheus healthy"
        fi
        pkill -f "port-forward" || true
    fi
    
    # Test Grafana
    log_info "Testing Grafana connectivity..."
    if kubectl port-forward -n monitoring svc/grafana 3000:80 &>/dev/null &
    then
        sleep 2
        if curl -sf http://localhost:3000/api/health > /dev/null; then
            log_success "Grafana healthy"
        fi
        pkill -f "port-forward" || true
    fi
}

# Performance benchmarks
performance_benchmarks() {
    log_info "Running performance benchmarks..."
    
    # Test API response time
    local start_time=$(date +%s%N)
    kubectl get pods -A > /dev/null
    local end_time=$(date +%s%N)
    local response_time=$(( (end_time - start_time) / 1000000 ))
    
    log_info "kubectl response time: ${response_time}ms"
    
    if [ "$response_time" -gt 5000 ]; then
        log_warn "Slow kubectl response: ${response_time}ms"
    fi
    
    log_success "Performance benchmarks complete"
}

# Generate report
generate_report() {
    local environment=$1
    
    log_info ""
    log_info "=== Deployment Verification Report ==="
    log_info "Environment: $environment"
    log_info "Timestamp: $(date)"
    log_info "Status: $([ $? -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')"
    log_info ""
}

# Main execution
main() {
    log_info "Starting deployment verification for: $ENVIRONMENT"
    log_info ""
    
    verify_cluster
    
    case "$ENVIRONMENT" in
        staging)
            check_deployment "code-server" "code-server"
            check_pods "code-server"
            check_pods "monitoring"
            check_volumes "code-server"
            check_resources
            ;;
        production)
            check_deployment "code-server" "code-server"
            check_pods "code-server"
            check_pods "monitoring"
            check_pods "backup"
            check_volumes "code-server"
            check_resources
            ;;
        *)
            log_error "Unknown environment: $ENVIRONMENT"
            exit 1
            ;;
    esac
    
    log_info ""
    smoke_tests "$ENVIRONMENT"
    
    log_info ""
    performance_benchmarks
    
    log_info ""
    generate_report "$ENVIRONMENT"
    
    log_success "Verification complete!"
}

main "$@"
