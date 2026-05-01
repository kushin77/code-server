#!/bin/bash
# @file backup-idempotent.sh
# @module infrastructure
# @description Idempotent backup - skip if already backed up in this period
# @idempotent YES - Checks backup age before creating new backup
set -euo pipefail

# Source canonical bootstrap (provides log_info, log_error, and shared configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

readonly BACKUP_DIR="./state/backups"
readonly BACKUP_AGE_HOURS="${BACKUP_AGE_HOURS:-1}"  # Don't backup more than once per hour

mkdir -p "$BACKUP_DIR"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Backup failed at line $LINENO (exit code: $?)"; rm -f "${BACKUP_FILE}" 2>/dev/null || true; exit 1' ERR
trap 'log_info "Performing cleanup..."; true' EXIT

# Check if recent backup exists
has_recent_backup() {
  local cutoff_time=$(($(date '+%s') - (BACKUP_AGE_HOURS * 3600)))
  
  for backup in "${BACKUP_DIR}"/backup-*.tar.gz; do
    if [[ -f "$backup" ]]; then
      local backup_time=$(stat -f %m "$backup" 2>/dev/null || stat -c %Y "$backup")
      if [[ $backup_time -gt $cutoff_time ]]; then
        log_info "✅ Recent backup exists: $backup"
        return 0
      fi
    fi
  done
  return 1
}

# Perform backup
backup() {
  log_info "Starting idempotent backup"
  
  if has_recent_backup; then
    log_info "Skipping backup - recent backup exists"
    return 0
  fi
  
  log_info "Creating new backup..."
  local backup_file="${BACKUP_DIR}/backup-$(date +%s).tar.gz"
  
  tar czf "$backup_file" \
    docker-compose.yml \
    config/ \
    .env \
    scripts/ops/ \
    --exclude=artifacts \
    --exclude=state
  
  log_info "✅ Backup created: $backup_file"
}

main() {
  backup
}

main "$@"
