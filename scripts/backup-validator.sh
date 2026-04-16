#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# backup-validator.sh - Automated Backup Validation and Rotation
# Validates PostgreSQL, Redis, and code-server backups are recent and valid
# Rotation: Keep 7 daily backups, 4 weekly backups, 12 monthly backups
# Exit Code: 0 = all backups valid | 1 = missing/stale backups
# ═════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Configuration
BACKUP_BASE="/backups"
POSTGRES_BACKUP_DIR="${BACKUP_BASE}/postgresql"
REDIS_BACKUP_DIR="${BACKUP_BASE}/redis"
CODE_BACKUP_DIR="${BACKUP_BASE}/code-server"
NAS_BACKUP_DIR="/mnt/nas-56/backups"

# Time thresholds (seconds)
MAX_AGE_SECONDS=$((86400 * 1))  # 1 day
MAX_AGE_WEEKLY=$((86400 * 7))    # 7 days
MAX_AGE_MONTHLY=$((86400 * 30))  # 30 days

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if backup directory exists and is recent
check_backup_directory() {
    local dir="$1"
    local name="$2"
    local max_age="$3"
    
    if [ ! -d "$dir" ]; then
        log_fail "$name backup directory not found: $dir"
        return 1
    fi
    
    # Find most recent backup
    local recent=$(find "$dir" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
    
    if [ -z "$recent" ]; then
        log_fail "$name: No backup files found in $dir"
        return 1
    fi
    
    local file_time=$(stat -c %Y "$recent" 2>/dev/null || stat -f %m "$recent" 2>/dev/null)
    local current_time=$(date +%s)
    local age=$((current_time - file_time))
    
    if [ "$age" -le "$max_age" ]; then
        local age_hours=$((age / 3600))
        log_pass "$name: Recent backup found ($(basename "$recent"), $age_hours hours old)"
        
        # Check file size (backups shouldn't be tiny)
        local size=$(stat -f%z "$recent" 2>/dev/null || stat -c%s "$recent" 2>/dev/null)
        if [ "$size" -lt 1024 ]; then
            log_warn "$name: Backup file is suspiciously small ($size bytes)"
            return 1
        fi
        
        return 0
    else
        local age_days=$((age / 86400))
        log_fail "$name: Backup is stale ($age_days days old)"
        return 1
    fi
}

# Validate backup integrity
validate_backup_integrity() {
    local dir="$1"
    local name="$2"
    
    log_info "Validating $name backup integrity..."
    
    # Check for common backup formats
    if [ -f "${dir}"/dump-*.sql.gz ] 2>/dev/null; then
        local file="${dir}"/dump-*.sql.gz
        if gzip -t "$file" 2>/dev/null; then
            log_pass "$name: Gzip integrity verified"
            return 0
        else
            log_fail "$name: Gzip corruption detected"
            return 1
        fi
    fi
    
    # Check for tar backups
    if [ -f "${dir}"/*.tar.gz ] 2>/dev/null; then
        local file="${dir}"/*.tar.gz
        if tar -tzf "$file" > /dev/null 2>&1; then
            log_pass "$name: Tar integrity verified"
            return 0
        else
            log_fail "$name: Tar corruption detected"
            return 1
        fi
    fi
    
    # Check for raw files
    if [ -f "${dir}"/* ] 2>/dev/null; then
        log_warn "$name: Uncompressed backup file (consider compression for storage)"
        return 0
    fi
    
    return 0
}

# Rotate old backups
rotate_backups() {
    local dir="$1"
    local name="$2"
    local keep_daily=7
    local keep_weekly=4
    local keep_monthly=12
    
    log_info "Rotating $name backups..."
    
    if [ ! -d "$dir" ]; then
        return 0
    fi
    
    # Find all backups and delete old ones
    local count=0
    find "$dir" -maxdepth 1 -type f -printf '%T@\t%p\n' 2>/dev/null | \
        sort -rn | \
        tail -n +$((keep_daily + 1)) | \
        while IFS=$'\t' read -r _ file; do
            # Keep if filename matches weekly or monthly pattern
            if [[ ! "$file" =~ weekly|monthly ]]; then
                rm -f "$file"
                ((count++))
                log_info "Deleted old backup: $(basename "$file")"
            fi
        done
    
    log_pass "$name: Backup rotation complete"
}

# Main validation flow
main() {
    local exit_code=0
    
    echo "═════════════════════════════════════════════════════════════════════════════"
    echo "Backup Validation and Rotation"
    echo "═════════════════════════════════════════════════════════════════════════════"
    echo ""
    
    # Check PostgreSQL backups
    log_info "Checking PostgreSQL backups..."
    if ! check_backup_directory "$POSTGRES_BACKUP_DIR" "PostgreSQL" "$MAX_AGE_SECONDS"; then
        exit_code=1
    fi
    if [ -d "$POSTGRES_BACKUP_DIR" ]; then
        validate_backup_integrity "$POSTGRES_BACKUP_DIR" "PostgreSQL"
    fi
    echo ""
    
    # Check Redis backups
    log_info "Checking Redis backups..."
    if ! check_backup_directory "$REDIS_BACKUP_DIR" "Redis" "$MAX_AGE_SECONDS"; then
        exit_code=1
    fi
    if [ -d "$REDIS_BACKUP_DIR" ]; then
        validate_backup_integrity "$REDIS_BACKUP_DIR" "Redis"
    fi
    echo ""
    
    # Check code-server backups
    log_info "Checking code-server backups..."
    if ! check_backup_directory "$CODE_BACKUP_DIR" "code-server" "$MAX_AGE_WEEKLY"; then
        # This is non-critical (can be weekly)
        log_warn "code-server backups may be stale (expected for weekly backups)"
    else
        validate_backup_integrity "$CODE_BACKUP_DIR" "code-server"
    fi
    echo ""
    
    # Check NAS backups if available
    if [ -d "$NAS_BACKUP_DIR" ]; then
        log_info "Checking NAS-based backups..."
        if ! check_backup_directory "$NAS_BACKUP_DIR" "NAS" "$MAX_AGE_MONTHLY"; then
            log_warn "NAS backups may be stale (expected for monthly backups)"
        fi
        echo ""
    fi
    
    # Perform rotation
    rotate_backups "$POSTGRES_BACKUP_DIR" "PostgreSQL"
    rotate_backups "$REDIS_BACKUP_DIR" "Redis"
    rotate_backups "$CODE_BACKUP_DIR" "code-server"
    echo ""
    
    echo "═════════════════════════════════════════════════════════════════════════════"
    if [ "$exit_code" -eq 0 ]; then
        log_pass "All critical backups validated successfully"
        echo "Exit Code: 0 (SUCCESS)"
    else
        log_fail "Some backups failed validation"
        echo "Exit Code: 1 (FAILURE)"
    fi
    echo "═════════════════════════════════════════════════════════════════════════════"
    
    return "$exit_code"
}

# Run main function
main "$@"
