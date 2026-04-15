#!/bin/bash
# Phase 3 Issue #164 - k3s Kubernetes Deployment Automation
# Production deployment script for Phase 3 k3s cluster

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_LOG="${PROJECT_ROOT}/deployment-phase3-#164.log"
KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# ============================================================================
# Prerequisites Validation
# ============================================================================

validate_prerequisites() {
    print_header "Phase 3 #164: k3s Cluster - Deployment Prerequisites"
    
    print_step "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        return 1
    fi
    print_success "Running as root"
    
    # Check if k3s setup script exists
    if [ ! -f "$SCRIPT_DIR/phase3-k3s-setup.sh" ]; then
        print_error "phase3-k3s-setup.sh not found"
        return 1
    fi
    print_success "Setup script found"
    
    # Check if kubernetes manifests exist
    if [ ! -f "$PROJECT_ROOT/kubernetes/storage-classes.yaml" ]; then
        print_error "kubernetes manifests not found"
        return 1
    fi
    print_success "Kubernetes manifests found"
    
    # Check connectivity
    if ! ping -c 1 192.168.168.56 &> /dev/null; then
        print_error "Cannot reach NFS server (192.168.168.56)"
        return 1
    fi
    print_success "NFS server reachable"
    
    return 0
}

# ============================================================================
# k3s Installation
# ============================================================================

install_k3s() {
    print_header "Step 1: Install k3s Kubernetes"
    
    print_step "Running k3s setup script..."
    
    if bash "$SCRIPT_DIR/phase3-k3s-setup.sh" 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "k3s installed successfully"
        sleep 10  # Wait for k3s to fully initialize
        return 0
    else
        print_error "k3s installation failed"
        return 1
    fi
}

# ============================================================================
# Verify k3s Cluster
# ============================================================================

verify_cluster() {
    print_header "Step 2: Verify k3s Cluster"
    
    export KUBECONFIG="$KUBECONFIG"
    
    print_step "Waiting for cluster to be ready..."
    
    # Wait for nodes to be ready
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        node_status=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)
        
        if [ "$node_status" = "Ready" ]; then
            print_success "Cluster node is ready"
            break
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 1
    done
    
    if [ $attempt -ge $max_attempts ]; then
        print_error "Cluster did not become ready within timeout"
        return 1
    fi
    
    # Get cluster info
    print_step "Cluster Status:"
    kubectl cluster-info | sed 's/^/  /'
    
    print_step "Nodes:"
    kubectl get nodes -o wide | sed 's/^/  /'
    
    print_success "Cluster verification complete"
    return 0
}

# ============================================================================
# Deploy Storage Providers
# ============================================================================

deploy_storage() {
    print_header "Step 3: Deploy Storage Providers"
    
    export KUBECONFIG="$KUBECONFIG"
    
    print_step "Applying storage class configurations..."
    
    if kubectl apply -f "$PROJECT_ROOT/kubernetes/storage-classes.yaml" 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "Storage providers deployed"
    else
        print_error "Failed to deploy storage providers"
        return 1
    fi
    
    # Wait for storage to be ready
    print_step "Waiting for storage providers to be ready..."
    sleep 10
    
    print_step "Storage Classes:"
    kubectl get storageclass | sed 's/^/  /'
    
    return 0
}

# ============================================================================
# Deploy Network Policies
# ============================================================================

deploy_network_policies() {
    print_header "Step 4: Deploy Network Policies"
    
    export KUBECONFIG="$KUBECONFIG"
    
    print_step "Applying network policy configurations..."
    
    if kubectl apply -f "$PROJECT_ROOT/kubernetes/network-policies.yaml" 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "Network policies deployed"
    else
        print_error "Failed to deploy network policies"
        return 1
    fi
    
    print_step "Network Policies:"
    kubectl get networkpolicies -A | sed 's/^/  /'
    
    return 0
}

# ============================================================================
# Deploy MetalLB Load Balancer
# ============================================================================

deploy_metallb() {
    print_header "Step 5: Deploy MetalLB Load Balancer"
    
    export KUBECONFIG="$KUBECONFIG"
    
    print_step "Installing MetalLB..."
    
    # Create namespace
    kubectl create namespace metallb-system 2>/dev/null || true
    
    # Add Helm repo
    if ! helm repo list | grep -q metallb.universe.tf; then
        helm repo add metallb https://metallb.universe.tf
    fi
    
    # Install/upgrade MetalLB
    print_step "Deploying MetalLB via Helm..."
    
    if helm upgrade --install metallb metallb/metallb \
        --namespace metallb-system \
        --set controller.enabled=true \
        --set speaker.enabled=true \
        --wait 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "MetalLB deployed"
    else
        print_error "Failed to deploy MetalLB (non-fatal, continuing)"
    fi
    
    # Apply MetalLB configuration
    print_step "Applying MetalLB configuration..."
    if kubectl apply -f "$PROJECT_ROOT/kubernetes/metallb-config.yaml" 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "MetalLB configuration applied"
    else
        print_error "Failed to apply MetalLB config (non-fatal)"
    fi
    
    return 0
}

