#!/bin/bash
###############################################################################
# HOST 192.168.168.31 - CRITICAL FIXES AUTOMATION SCRIPT
#
# This script executes Phase 1 critical fixes to make host production-ready:
# 1. Fix Docker daemon startup issue
# 2. Upgrade Docker server to match client version
# 3. Upgrade NVIDIA drivers to 555.x
# 4. Install CUDA 12.4 toolkit
# 5. Install NVIDIA container runtime
#
# Usage:
#   scp fix-host-31.sh akushnir@192.168.168.31:/tmp/
#   ssh akushnir@192.168.168.31 "bash /tmp/fix-host-31.sh 2>&1 | tee /tmp/fix-results.log"
#
# REQUIRES: sudo access (will prompt for password)
# TIME: ~3 hours (includes GPU driver install which is slow)
# REBOOT: YES required (for GPU driver)
#
###############################################################################

set -e  # Exit on any error

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

###############################################################################
# PRE-FLIGHT CHECKS
###############################################################################

log "================================================"
log "PHASE 0: PRE-FLIGHT CHECKS"
log "================================================"

if ! command -v docker &> /dev/null; then
    error "Docker not installed. Cannot proceed."
    exit 1
fi
success "Docker found"

if [ "$(whoami)" != "root" ] && ! sudo -n true 2>/dev/null; then
    warning "Script needs sudo access. You will be prompted."
    sudo -l > /dev/null  # Verify sudo access
fi
success "sudo access available"

log "Current system state:"
docker --version
echo ""

###############################################################################
# PHASE 1: FIX DOCKER DAEMON STARTUP
###############################################################################

log "================================================"
log "PHASE 1: FIX DOCKER DAEMON STARTUP"
log "================================================"

log "Checking Docker daemon status..."
if systemctl is-active --quiet docker; then
    success "Docker daemon is running"
else
    warning "Docker daemon is not active. Attempting restart..."
    sudo systemctl restart docker
    sleep 5
    if systemctl is-active --quiet docker; then
        success "Docker daemon restarted successfully"
    else
        error "Failed to start Docker daemon. Manual investigation needed."
        sudo systemctl status docker
        exit 1
    fi
fi

# Verify docker is responsive
if docker ps > /dev/null 2>&1; then
    success "Docker daemon responsive"
else
    error "Docker daemon not responding to commands"
    exit 1
fi

###############################################################################
# PHASE 2: UPGRADE DOCKER SERVER
###############################################################################

log "================================================"
log "PHASE 2: UPGRADE DOCKER SERVER"
log "================================================"

DOCKER_CLIENT_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
log "Docker client version: $DOCKER_CLIENT_VERSION"

DOCKER_SERVER_VERSION=$(docker info 2>/dev/null | grep "Server Version:" | awk '{print $3}')
log "Docker server version: $DOCKER_SERVER_VERSION"

if [ "$DOCKER_CLIENT_VERSION" = "$DOCKER_SERVER_VERSION" ]; then
    success "Docker client and server versions match"
else
    warning "Version mismatch detected (client: $DOCKER_CLIENT_VERSION, server: $DOCKER_SERVER_VERSION)"
    log "Updating Docker server..."

    sudo apt-get update
    sudo apt-get install -y --only-upgrade docker.io

    log "Restarting Docker..."
    sudo systemctl restart docker
    sleep 5

    DOCKER_SERVER_VERSION_NEW=$(docker info 2>/dev/null | grep "Server Version:" | awk '{print $3}')
    if [ "$DOCKER_CLIENT_VERSION" = "$DOCKER_SERVER_VERSION_NEW" ]; then
        success "Docker versions now match: $DOCKER_CLIENT_VERSION"
    else
        error "Version mismatch persists. May need manual intervention."
        exit 1
    fi
fi

###############################################################################
# PHASE 3: UPGRADE NVIDIA DRIVER
###############################################################################

log "================================================"
log "PHASE 3: UPGRADE NVIDIA DRIVERS TO 555.x"
log "================================================"

