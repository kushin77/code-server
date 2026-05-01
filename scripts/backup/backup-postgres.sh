#!/bin/bash
#
# @file backup-postgres.sh
# @module backup
# @description PostgreSQL automated backup script with compression and archival
# @author Operations Team
# @version 1.0
#

set -euo pipefail

# ============================================================================
# ERROR HANDLING
# ============================================================================

trap 'log_error "PostgreSQL backup failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/pg_backup_*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# CONFIGURATION
# ============================================================================

BACKUP_DIR="${BACKUP_DIR:-/backups/daily/postgres}"
NAS_BACKUP="${NAS_BACKUP:-/mnt/nas-backup/postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
LOG_FILE="/var/log/code-server-backup-postgres.log"

# PostgreSQL connection settings
export PGHOST="${POSTGRES_HOST:-localhost}"
export PGPORT="${POSTGRES_PORT:-5432}"
export PGUSER="${POSTGRES_USER:-postgres}"
export PGPASSWORD="${POSTGRES_PASSWORD:-}"
export PGDATABASE="postgres"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
# MAIN BACKUP LOGIC
# ============================================================================

# Create backup directories
mkdir -p "$BACKUP_DIR" "$NAS_BACKUP"

# Generate backup filename with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="postgres_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

log_info "Starting PostgreSQL backup: $BACKUP_NAME"

# Verify PostgreSQL connectivity
log_info "Verifying PostgreSQL connectivity at $PGHOST:$PGPORT..."
if ! pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" >/dev/null 2>&1; then
  log_error "Cannot connect to PostgreSQL at $PGHOST:$PGPORT"
  exit 1
fi
log_success "PostgreSQL connection verified"

# Perform logical backup (SQL dump) with compression
log_info "Creating logical backup (SQL dump with compression)..."
if pg_dump \
  -h "$PGHOST" \
  -p "$PGPORT" \
  -U "$PGUSER" \
  --format=custom \
  --compress=9 \
  --verbose \
  --create \
  --quote-all-identifiers \
  --jobs=4 \
  --file="${BACKUP_PATH}.sql.gz" \
  2>&1 | tee -a "$LOG_FILE"; then
  log_success "Logical backup created: ${BACKUP_PATH}.sql.gz"
else
  log_error "Failed to create logical backup"
  exit 1
fi

# Get backup file size
BACKUP_SIZE=$(du -h "${BACKUP_PATH}.sql.gz" | cut -f1)
log_info "Backup size: $BACKUP_SIZE"

# Verify backup integrity (check it's valid gzip)
log_info "Verifying backup integrity..."
if file "${BACKUP_PATH}.sql.gz" | grep -q gzip; then
  log_success "Backup integrity verified (valid gzip)"
else
  log_error "Backup file is not valid gzip"
  exit 1
fi

# Copy to NAS backup location
if [ -d "$NAS_BACKUP" ]; then
  log_info "Copying backup to NAS ($NAS_BACKUP)..."
  if cp "${BACKUP_PATH}.sql.gz" "$NAS_BACKUP/"; then
    log_success "Backup copied to NAS"
  else
    log_warning "Failed to copy backup to NAS (continuing anyway)"
  fi
else
  log_warning "NAS backup directory not available: $NAS_BACKUP"
fi

# Cleanup old backups (retention policy)
log_info "Cleaning up backups older than $RETENTION_DAYS days..."
DELETED_COUNT=0
if [ -d "$BACKUP_DIR" ]; then
  DELETED_COUNT=$(find "$BACKUP_DIR" -name "postgres_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
fi
log_info "Deleted $DELETED_COUNT old backups from primary"

if [ -d "$NAS_BACKUP" ]; then
  NAS_DELETED=$(find "$NAS_BACKUP" -name "postgres_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
  log_info "Deleted $NAS_DELETED old backups from NAS"
fi

# Generate backup metadata for tracking
{
  echo "Timestamp: $TIMESTAMP"
  echo "Hostname: $(hostname)"
  echo "Database: $PGDATABASE"
  echo "Size: $BACKUP_SIZE"
  echo "Format: PostgreSQL custom format (gzip compressed)"
  echo "Status: SUCCESS"
  echo "Retention: $RETENTION_DAYS days"
} > "${BACKUP_PATH}.metadata"

log_success "PostgreSQL backup complete: $BACKUP_NAME"

# Print summary
echo ""
echo "┌────────────────────────────────────────────┐"
echo "│ PostgreSQL Backup Summary                  │"
echo "├────────────────────────────────────────────┤"
echo "│ Timestamp:  $TIMESTAMP"
echo "│ Size:       $BACKUP_SIZE"
echo "│ Location:   $BACKUP_PATH.sql.gz"
echo "│ Status:     ✅ SUCCESS"
echo "│ NAS Copy:   $NAS_BACKUP/$BACKUP_NAME.sql.gz"
echo "└────────────────────────────────────────────┘"
echo ""
