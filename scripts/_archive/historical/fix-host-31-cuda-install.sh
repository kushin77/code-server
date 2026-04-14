#!/bin/bash
# Host 31 Critical Fix #2: CUDA 12.4 Toolkit Installation
# Required for Ollama GPU acceleration and deep learning workloads
# Idempotent: Safe to run multiple times

set -eo pipefail

CUDA_VERSION="12.4"
CUDA_PUBLIC_VERSION="12.4.1"
STATE_FILE="/tmp/cuda-install.lock"

echo "=========================================="
echo "HOST 31 FIX #2: CUDA 12.4 INSTALLATION"
echo "Target: CUDA $CUDA_PUBLIC_VERSION"
echo "=========================================="

# Check if CUDA already installed
INSTALLED_CUDA=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' || echo "0")
echo "Current CUDA version: $INSTALLED_CUDA"
echo "Target CUDA version: $CUDA_PUBLIC_VERSION"

# Idempotency: Skip if already at target version
if [ "$INSTALLED_CUDA" == "$CUDA_PUBLIC_VERSION" ]; then
    echo "✓ CUDA already at version $CUDA_PUBLIC_VERSION (skipping)"
    exit 0
fi

# Idempotency: Check if install already in progress
if [ -f "$STATE_FILE" ]; then
    echo "⚠ CUDA installation appears to be in progress (lock file exists)"
    echo "  If stuck, remove: rm $STATE_FILE"
    exit 1
fi

# Create lock file
touch "$STATE_FILE"

echo "Installing CUDA $CUDA_PUBLIC_VERSION toolkit..."

# Update package manager
echo "Updating package manager..."
sudo apt-get update -qq

# Download CUDA installer (runfile method for maximum compatibility)
echo "Downloading CUDA $CUDA_PUBLIC_VERSION runfile..."
cd /tmp
wget -q https://developer.download.nvidia.com/compute/cuda/12.4.1/local_installers/cuda_${CUDA_PUBLIC_VERSION}_555.42.02_linux_x86_64.run

# Make executable
chmod +x cuda_${CUDA_PUBLIC_VERSION}_555.42.02_linux_x86_64.run

# Install CUDA
echo "Installing CUDA toolkit..."
sudo bash cuda_${CUDA_PUBLIC_VERSION}_555.42.02_linux_x86_64.run \
    --silent \
    --accept-eula \
    --no-man-page \
    --no-questions \
    --toolkit

# Set up environment
echo "Configuring CUDA environment variables..."
sudo tee /etc/profile.d/cuda.sh > /dev/null <<'EOF'
export PATH=/usr/local/cuda-12.4/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH
export CUDA_HOME=/usr/local/cuda-12.4
export CUDA_PATH=/usr/local/cuda-12.4
EOF

# Source environment
source /etc/profile.d/cuda.sh

# Verify installation
sleep 2
INSTALLED_CUDA=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' || echo "0")

if [ "$INSTALLED_CUDA" == "$CUDA_PUBLIC_VERSION" ]; then
    echo "✓ CUDA successfully installed version $CUDA_PUBLIC_VERSION"
    echo "  CUDA_HOME: /usr/local/cuda-12.4"
    echo "  PATH updated for cuda binaries"
    echo "  LD_LIBRARY_PATH updated for cuda libraries"
    
    # Run verification
    echo "Running CUDA verification..."
    /usr/local/cuda-12.4/extras/demo_suite/deviceQuery || echo "⚠ deviceQuery not available"
    
    # Cleanup
    rm -f "$STATE_FILE" /tmp/cuda_${CUDA_PUBLIC_VERSION}_555.42.02_linux_x86_64.run
    
    echo "✓ CUDA 12.4 installation COMPLETE"
    exit 0
else
    echo "✗ CUDA installation verification FAILED"
    echo "  Expected: $CUDA_PUBLIC_VERSION"
    echo "  Got: $INSTALLED_CUDA"
    # Don't remove lock file - leave for investigation
    exit 1
fi