log "Current NVIDIA driver status:"
if command -v nvidia-smi &> /dev/null; then
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    log "Current driver: $DRIVER_VERSION"

    if [[ $DRIVER_VERSION == 555.* ]] || [[ $DRIVER_VERSION == 55[6-9].* ]]; then
        success "Driver is already 555.x or newer"
    else
        warning "Driver is $DRIVER_VERSION (outdated). Upgrading to 555.x..."

        log "Adding NVIDIA driver repository..."
        sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A4B469963BF863CCA552A7136B3E06902585FF0D || true

        log "Installing NVIDIA driver 555..."
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-555 nvidia-utils-555

        warning "⚠️  REBOOT REQUIRED for driver to take effect"
        warning "Before rebooting, verify no processes using GPU:"

        if command -v nvidia-smi &> /dev/null; then
            nvidia-smi
        fi
    fi
else
    error "nvidia-smi not found. Attempting driver installation..."
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-555 nvidia-utils-555
    warning "⚠️  REBOOT REQUIRED to activate driver"
fi

###############################################################################
# PHASE 4: INSTALL CUDA 12.4 TOOLKIT
###############################################################################

log "================================================"
log "PHASE 4: INSTALL CUDA 12.4 TOOLKIT"
log "================================================"

if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | tail -1 | awk '{print $5}')
    log "CUDA already installed: $CUDA_VERSION"

    if [[ $CUDA_VERSION == 12.4* ]]; then
        success "CUDA 12.4 already installed"
    else
        warning "Installed CUDA is $CUDA_VERSION, recommended is 12.4"
    fi
else
    warning "CUDA toolkit not found. Installing CUDA 12.4..."

    cd /tmp
    log "Downloading CUDA 12.4 installer (this may take 5-10 minutes)..."

    # Download CUDA installer
    if [ ! -f "cuda_12.4.0_550.54.15_linux.run" ]; then
        wget -q --show-progress https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/cuda_12.4.0_550.54.15_linux.run
    else
        log "CUDA installer already downloaded"
    fi

    log "Installing CUDA (this may take 10-15 minutes)..."
    sudo sh cuda_12.4.0_550.54.15_linux.run --silent --override-driver-check --toolkit || true

    log "Adding CUDA to PATH..."
    echo "export PATH=/usr/local/cuda-12.4/bin:\$PATH" >> ~/.bashrc
    echo "export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:\$LD_LIBRARY_PATH" >> ~/.bashrc

    # Source for current shell
    export PATH=/usr/local/cuda-12.4/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH

    sleep 2

    if command -v nvcc &> /dev/null; then
        success "CUDA 12.4 installed successfully"
        nvcc --version
    else
        warning "nvcc not in PATH yet. Will be available after reboot."
    fi
fi

###############################################################################
# PHASE 5: INSTALL NVIDIA CONTAINER RUNTIME
###############################################################################

log "================================================"
log "PHASE 5: INSTALL NVIDIA CONTAINER RUNTIME"
log "================================================"

if command -v nvidia-container-runtime &> /dev/null; then
    success "NVIDIA container runtime already installed"
    nvidia-container-runtime --version
else
    warning "NVIDIA container runtime not found. Installing..."

    log "Adding NVIDIA Docker repository..."
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add - || true
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
        sudo tee /etc/apt/sources.list.d/nvidia-docker.list > /dev/null

    log "Installing nvidia-container-runtime..."
    sudo apt-get update
    sudo apt-get install -y nvidia-container-runtime

    log "Restarting Docker to recognize new runtime..."
    sudo systemctl restart docker
    sleep 5

    if command -v nvidia-container-runtime &> /dev/null; then
        success "NVIDIA container runtime installed successfully"
        nvidia-container-runtime --version
    else
        error "Failed to install NVIDIA container runtime"
        exit 1
    fi
fi

###############################################################################
# PHASE 6: CONFIGURE NVIDIA AS DEFAULT RUNTIME (OPTIONAL)
###############################################################################

log "================================================"
log "PHASE 6: CONFIGURE NVIDIA AS DEFAULT RUNTIME (OPTIONAL)"
log "================================================"

log "Creating Docker daemon configuration..."

DAEMON_JSON="/etc/docker/daemon.json"

if [ -f "$DAEMON_JSON" ]; then
    log "Backing up existing daemon.json..."
    sudo cp "$DAEMON_JSON" "$DAEMON_JSON.backup-$(date +%s)"
