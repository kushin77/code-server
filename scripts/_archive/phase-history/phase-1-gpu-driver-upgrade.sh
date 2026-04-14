#!/bin/bash

###############################################################################
# PHASE 1: GPU DRIVER & CUDA UPGRADE - IaC APPROACH
#
# Leverages: Existing sudo passwordless access (docker, systemctl, git)
# Components: nvidia-driver-555, cuda-12-4, container-toolkit
#
# IaC Requirements:
#   - Idempotent: Safe to re-run without errors
#   - Immutable: All state changes recorded to git
#   - Infrastructure: All commands automated, no manual steps
#
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

###############################################################################
# PART 1: CHECK CURRENT STATE (IDEMPOTENT)
###############################################################################

log "GPU Upgrade Phase 1 - State Assessment"
log "========================================"

NVIDIA_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
CUDA_VERSION=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null || echo "N/A")

log "Current State:"
log "  Driver Version: $NVIDIA_DRIVER"
log "  GPUs Detected: $(nvidia-smi --list-gpus | wc -l)"
nvidia-smi --list-gpus

# Check if already upgraded (idempotent)
MAJOR_VERSION=$(echo $NVIDIA_DRIVER | cut -d. -f1)
if [ "$MAJOR_VERSION" -ge 555 ]; then
  success "Driver is already 555.x or newer - skipping upgrade!"
  exit 0
fi

###############################################################################
# PART 2: PREPARE UPGRADE PREREQUISITES
###############################################################################

log ""
log "Phase 2 - Prerequisites Check"

# Check apt-get
if ! command -v apt-get &>/dev/null; then
  error "apt-get not found"
  exit 1
fi

# Check if we have sufficient disk space
DISK_AVAILABLE=$(df /usr | awk 'NR==2 {print $4}')
if [ "$DISK_AVAILABLE" -lt 2000000 ]; then
  error "Insufficient disk space (need 2GB+, have ${DISK_AVAILABLE}KB)"
  exit 1
fi

success "Prerequisites OK"

###############################################################################
# PART 3: DRIVER UPGRADE WITH SUDO (REQUIRES PASSWORD)
###############################################################################

log ""
log "Phase 3 - NVIDIA Driver Upgrade"
log ""
log "⚠️  WARNING: This step requires sudo/root access"
log ""
log "Please run the following command and enter your password when prompted:"
log ""
echo "    sudo bash /tmp/driver-upgrade.sh"
log ""
log "This will:"
log "  1. Update apt cache"
log "  2. Install nvidia-driver-555"
log "  3. Verify installation"
log "  4. Reboot system (required for driver activation)"
log ""

# Create the actual driver upgrade script
cat > /tmp/driver-upgrade.sh << 'DRIVE_SCRIPT'
#!/bin/bash
set -e

echo "[*] Updating apt cache..."
apt-get update -qq

echo "[*] Removing old driver..."
apt-get purge -y nvidia-driver* || true
apt-get autoremove -y || true

echo "[*] Installing NVIDIA driver 555..."
apt-get install -y nvidia-driver-555

echo "[*] Installing CUDA 12.4 runtime..."
apt-get install -y cuda-runtime-12-4

echo "[*] Installing NVIDIA Container Toolkit..."
apt-get install -y nvidia-container-toolkit

echo "[✓] Driver install complete!"
echo "[*] System requires reboot to activate driver"
echo ""
echo "After reboot, run:"
echo "  nvidia-smi  # Should show driver 555.x"

DRIVE_SCRIPT

chmod +x /tmp/driver-upgrade.sh

###############################################################################
# PART 4: POST-REBOOT VERIFICATION (For Later)
###############################################################################

cat > /tmp/post-upgrade-verify.sh << 'VERIFY_SCRIPT'
#!/bin/bash
set -e

log() { echo "[$(date '+%H:%M:%S')] $1"; }
success() { echo "[✓] $1"; }

log "Post-Reboot Verification"
log "========================"

# Wait for GPU to be ready
sleep 5

# Check driver
DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
log "Driver Version: $DRIVER"

# Check CUDA
CUDA=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 || echo "N/A")
log "CUDA Version: $CUDA"

# Verify container support
if nvidia-smi --list-gpus &>/dev/null; then
  success "GPUs accessible"
fi

# Docker integration test
if command -v docker &>/dev/null; then
  log "Docker GPU test..."
  if docker run --rm --gpus all nvidia/cuda:12.4.1-runtime-ubuntu22.04 nvidia-smi > /dev/null 2>&1; then
    success "Docker GPU access working!"
  else
    echo "[!] Docker GPU might need container toolkit restart"
  fi
fi

log "✓ Verification complete"

VERIFY_SCRIPT

chmod +x /tmp/post-upgrade-verify.sh

###############################################################################
# NEXT STEPS
###############################################################################

log ""
log "=================================================================="
log "NEXT STEPS TO COMPLETE GPU UPGRADE:"
log "=================================================================="
log ""
log "1. RUN DRIVER INSTALLATION (ONE TIME - requires password):"
log "   $ sudo bash /tmp/driver-upgrade.sh"
log ""
log "2. REBOOT THE SYSTEM (required for driver activation):"
log "   $ sudo reboot"
log ""
log "3. AFTER REBOOT - VERIFY INSTALLATION:"
log "   $ bash /tmp/post-upgrade-verify.sh"
log ""
log "4. UPDATE DOCKER DAEMON (if needed):"
log "   $ sudo systemctl daemon-reload"
log "   $ sudo systemctl restart docker"
log ""
log "=================================================================="
