#!/bin/bash
# @file rollback-idempotent.sh
# @module infrastructure
# @description Idempotent rollback - safe to call multiple times
# @idempotent YES - Idempotent state checking before rollback
set -euo pipefail

readonly BACKUP_DIR="./state/backups"
readonly LOG_FILE="./artifacts/rollback-$(date +%s).log"

mkdir -p "$BACKUP_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Find latest deployment backup
latest_backup() {
  ls -t "${BACKUP_DIR}"/deployment-*.tar.gz 2>/dev/null | head -1
}

# Idempotent rollback
rollback() {
  log "Starting idempotent rollback"
  
  local latest=$(latest_backup)
  
  if [[ -z "$latest" ]]; then
    echo "ERROR: No backup found for rollback" >&2
    return 1
  fi
  
  log "Using backup: $latest"
  
  # Check if already rolled back
  if docker compose ps &>/dev/null; then
    local current_hash=$(docker compose config | sha256sum | cut -d' ' -f1)
    if [[ -f "${BACKUP_DIR}/.last_rollback" ]]; then
      local last_hash=$(cat "${BACKUP_DIR}/.last_rollback")
      if [[ "$current_hash" == "$last_hash" ]]; then
        log "✅ Already rolled back to this version"
        return 0
      fi
    fi
  fi
  
  # Perform rollback
  log "Stopping services..."
  docker compose down
  
  log "Restoring from backup..."
  tar xzf "$latest" -C .
  
  log "Restarting services..."
  docker compose up -d
  
  # Record rollback state
  docker compose config | sha256sum | cut -d' ' -f1 > "${BACKUP_DIR}/.last_rollback"
  log "✅ Rollback complete"
}

main() {
  rollback
}

main "$@"
