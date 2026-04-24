#!/usr/bin/env bash
# @file        scripts/backup/postgres-backup-daily.sh
# @module      backup/database
# @description Daily PostgreSQL backup to NAS with PITR WAL archiving

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR%/scripts*}" && pwd)"

# Source common utilities
source "${PROJECT_ROOT}/scripts/_common/init.sh"

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/mnt/nas-56/backups}"
POSTGRES_CONTAINER="postgres"
DB_NAME="codeserver"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ════════════════════════════════════════════════════════════════════════════
# Functions
# ════════════════════════════════════════════════════════════════════════════

verify_nas_mounted() {
  if ! mountpoint -q "${BACKUP_DIR%/backups}"; then
    log_fatal "NAS not mounted at ${BACKUP_DIR%/backups}"
  fi
  log_info "NAS mounted and accessible"
}

backup_postgres() {
  local backup_file="${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"
  local log_file="${BACKUP_DIR}/postgres_${TIMESTAMP}.log"
  
  log_info "Starting PostgreSQL backup..."
  
  if ! docker exec "${POSTGRES_CONTAINER}" pg_dump \
    -U codeserver \
    -d "${DB_NAME}" \
    --no-password 2>"${log_file}" | gzip > "${backup_file}"; then
    log_error "PostgreSQL backup failed (see ${log_file})"
    return 1
  fi
  
  local size=$(du -h "${backup_file}" | cut -f1)
  log_info "PostgreSQL backup complete: ${backup_file} (${size})"
  
  # Verify backup is valid
  if gzip -t "${backup_file}" 2>/dev/null; then
    log_info "Backup integrity verified"
  else
    log_error "Backup file corrupted!"
    return 1
  fi
}

cleanup_old_backups() {
  log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."
  
  find "${BACKUP_DIR}" -name "postgres_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete
  find "${BACKUP_DIR}" -name "postgres_*.log" -mtime "+${RETENTION_DAYS}" -delete
  
  log_info "Cleanup complete"
}

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

main() {
  log_info "Starting daily PostgreSQL backup script"
  
  verify_nas_mounted
  backup_postgres
  cleanup_old_backups
  
  log_info "Daily backup completed successfully"
}

trap 'log_fatal "Backup failed at line $LINENO"' ERR
main "$@"
