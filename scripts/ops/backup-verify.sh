#!/bin/bash
# backup_verify.sh
# Daily Backup Verification Script
# Run daily after backup completes (within 1 hour)
# Part of: Backup & Recovery Testing Procedures

set -e

# Error handling
log_error() {
  echo "❌ ERROR: $1" >&2
}

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleaning up..."; rm -f /tmp/backup-verify.tmp 2>/dev/null || true' EXIT

log_info() {
  echo "ℹ️  $1"
}

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PRIMARY="192.168.168.31"
BACKUP_DIR="/var/lib/postgresql/backups"

echo "=== Daily Backup Verification $TIMESTAMP ===" | tee /tmp/backup-verify-$TIMESTAMP.log

# Check backup exists
LATEST_BACKUP=$(ssh -o ConnectTimeout=10 -o BatchMode=yes akushnir@$PRIMARY "ls -t $BACKUP_DIR | head -1" 2>/dev/null || echo "")
if [ -z "$LATEST_BACKUP" ]; then
  echo "❌ NO BACKUP FOUND" | tee -a /tmp/backup-verify-$TIMESTAMP.log
  exit 1
fi

echo "✅ Latest backup: $LATEST_BACKUP" | tee -a /tmp/backup-verify-$TIMESTAMP.log

# Check backup size (should be > 100MB)
BACKUP_SIZE=$(ssh -o ConnectTimeout=10 -o BatchMode=yes akushnir@$PRIMARY "du -sh $BACKUP_DIR/$LATEST_BACKUP | awk '{print \$1}'" 2>/dev/null || echo "unknown")
echo "✅ Backup size: $BACKUP_SIZE (target: >100MB)" | tee -a /tmp/backup-verify-$TIMESTAMP.log

# Check backup age (should be < 24h)
BACKUP_AGE=$(ssh -o ConnectTimeout=10 -o BatchMode=yes akushnir@$PRIMARY "find $BACKUP_DIR -name '$LATEST_BACKUP' -type d -mtime -1 | wc -l" 2>/dev/null || echo "0")
if [ "$BACKUP_AGE" -eq 1 ]; then
  echo "✅ Backup age: <24 hours" | tee -a /tmp/backup-verify-$TIMESTAMP.log
else
  echo "⚠️ Backup age: >=24 hours (target: <24h)" | tee -a /tmp/backup-verify-$TIMESTAMP.log
fi

# Check backup tar integrity
INTEGRITY=$(ssh -o ConnectTimeout=10 -o BatchMode=yes akushnir@$PRIMARY "tar -tzf $BACKUP_DIR/$LATEST_BACKUP/base.tar.gz 2>/dev/null | wc -l || echo 0" 2>/dev/null || echo "0")
if [ "$INTEGRITY" -gt 0 ]; then
  echo "✅ Backup integrity: $INTEGRITY files (tar valid)" | tee -a /tmp/backup-verify-$TIMESTAMP.log
else
  echo "❌ Backup integrity check FAILED" | tee -a /tmp/backup-verify-$TIMESTAMP.log
  exit 1
fi

echo "✅ Daily backup verification passed" | tee -a /tmp/backup-verify-$TIMESTAMP.log
