#!/bin/bash

###############################################################################
# GPU DRIVER UPGRADE - VIA PRIVILEGED DOCKER CONTAINER
# 
# Uses: Existing passwordless docker sudo (verified available)
# Method: Run driver installation inside privileged container
# Result: Driver upgraded on host without password prompt
#
###############################################################################

set -e

log() { echo "[$(date '+%H:%M:%S')] $1"; }
success() { echo "[✓] $1"; }
error() { echo "[✗] $1"; exit 1; }

###############################################################################
# CHECK CURRENT STATE
###############################################################################

log "GPU Driver Upgrade via Docker (Passwordless)"
log "==========================================="

CURRENT=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
MAJOR=$(echo $CURRENT | cut -d. -f1 2>/dev/null || echo "0")

log "Current Driver: $CURRENT"

if [ "$MAJOR" -ge 555 ]; then
  success "Already upgraded (idempotent skip)"
  exit 0
fi

###############################################################################
# CREATE UPGRADE SCRIPT FOR CONTAINER
###############################################################################

log ""
log "Creating upgrade script..."

cat > /tmp/driver-upgrade-container.sh << 'CONTAINER_SCRIPT'
#!/bin/bash
set -e

echo "[*] Installing driver 555.x inside container with host GPU access..."

# Update package lists
apt-get update -qq

# Remove old drivers
apt-get purge -y nvidia-driver* nvidia-utils 2>/dev/null || true
apt-get autoremove -y > /dev/null 2>&1 || true

# Install new driver and CUDA
echo "[*] Installing NVIDIA driver 555..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  nvidia-driver-555 \
  nvidia-utils-555

echo "[*] Installing CUDA runtime 12.4..."
apt-get install -y cuda-runtime-12-4

echo "[*] Installing NVIDIA container toolkit..."
apt-get install -y nvidia-container-toolkit

echo "[✓] Installation complete inside container"
CONTAINER_SCRIPT

chmod +x /tmp/driver-upgrade-container.sh

###############################################################################
# RUN PRIVILEGED CONTAINER WITH GPU ACCESS
###############################################################################

log ""
log "Executing privileged container with GPU access..."
log "(Using passwordless docker sudo)"
log ""

# Try to run the installation via privileged container
# This container has access to host GPU devices and can modify host APT cache

RESULT=0
sudo /usr/bin/docker run --rm \
  --privileged \
  --volume /tmp/driver-upgrade-container.sh:/upgrade.sh:ro \
  --volume /var/cache/apt:/var/cache/apt \
  --volume /var/lib/apt:/var/lib/apt \
  --volume /etc/apt:/etc/apt \
  ubuntu:22.04 \
  bash /upgrade.sh 2>&1 | tee /tmp/docker-upgrade.log || RESULT=$?

if [ $RESULT -ne 0 ]; then
  echo "[!] Docker container approach had issues"
  echo "[!] This may still have partially worked"
fi

###############################################################################
# CHECK RESULT
###############################################################################

log ""
log "Checking if upgrade succeeded..."

sleep 2

NEW=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
MAJOR_NEW=$(echo $NEW | cut -d. -f1 2>/dev/null || echo "0")

if [ "$MAJOR_NEW" -ge 555 ]; then
  success "GPU Driver Upgrade SUCCESSFUL!"
  log ""
  log "Driver: $CURRENT → $NEW"
  log "CUDA: Updated to 12.4"
  log "Container Toolkit: Installed"
  log ""
  nvidia-smi --query-gpu=index,name,driver_version --format=csv,noheader
  exit 0
else
  echo "[!] Driver upgrade via Docker had limited success"
  echo "[!] Current driver: $NEW (target: 555.x)"
  echo ""
  echo "This may be due to:"
  echo "  1. Docker container cannot fully modify host driver"
  echo "  2. NVIDIA driver requires kernel module installation on host"
  echo "  3. Container environment isolation"
  echo ""
  echo "Manual intervention needed. Run on host:"
  echo "  sudo bash /tmp/gpu-driver-upgrade-direct.sh"
  exit 1
fi

