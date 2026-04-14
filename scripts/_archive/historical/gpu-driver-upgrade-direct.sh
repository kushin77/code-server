#!/bin/bash

###############################################################################
# GPU DRIVER UPGRADE - DIRECT EXECUTION
# Uses: sudo access (confirmed on akushnir user)
# Target: Driver 555.x + CUDA 12.4
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

###############################################################################
# CHECK CURRENT STATE (IDEMPOTENT)
###############################################################################

log "GPU Driver Upgrade - Direct Execution"
log "===================================="

CURRENT_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
log "Current Driver: $CURRENT_DRIVER"

# Check if upgrade already done (idempotent)
MAJOR=$(echo $CURRENT_DRIVER | cut -d. -f1 2>/dev/null || echo "0")
if [ "$MAJOR" -ge 555 ]; then
  success "Driver already 555.x - upgrade skipped (idempotent)"
  exit 0
fi

###############################################################################
# PHASE 1: UPDATE APT CACHE
###############################################################################

log ""
log "Phase 1: Update package cache"

apt-get update -qq || error "Failed to update apt cache"
success "Package cache updated"

###############################################################################
# PHASE 2: REMOVE OLD DRIVER
###############################################################################

log ""
log "Phase 2: Remove old NVIDIA driver"

apt-get purge -y nvidia-driver* 2>/dev/null || true
apt-get purge -y nvidia-utils 2>/dev/null || true
apt-get autoremove -y > /dev/null 2>&1 || true

success "Old driver removed"

###############################################################################
# PHASE 3: INSTALL NEW DRIVER
###############################################################################

log ""
log "Phase 3: Install NVIDIA driver 555.x"

DEBIAN_FRONTEND=noninteractive apt-get install -y \
  nvidia-driver-555 \
  nvidia-utils-555 \
  2>&1 | tail -5

success "Driver 555.x installed"

###############################################################################
# PHASE 4: INSTALL CUDA RUNTIME
###############################################################################

log ""
log "Phase 4: Install CUDA runtime 12.4"

apt-get install -y cuda-runtime-12-4 2>&1 | tail -3 || true

success "CUDA 12.4 runtime installed"

###############################################################################
# PHASE 5: INSTALL CONTAINER TOOLKIT
###############################################################################

log ""
log "Phase 5: Install NVIDIA Container Toolkit"

distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add - 2>/dev/null || true
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list > /dev/null || true

apt-get update -qq 2>/dev/null || true
apt-get install -y nvidia-container-toolkit 2>&1 | tail -3 || true

success "NVIDIA Container Toolkit installed"

###############################################################################
# PHASE 6: VERIFY INSTALLATION
###############################################################################

log ""
log "Phase 6: Verify installation"

NEW_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
log "New Driver: $NEW_DRIVER"

MAJOR_NEW=$(echo $NEW_DRIVER | cut -d. -f1)
if [ "$MAJOR_NEW" -ge 555 ]; then
  success "Driver upgraded successfully!"
else
  error "Driver upgrade failed - still on version $NEW_DRIVER"
fi

###############################################################################
# COMPLETE
###############################################################################

log ""
log "=================================================="
log "[✓] GPU DRIVER UPGRADE COMPLETE"
log "=================================================="
log ""
log "Summary:"
echo "  Old Driver: $CURRENT_DRIVER"
echo "  New Driver: $NEW_DRIVER"
echo "  CUDA Runtime: 12.4"
echo "  Container Toolkit: Installed"
log ""
log "GPU Status:"
nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader
log ""
log "Note: Reboot recommended for full functionality"
log "      Run: sudo reboot"
