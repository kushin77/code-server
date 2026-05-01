#!/bin/bash
# Production Redis Backup Script
# Run hourly: every hour via cron
# Usage: ./backup-redis.sh

set -euo pipefail

BACKUP_DIR="/backups/redis"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTAINER="code-server-redis"
LOG_FILE="/var/log/redis-backup.log"

# Ensure backup directory exists
sudo mkdir -p $BACKUP_DIR
sudo chown 999:999 $BACKUP_DIR

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

trap 'log "❌ Backup failed with error"; exit 1' ERR

log "Starting Redis snapshot backup (dump_${TIMESTAMP}.rdb)"

# Verify Redis is running
if ! docker-compose ps $CONTAINER | grep -q "Up"; then
  log "❌ Redis container not running"
  exit 1
fi

# Trigger SAVE command
log "Triggering Redis SAVE..."
docker-compose exec -T $CONTAINER redis-cli SAVE || {
  log "⚠️  SAVE command failed, trying BGSAVE..."
  docker-compose exec -T $CONTAINER redis-cli BGSAVE
}

# Wait for save to complete
sleep 5

# Copy dump file
log "Copying snapshot to backup directory..."
docker cp $CONTAINER:/data/dump.rdb $BACKUP_DIR/dump_${TIMESTAMP}.rdb

# Verify backup file
if [ ! -f "$BACKUP_DIR/dump_${TIMESTAMP}.rdb" ]; then
  log "❌ Backup file not found"
  exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_DIR/dump_${TIMESTAMP}.rdb" | awk '{print $1}')
log "✅ Redis snapshot successful - Size: $BACKUP_SIZE"

# Verify backup is valid RDB format
if ! file "$BACKUP_DIR/dump_${TIMESTAMP}.rdb" | grep -q "data"; then
  log "⚠️  Warning: backup file might be invalid"
fi

# Keep only last 24 snapshots (one per hour)
DELETED_COUNT=$(find $BACKUP_DIR -name "dump_*.rdb" -type f | sort -r | tail -n +25 | xargs rm -f 2>/dev/null; echo 0)
log "Kept last 24 hourly snapshots"

# Create timestamp file for monitoring
echo $TIMESTAMP > $BACKUP_DIR/.last_backup_timestamp

log "✅ Redis backup complete"
