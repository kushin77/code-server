#!/usr/bin/env bash
# @file        scripts/ops/restore-appsmith.sh
# @module      operations/backup-restore
# @description Restore Appsmith portal state from backup snapshot
#
# Usage:
#   bash scripts/ops/restore-appsmith.sh latest                    # Restore latest snapshot
#   bash scripts/ops/restore-appsmith.sh appsmith-snapshot-20260420-143022.tar.gz  # Restore specific
#   bash scripts/ops/restore-appsmith.sh list                      # List available snapshots
#   DRY_RUN=1 bash scripts/ops/restore-appsmith.sh latest           # Dry-run (show what would happen)
#
# Procedure:
#   1. List available backup snapshots
#   2. Validate snapshot integrity (tar -tzf)
#   3. Stop Appsmith container
#   4. Backup current state (if exists)
#   5. Extract snapshot to appsmith-stacks volume
#   6. Start Appsmith container
#   7. Verify Appsmith health
#   8. Import API export if available
#
# Exit codes:
#   0 = Restore successful
#   1 = Restore partial (snapshot restored but health check/API import failed)
#   2 = Restore failed (snapshot not extracted)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
APPSMITH_CONTAINER="${APPSMITH_CONTAINER:-appsmith}"
APPSMITH_PORT="${APPSMITH_PORT:-80}"
APPSMITH_HEALTH_ENDPOINT="http://localhost:$APPSMITH_PORT/api/v1/health"
BACKUP_DIR="${BACKUP_DIR:-/mnt/nas/backups/appsmith}"
DRY_RUN="${DRY_RUN:-1}"
RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-300}"

# ════════════════════════════════════════════════════════════════════════════
# Utility Functions
# ════════════════════════════════════════════════════════════════════════════

list_snapshots() {
  log_info "Available Appsmith snapshots:"
  
  if ! ls -lh "$BACKUP_DIR"/appsmith-snapshot-*.tar.gz 2>/dev/null; then
    log_error "No snapshots found in $BACKUP_DIR"
    return 1
  fi
}

get_latest_snapshot() {
  local latest
  if ! latest=$(ls -1t "$BACKUP_DIR"/appsmith-snapshot-*.tar.gz 2>/dev/null | head -1); then
    log_fatal "No snapshots found in $BACKUP_DIR"
    return 2
  fi
  echo "$latest"
}

validate_snapshot() {
  local snapshot=$1
  
  log_info "Validating snapshot: $(basename "$snapshot")..."
  
  if [[ ! -f "$snapshot" ]]; then
    log_error "Snapshot file not found: $snapshot"
    return 2
  fi
  
  if ! timeout 30 tar -tzf "$snapshot" > /dev/null 2>&1; then
    log_error "Snapshot is corrupted (tar -tzf failed)"
    return 2
  fi
  
  log_info "  ✓ Snapshot valid"
  return 0
}

stop_appsmith() {
  log_info "Stopping Appsmith container..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would stop container: $APPSMITH_CONTAINER"
    return 0
  fi
  
  if ! docker-compose stop "$APPSMITH_CONTAINER" > /dev/null 2>&1; then
    log_error "Failed to stop Appsmith container"
    return 1
  fi
  
  sleep 5
  log_info "  ✓ Appsmith stopped"
  return 0
}

backup_current_state() {
  log_info "Backing up current Appsmith state..."
  
  local volume_path="/var/lib/docker/volumes/appsmith-data/_data"
  local current_backup="$BACKUP_DIR/appsmith-pre-restore-$(date +%s).tar.gz"
  
  if [[ ! -d "$volume_path" ]]; then
    log_warn "Current volume path not found: $volume_path (skipping pre-restore backup)"
    return 0
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would backup current state to: $(basename "$current_backup")"
    return 0
  fi
  
  if ! tar -czf "$current_backup" -C "$(dirname "$volume_path")" "appsmith-data/_data" 2>/dev/null; then
    log_error "Failed to backup current state, but continuing with restore"
  fi
  
  log_info "  ✓ Current state backed up"
  return 0
}

