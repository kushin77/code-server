#!/bin/bash
# Production PostgreSQL Backup Script
# Run daily: 02:00 UTC via cron
# Usage: ./backup-postgresql.sh

set -euo pipefail

BACKUP_DIR="/backups/postgresql"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTAINER="code-server-postgres"
LOG_FILE="/var/log/postgresql-backup.log"

# Ensure backup directory exists
sudo mkdir -p $BACKUP_DIR
sudo chown 999:999 $BACKUP_DIR

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

trap 'log "❌ Backup failed with error"; exit 1' ERR

log "Starting PostgreSQL backup (backup_${TIMESTAMP}.dump)"

# Verify PostgreSQL is running
if ! docker-compose ps $CONTAINER | grep -q "Up"; then
  log "❌ PostgreSQL container not running"
  exit 1
fi

# Create dump file inside container
log "Creating database dump..."
docker exec $CONTAINER pg_dump -U postgres --format=custom \
  --compress=5 \
  --jobs=2 \
  -f /tmp/backup_${TIMESTAMP}.dump purebliss_db

# Copy to backup directory
log "Copying to backup directory..."
docker cp $CONTAINER:/tmp/backup_${TIMESTAMP}.dump $BACKUP_DIR/

# Verify backup file
if [ ! -f "$BACKUP_DIR/backup_${TIMESTAMP}.dump" ]; then
  log "❌ Backup file not found"
  exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_DIR/backup_${TIMESTAMP}.dump" | awk '{print $1}')
log "✅ Backup successful - Size: $BACKUP_SIZE"

# Verify backup integrity by listing contents
if ! docker exec $CONTAINER pg_restore --list "$BACKUP_DIR/backup_${TIMESTAMP}.dump" > /dev/null 2>&1; then
  log "❌ Backup integrity check failed"
  exit 1
fi

log "✅ Backup integrity verified"

# Cleanup old backups (keep 7 days)
DELETED_COUNT=$(find $BACKUP_DIR -name "backup_*.dump" -mtime +7 -delete -print | wc -l)
log "Cleaned up $DELETED_COUNT old backups (> 7 days)"

# Create timestamp file for monitoring
echo $TIMESTAMP > $BACKUP_DIR/.last_backup_timestamp

log "✅ PostgreSQL backup complete"
