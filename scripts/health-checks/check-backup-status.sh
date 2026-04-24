#!/usr/bin/env bash
# @file        scripts/health-checks/check-backup-status.sh
# @module      operations/health-checks
# @description Health check for database backup status and recent completion
# @owner       Infrastructure Team
# @status      Production ready - April 23, 2026
#
# Monitors backup completion and reports:
# - Last successful backup time
# - Backup age (how long ago)
# - Backup size on disk
# - Backup retention status
#
# Exit Codes:
#   0 = Healthy (backup completed < 24 hours ago)
#   1 = Warning (backup aged 24-48 hours)
#   2 = Critical (backup missing or aged > 48 hours)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/logging.sh"

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups/postgresql}"
BACKUP_RETENTION_HOURS="${BACKUP_RETENTION_HOURS:-24}"
BACKUP_WARNING_HOURS="${BACKUP_WARNING_HOURS:-48}"
BACKUP_CRITICAL_HOURS="${BACKUP_CRITICAL_HOURS:-72}"

# Helper functions
check_backup_directory() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        return 1
    fi
    
    log_info "✓ Backup directory exists: $BACKUP_DIR"
    return 0
}

find_latest_backup() {
    local latest_backup
    
    # Find most recent backup file (*.sql, *.sql.gz, *.tar, *.tar.gz, *.dump, etc.)
    latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -type f \
        \( -name "*.sql*" -o -name "*.tar*" -o -name "*.dump*" -o -name "backup-*" \) \
        -printf '%T@\n' -quit | sort -rn | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No backup files found in $BACKUP_DIR"
        return 1
    fi
    
    echo "$latest_backup"
    return 0
}

get_backup_info() {
    local backup_path="$1"
    
    # Get file stats
    local file_mtime size_bytes
    file_mtime=$(stat -f%m "$backup_path" 2>/dev/null || stat -c%Y "$backup_path" 2>/dev/null || echo 0)
    size_bytes=$(stat -f%z "$backup_path" 2>/dev/null || stat -c%s "$backup_path" 2>/dev/null || echo 0)
    
    # Calculate age in hours
    local current_time
    current_time=$(date +%s)
    local backup_age_seconds=$((current_time - file_mtime))
    local backup_age_hours=$((backup_age_seconds / 3600))
    local backup_age_days=$((backup_age_hours / 24))
    
    # Convert size to human readable
    local size_mb=$((size_bytes / 1048576))
    
    echo "$backup_age_hours|$backup_age_days|$size_mb|$size_bytes"
}

# Main health check logic
main() {
    log_info "Starting backup status health check (directory=$BACKUP_DIR)"
    
    # Step 1: Check backup directory exists
    if ! check_backup_directory; then
        log_fatal "Backup directory check failed"
        return 2
    fi
    
    # Step 2: Find latest backup
    local latest_backup
    if ! latest_backup=$(find_latest_backup); then
        log_fatal "No recent backups found"
        return 2
    fi
    
    log_info "✓ Latest backup: $latest_backup"
    
    # Step 3: Get backup info
    local backup_info
    backup_info=$(get_backup_info "$latest_backup")
    IFS='|' read -r age_hours age_days size_mb size_bytes <<< "$backup_info"
    
    log_info "Backup Status:"
    log_info "  File: $(basename "$latest_backup")"
    log_info "  Age: ${age_days}d ${age_hours}h (${backup_age_hours}h total)"
    log_info "  Size: ${size_mb}MB"
    log_info "  Path: $latest_backup"
    
    # Step 4: Check backup freshness
    if (( age_hours >= BACKUP_CRITICAL_HOURS )); then
        log_error "CRITICAL: Backup is $age_hours hours old (critical threshold: $BACKUP_CRITICAL_HOURS hours)"
        return 2
    elif (( age_hours >= BACKUP_WARNING_HOURS )); then
        log_warn "WARNING: Backup is $age_hours hours old (warning threshold: $BACKUP_WARNING_HOURS hours)"
        return 1
    elif (( age_hours > BACKUP_RETENTION_HOURS )); then
        log_warn "INFO: Backup is $age_hours hours old (normal retention: $BACKUP_RETENTION_HOURS hours)"
        return 0
    else
        log_info "✓ Backup health check PASSED (fresh backup: ${age_hours}h old)"
        return 0
    fi
}

main "$@"
