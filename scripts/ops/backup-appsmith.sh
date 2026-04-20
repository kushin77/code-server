#!/usr/bin/env bash
# @file        scripts/ops/backup-appsmith.sh
# @module      operations/backup-restore
# @description Backup Appsmith portal state to NAS for disaster recovery
#
# Usage:
#   bash scripts/ops/backup-appsmith.sh                           # Create backup snapshot
#   bash scripts/ops/backup-appsmith.sh -v                        # Verbose output
#   BACKUP_DIR=/custom/path bash scripts/ops/backup-appsmith.sh  # Custom backup location
#
# Procedure:
#   1. Export Appsmith apps via Appsmith API (/api/v1/applications/export)
#   2. Create tar.gz snapshot of appsmith-stacks volume
#   3. Store snapshot on NAS with timestamp
#   4. Keep last 10 snapshots; rotate older backups
#   5. Log snapshot location for recovery procedures
#
# Exit codes:
#   0 = Backup successful
#   1 = Backup partial (API export failed but volume snapshot created)
#   2 = Backup failed (no snapshot created)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
APPSMITH_CONTAINER="${APPSMITH_CONTAINER:-appsmith}"
APPSMITH_PORT="${APPSMITH_PORT:-80}"
APPSMITH_HEALTH_ENDPOINT="http://localhost:$APPSMITH_PORT/api/v1/health"
BACKUP_DIR="${BACKUP_DIR:-/mnt/nas/backups/appsmith}"
BACKUP_RETENTION="${BACKUP_RETENTION:-10}"
VERBOSE="${VERBOSE:-0}"
DRY_RUN="${DRY_RUN:-1}"

# Tracking
BACKUP_STATUS=0
API_EXPORT_SUCCESS=0

# ════════════════════════════════════════════════════════════════════════════
# Utility Functions
# ════════════════════════════════════════════════════════════════════════════

create_backup_dir() {
  if ! mkdir -p "$BACKUP_DIR"; then
    log_fatal "Cannot create backup directory: $BACKUP_DIR"
    return 2
  fi
  if ! chmod 755 "$BACKUP_DIR"; then
    log_warn "Cannot chmod backup directory, continuing..."
  fi
}

check_appsmith_health() {
  log_info "Checking Appsmith health..."
  
  if ! timeout 10 curl -sf "$APPSMITH_HEALTH_ENDPOINT" > /dev/null 2>&1; then
    log_error "Appsmith is not healthy at $APPSMITH_HEALTH_ENDPOINT"
    return 1
  fi
  
  log_info "  ✓ Appsmith healthy"
  return 0
}

export_appsmith_api() {
  log_info "Exporting Appsmith apps via API..."
  
  local export_file="$BACKUP_DIR/appsmith-apps-export-$(date +%s).json"
  
  if ! timeout 60 curl -sf \
    -X GET "$APPSMITH_HEALTH_ENDPOINT/../applications/export" \
    > "$export_file" 2>/dev/null; then
    
    log_error "API export failed, but continuing with volume snapshot"
    rm -f "$export_file"
    return 1
  fi
  
  local file_size=$(stat -f%z "$export_file" 2>/dev/null || stat -c%s "$export_file")
  if [[ $file_size -lt 100 ]]; then
    log_error "API export file too small ($file_size bytes), likely error"
    rm -f "$export_file"
    return 1
  fi
  
  log_info "  ✓ API export created: $(basename "$export_file") ($file_size bytes)"
  API_EXPORT_SUCCESS=1
  return 0
}

snapshot_appsmith_volume() {
  log_info "Creating volume snapshot..."
  
  local timestamp=$(date +%Y%m%d-%H%M%S)
  local snapshot_file="$BACKUP_DIR/appsmith-snapshot-$timestamp.tar.gz"
  
  # Source: appsmith-stacks volume (typically at /var/lib/docker/volumes/appsmith-data/_data)
  local volume_path="/var/lib/docker/volumes/appsmith-data/_data"
  
  if [[ ! -d "$volume_path" ]]; then
    log_error "Volume path not found: $volume_path"
    return 2
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would create snapshot: $snapshot_file"
    return 0
  fi
  
  # Create compressed tarball of volume
  if ! tar -czf "$snapshot_file" -C "$(dirname "$volume_path")" "appsmith-data/_data" 2>/dev/null; then
    log_error "Failed to create snapshot tarball"
    return 2
  fi
  
  local file_size=$(stat -f%z "$snapshot_file" 2>/dev/null || stat -c%s "$snapshot_file")
  log_info "  ✓ Snapshot created: $(basename "$snapshot_file") ($file_size bytes)"
  
  return 0
}

rotate_old_backups() {
  log_info "Rotating old backups (keep last $BACKUP_RETENTION)..."
  
  local snapshot_count=$(ls -1 "$BACKUP_DIR"/appsmith-snapshot-*.tar.gz 2>/dev/null | wc -l)
  
  if [[ $snapshot_count -le $BACKUP_RETENTION ]]; then
    log_info "  Snapshots: $snapshot_count (no rotation needed)"
    return 0
  fi
  
  local excess=$((snapshot_count - BACKUP_RETENTION))
  log_info "  Deleting $excess old snapshot(s)..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would delete oldest snapshots"
    return 0
  fi
  
  # Delete oldest snapshots
  ls -1t "$BACKUP_DIR"/appsmith-snapshot-*.tar.gz 2>/dev/null | tail -n "$excess" | while read -r old_file; do
    if rm -f "$old_file"; then
      log_info "    Deleted: $(basename "$old_file")"
    fi
  done
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# Main Backup Procedure
# ════════════════════════════════════════════════════════════════════════════

main() {
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Appsmith Portal Backup"
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  log_info "Backup directory: $BACKUP_DIR"
  log_info "Dry-run mode: $DRY_RUN"
  log_info ""
  
  create_backup_dir || return 2
  
  if ! check_appsmith_health; then
    log_warn "Appsmith health check failed, proceeding with volume snapshot only"
  fi
  
  export_appsmith_api || BACKUP_STATUS=1
  log_info ""
  
  if ! snapshot_appsmith_volume; then
    log_fatal "Volume snapshot failed"
    return 2
  fi
  log_info ""
  
  rotate_old_backups || true
  log_info ""
  
  log_info "═══════════════════════════════════════════════════════════"
  if [[ $BACKUP_STATUS -eq 0 ]] && [[ $API_EXPORT_SUCCESS -eq 1 ]]; then
    log_info "✓ Backup Complete (API export + snapshot)"
  elif [[ $BACKUP_STATUS -eq 1 ]]; then
    log_warn "⚠ Backup Partial (snapshot created, API export failed)"
  else
    log_error "✗ Backup Failed"
    return 2
  fi
  log_info "═══════════════════════════════════════════════════════════"
  
  return $BACKUP_STATUS
}

main "$@"
