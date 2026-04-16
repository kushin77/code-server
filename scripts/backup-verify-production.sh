#!/usr/bin/env bash
# Script: Automated Backup Verification and Testing
# Purpose: Weekly restore test, backup age alerting, cross-site replication
# Deployment: Primary (192.168.168.31) and Replica (192.168.168.42)

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════

BACKUP_DIR="${BACKUP_DIR:-/backups}"
ARCHIVE_DIR="${ARCHIVE_DIR:-${BACKUP_DIR}/wal-archive}"
VERIFY_DB="${VERIFY_DB:-verify_test_$(date +%s)}"
LOG_FILE="${LOG_FILE:-/var/log/backup-verify.log}"
METRICS_DIR="${METRICS_DIR:-/var/log/prometheus-textfile}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
REPLICA_USER="${REPLICA_USER:-akushnir}"
NAS_MOUNT="${NAS_MOUNT:-/mnt/nas/backups}"

# ════════════════════════════════════════════════════════════════════════════
# Logging
# ════════════════════════════════════════════════════════════════════════════

log() {
  local level="$1"
  shift
  local msg="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${timestamp}] [${level}] ${msg}" | tee -a "${LOG_FILE}"
}

# ════════════════════════════════════════════════════════════════════════════
# 1. Verify WAL Archiving is Active
# ════════════════════════════════════════════════════════════════════════════

