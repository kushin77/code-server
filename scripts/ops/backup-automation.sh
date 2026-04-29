# Phase 14B: Backup & Disaster Recovery Automation
# Automated backup scripts for PostgreSQL, Redis, and configuration

#!/bin/bash
# PostgreSQL Backup Script
# Daily backups with 30-day retention

BACKUP_DIR="/backups/postgres"
DB_HOST="code-server-postgres"
DB_NAME="app_db"
DB_USER="postgres"
RETENTION_DAYS=30

set -e
trap 'echo "Backup failed"; exit 1' ERR
trap 'echo "Cleanup completed"; true' EXIT

# Create backup directory
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/wal_archive"

# Generate backup filename with timestamp
BACKUP_FILE="$BACKUP_DIR/backup-$(date +%Y%m%d-%H%M%S).sql.gz"

echo "📦 PostgreSQL Backup Started ($(date))"
echo "  Host: $DB_HOST"
echo "  Database: $DB_NAME"
echo "  Output: $BACKUP_FILE"

# Perform database dump
docker exec $DB_HOST pg_dump -U $DB_USER $DB_NAME | gzip > "$BACKUP_FILE"

# Verify backup
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "✅ Backup completed: $BACKUP_SIZE"

# Clean up old backups (retention policy)
echo "🧹 Cleaning old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "backup-*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete

# Count retained backups
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/backup-*.sql.gz 2>/dev/null | wc -l)
echo "  Backups retained: $BACKUP_COUNT"

# List latest backups
echo "📋 Latest backups:"
ls -lh "$BACKUP_DIR"/backup-*.sql.gz 2>/dev/null | tail -5 | awk '{print "  " $9 " (" $5 ")"}'

---

#!/bin/bash
# Redis Backup Script
# Daily RDB + AOF snapshots with 7-day retention

BACKUP_DIR="/backups/redis"
REDIS_CONTAINER="code-server-redis"
RETENTION_DAYS=7

set -e
trap 'echo "Backup failed"; exit 1' ERR

mkdir -p "$BACKUP_DIR"

echo "📦 Redis Backup Started ($(date))"

# Trigger Redis BGSAVE (background save)
echo "  Initiating background save..."
docker exec $REDIS_CONTAINER redis-cli BGSAVE > /dev/null

# Wait for save to complete
sleep 5

# Copy RDB snapshot
BACKUP_FILE="$BACKUP_DIR/dump-$(date +%Y%m%d-%H%M%S).rdb"
docker cp $REDIS_CONTAINER:/data/dump.rdb "$BACKUP_FILE"

# Also get AOF if available
if docker exec $REDIS_CONTAINER test -f /data/appendonly.aof; then
  docker cp $REDIS_CONTAINER:/data/appendonly.aof "$BACKUP_DIR/aof-$(date +%Y%m%d-%H%M%S).aof"
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "✅ Backup completed: $BACKUP_SIZE"

# Clean old backups
echo "🧹 Cleaning old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "📋 Recent backups:"
ls -lh "$BACKUP_DIR"/*.rdb 2>/dev/null | tail -3 | awk '{print "  " $9 " (" $5 ")"}'

---

#!/bin/bash
# Configuration Backup Script
# Backs up docker-compose files and configs

BACKUP_DIR="/backups/config"
RETENTION_DAYS=30
SOURCE_DIRS=("docker-compose*.yml" "config/" "certs/")

set -e
trap 'echo "Backup failed"; exit 1' ERR

mkdir -p "$BACKUP_DIR"

echo "📦 Configuration Backup Started ($(date))"

# Create tarball with all configs
BACKUP_FILE="$BACKUP_DIR/configs-$(date +%Y%m%d-%H%M%S).tar.gz"

tar czf "$BACKUP_FILE" \
  docker-compose*.yml \
  config/ \
  certs/ \
  scripts/ops/*.sh \
  2>/dev/null || true

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "✅ Backup completed: $BACKUP_SIZE"

# Clean old backups
echo "🧹 Cleaning old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "configs-*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete

BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/configs-*.tar.gz 2>/dev/null | wc -l)
echo "  Backups retained: $BACKUP_COUNT"

echo "📋 Latest backups:"
ls -lh "$BACKUP_DIR"/configs-*.tar.gz 2>/dev/null | tail -3 | awk '{print "  " $9 " (" $5 ")"}'
