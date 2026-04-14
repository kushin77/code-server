#!/bin/bash

###############################################################################
# GPU DRIVER UPGRADE - STDIN PASSWORD METHOD
#
# Uses: sudo -S to read password from stdin
# Requirement: Password passed via environment or stdin
###############################################################################

set -e

log() { echo "[$(date '+%H:%M:%S')] $1"; }
success() { echo "[✓] $1"; }
error() { echo "[✗] $1"; exit 1; }

###############################################################################
# CHECK CURRENT STATE
###############################################################################

log "GPU Driver Upgrade - Using stdin password method"
log "==============================================="

CURRENT=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
MAJOR=$(echo $CURRENT | cut -d. -f1 2>/dev/null || echo "0")

log "Current Driver: $CURRENT"

if [ "$MAJOR" -ge 555 ]; then
  success "Already upgraded (idempotent skip)"
  exit 0
fi

###############################################################################
# MAIN UPGRADE (reads password from stdin via sudo -S)
###############################################################################

log ""
log "Executing GPU driver upgrade with stdin password..."
log ""

# The actual upgrade commands that require sudo
{
  echo "apt-get update -qq"
  echo "apt-get purge -y nvidia-driver* nvidia-utils 2>/dev/null || true"
  echo "apt-get autoremove -y"
  echo "DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-555 nvidia-utils-555"
  echo "apt-get install -y cuda-runtime-12-4"
  echo "apt-get install -y nvidia-container-toolkit"
} | while read cmd; do
  log "Running: sudo $cmd"
  echo "$cmd" | sudo -S bash 2>&1 || true
done

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
  echo "  Old Driver: $CURRENT"
  echo "  New Driver: $NEW"
  nvidia-smi
  exit 0
else
  error "Driver upgrade failed - still on $NEW"
fi

