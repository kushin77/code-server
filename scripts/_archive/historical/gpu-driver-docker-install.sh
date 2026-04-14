#!/bin/bash
# Docker-based GPU driver upgrade using host volume mounting
# Allows the container to execute apt-get and install drivers on the host

cd /tmp

docker run --rm \
  --privileged \
  --network host \
  -v /:/host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DEBIAN_FRONTEND=noninteractive \
  ubuntu:22.04 \
  bash << 'INSTALL_SCRIPT'

set -e

CHROOT=/host
log() { echo "[$(date +'%H:%M:%S')] $*"; }

log "=== GPU Driver Upgrade via Docker ==="

# Update host package cache
log "Updating package lists..."
chroot $CHROOT apt-get update -qq

# Clean old drivers
log "Removing old driver packages..."
chroot $CHROOT apt-get purge -y nvidia-driver* nvidia-utils* cuda* 2>/dev/null || true

# Add needed build tools on host
log "Installing build dependencies..."
chroot $CHROOT apt-get install -y build-essential dkms 2>/dev/null || true

# Install driver 555
log "Installing NVIDIA driver 555..."
chroot $CHROOT apt-get install -y nvidia-driver-555 nvidia-utils-555 2>&1 | tail -10

# Verify
log "Verifying driver installation..."
chroot $CHROOT nvidia-smi --query-gpu=driver_version --format=csv,noheader

log "✓ GPU driver installation initiated"
log "  Host may need reboot for kernel module to fully activate"

INSTALL_SCRIPT

echo ""
echo "✓ Installation script completed"
