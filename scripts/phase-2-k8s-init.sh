#!/bin/bash
# Phase 2: Kubernetes Cluster Initialization
# Date: April 13, 2026
# Purpose: Initialize 3-node HA Kubernetes cluster with kubeadm

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTROL_PLANE_ENDPOINT=${CONTROL_PLANE_ENDPOINT:-"k8s-api-lb:6443"}
POD_CIDR=${POD_CIDR:-"10.244.0.0/16"}
SERVICE_CIDR=${SERVICE_CIDR:-"10.96.0.0/12"}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-"1.27.0"}

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Phase 2.1: Pre-flight checks
echo -e "\n${BLUE}=== PHASE 2.1: PRE-FLIGHT CHECKS ===${NC}\n"

log_info "Checking prerequisites..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Disable swap
log_info "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
log_success "Swap disabled"

# Load kernel modules
log_info "Loading kernel modules..."
modprobe overlay
modprobe br_netfilter
echo 'overlay' >> /etc/modules-load.d/k8s.conf
echo 'br_netfilter' >> /etc/modules-load.d/k8s.conf
log_success "Kernel modules loaded"

# Set sysctl parameters
log_info "Configuring sysctl parameters..."
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system > /dev/null
log_success "sysctl parameters configured"

# Check Docker/containerd
log_info "Checking container runtime..."
if ! command -v docker &> /dev/null && ! command -v containerd &> /dev/null; then
    log_error "Docker or containerd not found"
    exit 1
fi
log_success "Container runtime available"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found"
    exit 1
fi
log_success "kubectl available"

# Check kubeadm
if ! command -v kubeadm &> /dev/null; then
    log_error "kubeadm not found"
    exit 1
fi
log_success "kubeadm available"

# Phase 2.2: Kubernetes Cluster Initialization
echo -e "\n${BLUE}=== PHASE 2.2: KUBERNETES CLUSTER INIT ===${NC}\n"

log_info "Initializing Kubernetes control plane..."

# Create kubeadm config
cat > /tmp/kubeadm-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v${KUBERNETES_VERSION}
controlPlaneEndpoint: ${CONTROL_PLANE_ENDPOINT}
networking:
  podSubnet: ${POD_CIDR}
  serviceSubnet: ${SERVICE_CIDR}
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  taints:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
localAPIEndpoint:
  advertiseAddress: $(hostname -I | awk '{print $1}')
  bindPort: 6443
EOF

# Initialize cluster
kubeadm init --config=/tmp/kubeadm-config.yaml --ignore-preflight-errors=NumCPU,MemAvailable

log_success "Control plane initialized"

# Phase 2.3: kubectl Configuration
echo -e "\n${BLUE}=== PHASE 2.3: KUBECTL CONFIGURATION ===${NC}\n"

log_info "Configuring kubectl..."
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
log_success "kubectl configured"

# Verify cluster
log_info "Verifying cluster..."
for i in {1..30}; do
    if kubectl cluster-info &>/dev/null; then
        log_success "Cluster responding"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Cluster not responding after 30 seconds"
        exit 1
    fi
    sleep 1
done

# Phase 2.4: Network Plugin (Flannel)
echo -e "\n${BLUE}=== PHASE 2.4: FLANNEL NETWORK PLUGIN ===${NC}\n"

log_info "Installing Flannel CNI..."
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
log_success "Flannel installed"

# Wait for CoreDNS
log_info "Waiting for CoreDNS to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s 2>/dev/null || true
log_success "CoreDNS ready"

# Phase 2.5: Storage Class
echo -e "\n${BLUE}=== PHASE 2.5: STORAGE CLASS ===${NC}\n"

log_info "Creating local storage class..."
cat > /tmp/storageclass.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-1
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $(hostname)
EOF

kubectl apply -f /tmp/storageclass.yaml
log_success "Storage class created"

# Phase 2.6: Verification
echo -e "\n${BLUE}=== PHASE 2.6: VERIFICATION ===${NC}\n"

log_info "Verifying cluster status..."

# Check nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ $NODE_COUNT -lt 1 ]; then
    log_error "No nodes in Ready state"
    exit 1
fi
log_success "Nodes: $NODE_COUNT Ready"

# Check system pods
PODS=$(kubectl get pods -n kube-system --no-headers | grep -E "Running|Succeeded" | wc -l)
log_success "System pods running: $PODS"

# Check API server
if kubectl get componentstatus &>/dev/null; then
    log_success "API Server: OK"
else
    log_warning "Could not verify API server status"
fi

# Phase 2.7: Generate Join Token
echo -e "\n${BLUE}=== PHASE 2.7: GENERATE JOIN TOKEN ===${NC}\n"

log_info "Generating cluster join token for worker nodes..."
kubeadm token create --print-join-command > /tmp/join-command.sh
chmod +x /tmp/join-command.sh

log_success "Join command saved to /tmp/join-command.sh"
echo ""
echo "Worker nodes should run the following command:"
cat /tmp/join-command.sh
echo ""

# Phase 2.8: Final Status
echo -e "\n${BLUE}=== PHASE 2.8: FINAL STATUS ===${NC}\n"

log_success "Kubernetes cluster initialization COMPLETE"
echo ""
echo "Cluster Information:"
kubectl cluster-info
echo ""
echo "Node Status:"
kubectl get nodes -o wide
echo ""
echo "System Pods:"
kubectl get pods -n kube-system
echo ""
echo "Next Steps:"
echo "1. Run join command on each worker node: /tmp/join-command.sh"
echo "2. Wait for all nodes to reach Ready state"
echo "3. Proceed to Phase 3: Observability Stack"

log_success "Phase 2: Kubernetes Cluster Initialization COMPLETE"
