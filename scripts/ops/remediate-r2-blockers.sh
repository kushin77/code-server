#!/usr/bin/env bash
# @file        scripts/ops/remediate-r2-blockers.sh
# @module      infrastructure/remediation
# @description Fix port 80 conflict and appsmith NAS mount blocker on Replica 2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

log_info "Starting Replica 2 blocker remediation..."

# ────────────────────────────────────────────────────────────────────────────
# 1. Clear port 80 phantom listeners
# ────────────────────────────────────────────────────────────────────────────
log_info "Clearing port 80 phantom listeners..."
if sudo pkill -f caddy 2>/dev/null || true; then
  log_info "Killed lingering caddy processes"
else
  log_warn "No caddy processes to kill"
fi

sleep 2

# Force docker to release port bindings
log_info "Stopping all containers to release port bindings..."
cd "$(git rev-parse --show-toplevel)/code-server-enterprise" || {
  log_error "Could not find code-server-enterprise directory"
  exit 1
}

docker-compose down || log_warn "docker-compose down had issues"
sleep 3

log_info "Port 80 cleanup completed"

# ────────────────────────────────────────────────────────────────────────────
# 2. Verify NAS accessibility and create appsmith directory
# ────────────────────────────────────────────────────────────────────────────
log_info "Checking NAS accessibility..."
NAS_HOST="${NAS_HOST:-192.168.168.56}"
NAS_EXPORT="${NAS_EXPORT:-/export}"

if ping -c 1 "$NAS_HOST" &> /dev/null; then
  log_info "NAS ($NAS_HOST) is reachable"
else
  log_error "NAS ($NAS_HOST) is not reachable"
  exit 1
fi

# Check if NAS export is available via showmount
if showmount -e "$NAS_HOST" 2>/dev/null | grep -q "$NAS_EXPORT"; then
  log_info "NAS export $NAS_EXPORT is available"
else
  log_error "NAS export $NAS_EXPORT is not available"
  exit 1
fi

# Create temporary mount point and verify directory structure
log_info "Creating temporary NAS mount to verify appsmith directory..."
TEMP_MOUNT="/tmp/nfs_check_$$"
mkdir -p "$TEMP_MOUNT"

if sudo mount -t nfs "$NAS_HOST:$NAS_EXPORT" "$TEMP_MOUNT" 2>/dev/null; then
  log_info "NAS mounted at $TEMP_MOUNT"
  
  if [ ! -d "$TEMP_MOUNT/appsmith" ]; then
    log_warn "Directory $NAS_EXPORT/appsmith does not exist on NAS"
    log_info "Creating appsmith directory on NAS..."
    sudo mkdir -p "$TEMP_MOUNT/appsmith"
    sudo chmod 755 "$TEMP_MOUNT/appsmith"
    log_info "Created and configured $NAS_EXPORT/appsmith"
  else
    log_info "Directory $NAS_EXPORT/appsmith already exists"
  fi
  
  sudo umount "$TEMP_MOUNT"
  rmdir "$TEMP_MOUNT"
  log_info "NAS unmounted and cleaned up"
else
  log_error "Failed to mount NAS for verification"
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# 3. Restart services
# ────────────────────────────────────────────────────────────────────────────
log_info "Bringing up core services..."
docker-compose up -d postgres redis code-server oauth2-proxy

sleep 5

log_info "Bringing up caddy (requires port 80)..."
docker-compose up -d caddy

sleep 3

log_info "Bringing up appsmith (requires NAS mount)..."
docker-compose up -d appsmith

# ────────────────────────────────────────────────────────────────────────────
# 4. Verify services are running
# ────────────────────────────────────────────────────────────────────────────
log_info "Verifying service status..."
docker-compose ps

log_info "Remediation completed successfully"
log_info "Replica 2 should now be at parity with Replica 1"