# ============================================================================
# Deploy GPU Support
# ============================================================================

deploy_gpu_support() {
    print_header "Step 6: Deploy GPU Support"
    
    export KUBECONFIG="$KUBECONFIG"
    
    # Check if GPU exists
    if ! command -v nvidia-smi &> /dev/null; then
        print_step "No GPU detected, skipping GPU support"
        return 0
    fi
    
    print_step "Deploying NVIDIA GPU support..."
    
    # Install NVIDIA device plugin
    if kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "NVIDIA device plugin deployed"
    else
        print_error "Failed to deploy NVIDIA device plugin"
        return 1
    fi
    
    # Wait for device plugin to be ready
    print_step "Waiting for GPU device plugin to be ready..."
    sleep 10
    
    # Verify GPU is visible
    print_step "GPU Status:"
    kubectl describe node | grep -A 5 "allocatable" | sed 's/^/  /'
    
    return 0
}

# ============================================================================
# Run Tests
# ============================================================================

run_tests() {
    print_header "Step 7: Run Validation Tests"
    
    export KUBECONFIG="$KUBECONFIG"
    
    print_step "Running k3s validation tests..."
    
    local test_script="$SCRIPT_DIR/phase3-k3s-test.sh"
    
    if [ ! -f "$test_script" ]; then
        print_error "Test script not found"
        return 1
    fi
    
    if bash "$test_script" 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "All validation tests passed"
        return 0
    else
        print_error "Some validation tests failed"
        return 1
    fi
}

# ============================================================================
# Summary
# ============================================================================

generate_summary() {
    print_header "Phase 3 Issue #164: k3s Cluster Deployment Summary"
    
    export KUBECONFIG="$KUBECONFIG"
    
    print_success "k3s Kubernetes Cluster deployed successfully!"
    echo ""
    
    print_step "Cluster Details:"
    echo "  Kubeconfig: $KUBECONFIG"
    echo "  Version: $(kubectl version --short 2>/dev/null | head -1 || echo 'Unknown')"
    echo "  Nodes: $(kubectl get nodes --no-headers | wc -l)"
    echo ""
    
    print_step "Next Steps:"
    echo "  1. Deploy Harbor Registry (#165)"
    echo "  2. Deploy HashiCorp Vault (#166)"
    echo "  3. Deploy ArgoCD (#168)"
    echo "  4. Deploy Dagger CI/CD (#169)"
    echo ""
    
    print_step "Troubleshooting:"
    echo "  Check cluster health: kubectl get nodes"
    echo "  View system pods: kubectl get pods -n kube-system"
    echo "  View logs: journalctl -u k3s -f"
    echo ""
    
    print_step "Deployment Log:"
    echo "  $DEPLOY_LOG"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    local exit_code=0
    
    echo "k3s Kubernetes Deployment - Phase 3 Issue #164"
    echo "Started: $(date)"
    echo "Log: $DEPLOY_LOG"
    echo ""
    
    {
        # Step 0: Validate prerequisites
        if ! validate_prerequisites; then
            print_error "Prerequisites validation failed"
            exit 1
        fi
        
        # Step 1: Install k3s
        if ! install_k3s; then
            exit_code=1
            print_error "k3s installation failed"
            exit $exit_code
        fi
        
        # Step 2: Verify cluster
        if ! verify_cluster; then
            exit_code=1
            print_error "Cluster verification failed"
            exit $exit_code
        fi
        
        # Step 3: Deploy storage
        if ! deploy_storage; then
            exit_code=1
            print_error "Storage deployment failed"
            exit $exit_code
        fi
        
        # Step 4: Deploy network policies
        if ! deploy_network_policies; then
            print_error "Network policy deployment failed (non-fatal)"
        fi
        
        # Step 5: Deploy MetalLB
        if ! deploy_metallb; then
            print_error "MetalLB deployment failed (non-fatal)"
        fi
        
        # Step 6: Deploy GPU support
        if ! deploy_gpu_support; then
            print_error "GPU support deployment failed"
        fi
        
        # Step 7: Run tests
        if ! run_tests; then
            print_error "Validation tests failed (non-fatal)"
        fi
        
        # Generate summary
        generate_summary
        
    } | tee -a "$DEPLOY_LOG"
    
    echo ""
    echo "Deployment finished: $(date)"
    
    if [ $exit_code -eq 0 ]; then
        print_success "Deployment completed successfully!"
    else
        print_error "Deployment completed with errors"
    fi
    
    return $exit_code
}

# Execute main
main "$@"
exit $?
