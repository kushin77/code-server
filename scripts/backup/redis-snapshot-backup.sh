#!/usr/bin/env bash
# @file        scripts/backup/redis-snapshot-backup.sh
# @module      backup/cache
# @description Daily Redis snapshot backup to NAS with automatic cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR%/scripts*}" && pwd)"

# Source common utilities
source "${PROJECT_ROOT}/scripts/_common/init.sh" || {
  echo "ERROR: Cannot load init.sh" >&2
  exit 1
}

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/mnt/nas-56/redis-backups}"
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD}" # MUST be set via env or vault, no default
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Validate required credentials
if [[ -z "${REDIS_PASSWORD:-}" ]]; then
  log_fatal "REDIS_PASSWORD must be set via environment variable (use vault/GSM, not defaults)"
fi

# ════════════════════════════════════════════════════════════════════════════
# Functions
# ════════════════════════════════════════════════════════════════════════════

verify_nas_mounted() {
  if ! mountpoint -q "${BACKUP_DIR%/redis-backups}"; then
    log_fatal "NAS not mounted at ${BACKUP_DIR%/redis-backups}"
  fi
  log_info "NAS mounted and accessible"
}

ensure_backup_dir() {
  mkdir -p "${BACKUP_DIR}"
  log_info "Backup directory ready: ${BACKUP_DIR}"
}

trigger_redis_save() {
  log_info "Triggering Redis BGSAVE..."
  
  redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" \
    -a "${REDIS_PASSWORD}" BGSAVE || {
    log_warn "BGSAVE failed, trying SAVE..."
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" \
      -a "${REDIS_PASSWORD}" SAVE
  }
}

backup_redis_snapshot() {
  local redis_dump="/var/lib/redis/dump.rdb"
  local backup_file="${BACKUP_DIR}/redis-snapshot_${TIMESTAMP}.rdb"
  
  # If Docker container, get snapshot from container
  if command -v docker &>/dev/null; then
    redis_dump="/data/dump.rdb"
  fi
  
  log_info "Copying Redis snapshot to NAS..."
  
  if [[ -f "${redis_dump}" ]]; then
    cp "${redis_dump}" "${backup_file}"
    local size=$(du -h "${backup_file}" | cut -f1)
    log_info "Redis snapshot backed up: ${backup_file} (${size})"
  else
    log_warn "Redis dump file not found at ${redis_dump}"
    return 1
  fi
}

verify_snapshot() {
  local backup_file="${BACKUP_DIR}/redis-snapshot_${TIMESTAMP}.rdb"
  
  # Check RDB file magic bytes (REDIS)
  if [[ $(head -c 5 "${backup_file}" | od -A n -t c) == *"R E D I S"* ]]; then
    log_info "Snapshot format verified (RDB header valid)"
  else
    log_warn "Snapshot may not be valid RDB format"
  fi
}

cleanup_old_snapshots() {
  log_info "Cleaning up snapshots older than ${RETENTION_DAYS} days..."
  
  find "${BACKUP_DIR}" -name "redis-snapshot_*.rdb" -mtime "+${RETENTION_DAYS}" -delete
  
  log_info "Cleanup complete"
}

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

main() {
  log_info "Starting daily Redis snapshot backup"
  
  verify_nas_mounted
  ensure_backup_dir
  trigger_redis_save
  sleep 2  # Give BGSAVE time to complete
  backup_redis_snapshot
  verify_snapshot
  cleanup_old_snapshots
  
  log_info "Redis backup completed successfully"
}

trap 'log_fatal "Backup failed at line $LINENO"' ERR
main "$@"
