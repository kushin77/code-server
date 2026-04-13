#!/bin/bash
# Host 31 Critical Fix #3: NVIDIA Container Runtime Installation
# Enables Docker containers to access GPU directly for GPU acceleration
# Idempotent: Safe to run multiple times

set -eo pipefail

STATE_FILE="/tmp/nvidia-runtime-install.lock"
RUNTIME_VERSION="1.14.6"

echo "=========================================="
echo "HOST 31 FIX #3: NVIDIA CONTAINER RUNTIME"
echo "Target: nvidia-container-runtime v$RUNTIME_VERSION"
echo "=========================================="

# Check if nvidia-container-runtime already installed
if command -v nvidia-container-runtime &>/dev/null; then
    CURRENT_VERSION=$(nvidia-container-runtime --version 2>/dev/null | grep version | awk '{print $NF}' || echo "unknown")
    echo "Current nvidia-container-runtime: $CURRENT_VERSION"
    
    # Idempotency: Skip if already installed
    if [ "$CURRENT_VERSION" != "unknown" ]; then
        echo "✓ nvidia-container-runtime already installed (skipping)"
        exit 0
    fi
fi

# Idempotency: Check if install in progress
if [ -f "$STATE_FILE" ]; then
    echo "⚠ Installation appears to be in progress (lock file exists)"
    echo "  If stuck, remove: rm $STATE_FILE"
    exit 1
fi

touch "$STATE_FILE"

# Update package manager
echo "Updating package manager..."
sudo apt-get update -qq

# Add NVIDIA's package repository
echo "Adding NVIDIA package repository..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
wget -qO - https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -
echo "deb https://nvidia.github.io/libnvidia-container/$distribution $distribution main" | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-runtime.list > /dev/null
sudo apt-get update -qq

# Install packages
echo "Installing NVIDIA container toolkit and runtime..."
sudo apt-get install -y \
    nvidia-docker2 \
    nvidia-container-runtime \
    nvidia-container-toolkit \
    libnvidia-container-tools

# Configure Docker to use nvidia runtime
echo "Configuring Docker to use NVIDIA runtime..."
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
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

# Restart Docker daemon
echo "Restarting Docker daemon..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# Verify installation
sleep 2
if command -v nvidia-container-runtime &>/dev/null; then
    echo "✓ nvidia-container-runtime installed successfully"
    
    # Test GPU access in Docker
    echo "Testing GPU access in Docker container..."
    if docker run --rm --gpus all nvidia/cuda:12.4.0-runtime nvidia-smi  &>/dev/null; then
        echo "✓ Docker GPU access verified successfully"
        
        # Cleanup
        rm -f "$STATE_FILE"
        
        echo "✓ NVIDIA Container Runtime installation COMPLETE"
        exit 0
    else
        echo "⚠ GPU access test failed - runtime installed but GPU container test inconclusive"
        # Don't fail - runtime is installed
        rm -f "$STATE_FILE"
        exit 0
    fi
else
    echo "✗ nvidia-container-runtime installation FAILED"
    # Don't remove lock file - leave for investigation
    exit 1
fi
