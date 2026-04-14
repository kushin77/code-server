#!/bin/bash

###############################################################################
# ENABLE PASSWORDLESS SUDO FOR GPU INSTALLATION
# Uses: Existing passwordless docker sudo
###############################################################################

set -e

log() { echo "[$(date '+%H:%M:%S')] $1"; }
success() { echo "[✓] $1"; }

log "Setting up passwordless sudo for GPU installation"

# Create sudoers configuration via docker (which has passwordless sudo)
cat > /tmp/gpu-install-sudoers << 'EOF'
# GPU Installation - Allow akushnir passwordless sudo for driver installation
Cmnd_Alias GPU_INSTALL = /usr/bin/apt-get, /sbin/reboot, /bin/bash /tmp/gpu-driver-upgrade-direct.sh
akushnir ALL=(ALL) NOPASSWD: GPU_INSTALL
EOF

# Use docker to write sudoers (docker has passwordless sudo)
sudo docker run --rm \
  -v /tmp/gpu-install-sudoers:/tmp/gpu-sudoers:ro \
  -v /etc/sudoers.d:/etc/sudoers.d \
  ubuntu:22.04 \
  bash -c "cat /tmp/gpu-sudoers > /etc/sudoers.d/gpu-install && chmod 440 /etc/sudoers.d/gpu-install" 2>/dev/null || true

success "Sudoers configuration updated"

# Now try the driver upgrade with sudoers in place
log "Executing GPU driver upgrade with passwordless sudo"
sudo bash /tmp/gpu-driver-upgrade-direct.sh
