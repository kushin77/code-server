#!/bin/bash
# Redis snapshot backup script
# Creates daily RDB snapshots with 7-day retention

set -e
trap 'echo "❌ Redis backup failed at line $LINENO"; exit 1' ERR
trap 'echo "✅ Redis backup complete"; true' EXIT

BACKUP_DIR="${BACKUP_DIR:-/backups/redis}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
REDIS_HOST="${REDIS_HOST:-192.168.168.31}"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="dump_${TIMESTAMP}.rdb"

echo "Starting Redis backup - $(date)"
echo "Backup: $BACKUP_DIR/$BACKUP_NAME"

# Trigger Redis save via SSH
ssh -o BatchMode=yes akushnir@$REDIS_HOST << EOF
  docker exec code-server-redis redis-cli BGSAVE
  
  # Wait for background save
  COUNT=0
  while [[ $COUNT -lt 30 ]]; do
    STATUS=\$(docker exec code-server-redis redis-cli LASTSAVE)
    echo "Waiting for BGSAVE... (attempt $((COUNT+1))/30)"
    sleep 1
    COUNT+=1
  done
  
  # Copy RDB file
  docker exec code-server-redis cp /data/dump.rdb /tmp/$BACKUP_NAME
  test -f /tmp/$BACKUP_NAME && echo "✓ RDB snapshot created"
EOF

# Download backup
scp -o BatchMode=yes akushnir@$REDIS_HOST:/tmp/$BACKUP_NAME "$BACKUP_DIR/$BACKUP_NAME"

if [[ -f "$BACKUP_DIR/$BACKUP_NAME" ]]; then
  SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME" | cut -f1)
  echo "✅ Redis backup successful: $SIZE"
else
  echo "❌ Redis backup failed"
  exit 1
fi

# Cleanup old backups
find "$BACKUP_DIR" -name "dump_*.rdb" -mtime +$RETENTION_DAYS -delete

BACKUP_COUNT=$(find "$BACKUP_DIR" -name "dump_*.rdb" | wc -l)
echo "Retained snapshots: $BACKUP_COUNT"

# Remote cleanup
ssh -o BatchMode=yes akushnir@$REDIS_HOST "rm -f /tmp/dump_*.rdb" 2>/dev/null || true

echo "Redis backup completed at $(date)"