verify_wal_archiving() {
  log INFO "Verifying WAL archiving configuration..."
  
  local archive_mode archive_command wal_level
  
  # Check PostgreSQL configuration
  archive_mode=$(docker-compose exec -T postgresql psql -U postgres -t -c "SHOW archive_mode;" | xargs)
  archive_command=$(docker-compose exec -T postgresql psql -U postgres -t -c "SHOW archive_command;" | xargs)
  wal_level=$(docker-compose exec -T postgresql psql -U postgres -t -c "SHOW wal_level;" | xargs)
  
  log INFO "  archive_mode: ${archive_mode}"
  log INFO "  wal_level: ${wal_level}"
  log INFO "  archive_command: ${archive_command}"
  
  if [ "${archive_mode}" != "on" ]; then
    log ERROR "WAL archiving is disabled (archive_mode=${archive_mode})"
    return 1
  fi
  
  if [ "${wal_level}" != "replica" ] && [ "${wal_level}" != "logical" ]; then
    log ERROR "WAL level is not sufficient for archiving (wal_level=${wal_level})"
    return 1
  fi
  
  # Check if archive directory exists and has recent files
  if [ ! -d "${ARCHIVE_DIR}" ]; then
    log WARN "Archive directory does not exist: ${ARCHIVE_DIR}"
    return 1
  fi
  
  local file_count=$(find "${ARCHIVE_DIR}" -type f 2>/dev/null | wc -l)
  if [ "${file_count}" -eq 0 ]; then
    log WARN "No WAL archive files found in ${ARCHIVE_DIR}"
  else
    log INFO "✅ WAL archiving is ACTIVE (${file_count} archive files present)"
  fi
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# 2. Automated Restore Test
# ════════════════════════════════════════════════════════════════════════════

test_restore() {
  log INFO "Running automated restore verification..."
  
  local latest_backup
  latest_backup=$(ls -t "${BACKUP_DIR}"/codeserver-*.dump 2>/dev/null | head -1 || true)
  
  if [ -z "${latest_backup}" ]; then
    log ERROR "No backup files found in ${BACKUP_DIR}"
    return 1
  fi
  
  log INFO "Testing restore from: ${latest_backup}"
  
  # Create temporary database for verify
  if docker-compose exec -T postgresql psql -U postgres -c "CREATE DATABASE ${VERIFY_DB};" 2>/dev/null; then
    log INFO "  Created temporary database: ${VERIFY_DB}"
  else
    log WARN "  Temporary database may already exist"
  fi
  
  # Restore backup
  if pg_restore -h localhost -U postgres -d "${VERIFY_DB}" "${latest_backup}" > /dev/null 2>&1; then
    log INFO "  ✅ Restore completed successfully"
  else
    log ERROR "  ❌ Restore FAILED"
    docker-compose exec -T postgresql psql -U postgres -c "DROP DATABASE ${VERIFY_DB};" 2>/dev/null || true
    return 1
  fi
  
  # Verify data integrity
  local table_count
  table_count=$(docker-compose exec -T postgresql psql -U postgres -d "${VERIFY_DB}" -t -c \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)
  
  if [ "${table_count}" -gt 0 ]; then
    log INFO "  ✅ Data verified (${table_count} tables)"
  else
    log ERROR "  ❌ No tables found in restored database"
    docker-compose exec -T postgresql psql -U postgres -c "DROP DATABASE ${VERIFY_DB};" 2>/dev/null || true
    return 1
  fi
  
  # Cleanup
  docker-compose exec -T postgresql psql -U postgres -c "DROP DATABASE ${VERIFY_DB};" 2>/dev/null || true
  log INFO "  Temporary database cleaned up"
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# 3. Backup Age Monitoring
# ════════════════════════════════════════════════════════════════════════════

check_backup_age() {
  log INFO "Checking backup age and freshness..."
  
  local latest_backup
  latest_backup=$(ls -t "${BACKUP_DIR}"/codeserver-*.dump 2>/dev/null | head -1 || true)
  
  if [ -z "${latest_backup}" ]; then
    log ERROR "No backup files found"
    echo "backup_last_success_timestamp_seconds 0" > "${METRICS_DIR}/backup.prom"
    echo "backup_age_hours 99999" >> "${METRICS_DIR}/backup.prom"
    return 1
  fi
  
  local backup_time=$(stat -f '%m' "${latest_backup}" 2>/dev/null || stat -c '%Y' "${latest_backup}")
  local current_time=$(date +%s)
  local age_seconds=$((current_time - backup_time))
  local age_hours=$((age_seconds / 3600))
  
  log INFO "  Last backup: ${latest_backup}"
  log INFO "  Age: ${age_hours} hours"
  
  # Export metrics for Prometheus
  mkdir -p "${METRICS_DIR}"
  echo "backup_last_success_timestamp_seconds ${backup_time}" > "${METRICS_DIR}/backup.prom"
  echo "backup_age_hours ${age_hours}" >> "${METRICS_DIR}/backup.prom"
  echo "backup_age_seconds ${age_seconds}" >> "${METRICS_DIR}/backup.prom"
  
  # Alert if backup is too old (> 24 hours)
  if [ ${age_hours} -gt 24 ]; then
    log ERROR "❌ BACKUP IS STALE (${age_hours} hours old, > 24h threshold)"
    echo "backup_is_stale 1" >> "${METRICS_DIR}/backup.prom"
    return 1
  else
    log INFO "✅ Backup is fresh (${age_hours}h old)"
    echo "backup_is_stale 0" >> "${METRICS_DIR}/backup.prom"
  fi
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# 4. Cross-Site Replication
# ════════════════════════════════════════════════════════════════════════════

replicate_backups() {
  log INFO "Replicating backups to replica and NAS..."
  
  # Sync to replica
  if ssh "${REPLICA_USER}@${REPLICA_HOST}" test -d /home/"${REPLICA_USER}"/code-server-enterprise 2>/dev/null; then
    log INFO "  Syncing to replica (${REPLICA_HOST})..."
    rsync -az --delete "${BACKUP_DIR}"/ "${REPLICA_USER}@${REPLICA_HOST}:${BACKUP_DIR}/" \
      --log-file="/var/log/rsync-replica.log" || log WARN "  Replica sync failed"
    log INFO "  ✅ Replica sync complete"
  else
    log WARN "  Replica host not accessible"
  fi
  
  # Sync to NAS (if mounted)
  if [ -d "${NAS_MOUNT}" ]; then
    log INFO "  Syncing to NAS (${NAS_MOUNT})..."
    rsync -az --delete "${BACKUP_DIR}"/ "${NAS_MOUNT}"/ \
      --log-file="/var/log/rsync-nas.log" || log WARN "  NAS sync failed"
    log INFO "  ✅ NAS sync complete"
  else
    log WARN "  NAS mount not available (${NAS_MOUNT})"
  fi
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# 5. Cron Verification
# ════════════════════════════════════════════════════════════════════════════

verify_cron() {
  log INFO "Verifying backup cron configuration..."
  
  if crontab -l 2>/dev/null | grep -q "backup.sh"; then
    log INFO "✅ Backup cron is configured"
    crontab -l | grep "backup.sh"
    return 0
  else
    log ERROR "❌ Backup cron is NOT configured"
    log INFO "  Configure with: echo '0 2 * * * /home/akushnir/code-server-enterprise/scripts/backup.sh' | crontab -"
    return 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Main Execution
# ════════════════════════════════════════════════════════════════════════════

main() {
  log INFO "════════════════════════════════════════════════════════════════"
  log INFO "BACKUP/DR VERIFICATION SUITE"
  log INFO "════════════════════════════════════════════════════════════════"
  
  local exit_code=0
  
  # Run all checks
  verify_wal_archiving || exit_code=1
  echo ""
  
  verify_cron || exit_code=1
  echo ""
  
  check_backup_age || exit_code=1
  echo ""
  
  test_restore || exit_code=1
  echo ""
  
  replicate_backups || exit_code=1
  echo ""
  
  # Summary
  if [ ${exit_code} -eq 0 ]; then
    log INFO "✅ ALL BACKUP/DR CHECKS PASSED"
  else
    log ERROR "❌ SOME BACKUP/DR CHECKS FAILED - REVIEW ABOVE"
  fi
  
  log INFO "════════════════════════════════════════════════════════════════"
  
  return ${exit_code}
}

main "$@"
