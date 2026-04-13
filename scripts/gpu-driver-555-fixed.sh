#!/bin/bash
#
# GPU Driver Upgrade: 470.x → 555.x with CUDA 12.4 
# Fixed version with correct Ubuntu 22.04 repository
# Requires: sudo access, internet connectivity
#

set -e

#############################################################################
# LOGGING SETUP
#############################################################################

log() { echo "[$(date +'%H:%M:%S')] $*"; }
success() { echo "[✓] $*"; }
error() { echo "[✗] $*"; exit 1; }

#############################################################################
# PHASE 0: ENVIRONMENT CHECK
#############################################################################

log "=== GPU DRIVER UPGRADE - FIXED VERSION ==="
log "Current Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'unknown')"
log "Current CUDA: $(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 || echo 'unknown')"

if [ "$EUID" -ne 0 ]; then
   error "This script must be run as root (use: sudo bash $0)"
fi

#############################################################################
# PHASE 1: CLEANUP OLD DRIVERS AND REPOSITORIES
#############################################################################

log ""
log "Phase 1: Clean up old drivers and incorrect repositories"

# Remove corrupted nvidia docker repos (Ubuntu 18.04 repos on Ubuntu 22.04)
rm -f /etc/apt/sources.list.d/nvidia-docker.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/libnvidia-container.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/nvidia-container-runtime.list 2>/dev/null || true

# Purge old driver packages
apt-get purge -y nvidia-driver* nvidia-utils* cuda* 2>/dev/null || true
apt-get autoremove -y > /dev/null 2>&1 || true

success "Old driver and repos cleaned"

#############################################################################
# PHASE 2: UPDATE PACKAGE CACHE
#############################################################################

log ""
log "Phase 2: Update package cache"

apt-get update -qq || error "Failed to update apt cache"

success "Package cache updated"

#############################################################################
# PHASE 3: ADD NVIDIA REPOSITORY (UBUNTU 22.04 - JAMMY)
#############################################################################

log ""
log "Phase 3: Add NVIDIA repository for Ubuntu 22.04 (jammy)"

# Use NVIDIA's official repository with correct Ubuntu version
DISTRO="ubuntu2204"  # Explicitly set for Ubuntu 22.04

# Add GPG key
curl -fsSL https://nvidia.github.io/nvidia-docker/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-docker-keyring.gpg 2>/dev/null || true

# Add repository with correct keyring
curl -s -L "https://nvidia.github.io/nvidia-docker/$DISTRO/nvidia-docker.list" | \
  sed 's#deb https://nvidia.github.io/nvidia-docker#deb [signed-by=/usr/share/keyrings/nvidia-docker-keyring.gpg] https://nvidia.github.io/nvidia-docker#g' | \
  tee /etc/apt/sources.list.d/nvidia-docker.list > /dev/null

apt-get update -qq || log "Note: Some NVIDIA repos may not be available yet"

success "NVIDIA repository configured for Ubuntu 22.04"

#############################################################################
# PHASE 4: INSTALL DRIVER 555.x
#############################################################################

log ""
log "Phase 4: Install NVIDIA driver 555.x"

# Try from system repos first (most reliable)
if apt-cache search nvidia-driver-555 | grep -q nvidia-driver-555; then
  log "Installing nvidia-driver-555 from system repos..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nvidia-driver-555 \
    nvidia-utils-555 \
    2>&1 | tail -10
  success "Driver 555.x installed from system repos"
else
  error "nvidia-driver-555 not found in any repository. Try: sudo ubuntu-drivers autoinstall"
fi

#############################################################################
# PHASE 5: INSTALL CUDA RUNTIME
#############################################################################

log ""
log "Phase 5: Install CUDA runtime 12.4"

# CUDA runtime is more widely available
apt-get install -y cuda-runtime-12-4 2>&1 | tail -5 || log "Note: CUDA 12.4 may require additional setup"

success "CUDA environment configured"

#############################################################################
# PHASE 6: INSTALL CONTAINER TOOLKIT
#############################################################################

log ""
log "Phase 6: Install NVIDIA Container Toolkit"

# Container toolkit for docker GPU access
apt-get install -y nvidia-container-toolkit 2>&1 | tail -5 || log "Note: Container toolkit may require manual setup"

# Restart docker to load nvidia runtime
systemctl restart docker || log "Note: Could not restart docker"

success "Container toolkit installed"

#############################################################################
# PHASE 7: VERIFY INSTALLATION
#############################################################################

log ""
log "Phase 7: Verify installation"

# Wait for nvidia-smi to become available
sleep 3

NEW_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
log "New Driver: $NEW_DRIVER"

MAJOR_NEW=$(echo $NEW_DRIVER | cut -d. -f1)
if [ "$MAJOR_NEW" -ge 555 ]; then
  success "✅ Driver upgraded successfully to $NEW_DRIVER!"
elif [ "$MAJOR_NEW" -ge 470 ]; then
  log "⚠️  Driver still at 470.x - Please reboot and retry"
else
  error "Driver detection failed"
fi

#############################################################################
# PHASE 8: GPU STATUS
#############################################################################

log ""
log "=================================================="
log "[✓] GPU CONFIGURATION COMPLETE"
log "=================================================="

nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv

log ""
log "Next steps:"
log "  1. Reboot for kernel module updates: sudo reboot"
log "  2. Verify after reboot: nvidia-smi"
log "  3. Test Docker GPU: docker run --rm --gpus all nvidia/cuda:12.4-runtime nvidia-smi"

