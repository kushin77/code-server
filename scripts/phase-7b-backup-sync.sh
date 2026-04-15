#!/bin/bash
# Phase 7b: NAS Backup Synchronization Script
# Purpose: Sync PostgreSQL and Redis backups from primary (192.168.168.31) to NAS
# Frequency: Hourly cron job
# Target NAS: 192.168.168.55:/export (mounted at /mnt/nas-export or /nas)

set -e

# Configuration
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
NAS_MOUNT="/mnt/nas-export"
BACKUP_DIR="${NAS_MOUNT}/backups"
POSTGRES_BACKUP_DIR="${BACKUP_DIR}/postgresql"
REDIS_BACKUP_DIR="${BACKUP_DIR}/redis"
LOG_FILE="/var/log/phase-7b-backup-sync.log"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Check NAS mount
check_nas_mount() {
    if ! mountpoint -q "${NAS_MOUNT}"; then
        log_error "NAS not mounted at ${NAS_MOUNT}"
        exit 1
    fi
    log "✅ NAS mounted at ${NAS_MOUNT}"
}

# Create backup directories
create_backup_dirs() {
    mkdir -p "${POSTGRES_BACKUP_DIR}" "${REDIS_BACKUP_DIR}"
    log "✅ Backup directories created"
}

# Backup PostgreSQL database
backup_postgresql() {
    log "Starting PostgreSQL backup..."
    
    local backup_file="${POSTGRES_BACKUP_DIR}/backup-$(date +%Y%m%d-%H%M%S).sql.gz"
    
    ssh akushnir@${PRIMARY_HOST} \
        "docker exec postgres pg_dump -U codeserver -d codeserver | gzip" \
        > "${backup_file}" 2>>"${LOG_FILE}"
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "${backup_file}" | awk '{print $1}')
        log_success "PostgreSQL backup completed: ${backup_file} (${size})"
    else
        log_error "PostgreSQL backup failed"
        return 1
    fi
}

# Backup Redis database
backup_redis() {
    log "Starting Redis backup..."
    
    local backup_file="${REDIS_BACKUP_DIR}/redis-dump-$(date +%Y%m%d-%H%M%S).rdb"
    
    # SSH to primary and bgsave, then copy dump.rdb
    ssh akushnir@${PRIMARY_HOST} \
        "docker exec redis redis-cli -a redis-secure-default BGSAVE && sleep 2" 2>>"${LOG_FILE}"
    
    # Copy redis dump.rdb from primary
    ssh akushnir@${PRIMARY_HOST} \
        "docker exec redis cat /data/dump.rdb" \
        > "${backup_file}" 2>>"${LOG_FILE}"
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "${backup_file}" | awk '{print $1}')
        log_success "Redis backup completed: ${backup_file} (${size})"
    else
        log_error "Redis backup failed"
        return 1
    fi
}

# Verify backup integrity
verify_backups() {
    log "Verifying backup integrity..."
    
    # Check PostgreSQL dump
    if gzip -t "${POSTGRES_BACKUP_DIR}"/*.sql.gz 2>/dev/null; then
        log_success "PostgreSQL backups verified (gzip integrity OK)"
    else
        log_error "PostgreSQL backup verification failed"
        return 1
    fi
    
    # Check Redis dump
    if [ -s "${REDIS_BACKUP_DIR}"/*.rdb ]; then
        log_success "Redis backups verified (size > 0)"
    else
        log_error "Redis backup verification failed (zero size)"
        return 1
    fi
}

# Report backup status
report_status() {
    log "=== Backup Summary ==="
    
    echo "PostgreSQL backups:" >> "${LOG_FILE}"
    ls -lh "${POSTGRES_BACKUP_DIR}"/ 2>/dev/null | tail -5 >> "${LOG_FILE}"
    
    echo "Redis backups:" >> "${LOG_FILE}"
    ls -lh "${REDIS_BACKUP_DIR}"/ 2>/dev/null | tail -5 >> "${LOG_FILE}"
    
    echo "NAS usage:" >> "${LOG_FILE}"
    du -sh "${BACKUP_DIR}" >> "${LOG_FILE}"
    
    log_success "Backup synchronization complete"
}

# Cleanup old backups (keep last 30 days)
cleanup_old_backups() {
    log "Cleaning up backups older than 30 days..."
    
    find "${POSTGRES_BACKUP_DIR}" -name "backup-*.sql.gz" -mtime +30 -delete
    find "${REDIS_BACKUP_DIR}" -name "redis-dump-*.rdb" -mtime +30 -delete
    
    log_success "Cleanup complete"
}

# Main execution
main() {
    log "=========================================="
    log "Phase 7b: NAS Backup Synchronization"
    log "=========================================="
    
    check_nas_mount
    create_backup_dirs
    
    if backup_postgresql; then
        log "PostgreSQL backup successful"
    else
        log_error "PostgreSQL backup failed - continuing"
    fi
    
    if backup_redis; then
        log "Redis backup successful"
    else
        log_error "Redis backup failed - continuing"
    fi
    
    verify_backups
    report_status
    cleanup_old_backups
    
    log "=========================================="
}

# Execute main
main
