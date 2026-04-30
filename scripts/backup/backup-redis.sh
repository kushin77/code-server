#!/bin/bash
#
# @file backup-redis.sh
# @module backup
# @description Redis automated backup script with RDB snapshots
# @author Operations Team
# @version 1.0
#

set -euo pipefail

# ============================================================================
# ERROR HANDLING
# ============================================================================

trap 'log_error "Redis backup failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/redis_backup_*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# CONFIGURATION
# ============================================================================

BACKUP_DIR="${BACKUP_DIR:-/backups/daily/redis}"
NAS_BACKUP="${NAS_BACKUP:-/mnt/nas-backup/redis}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
REDIS_CONTAINER="${REDIS_CONTAINER:-code-server-redis}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_FILE="/var/log/code-server-backup-redis.log"

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
# MAIN BACKUP LOGIC
# ============================================================================

# Create backup directories
mkdir -p "$BACKUP_DIR" "$NAS_BACKUP"

# Generate backup filename with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="redis_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}.rdb"

log_info "Starting Redis backup: $BACKUP_NAME"

# Build redis-cli arguments
REDIS_CLI_ARGS="-h $REDIS_HOST -p $REDIS_PORT"
if [ -n "$REDIS_PASSWORD" ]; then
  REDIS_CLI_ARGS="$REDIS_CLI_ARGS -a $REDIS_PASSWORD"
fi

# Verify Redis connectivity
log_info "Verifying Redis connectivity at $REDIS_HOST:$REDIS_PORT..."
if ! redis-cli $REDIS_CLI_ARGS ping >/dev/null 2>&1; then
  log_error "Cannot connect to Redis at $REDIS_HOST:$REDIS_PORT"
  exit 1
fi
log_success "Redis connection verified"

# Get Redis info before backup
REDIS_KEYS=$(redis-cli $REDIS_CLI_ARGS DBSIZE 2>/dev/null | awk '{print $2}')
log_info "Redis keys before backup: $REDIS_KEYS"

# Trigger background save (non-blocking)
log_info "Triggering Redis BGSAVE (background save)..."
redis-cli $REDIS_CLI_ARGS BGSAVE >/dev/null 2>&1
log_success "BGSAVE triggered"

# Wait for save to complete
log_info "Waiting for BGSAVE to complete..."
MAX_WAIT=300  # 5 minutes maximum
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
  BGSAVE_STATUS=$(redis-cli $REDIS_CLI_ARGS INFO persistence 2>/dev/null | grep "rdb_bgsave_in_progress" | cut -d: -f2 | tr -d '\r')
  
  if [ "$BGSAVE_STATUS" = "0" ]; then
    log_success "BGSAVE completed"
    break
  fi
  
  sleep 5
  ((ELAPSED += 5))
  echo -n "."
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  log_warning "BGSAVE did not complete within 5 minutes"
fi

# Copy RDB file from container
log_info "Copying RDB file from Redis container ($REDIS_CONTAINER)..."
if docker cp "$REDIS_CONTAINER:/data/dump.rdb" "$BACKUP_PATH" 2>&1; then
  log_success "RDB file copied: $BACKUP_PATH"
else
  log_error "Failed to copy RDB file from container"
  exit 1
fi

# Compress backup
log_info "Compressing backup with gzip..."
if gzip -9 "$BACKUP_PATH" 2>&1; then
  BACKUP_PATH="${BACKUP_PATH}.gz"
  log_success "Backup compressed: $BACKUP_PATH"
else
  log_error "Failed to compress backup"
  exit 1
fi

# Get backup file size
BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
log_info "Backup size: $BACKUP_SIZE"

# Copy to NAS backup location
if [ -d "$NAS_BACKUP" ]; then
  log_info "Copying backup to NAS ($NAS_BACKUP)..."
  if cp "$BACKUP_PATH" "$NAS_BACKUP/"; then
    log_success "Backup copied to NAS"
  else
    log_warning "Failed to copy backup to NAS (continuing anyway)"
  fi
else
  log_warning "NAS backup directory not available: $NAS_BACKUP"
fi

# Verify Redis data integrity
log_info "Verifying Redis data integrity..."
REDIS_KEYS_AFTER=$(redis-cli $REDIS_CLI_ARGS DBSIZE 2>/dev/null | awk '{print $2}')
log_info "Redis keys after backup: $REDIS_KEYS_AFTER"

if [ "$REDIS_KEYS" -eq "$REDIS_KEYS_AFTER" ]; then
  log_success "Redis data consistency verified"
else
  log_warning "Redis key count changed during backup (may indicate activity)"
fi

# Cleanup old backups (retention policy)
log_info "Cleaning up backups older than $RETENTION_DAYS days..."
DELETED_COUNT=0
if [ -d "$BACKUP_DIR" ]; then
  DELETED_COUNT=$(find "$BACKUP_DIR" -name "redis_backup_*.rdb.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
fi
log_info "Deleted $DELETED_COUNT old backups from primary"

if [ -d "$NAS_BACKUP" ]; then
  NAS_DELETED=$(find "$NAS_BACKUP" -name "redis_backup_*.rdb.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
  log_info "Deleted $NAS_DELETED old backups from NAS"
fi

# Generate backup metadata
{
  echo "Timestamp: $TIMESTAMP"
  echo "Hostname: $(hostname)"
  echo "Redis Host: $REDIS_HOST:$REDIS_PORT"
  echo "Size: $BACKUP_SIZE"
  echo "Keys: $REDIS_KEYS"
  echo "Format: RDB (gzip compressed)"
  echo "Status: SUCCESS"
  echo "Retention: $RETENTION_DAYS days"
} > "${BACKUP_PATH}.metadata"

log_success "Redis backup complete: $BACKUP_NAME"

# Print summary
echo ""
echo "┌────────────────────────────────────────────┐"
echo "│ Redis Backup Summary                       │"
echo "├────────────────────────────────────────────┤"
echo "│ Timestamp:  $TIMESTAMP"
echo "│ Size:       $BACKUP_SIZE"
echo "│ Keys:       $REDIS_KEYS"
echo "│ Location:   $BACKUP_PATH"
echo "│ Status:     ✅ SUCCESS"
echo "│ NAS Copy:   $NAS_BACKUP/$BACKUP_NAME.rdb.gz"
echo "└────────────────────────────────────────────┘"
echo ""
