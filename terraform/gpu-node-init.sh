#!/bin/bash
# GPU Node Initialization Script for Phase 22-D
# Runs on first boot of GPU worker nodes in EKS cluster
# Purpose: Install NVIDIA drivers, CUDA toolkit, container runtime support

set -e

LOG_FILE="/var/log/gpu-node-init.log"

log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
}

log_info "Starting GPU node initialization..."

# ═════════════════════════════════════════════════════════════════════════════
# 1. Update system and install dependencies
# ═════════════════════════════════════════════════════════════════════════════

log_info "Updating system packages..."
apt-get update
apt-get upgrade -y
apt-get install -y \
  build-essential \
  wget \
  curl \
  git \
  vim \
  htop \
  nvidia-driver-535

# ═════════════════════════════════════════════════════════════════════════════
# 2. Install NVIDIA Docker runtime
# ═════════════════════════════════════════════════════════════════════════════

log_info "Installing NVIDIA Docker runtime..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list

apt-get update
apt-get install -y nvidia-docker2

# Update Docker daemon config for NVIDIA support
cat > /etc/docker/daemon.json <<EOF
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "default-runtime": "runc"
}
EOF

systemctl daemon-reload
systemctl restart docker

log_info "NVIDIA Docker runtime installed"

# ═════════════════════════════════════════════════════════════════════════════
# 3. Install CUDA toolkit (for GPU-accelerated libraries)
# ═════════════════════════════════════════════════════════════════════════════

log_info "Installing CUDA 12.3 toolkit..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
rm cuda-keyring_1.1-1_all.deb

apt-get update
apt-get install -y cuda-12-3

# Set CUDA environment variables
cat >> /etc/environment <<EOF
CUDA_HOME=/usr/local/cuda
PATH=/usr/local/cuda/bin:$PATH
LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
EOF

log_info "CUDA 12.3 installed at /usr/local/cuda"

# ═════════════════════════════════════════════════════════════════════════════
# 4. Install cuDNN for deep learning (optional, for TensorFlow/PyTorch)
# ═════════════════════════════════════════════════════════════════════════════

log_info "Installing cuDNN 8.9..."
apt-get install -y libcudnn8 libcudnn8-dev

# ═════════════════════════════════════════════════════════════════════════════
# 5. Configure containerd for GPU support (Kubernetes alternative to Docker)
# ═════════════════════════════════════════════════════════════════════════════

log_info "Configuring containerd for GPU support..."
cat > /etc/containerd/config.toml <<EOF
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      default_runtime_name = "runc"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
          runtime_engine = ""
          runtime_root = ""
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
            BinaryName = "/usr/bin/nvidia-container-runtime"
EOF

systemctl restart containerd

# ═════════════════════════════════════════════════════════════════════════════
# 6. Join Kubernetes cluster (handled by EKS, but verify kubelet)
# ═════════════════════════════════════════════════════════════════════════════

log_info "Verifying Kubernetes kubelet..."
systemctl enable kubelet
systemctl start kubelet
systemctl status kubelet

# ═════════════════════════════════════════════════════════════════════════════
# 7. Verify GPU detection
# ═════════════════════════════════════════════════════════════════════════════

log_info "Verifying NVIDIA GPU detection..."
nvidia-smi --query-gpu=index,name,driver_version,compute_cap --format=csv,noheader | tee -a "$LOG_FILE"

GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
log_info "Detected $GPU_COUNT GPU(s) on this node"

# ═════════════════════════════════════════════════════════════════════════════
# 8. Install GPU monitoring tools
# ═════════════════════════════════════════════════════════════════════════════

log_info "Installing GPU monitoring tools..."

# NVIDIA DCGM for metrics collection
apt-get install -y datacenter-gpu-manager

# Start DCGM service
systemctl enable nvidia-dcgm
systemctl start nvidia-dcgm

log_info "GPU monitoring tools installed"

# ═════════════════════════════════════════════════════════════════════════════
# 9. Configure persistent GPU state
# ═════════════════════════════════════════════════════════════════════════════

log_info "Configuring persistent GPU state..."

# Set GPU persistence mode (prevents GPU timeout)
nvidia-smi -pm 1

# Set GPU clock speeds to max performance (optional)
# nvidia-smi -lgc 1500  # Lock GPU graphics clock

# ═════════════════════════════════════════════════════════════════════════════
# 10. Save configuration and mark initialization complete
# ═════════════════════════════════════════════════════════════════════════════

log_info "=== GPU Node Initialization Complete ==="
log_info "GPU Node ready for Kubernetes GPU workloads"
nvidia-smi 2>&1 | tee -a "$LOG_FILE"

# Mark completion
touch /var/run/gpu-node-init-complete

echo "GPU Node Init complete at $(date)" > /var/log/gpu-node-init-complete.log
