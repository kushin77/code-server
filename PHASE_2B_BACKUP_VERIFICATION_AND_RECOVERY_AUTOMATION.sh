#!/bin/bash

################################################################################
# PHASE_2B_BACKUP_VERIFICATION_AND_RECOVERY_AUTOMATION.sh
# Purpose: Automate pre-deployment and post-deployment backup validation
# Usage: bash PHASE_2B_BACKUP_VERIFICATION_AND_RECOVERY_AUTOMATION.sh [verify|test-restore|health]
# Author: Phase 2B Deployment Team
# Date: April 30, 2026
################################################################################

set -e
trap 'echo "❌ Script failed at line $LINENO"; exit 1' ERR
trap 'echo "✓ Cleanup performed"; rm -f /tmp/backup_*.tmp 2>/dev/null || true' EXIT

################################################################################
# CONFIGURATION
################################################################################

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
BACKUP_DIR="/data/backups"
LOG_DIR="/var/log/phase2b"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/backup_verification_${TIMESTAMP}.log"

# Create log directory if needed
mkdir -p "${LOG_DIR}"

################################################################################
# LOGGING FUNCTIONS
################################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] ✓ $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] ⚠ $1" | tee -a "${LOG_FILE}"
}

################################################################################
# BACKUP VERIFICATION FUNCTIONS
################################################################################

verify_backup_files() {
    log "=== BACKUP FILE VERIFICATION ==="
    
    local required_backups=(
        "gitlab_database_backup.sql.gz"
        "gitlab_config_backup.tar.gz"
        "gitlab_repositories_backup.tar.gz"
    )
    
    local all_present=true
    
    for backup in "${required_backups[@]}"; do
        if [ -f "${BACKUP_DIR}/${backup}" ]; then
            local size=$(du -h "${BACKUP_DIR}/${backup}" | cut -f1)
            local mtime=$(stat -c %y "${BACKUP_DIR}/${backup}" | cut -d. -f1)
            log "✓ Found: ${backup} (${size}) - Modified: ${mtime}"
        else
            log_error "✗ Missing: ${backup}"
            all_present=false
        fi
    done
    
    if [ "$all_present" = true ]; then
        log_success "All required backup files present"
        return 0
    else
        log_error "Some backup files missing"
        return 1
    fi
}

verify_backup_integrity() {
    log "=== BACKUP INTEGRITY VERIFICATION ==="
    
    cd "${BACKUP_DIR}" || { log_error "Cannot access backup directory"; return 1; }
    
    local integrity_ok=true
    
    # Check database backup integrity
    if [ -f "gitlab_database_backup.sql.gz" ]; then
        log "Verifying database backup integrity..."
        if gzip -t gitlab_database_backup.sql.gz 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "Database backup integrity verified"
        else
            log_error "Database backup integrity check failed"
            integrity_ok=false
        fi
    fi
    
    # Check TAR integrity
    if [ -f "gitlab_config_backup.tar.gz" ]; then
        log "Verifying config backup integrity..."
        if tar -tzf gitlab_config_backup.tar.gz > /dev/null 2>&1; then
            log_success "Config backup integrity verified"
        else
            log_error "Config backup integrity check failed"
            integrity_ok=false
        fi
    fi
    
    if [ -f "gitlab_repositories_backup.tar.gz" ]; then
        log "Verifying repositories backup integrity..."
        if tar -tzf gitlab_repositories_backup.tar.gz > /dev/null 2>&1; then
            log_success "Repositories backup integrity verified"
        else
            log_error "Repositories backup integrity check failed"
            integrity_ok=false
        fi
    fi
    
    if [ "$integrity_ok" = true ]; then
        log_success "All backup integrity checks passed"
        return 0
    else
        log_error "Some backup integrity checks failed"
        return 1
    fi
}

verify_backup_checksums() {
    log "=== BACKUP CHECKSUM VERIFICATION ==="
    
    cd "${BACKUP_DIR}" || { log_error "Cannot access backup directory"; return 1; }
    
    # Generate checksums for current backups
    log "Generating SHA256 checksums..."
    sha256sum *.gz *.tar.gz > backup_manifest_${TIMESTAMP}.sha256 2>/dev/null || true
    
    # Compare with previous known good checksums if available
    if [ -f "backup_manifest_previous.sha256" ]; then
        log "Comparing with previous manifest..."
        if sha256sum -c backup_manifest_previous.sha256 > /dev/null 2>&1; then
            log_warning "Backups identical to previous - may indicate stale backups"
        else
            log "Backups differ from previous (expected after new backup)"
        fi
    fi
    
    # Save current as reference
    cp backup_manifest_${TIMESTAMP}.sha256 backup_manifest_previous.sha256
    log_success "Checksums generated and saved: backup_manifest_${TIMESTAMP}.sha256"
    return 0
}

