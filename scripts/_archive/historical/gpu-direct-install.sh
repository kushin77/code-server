#!/bin/bash
# Direct GPU driver upgrade for 555.x
# Handles Ubuntu 22.04 repository correctly

(
set -e

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STARTING GPU DRIVER UPGRADE ==="
log "Machine: $(hostname)"
log "Current driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'N/A')"
log ""

# Step 1: Update
log "Updating package database..."
apt-get update -qq 2>&1 | grep -i nvidia || log "Package lists updated"

# Step 2: Install build essentials
log "Installing build dependencies..."
apt-get install -y build-essential dkms 2>&1 | tail -3

# Step 3: Remove old drivers
log "Removing old NVIDIA packages..."
apt-get purge -y nvidia-driver* nvidia-utils* 2>/dev/null || log "No old packages to remove"

# Step 4: Install new driver
log "Installing NVIDIA driver 555.x..."
DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-555 2>&1 | tail -20

# Step 5: Verify
log ""
log "Verification:"
nvidia-smi --query-gpu=driver_version --format=csv,noheader || log "Driver check pending reboot"

log ""
log "✅ Installation complete - reboot recommended"

) |& tee /tmp/gpu-install-$(date +%s).log
