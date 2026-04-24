#!/bin/bash
# Automated GPU driver upgrade using ubuntu-drivers
# This method works better for non-interactive upgrades

set -e

log() { echo "[$(date +'%H:%M:%S')] $*"; }
success() { echo "[✓] $*"; }

log "=== GPU Driver Upgrade via ubuntu-drivers ==="
log "Current Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'unknown')"
log ""

# Update package database
log "Step 1: Updating package lists..."
apt-get update -qq

# Install ubuntu-drivers-common if not present
log "Step 2: Ensuring ubuntu-drivers-common is available..."
apt-get install -y ubuntu-drivers-common

# Detect and install recommended driver
log "Step 3: Detecting recommended GPU driver..."
RECOMMENDED=$(ubuntu-drivers devices | grep -i recommended | head -1 | awk '{print $NF}')

if [ -z "$RECOMMENDED" ]; then
  log "No recommended driver detected. Installing latest stable..."
  DRIVER="nvidia-driver-555"
else
  DRIVER="$RECOMMENDED"
  log "Recommended driver: $DRIVER"
fi

# Install the driver
log "Step 4: Installing $DRIVER..."
DEBIAN_FRONTEND=noninteractive apt-get install -y "$DRIVER" 2>&1 | tail -20

# Verify installation
log ""
log "Step 5: Verifying installation..."
sleep 5

NEW_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
log "New Driver Version: $NEW_DRIVER"

success "GPU driver installation complete!"
log ""
log "GPU Status:"
nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv

log ""
log "⚠️  Reboot recommended to fully activate kernel modules"
log "    sudo reboot"