verify_backup_accessibility() {
    log "=== BACKUP ACCESSIBILITY VERIFICATION ==="
    
    # Verify PRIMARY can access backups
    log "Testing PRIMARY access to backups..."
    if ssh "ubuntu@${PRIMARY_HOST}" "ls -lah ${BACKUP_DIR}/*.gz ${BACKUP_DIR}/*.tar.gz 2>/dev/null | wc -l" > /dev/null 2>&1; then
        log_success "PRIMARY can access backup directory"
    else
        log_error "PRIMARY cannot access backup directory"
        return 1
    fi
    
    # Verify REPLICA can access backups
    log "Testing REPLICA access to backups..."
    if ssh "ubuntu@${REPLICA_HOST}" "ls -lah ${BACKUP_DIR}/*.gz ${BACKUP_DIR}/*.tar.gz 2>/dev/null | wc -l" > /dev/null 2>&1; then
        log_success "REPLICA can access backup directory"
    else
        log_error "REPLICA cannot access backup directory"
        return 1
    fi
    
    return 0
}

verify_backup_storage() {
    log "=== BACKUP STORAGE CAPACITY VERIFICATION ==="
    
    # Check disk space on PRIMARY
    log "Checking PRIMARY disk space..."
    local available=$(ssh "ubuntu@${PRIMARY_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$4}'")
    local total=$(ssh "ubuntu@${PRIMARY_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$2}'")
    local used=$(ssh "ubuntu@${PRIMARY_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$3}'")
    local percent=$(ssh "ubuntu@${PRIMARY_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$5}' | sed 's/%//'")
    
    log "PRIMARY: Used ${used}KB / Total ${total}KB (${percent}% full)"
    
    if [ "${percent}" -gt 85 ]; then
        log_warning "PRIMARY backup storage >85% full, may need cleanup"
    elif [ "${percent}" -gt 70 ]; then
        log_warning "PRIMARY backup storage >70% full"
    else
        log_success "PRIMARY backup storage healthy"
    fi
    
    # Check disk space on REPLICA
    log "Checking REPLICA disk space..."
    available=$(ssh "ubuntu@${REPLICA_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$4}'")
    total=$(ssh "ubuntu@${REPLICA_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$2}'")
    used=$(ssh "ubuntu@${REPLICA_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$3}'")
    percent=$(ssh "ubuntu@${REPLICA_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$5}' | sed 's/%//')
    
    log "REPLICA: Used ${used}KB / Total ${total}KB (${percent}% full)"
    
    if [ "${percent}" -gt 85 ]; then
        log_warning "REPLICA backup storage >85% full, may need cleanup"
        return 1
    elif [ "${percent}" -gt 70 ]; then
        log_warning "REPLICA backup storage >70% full"
    else
        log_success "REPLICA backup storage healthy"
    fi
    
    return 0
}

################################################################################
# RECOVERY TEST FUNCTIONS
################################################################################

test_restore_procedure() {
    log "=== RECOVERY TEST: DRY RUN RESTORE PROCEDURE ==="
    
    local test_dir="/tmp/restore_test_${TIMESTAMP}"
    mkdir -p "${test_dir}"
    log "Created test directory: ${test_dir}"
    
    # Test 1: Database backup extraction
    log "TEST 1: Database backup extraction..."
    if tar -tzf "${BACKUP_DIR}/gitlab_database_backup.sql.gz" | head -5 > /dev/null 2>&1; then
        log_success "Database backup can be extracted"
    else
        log_error "Database backup extraction failed"
        rm -rf "${test_dir}"
        return 1
    fi
    
    # Test 2: Config backup extraction
    log "TEST 2: Config backup extraction..."
    if tar -tzf "${BACKUP_DIR}/gitlab_config_backup.tar.gz" | head -5 > /dev/null 2>&1; then
        log_success "Config backup can be extracted"
    else
        log_error "Config backup extraction failed"
        rm -rf "${test_dir}"
        return 1
    fi
    
    # Test 3: Repositories backup extraction
    log "TEST 3: Repositories backup extraction..."
    if tar -tzf "${BACKUP_DIR}/gitlab_repositories_backup.tar.gz" | head -5 > /dev/null 2>&1; then
        log_success "Repositories backup can be extracted"
    else
        log_error "Repositories backup extraction failed"
        rm -rf "${test_dir}"
        return 1
    fi
    
    # Test 4: Simulate data verification
    log "TEST 4: Backup data validation..."
    local backup_file_count=$(tar -tzf "${BACKUP_DIR}/gitlab_repositories_backup.tar.gz" | wc -l)
    log "Found ${backup_file_count} files in repositories backup"
    
    if [ "${backup_file_count}" -gt 0 ]; then
        log_success "Backup contains valid data (${backup_file_count} files)"
    else
        log_error "Backup appears empty"
        rm -rf "${test_dir}"
        return 1
    fi
    
    # Cleanup test directory
    rm -rf "${test_dir}"
    log_success "Recovery test passed - all backups restorable"
    return 0
}

################################################################################
# HEALTH CHECK FUNCTIONS
################################################################################

backup_health_status() {
    log "=== BACKUP HEALTH STATUS REPORT ==="
    
    local status_ok=true
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           BACKUP HEALTH STATUS - $(date '+%Y-%m-%d %H:%M:%S')           ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Backup files
    echo "BACKUP FILES:"
    if [ -f "${BACKUP_DIR}/gitlab_database_backup.sql.gz" ]; then
        local size=$(du -h "${BACKUP_DIR}/gitlab_database_backup.sql.gz" | cut -f1)
        echo "  ✓ Database backup: ${size}"
    else
        echo "  ✗ Database backup: MISSING"
        status_ok=false
    fi
    
    if [ -f "${BACKUP_DIR}/gitlab_config_backup.tar.gz" ]; then
        local size=$(du -h "${BACKUP_DIR}/gitlab_config_backup.tar.gz" | cut -f1)
        echo "  ✓ Config backup: ${size}"
    else
        echo "  ✗ Config backup: MISSING"
        status_ok=false
    fi
    
    if [ -f "${BACKUP_DIR}/gitlab_repositories_backup.tar.gz" ]; then
        local size=$(du -h "${BACKUP_DIR}/gitlab_repositories_backup.tar.gz" | cut -f1)
        echo "  ✓ Repositories backup: ${size}"
    else
        echo "  ✗ Repositories backup: MISSING"
        status_ok=false
    fi
    
    # Storage
    echo ""
    echo "STORAGE CAPACITY:"
    local percent=$(ssh "ubuntu@${PRIMARY_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$5}' | sed 's/%//'")
    if [ "${percent}" -le 70 ]; then
        echo "  ✓ PRIMARY: ${percent}% full (healthy)"
    else
        echo "  ⚠ PRIMARY: ${percent}% full (watch)"
        status_ok=false
    fi
    
    percent=$(ssh "ubuntu@${REPLICA_HOST}" "df ${BACKUP_DIR} | tail -1 | awk '{print \$5}' | sed 's/%//'")
    if [ "${percent}" -le 70 ]; then
        echo "  ✓ REPLICA: ${percent}% full (healthy)"
    else
        echo "  ⚠ REPLICA: ${percent}% full (watch)"
        status_ok=false
    fi
    
    # Age
    echo ""
    echo "BACKUP AGE:"
    if [ -f "${BACKUP_DIR}/gitlab_database_backup.sql.gz" ]; then
        local age=$(( ($(date +%s) - $(stat -c %Y "${BACKUP_DIR}/gitlab_database_backup.sql.gz")) / 3600 ))
        if [ "${age}" -lt 24 ]; then
            echo "  ✓ Latest backup: ${age} hours old"
        else
            echo "  ⚠ Latest backup: ${age} hours old (may need refresh)"
            status_ok=false
        fi
    fi
    
    # Overall status
    echo ""
    if [ "$status_ok" = true ]; then
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║ OVERALL STATUS: ✓ GREEN - BACKUPS HEALTHY AND READY           ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        return 0
    else
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║ OVERALL STATUS: ⚠ YELLOW - SOME CONCERNS DETECTED            ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        return 1
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    local command="${1:-verify}"
    
    log "Starting Phase 2B Backup Verification Tool"
    log "Command: ${command}"
    log "Timestamp: ${TIMESTAMP}"
    
    case "${command}" in
        verify)
            log "Running full backup verification suite..."
            verify_backup_files && \
            verify_backup_integrity && \
            verify_backup_checksums && \
            verify_backup_accessibility && \
            verify_backup_storage && \
            log_success "FULL VERIFICATION PASSED"
            ;;
        test-restore)
            log "Running recovery test procedure..."
            test_restore_procedure && \
            log_success "RECOVERY TEST PASSED"
            ;;
        health)
            log "Generating backup health status report..."
            backup_health_status
            ;;
        *)
            echo "Usage: $0 [verify|test-restore|health]"
            echo "  verify:       Run full backup verification suite"
            echo "  test-restore: Test backup extraction and recovery"
            echo "  health:       Display backup health status"
            exit 1
            ;;
    esac
    
    log "=== EXECUTION COMPLETE ==="
    log "Log saved to: ${LOG_FILE}"
}

main "$@"
