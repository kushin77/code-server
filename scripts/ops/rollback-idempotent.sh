#!/bin/bash
# @file rollback-idempotent.sh
# @module infrastructure
# @description Idempotent rollback - safe to call multiple times
# @idempotent YES - Idempotent state checking before rollback
set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

readonly BACKUP_DIR="${REPO_ROOT}/state/backups"
readonly LOG_FILE="${REPO_ROOT}/artifacts/rollback-$(date +%s).log"

mkdir -p "$BACKUP_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
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
    log_error "No backup found for rollback"
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

  if ! wait_for_healthy_services; then
    log_error "Services did not become healthy after rollback"
    return 1
  fi
  
  # Record rollback state
  docker compose config | sha256sum | cut -d' ' -f1 > "${BACKUP_DIR}/.last_rollback"
  log "✅ Rollback complete"
}

main() {
  rollback
}

main "$@"
