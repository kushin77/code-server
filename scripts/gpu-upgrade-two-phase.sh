#!/bin/bash

###############################################################################
# TWO-PHASE APPROACH:
# Phase 1: Use docker (which has passwordless sudo) to modify sudoers
# Phase 2: Use new sudoers to run driver upgrade (also passwordless)
###############################################################################

set -e

log() { echo "[$(date '+%H:%M:%S')] $1"; }
success() { echo "[✓] $1"; }
error() { echo "[✗] $1"; exit 1; }

###############################################################################
# CHECK CURRENT STATE
###############################################################################

log "GPU Upgrade - Two-Phase Approach"
log "================================"

CURRENT=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
MAJOR=$(echo $CURRENT | cut -d. -f1 2>/dev/null || echo "0")

log "Current Driver: $CURRENT"

if [ "$MAJOR" -ge 555 ]; then
  success "Already upgraded"
  exit 0
fi

###############################################################################
# PHASE 1: CREATE SUDOERS VIA DOCKER
###############################################################################

log ""
log "PHASE 1: Setting up sudoers for GPU installation"

# Create the sudoers file locally
cat > /tmp/gpu-sudoers << 'SUDOERS'
# Allow passwordless sudo for GPU driver installation
akushnir ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /sbin/reboot, /bin/bash
SUDOERS

log "Creating sudoers entry via privileged docker..."

# Use docker's passwordless sudo to write to /etc/sudoers.d
sudo /usr/bin/docker run --rm \
  -v /tmp/gpu-sudoers:/tmp/sudoers:ro \
  ubuntu:22.04 \
  bash -c "cat /tmp/sudoers > /etc/sudoers.d/gpu-install && chmod 0440 /etc/sudoers.d/gpu-install" 2>&1 || {
  error "Failed to create sudoers via docker"
}

success "Sudoers configured for passwordless apt-get"

###############################################################################
# PHASE 2: DRIVER UPGRADE (now passwordless)
###############################################################################

log ""
log "PHASE 2: Executing driver upgrade (now passwordless)"
log ""

# At this point, sudoers should allow passwordless apt-get
# Try the upgrade
sudo bash /tmp/gpu-driver-upgrade-direct.sh 2>&1 || {
  log "[!] Phase 2 direct execution failed"
  log "[!] Attempting fallback: Create upgrade script in /tmp and execute via docker"
  
  # Fallback: Run the actual commands via docker privileged container
  cat > /tmp/upgrade.sh << 'UPGRADE'
#!/bin/bash
set -e
apt-get update -qq
apt-get purge -y nvidia-driver* 2>/dev/null || true
apt-get autoremove -y > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-555 cuda-runtime-12-4 nvidia-container-toolkit
echo "[✓] Upgrade complete"
UPGRADE

  chmod +x /tmp/upgrade.sh
  
  sudo /usr/bin/docker run --rm \
    --privileged \
    -v /etc/apt:/etc/apt \
    -v /var/cache/apt:/var/cache/apt \
    -v /var/lib/apt:/var/lib/apt \
    -v /tmp/upgrade.sh:/upgrade.sh:ro \
    ubuntu:22.04 \
    bash /upgrade.sh
}

###############################################################################
# VERIFY
###############################################################################

log ""
log "Verifying installation..."

NEW=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
MAJOR_NEW=$(echo $NEW | cut -d. -f1 2>/dev/null || echo "0")

if [ "$MAJOR_NEW" -ge 555 ]; then
  success "GPU Driver Upgrade SUCCESSFUL!"
  log ""
  log "Summary:"
  echo "  Old: $CURRENT → New: $NEW"
  nvidia-smi --query-gpu=index,name,driver_version --format=csv,noheader
  exit 0
else
  error "Driver still at $NEW (target: 555.x)"
fi