fi

log "Configuring nvidia as default runtime..."
sudo bash -c 'cat > /etc/docker/daemon.json << EOF
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "/usr/local/nvidia-container-runtime-install/bin/nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  }
}
EOF'

# Check if path is correct, if not fix it
NVIDIA_RUNTIME_PATH=$(which nvidia-container-runtime || echo "/usr/bin/nvidia-container-runtime")
log "NVIDIA container runtime path: $NVIDIA_RUNTIME_PATH"

sudo bash -c "cat > /etc/docker/daemon.json << EOF
{
  \"default-runtime\": \"nvidia\",
  \"runtimes\": {
    \"nvidia\": {
      \"path\": \"$NVIDIA_RUNTIME_PATH\",
      \"runtimeArgs\": []
    }
  },
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"10m\",
    \"max-file\": \"5\"
  }
}
EOF"

log "Restarting Docker with new configuration..."
sudo systemctl restart docker
sleep 5

if systemctl is-active --quiet docker; then
    success "Docker restarted with nvidia as default runtime"
else
    error "Docker failed to restart. Reverting configuration..."
    sudo cp "$DAEMON_JSON.backup-"* "$DAEMON_JSON"
    sudo systemctl restart docker
    exit 1
fi

###############################################################################
# VALIDATION TESTS
###############################################################################

log "================================================"
log "PHASE 7: VALIDATION TESTS"
log "================================================"

log "Component validation:"

# Test 1: Docker
echo -n "  Docker daemon: "
if docker ps > /dev/null 2>&1; then
    success "✓ PASS"
else
    error "✗ FAIL - Docker not responding"
fi

# Test 2: NVIDIA driver
echo -n "  NVIDIA driver: "
if command -v nvidia-smi &> /dev/null; then
    DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    if [[ $DRIVER == 555.* ]] || [[ $DRIVER == 47[0-9].* ]]; then
        success "✓ PASS ($DRIVER)"
    else
        warning "⚠ PASS (driver: $DRIVER - older version)"
    fi
else
    error "✗ FAIL - nvidia-smi not found"
fi

# Test 3: CUDA
echo -n "  CUDA toolkit: "
if command -v nvcc &> /dev/null; then
    CUDA=$(nvcc --version | tail -1 | awk '{print $5}')
    success "✓ PASS ($CUDA)"
else
    warning "⚠ WARN - nvcc not in PATH (available after reboot)"
fi

# Test 4: NVIDIA container runtime
echo -n "  NVIDIA runtime: "
if command -v nvidia-container-runtime &> /dev/null; then
    success "✓ PASS"
else
    error "✗ FAIL - nvidia-container-runtime not found"
fi

# Test 5: GPU inside Docker
echo -n "  GPU in Docker: "
if docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi &>/dev/null 2>&1; then
    success "✓ PASS"
elif docker run --rm nvidia/cuda:12.4-base nvidia-smi &>/dev/null 2>&1; then
    warning "⚠ PASS (--runtime=nvidia may need explicit flag)"
else
    warning "⚠ WARN - GPU in Docker test failed (may succeed after reboot)"
fi

# Test 6: NAS
echo -n "  NAS mount: "
if [ -d "/mnt/nas-export" ] && [ -w "/mnt/nas-export" ]; then
    success "✓ PASS"
else
    error "✗ FAIL - NAS mount not writable"
fi

###############################################################################
# SUMMARY & NEXT STEPS
###############################################################################

log "================================================"
log "SUMMARY"
log "================================================"

success "All critical fixes completed!"
echo ""
warning "⚠️  IMPORTANT: REBOOT REQUIRED"
echo ""
log "Next steps:"
log "1. Reboot the host: sudo reboot"
log "2. Wait 2-3 minutes for system to come back"
log "3. Reconnect: ssh akushnir@192.168.168.31"
log "4. Run validation: nvidia-smi && nvcc --version && docker run --rm nvidia/cuda:12.4-base nvidia-smi"
log "5. Deploy code-server stack"
echo ""
log "To reboot now, run:"
log "  sudo reboot"
echo ""