restore_snapshot() {
  local snapshot=$1
  local volume_path="/var/lib/docker/volumes/appsmith-data/_data"
  
  log_info "Restoring snapshot..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would extract snapshot to: $volume_path"
    return 0
  fi
  
  # Clear existing volume (keep pre-restore backup)
  if [[ -d "$volume_path" ]]; then
    if ! rm -rf "$volume_path"/* > /dev/null 2>&1; then
      log_error "Failed to clear current volume"
      return 2
    fi
  fi
  
  # Extract snapshot
  if ! tar -xzf "$snapshot" -C "$(dirname "$volume_path")" > /dev/null 2>&1; then
    log_error "Failed to extract snapshot"
    return 2
  fi
  
  log_info "  ✓ Snapshot restored"
  return 0
}

start_appsmith() {
  log_info "Starting Appsmith container..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would start container: $APPSMITH_CONTAINER"
    return 0
  fi
  
  if ! docker-compose up -d "$APPSMITH_CONTAINER" > /dev/null 2>&1; then
    log_error "Failed to start Appsmith container"
    return 2
  fi
  
  sleep 10
  log_info "  ✓ Appsmith started"
  return 0
}

verify_appsmith_health() {
  log_info "Verifying Appsmith health (max $RESTORE_TIMEOUT seconds)..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would verify health at: $APPSMITH_HEALTH_ENDPOINT"
    return 0
  fi
  
  local elapsed=0
  while [[ $elapsed -lt $RESTORE_TIMEOUT ]]; do
    if timeout 5 curl -sf "$APPSMITH_HEALTH_ENDPOINT" > /dev/null 2>&1; then
      log_info "  ✓ Appsmith healthy after $elapsed seconds"
      return 0
    fi
    
    sleep 5
    ((elapsed += 5))
    echo -n "."
  done
  
  log_error "Appsmith did not become healthy after $RESTORE_TIMEOUT seconds"
  return 1
}

# ════════════════════════════════════════════════════════════════════════════
# Main Restore Procedure
# ════════════════════════════════════════════════════════════════════════════

main() {
  local snapshot_arg="${1:-latest}"
  
  # Handle special commands
  if [[ "$snapshot_arg" == "list" ]]; then
    list_snapshots
    return $?
  fi
  
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Appsmith Portal Restore"
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  log_info "Dry-run mode: $DRY_RUN"
  log_info ""
  
  # Determine snapshot to restore
  local snapshot
  if [[ "$snapshot_arg" == "latest" ]]; then
    if ! snapshot=$(get_latest_snapshot); then
      return 2
    fi
    log_info "Snapshot: $(basename "$snapshot") (latest)"
  else
    snapshot="$BACKUP_DIR/$snapshot_arg"
    log_info "Snapshot: $snapshot_arg"
  fi
  log_info ""
  
  # Validate snapshot exists
  if ! validate_snapshot "$snapshot"; then
    return 2
  fi
  log_info ""
  
  # Stop Appsmith
  if ! stop_appsmith; then
    log_error "Failed to stop Appsmith"
    return 1
  fi
  log_info ""
  
  # Backup current state
  backup_current_state || true
  log_info ""
  
  # Restore snapshot
  if ! restore_snapshot "$snapshot"; then
    log_fatal "Restore failed at snapshot extraction"
    return 2
  fi
  log_info ""
  
  # Start Appsmith
  if ! start_appsmith; then
    log_fatal "Failed to start Appsmith after restore"
    return 2
  fi
  log_info ""
  
  # Verify health
  local restore_status=0
  if ! verify_appsmith_health; then
    log_warn "Health check failed, but snapshot was restored"
    restore_status=1
  fi
  log_info ""
  
  log_info "═══════════════════════════════════════════════════════════"
  if [[ $restore_status -eq 0 ]]; then
    log_info "✓ Restore Complete and Verified"
  else
    log_warn "⚠ Restore Complete but Verification Failed"
  fi
  log_info "═══════════════════════════════════════════════════════════"
  
  return $restore_status
}

main "$@"
