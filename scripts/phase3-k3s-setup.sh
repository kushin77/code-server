#!/bin/bash
# Phase 3 Issue #164 - k3s Kubernetes Cluster Setup
# Deploy lightweight Kubernetes with GPU support, storage, load balancing, network policies

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
K3S_VERSION=${K3S_VERSION:-"v1.28.5"}
K3S_URL="https://get.k3s.io"
KUBECONFIG_MODE=644
DATA_DIR="/var/lib/rancher/k3s"
STORAGE_DIR="/mnt/k3s-storage"
NFS_SERVER="${NFS_SERVER:-192.168.168.56}"
NFS_PATH="${NFS_PATH:-/mnt/nas}"
HOSTNAME=$(hostname)

print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# ============================================================================
# System Checks
# ============================================================================

check_system_requirements() {
    print_header "System Requirements Check"
    
    print_step "Checking system capabilities..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        return 1
    fi
    print_success "Running as root"
    
    # Check kernel
    kernel_version=$(uname -r)
    print_success "Kernel: $kernel_version"
    
    # Check CPU cores
    cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        print_error "Minimum 2 CPU cores required, found: $cpu_cores"
        return 1
    fi
    print_success "CPU cores: $cpu_cores"
    
    # Check memory
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_gb=$((mem_kb / 1024 / 1024))
    if [ "$mem_gb" -lt 4 ]; then
        print_error "Minimum 4GB RAM required, found: ${mem_gb}GB"
        return 1
    fi
    print_success "Memory: ${mem_gb}GB"
    
    # Check GPU (optional)
    if command -v nvidia-smi &> /dev/null; then
        gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
        print_success "GPU detected: $gpu_count GPU(s)"
    else
        print_step "GPU not detected (optional)"
    fi
    
    # Check cgroup v1 or v2
    if [ -d "/sys/fs/cgroup/cgroup.controllers" ]; then
        print_success "Using cgroup v2"
    else
        print_success "Using cgroup v1"
    fi
    
    # Check Docker (if installed)
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_success "Docker: $docker_version (will be used by k3s containerd)"
    fi
    
    return 0
}

# ============================================================================
# Dependency Installation
# ============================================================================

install_dependencies() {
    print_header "Installing Dependencies"
    
    print_step "Updating package manager..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq \
            curl \
            wget \
            git \
            jq \
            nfs-common \
            cifs-utils \
            apparmor \
            apparmor-utils \
            selinux-utils \
            ebtables \
            ethtool
        print_success "Debian/Ubuntu dependencies installed"
    elif command -v yum &> /dev/null; then
        yum install -y -q \
            curl \
            wget \
            git \
            jq \
            nfs-utils \
            selinux-policy
        print_success "RedHat/CentOS dependencies installed"
    else
        print_error "Unsupported package manager"
        return 1
    fi
    
    # Install kubectl
    if ! command -v kubectl &> /dev/null; then
        print_step "Installing kubectl..."
        curl -L "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
        chmod +x /usr/local/bin/kubectl
        print_success "kubectl installed"
    fi
    
    return 0
}

# ============================================================================
# Storage Setup
# ============================================================================

setup_storage() {
    print_header "Setting Up Storage"
    
    # Create local storage directory
    print_step "Creating local storage directory..."
    mkdir -p "$STORAGE_DIR"
    chmod 755 "$STORAGE_DIR"
    print_success "Local storage directory: $STORAGE_DIR"
    
    # Mount NFS if not already mounted
    if ! mountpoint -q /mnt/nfs-cluster; then
        print_step "Mounting NFS storage from $NFS_SERVER..."
        mkdir -p /mnt/nfs-cluster
        
        if mount -t nfs "$NFS_SERVER:$NFS_PATH" /mnt/nfs-cluster; then
            print_success "NFS mounted: /mnt/nfs-cluster"
            
            # Add to fstab for persistent mount
            if ! grep -q "/mnt/nfs-cluster" /etc/fstab; then
                echo "$NFS_SERVER:$NFS_PATH /mnt/nfs-cluster nfs defaults,hard,intr 0 0" >> /etc/fstab
            fi
        else
            print_error "Failed to mount NFS"
            return 1
        fi
    else
        print_success "NFS already mounted: /mnt/nfs-cluster"
    fi
    
    # Create k3s data directory
    mkdir -p "$DATA_DIR"
    print_success "k3s data directory: $DATA_DIR"
    
    return 0
}

