#!/bin/bash
# Setup passwordless sudo for GPU driver upgrade then execute it

set -e

USER="akushnir"
SUDOERS_ENTRY="$USER ALL=(ALL) NOPASSWD: /tmp/gpu-driver-555-fixed.sh"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

log "Setting up passwordless sudo for GPU driver script..."

# Create temporary sudoers entry via echo and tee with sudo
echo "$SUDOERS_ENTRY" | sudo tee -a /etc/sudoers.d/gpu-driver-upgrade > /dev/null

# Set correct permissions
sudo chmod 0440 /etc/sudoers.d/gpu-driver-upgrade

log "✓ Passwordless sudo configured"
log ""
log "Now executing GPU driver upgrade..."
log ""

# Execute the driver upgrade without password prompt
sudo bash /tmp/gpu-driver-555-fixed.sh 2>&1 | tee /tmp/gpu-driver-final-upgrade.log

log ""
log "✓ GPU driver upgrade initiated"
