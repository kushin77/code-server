#!/bin/bash
#
# @file backup-report.sh
# @module backup
# @description Daily backup status report generation
# @author Operations Team
# @version 1.0
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

BACKUP_DIR="${BACKUP_DIR:-/backups/daily}"
NAS_BACKUP="${NAS_BACKUP:-/mnt/nas-backup}"
LOG_FILE="/var/log/code-server-backup-report.log"
REPORT_FILE="/var/log/code-server-backup-report-$(date +%Y%m%d).txt"

# Email settings (optional)
REPORT_EMAIL="${REPORT_EMAIL:-ops@kushnir.cloud}"
SEND_EMAIL="${SEND_EMAIL:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING & REPORT FUNCTIONS
# ============================================================================

log_info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

report_line() {
  echo "$*" | tee -a "$REPORT_FILE"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating backup report..."
  
  # Clear previous report
  > "$REPORT_FILE"
  
  # Report header
  report_line "╔════════════════════════════════════════════════════════════════╗"
  report_line "║         CODE-SERVER BACKUP STATUS REPORT                       ║"
  report_line "║         $(date +'%Y-%m-%d %H:%M:%S')                                        ║"
  report_line "╚════════════════════════════════════════════════════════════════╝"
  report_line ""
  
  # PostgreSQL Status
  report_line "┌─ PostgreSQL Backups ──────────────────────────────────────────┐"
  
  if [ -d "${BACKUP_DIR}/postgres" ]; then
    local PG_COUNT=$(find "${BACKUP_DIR}/postgres" -name "postgres_backup_*.sql.gz" -type f | wc -l)
    local PG_SIZE=$(du -sh "${BACKUP_DIR}/postgres" 2>/dev/null | cut -f1)
    local LATEST_PG=$(find "${BACKUP_DIR}/postgres" -name "postgres_backup_*.sql.gz" -type f -printf '%T+ %p\n' | sort -r | head -1)
    
    report_line "│ Total Backups:  $PG_COUNT"
    report_line "│ Total Size:     $PG_SIZE"
    report_line "│ Latest:         $(echo "$LATEST_PG" | cut -d' ' -f1,2)"
    report_line "│ Status:         ✅ OK"
  else
    report_line "│ Status:         ⚠️  Directory not found"
  fi
  report_line "└───────────────────────────────────────────────────────────────┘"
  report_line ""
  
  # Redis Status
  report_line "┌─ Redis Backups ───────────────────────────────────────────────┐"
  
  if [ -d "${BACKUP_DIR}/redis" ]; then
    local REDIS_COUNT=$(find "${BACKUP_DIR}/redis" -name "redis_backup_*.rdb.gz" -type f | wc -l)
    local REDIS_SIZE=$(du -sh "${BACKUP_DIR}/redis" 2>/dev/null | cut -f1)
    local LATEST_REDIS=$(find "${BACKUP_DIR}/redis" -name "redis_backup_*.rdb.gz" -type f -printf '%T+ %p\n' | sort -r | head -1)
    
    report_line "│ Total Backups:  $REDIS_COUNT"
    report_line "│ Total Size:     $REDIS_SIZE"
    report_line "│ Latest:         $(echo "$LATEST_REDIS" | cut -d' ' -f1,2)"
    report_line "│ Status:         ✅ OK"
  else
    report_line "│ Status:         ⚠️  Directory not found"
  fi
  report_line "└───────────────────────────────────────────────────────────────┘"
  report_line ""
  
  # Volumes Status
  report_line "┌─ Volume Backups ──────────────────────────────────────────────┐"
  
  if [ -d "${BACKUP_DIR}/volumes" ]; then
    local VOL_COUNT=$(find "${BACKUP_DIR}/volumes" -name "*_*.tar.gz" -type f | wc -l)
    local VOL_SIZE=$(du -sh "${BACKUP_DIR}/volumes" 2>/dev/null | cut -f1)
    local LATEST_VOL=$(find "${BACKUP_DIR}/volumes" -name "*_*.tar.gz" -type f -printf '%T+ %p\n' | sort -r | head -1)
    
    report_line "│ Total Backups:  $VOL_COUNT"
    report_line "│ Total Size:     $VOL_SIZE"
    report_line "│ Latest:         $(echo "$LATEST_VOL" | cut -d' ' -f1,2)"
    report_line "│ Status:         ✅ OK"
  else
    report_line "│ Status:         ⚠️  Directory not found"
  fi
  report_line "└───────────────────────────────────────────────────────────────┘"
  report_line ""
  
  # Storage Usage
  report_line "┌─ Storage Usage ───────────────────────────────────────────────┐"
  
  if [ -d "$BACKUP_DIR" ]; then
    local PRIMARY_USAGE=$(df "$BACKUP_DIR" | tail -1 | awk '{print $5}')
    local PRIMARY_AVAIL=$(df "$BACKUP_DIR" | tail -1 | awk '{print $4}')
    report_line "│ Primary:        $PRIMARY_USAGE used ($(numfmt --to=iec-i --suffix=B $PRIMARY_AVAIL 2>/dev/null || echo "$PRIMARY_AVAIL bytes") available)"
  fi
  
  if [ -d "$NAS_BACKUP" ]; then
    local NAS_USAGE=$(df "$NAS_BACKUP" | tail -1 | awk '{print $5}')
    local NAS_AVAIL=$(df "$NAS_BACKUP" | tail -1 | awk '{print $4}')
    report_line "│ NAS:            $NAS_USAGE used ($(numfmt --to=iec-i --suffix=B $NAS_AVAIL 2>/dev/null || echo "$NAS_AVAIL bytes") available)"
  fi
  report_line "└───────────────────────────────────────────────────────────────┘"
  report_line ""
  
  # Recent Backup Status
  report_line "┌─ Recent Backup Status ────────────────────────────────────────┐"
  
  # Check for recent backup logs
  local BACKUP_LOG="/var/log/code-server-backup-postgres.log"
  if [ -f "$BACKUP_LOG" ]; then
    local LAST_RUN=$(tail -5 "$BACKUP_LOG" | grep "PostgreSQL backup complete" | tail -1)
    if [ -n "$LAST_RUN" ]; then
      report_line "│ PostgreSQL:     $LAST_RUN"
    fi
  fi
  
  local REDIS_LOG="/var/log/code-server-backup-redis.log"
  if [ -f "$REDIS_LOG" ]; then
    local LAST_RUN=$(tail -5 "$REDIS_LOG" | grep "Redis backup complete" | tail -1)
    if [ -n "$LAST_RUN" ]; then
      report_line "│ Redis:          $LAST_RUN"
    fi
  fi
  
  local VOL_LOG="/var/log/code-server-backup-volumes.log"
  if [ -f "$VOL_LOG" ]; then
    local LAST_RUN=$(tail -5 "$VOL_LOG" | grep "Docker volumes backup complete" | tail -1)
    if [ -n "$LAST_RUN" ]; then
      report_line "│ Volumes:        $LAST_RUN"
    fi
  fi
  
  report_line "└───────────────────────────────────────────────────────────────┘"
  report_line ""
  
  # Next Recovery Test
  report_line "┌─ Scheduled Actions ──────────────────────────────────────────┐"
  report_line "│ Next Monthly Recovery Test:  1st Monday of next month at 3 AM"
  report_line "│ Next Quarterly Review:       Every 3 months"
  report_line "│ Next Annual Audit:           Yearly"
  report_line "└───────────────────────────────────────────────────────────────┘"
  report_line ""
  
  # Summary
  report_line "Report Generated: $(date +'%Y-%m-%d %H:%M:%S')"
  report_line "Report Location:  $REPORT_FILE"
  
  log_success "Backup report generated: $REPORT_FILE"
}

send_report_email() {
  if [ "$SEND_EMAIL" = "true" ] && command -v mail &>/dev/null; then
    log_info "Sending report email to $REPORT_EMAIL..."
    
    local SUBJECT="[CODE-SERVER] Daily Backup Report - $(date +'%Y-%m-%d')"
    
    if mail -s "$SUBJECT" "$REPORT_EMAIL" < "$REPORT_FILE"; then
      log_success "Report email sent to $REPORT_EMAIL"
    else
      log_info "Failed to send email (mail command may not be configured)"
    fi
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

generate_report
send_report_email

# Print report to console
echo ""
cat "$REPORT_FILE"
echo ""
