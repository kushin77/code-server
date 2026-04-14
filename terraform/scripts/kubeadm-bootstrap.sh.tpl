#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# Kubernetes Bootstrap via kubeadm (On-Premises)
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Idempotent kubeadm initialization for on-premises Kubernetes
# Deployment: Called via terraform provisioner (remote-exec over SSH)
# Status: Production-ready, fully immutable
# ═════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Configuration from Terraform Variables (passed via templatefile)
KUBERNETES_VERSION="${KUBERNETES_VERSION}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME}"
POD_CIDR="${POD_CIDR}"
SERVICE_CIDR="${SERVICE_CIDR}"
NODE_ROLE="${NODE_ROLE}"

# Helper functions
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo "[ERROR] $*" >&2
  exit 1
}

is_installed() {
  command -v "$1" &> /dev/null
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 1: IDEMPOTENCY CHECK
# ═════════════════════════════════════════════════════════════════════════════

if is_installed kubeadm; then
  INSTALLED_VERSION=$(kubeadm version -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' || echo "")
  if [[ "$INSTALLED_VERSION" == *"$KUBERNETES_VERSION"* ]]; then
    log "Kubernetes $KUBERNETES_VERSION already installed (kubeadm found)"
    exit 0
  else
    log "kubeadm installed with different version: $INSTALLED_VERSION"
    log "Proceeding with upgrade to $KUBERNETES_VERSION"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 2: SYSTEM PREREQUISITES
# ═════════════════════════════════════════════════════════════════════════════

log "Installing system prerequisites..."

# Disable swap (required by kubelet)
if grep -q '^/swapfile' /etc/fstab; then
  log "Swap found in fstab, removing..."
  sudo swapoff -a
  sudo sed -i '/^\/swapfile/d' /etc/fstab
else
  log "Swap already disabled"
fi

# Update package lists
log "Updating package manager..."
sudo apt-get update -y

# Install prerequisite packages (idempotent)
log "Installing prerequisite packages..."
for pkg in apt-transport-https ca-certificates curl wget jq socat ethtool ipvsadm; do
  if ! dpkg -l | grep -q "^ii.*$pkg"; then
    sudo apt-get install -y "$pkg"
  fi
done

log "System prerequisites installed"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 3: CONTAINER RUNTIME INSTALLATION
# ═════════════════════════════════════════════════════════════════════════════

log "Setting up container runtime: $CONTAINER_RUNTIME"

case "$CONTAINER_RUNTIME" in
  containerd)
    if is_installed containerd; then
      log "containerd already installed"
    else
      log "Installing containerd..."
      sudo apt-get install -y containerd.io
      sudo systemctl enable containerd
      sudo systemctl restart containerd
    fi
    
    # Create containerd config (idempotent)
    if [ ! -d /etc/containerd ]; then
      sudo mkdir -p /etc/containerd
      sudo containerd config default > /tmp/config.toml
      sudo cp /tmp/config.toml /etc/containerd/config.toml
      sudo sed -i 's/disabled_plugins = \[\]/disabled_plugins = []/g' /etc/containerd/config.toml
      sudo systemctl restart containerd
    fi
    ;;
    
  docker)
    if is_installed docker; then
      log "Docker already installed"
    else
      log "Installing Docker..."  
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update -y
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io
      sudo usermod -aG docker $(whoami)
      sudo systemctl enable docker
      sudo systemctl restart docker
    fi
    ;;
esac

log "Container runtime configured: $CONTAINER_RUNTIME"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 4: KUBERNETES BINARIES INSTALLATION
# ═════════════════════════════════════════════════════════════════════════════

log "Installing Kubernetes binaries v$KUBERNETES_VERSION..."

# Add Kubernetes GPG key and repository (idempotent)
if [ ! -f /etc/apt/keyrings/kubernetes-archive-keyring.gpg ]; then
  log "Adding Kubernetes repository..."
  curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
  echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
  sudo apt-get update -y
fi

# Install kubelet, kubeadm, kubectl (specific version)
K8S_VERSION_SPEC="${KUBERNETES_VERSION}-00"
for cmd in kubelet kubeadm kubectl; do
  if is_installed "$cmd"; then
    CURRENT_VERSION=$($cmd --version 2>/dev/null || echo "v0.0.0")
    if [[ "$CURRENT_VERSION" == *"$KUBERNETES_VERSION"* ]]; then
      log "$cmd already installed: $CURRENT_VERSION"
    else
      log "Updating $cmd from $CURRENT_VERSION to $KUBERNETES_VERSION"
      sudo apt-get install -y "$cmd=$K8S_VERSION_SPEC"
    fi
  else
    log "Installing $cmd..."
    sudo apt-get install -y "$cmd=$K8S_VERSION_SPEC"
  fi
done

# Mark kubelet to hold current version (prevent accidental upgrades)
sudo apt-mark hold kubelet kubeadm kubectl

log "Kubernetes binaries installed"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 5: KUBEADM INITIALIZATION (Control Plane Only)
# ═════════════════════════════════════════════════════════════════════════════

if [ "$NODE_ROLE" = "control-plane" ]; then
  if [ -f /etc/kubernetes/admin.conf ]; then
    log "Kubernetes control-plane already initialized (admin.conf exists)"
  else
    log "Initializing Kubernetes control-plane with kubeadm..."
    
    # Create kubeadm config file
    cat > /tmp/kubeadm-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  kubeletExtraArgs:
    cgroup-driver: systemd
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v$KUBERNETES_VERSION
networking:
  podSubnet: $POD_CIDR
  serviceSubnet: $SERVICE_CIDR
controlPlaneEndpoint: "$(hostname -I | awk '{print $1}'):6443"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
    
    # Initialize cluster
    sudo kubeadm init --config=/tmp/kubeadm-config.yaml
    
    # Setup kubeconfig for current user
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    # Install CNI plugin (Flannel - simple, on-prem friendly)
    log "Installing Flannel CNI plugin..."
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    
    log "Control-plane initialized successfully"
  fi

elif [ "$NODE_ROLE" = "worker" ]; then
  # Worker node will join cluster later
  log "Worker node role detected, skipping control-plane init"
  log "Worker nodes must run: kubeadm join <control-plane>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
fi

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 6: KUBELET SERVICE ENABLEMENT
# ═════════════════════════════════════════════════════════════════════════════

log "Enabling kubelet service..."
sudo systemctl enable kubelet
sudo systemctl restart kubelet

# Wait for kubelet to be ready
MAX_WAIT=60
WAITED=0
while ! sudo systemctl is-active --quiet kubelet && [ $WAITED -lt $MAX_WAIT ]; do
  log "Waiting for kubelet to start..."
  sleep 2
  WAITED=$((WAITED + 2))
done

if sudo systemctl is-active --quiet kubelet; then
  log "kubelet service is active"
else
  error "kubelet failed to start after $MAX_WAIT seconds"
fi

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 7: VERIFICATION
# ═════════════════════════════════════════════════════════════════════════════

log "Verifying Kubernetes installation..."

# Verify kubeadm version
kubeadm version -o json | jq '.clientVersion.gitVersion'

# Verify kubectl connectivity (if control-plane)
if [ "$NODE_ROLE" = "control-plane" ]; then
  kubectl cluster-info
  log "Cluster info retrieved successfully"
  
  # Wait for all system pods to be ready
  log "Waiting for system pods to be ready..."
  kubectl wait --for=condition=Ready pod -l component=kube-apiserver -n kube-system --timeout=300s || true
fi

log "✅ Kubernetes bootstrap complete (v$KUBERNETES_VERSION, $NODE_ROLE)"