# ============================================================================
# k3s Installation
# ============================================================================

install_k3s() {
    print_header "Installing k3s Kubernetes"
    
    print_step "Downloading and installing k3s $K3S_VERSION..."
    
    export K3S_VERSION="$K3S_VERSION"
    export K3S_KUBECONFIG_MODE="$KUBECONFIG_MODE"
    export K3S_DATA_DIR="$DATA_DIR"
    export INSTALL_K3S_SKIP_DOWNLOAD=false
    
    # Install k3s with containerd
    if curl -sfL "$K3S_URL" | sh - ; then
        print_success "k3s installed successfully"
    else
        print_error "k3s installation failed"
        return 1
    fi
    
    # Wait for k3s to be ready
    print_step "Waiting for k3s to be ready..."
    sleep 10
    
    # Set up kubectl
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    chmod 644 /etc/rancher/k3s/k3s.yaml
    
    # Wait for API server to be responding
    local max_attempts=60
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if kubectl version &>/dev/null; then
            print_success "k3s API server is responding"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 1
    done
    
    print_error "k3s API server did not become ready"
    return 1
}

# ============================================================================
# GPU Scheduling Setup
# ============================================================================

setup_gpu_scheduling() {
    print_header "Configuring GPU Scheduling"
    
    if ! command -v nvidia-smi &> /dev/null; then
        print_step "GPU not detected, skipping GPU setup"
        return 0
    fi
    
    print_step "Setting up NVIDIA GPU support..."
    
    # Check if NVIDIA GPU operator is needed or if device plugins are sufficient
    # For single node, we can use nvidia-device-plugin directly
    
    # Label the node as having GPU
    if kubectl label nodes "$HOSTNAME" nvidia.com/gpu=true --overwrite; then
        print_success "Node labeled for GPU scheduling"
    else
        print_error "Failed to label node for GPU"
        return 1
    fi
    
    # Note: NVIDIA device plugin is typically deployed as a DaemonSet
    # This will be done in the deployment script
    
    return 0
}

# ============================================================================
# Network Policy Setup
# ============================================================================

setup_network_policies() {
    print_header "Configuring Network Policies"
    
    print_step "k3s uses Flannel by default with network policies support"
    
    # Verify Flannel is running
    if kubectl get daemonset -n kube-flannel flannel &>/dev/null; then
        print_success "Flannel CNI is running"
    else
        print_error "Flannel CNI not found"
        return 1
    fi
    
    # Note: Specific network policies will be applied in deployment script
    
    return 0
}

# ============================================================================
# Cleanup and Status
# ============================================================================

cleanup_old_installation() {
    print_step "Checking for existing k3s installation..."
    
    if systemctl is-active --quiet k3s; then
        print_step "k3s is already running"
        return 0
    fi
    
    return 0
}

print_status() {
    print_header "k3s Installation Status"
    
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    
    print_step "Cluster Info:"
    kubectl cluster-info
    
    print_step "Nodes:"
    kubectl get nodes -o wide
    
    print_step "System Pods:"
    kubectl get pods -n kube-system -o wide
    
    print_step "Storage Classes:"
    kubectl get storageclass
    
    print_success "k3s setup complete!"
    
    return 0
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo ""
    echo "Phase 3 Issue #164: k3s Kubernetes Cluster Setup"
    echo "Started: $(date)"
    echo ""
    
    # Execute setup steps
    if ! check_system_requirements; then
        print_error "System requirements check failed"
        return 1
    fi
    
    if ! install_dependencies; then
        print_error "Dependency installation failed"
        return 1
    fi
    
    if ! setup_storage; then
        print_error "Storage setup failed"
        return 1
    fi
    
    if ! install_k3s; then
        print_error "k3s installation failed"
        return 1
    fi
    
    if ! setup_gpu_scheduling; then
        print_error "GPU scheduling setup failed"
        return 1
    fi
    
    if ! setup_network_policies; then
        print_error "Network policies setup failed"
        return 1
    fi
    
    if ! print_status; then
        print_error "Status check failed"
        return 1
    fi
    
    echo ""
    print_success "k3s Installation Complete!"
    echo "Finished: $(date)"
    echo ""
    echo "Next Steps:"
    echo "  1. Deploy storage provisioners"
    echo "  2. Configure MetalLB load balancer"
    echo "  3. Apply network policies"
    echo "  4. Deploy NVIDIA device plugin"
    echo ""
    
    return 0
}

main "$@"
exit $?
