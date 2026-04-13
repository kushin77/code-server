#!/bin/bash
# Host 31 Critical Fix #1: GPU Driver Upgrade (470.256 → 555.x)
# Ensures Ollama GPU acceleration support and CUDA 12.4 compatibility
# Idempotent: Safe to run multiple times

set -eo pipefail

DRIVER_VERSION="555.52.04"  # Latest stable for CUDA 12.4 compatibility
STATE_FILE="/tmp/gpu-driver-upgrade.lock"

echo "=========================================="
echo "HOST 31 FIX #1: GPU DRIVER UPGRADE"
echo "Target: NVIDIA Driver $DRIVER_VERSION"
echo "=========================================="

# Check current driver version
CURRENT_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "0")
echo "Current GPU driver: $CURRENT_VERSION"
echo "Target GPU driver: $DRIVER_VERSION"

# Idempotency: Skip if already at target version
if [ "$CURRENT_VERSION" == "$DRIVER_VERSION" ]; then
    echo "✓ GPU driver already at version $DRIVER_VERSION (skipping)"
    exit 0
fi

# Idempotency: Check if upgrade already in progress
if [ -f "$STATE_FILE" ]; then
    echo "⚠ GPU driver upgrade appears to be in progress (lock file exists)"
    echo "  If stuck, remove: rm $STATE_FILE"
    exit 1
fi

# Create lock file
touch "$STATE_FILE"

# Disable GPU-based processes gracefully
echo "Disabling GPU-dependent processes..."
sudo systemctl stop ollama 2>/dev/null || true
sudo systemctl stop nccl-tests 2>/dev/null || true
docker stop ollama 2>/dev/null || true

# Update package manager
echo "Updating package manager..."
sudo apt-get update -qq

# Remove old kernel and driver headers that might conflict
echo "Cleaning old driver packages..."
sudo apt-get purge -y "*nvidia*" || true
sudo apt-get autoremove -y

# Download driver
echo "Downloading NVIDIA driver $DRIVER_VERSION..."
cd /tmp
wget -q https://us.download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run

# Make executable  
chmod +x NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run

# Install driver (non-interactive)
echo "Installing NVIDIA driver $DRIVER_VERSION..."
sudo bash NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run \
    --silent \
    --no-questions \
    --no-interactive \
    --ui=none \
    --no-window-system \
    --no-nouveau-check \
    --dkms \
    --no-questions

# Verify installation
sleep 2
INSTALLED_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)

if [ "$INSTALLED_VERSION" == "$DRIVER_VERSION" ]; then
    echo "✓ GPU driver successfully upgraded to $DRIVER_VERSION"
    
    # Restart GPU-dependent services
    echo "Restarting GPU-dependent services..."
    sudo systemctl start ollama 2>/dev/null || true
    docker start ollama 2>/dev/null || true
    
    # Cleanup
    rm -f "$STATE_FILE" /tmp/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run
    
    echo "✓ GPU driver upgrade COMPLETE"
    exit 0
else
    echo "✗ GPU driver installation verification FAILED"
    echo "  Expected: $DRIVER_VERSION"
    echo "  Got: $INSTALLED_VERSION"
    # Don't remove lock file - leave for investigation
    exit 1
fi
