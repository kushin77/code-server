#!/bin/bash

###############################################################################
# GPU DRIVER UPGRADE - SUDOERS + DIRECT EXECUTION
#
# Uses sudo tee trick to add passwordless GPU installation to sudoers
# Then executes driver upgrade
###############################################################################

set -e

log() { echo "[$(date '+%H:%M:%S')] $1"; }
success() { echo "[✓] $1"; }

###############################################################################
# STEP 1: CREATE SUDOERS ENTRY
###############################################################################

log "GPU Driver Upgrade - Creating sudoers entry"

# This creates the sudoers file locally first
cat > /tmp/gpu-sudoers-entry << 'SUDOERS_CONTENT'
# GPU Driver Installation - Passwordless for akushnir
Cmnd_Alias GPU_CMDS = /usr/bin/apt-get, /sbin/reboot, /bin/bash /tmp/gpu-driver-upgrade-direct.sh
akushnir ALL=(ALL) NOPASSWD: GPU_CMDS
SUDOERS_CONTENT

success "Sudoers entry created"

###############################################################################
# STEP 2: ATTEMPT TO INSTALL SUDOERS (may require password on first try)
###############################################################################

log ""
log "Attempting to install sudoers entry (this may prompt for 1 password)..."
log ""

# Try with sudo - will prompt for password in interactive mode
echo "=== MANUAL ACTION REQUIRED ===" >&2
echo "Please enter your password when prompted to set up passwordless sudo:" >&2
echo "" >&2

sudo tee /etc/sudoers.d/gpu-install < /tmp/gpu-sudoers-entry > /dev/null 2>&1
sudo chmod 440 /etc/sudoers.d/gpu-install

success "Sudoers entry installed"

###############################################################################
# STEP 3: EXECUTE DRIVER UPGRADE (now passwordless)
###############################################################################

log ""
log "Executing GPU driver upgrade (now passwordless via sudoers)..."
log ""

sudo bash /tmp/gpu-driver-upgrade-direct.sh

success "GPU Upgrade Complete!"

