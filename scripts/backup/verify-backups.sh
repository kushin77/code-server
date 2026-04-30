#!/bin/bash
#
# @file verify-backups.sh
# @module backup
# @description Backup verification and integrity checking
# @author Operations Team
# @version 1.0
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

BACKUP_DIR="${BACKUP_DIR:-/backups/daily}"
NAS_BACKUP="${NAS_BACKUP:-/mnt/nas-backup}"
LOG_FILE="/var/log/code-server-backup-verify.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# VERIFICATION FUNCTIONS
# ============================================================================

verify_postgres_backups() {
  log_info "Verifying PostgreSQL backups..."
  local POSTGRES_DIR="${BACKUP_DIR}/postgres"
  
  if [ ! -d "$POSTGRES_DIR" ]; then
    log_warning "PostgreSQL backup directory not found"
    return 1
  fi
  
  local BACKUP_COUNT=$(find "$POSTGRES_DIR" -name "postgres_backup_*.sql.gz" -type f | wc -l)
  local TOTAL_SIZE=$(du -sh "$POSTGRES_DIR" 2>/dev/null | cut -f1)
  
  if [ "$BACKUP_COUNT" -eq 0 ]; then
    log_error "No PostgreSQL backups found in $POSTGRES_DIR"
    return 1
  fi
  
  # Check latest backup age
  local LATEST_BACKUP=$(find "$POSTGRES_DIR" -name "postgres_backup_*.sql.gz" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
  local LATEST_TIME=$(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || stat -f %m "$LATEST_BACKUP" 2>/dev/null)
  local CURRENT_TIME=$(date +%s)
  local AGE=$(( (CURRENT_TIME - LATEST_TIME) / 3600 ))
  
  if [ "$AGE" -gt 2 ]; then
    log_warning "Latest PostgreSQL backup is $AGE hours old (should be <2h)"
  else
    log_success "PostgreSQL backups verified: $BACKUP_COUNT files, $TOTAL_SIZE, latest $AGE hours old"
  fi
}

verify_redis_backups() {
  log_info "Verifying Redis backups..."
  local REDIS_DIR="${BACKUP_DIR}/redis"
  
  if [ ! -d "$REDIS_DIR" ]; then
    log_warning "Redis backup directory not found"
    return 1
  fi
  
  local BACKUP_COUNT=$(find "$REDIS_DIR" -name "redis_backup_*.rdb.gz" -type f | wc -l)
  local TOTAL_SIZE=$(du -sh "$REDIS_DIR" 2>/dev/null | cut -f1)
  
  if [ "$BACKUP_COUNT" -eq 0 ]; then
    log_error "No Redis backups found in $REDIS_DIR"
    return 1
  fi
  
  # Check latest backup age
  local LATEST_BACKUP=$(find "$REDIS_DIR" -name "redis_backup_*.rdb.gz" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
  local LATEST_TIME=$(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || stat -f %m "$LATEST_BACKUP" 2>/dev/null)
  local CURRENT_TIME=$(date +%s)
  local AGE=$(( (CURRENT_TIME - LATEST_TIME) / 3600 ))
  
  if [ "$AGE" -gt 2 ]; then
    log_warning "Latest Redis backup is $AGE hours old (should be <2h)"
  else
    log_success "Redis backups verified: $BACKUP_COUNT files, $TOTAL_SIZE, latest $AGE hours old"
  fi
}

verify_volume_backups() {
  log_info "Verifying Volume backups..."
  local VOLUMES_DIR="${BACKUP_DIR}/volumes"
  
  if [ ! -d "$VOLUMES_DIR" ]; then
    log_warning "Volumes backup directory not found"
    return 1
  fi
  
  local BACKUP_COUNT=$(find "$VOLUMES_DIR" -name "*_*.tar.gz" -type f | wc -l)
  local TOTAL_SIZE=$(du -sh "$VOLUMES_DIR" 2>/dev/null | cut -f1)
  
  if [ "$BACKUP_COUNT" -eq 0 ]; then
    log_error "No volume backups found in $VOLUMES_DIR"
    return 1
  fi
  
  # Check latest backup age
  local LATEST_BACKUP=$(find "$VOLUMES_DIR" -name "*_*.tar.gz" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
  local LATEST_TIME=$(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || stat -f %m "$LATEST_BACKUP" 2>/dev/null)
  local CURRENT_TIME=$(date +%s)
  local AGE=$(( (CURRENT_TIME - LATEST_TIME) / 86400 ))
  
  if [ "$AGE" -gt 1 ]; then
    log_warning "Latest volume backup is $AGE days old (should be <1d)"
  else
    log_success "Volume backups verified: $BACKUP_COUNT files, $TOTAL_SIZE"
  fi
}

verify_disk_space() {
  log_info "Verifying disk space..."
  
  local PRIMARY_USAGE=$(df "$BACKUP_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
  log_info "Primary backup disk usage: $PRIMARY_USAGE%"
  
  if [ "$PRIMARY_USAGE" -gt 95 ]; then
    log_error "Primary backup disk CRITICAL (>95%)"
    return 1
  elif [ "$PRIMARY_USAGE" -gt 85 ]; then
    log_warning "Primary backup disk high (>85%)"
  else
    log_success "Primary backup disk space OK ($PRIMARY_USAGE%)"
  fi
  
  if [ -d "$NAS_BACKUP" ]; then
    local NAS_USAGE=$(df "$NAS_BACKUP" | tail -1 | awk '{print $5}' | sed 's/%//')
    log_info "NAS backup disk usage: $NAS_USAGE%"
    
    if [ "$NAS_USAGE" -gt 95 ]; then
      log_error "NAS backup disk CRITICAL (>95%)"
      return 1
    elif [ "$NAS_USAGE" -gt 85 ]; then
      log_warning "NAS backup disk high (>85%)"
    else
      log_success "NAS backup disk space OK ($NAS_USAGE%)"
    fi
  fi
}

verify_backup_integrity() {
  log_info "Verifying backup file integrity..."
  
  local ERRORS=0
  
  # Check PostgreSQL backups for corruption
  if [ -d "${BACKUP_DIR}/postgres" ]; then
    while IFS= read -r backup; do
      if ! file "$backup" | grep -q gzip; then
        log_error "PostgreSQL backup corruption detected: $(basename $backup)"
        ((ERRORS++))
      fi
    done < <(find "${BACKUP_DIR}/postgres" -name "*.sql.gz" -type f)
  fi
  
  # Check Redis backups for corruption
  if [ -d "${BACKUP_DIR}/redis" ]; then
    while IFS= read -r backup; do
      if ! file "$backup" | grep -q gzip; then
        log_error "Redis backup corruption detected: $(basename $backup)"
        ((ERRORS++))
      fi
    done < <(find "${BACKUP_DIR}/redis" -name "*.rdb.gz" -type f)
  fi
  
  if [ $ERRORS -eq 0 ]; then
    log_success "All backup files passed integrity checks"
  else
    log_error "$ERRORS backup files failed integrity checks"
    return 1
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log_info "Starting backup verification..."
echo ""

VERIFICATION_FAILED=0

verify_postgres_backups || ((VERIFICATION_FAILED++))
verify_redis_backups || ((VERIFICATION_FAILED++))
verify_volume_backups || ((VERIFICATION_FAILED++))
verify_disk_space || ((VERIFICATION_FAILED++))
verify_backup_integrity || ((VERIFICATION_FAILED++))

echo ""
if [ $VERIFICATION_FAILED -eq 0 ]; then
  log_success "All backup verifications passed ✅"
  exit 0
else
  log_error "$VERIFICATION_FAILED verification(s) failed ❌"
  exit 1
fi
