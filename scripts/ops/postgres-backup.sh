#!/bin/bash
# PostgreSQL automated backup script
# Creates daily compressed backups with 30-day retention

set -e
trap 'echo "❌ Backup failed at line $LINENO"; exit 1' ERR
trap 'echo "✅ Backup operation complete"; true' EXIT

BACKUP_DIR="${BACKUP_DIR:-/backups/postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DB_HOST="${DB_HOST:-192.168.168.31}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres_password_2026}"
DB_NAME="${DB_NAME:-code_server}"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.sql.gz"

echo "Starting PostgreSQL backup - $(date)"
echo "Backup file: $BACKUP_FILE"
echo "Retention: $RETENTION_DAYS days"

# Execute backup via SSH
ssh -o BatchMode=yes akushnir@$DB_HOST << BACKUP_EOF
  docker exec code-server-postgres pg_dump \
    -U $DB_USER \
    -d $DB_NAME \
    --format=plain \
    --no-owner \
    --no-privileges | gzip > /tmp/backup_${TIMESTAMP}.sql.gz
  
  test -f /tmp/backup_${TIMESTAMP}.sql.gz && echo "✓ Backup created"
BACKUP_EOF

# Download backup
scp -o BatchMode=yes akushnir@$DB_HOST:/tmp/backup_${TIMESTAMP}.sql.gz "$BACKUP_FILE"

# Verify
if [[ -f "$BACKUP_FILE" ]]; then
  SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "✅ Backup successful: $SIZE"
else
  echo "❌ Backup file not found"
  exit 1
fi

# Cleanup old backups
find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete

# List current backups
BACKUP_COUNT=$(find "$BACKUP_DIR" -name "backup_*.sql.gz" | wc -l)
echo "Retained backups: $BACKUP_COUNT"

# Remote cleanup
ssh -o BatchMode=yes akushnir@$DB_HOST "rm -f /tmp/backup_*.sql.gz" 2>/dev/null || true

echo "Backup completed at $(date)"
