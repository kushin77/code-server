#!/bin/bash
# Backup health check - verifies backup system status
# Reports on backup freshness and storage status

set -e
trap 'true' EXIT

BACKUP_DIR="${BACKUP_DIR:-/backups}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            BACKUP HEALTH CHECK - $(date +%Y-%m-%d)         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# PostgreSQL Backups
echo "PostgreSQL Backups:"
echo "─────────────────────"
if [[ -d "$BACKUP_DIR/postgres" ]]; then
  POSTGRES_COUNT=$(find "$BACKUP_DIR/postgres" -name "backup_*.sql.gz" 2>/dev/null | wc -l)
  if [[ $POSTGRES_COUNT -gt 0 ]]; then
    LATEST=$(ls -t "$BACKUP_DIR/postgres"/backup_*.sql.gz 2>/dev/null | head -1)
    LATEST_TIME=$(stat -c %y "$LATEST" | cut -d' ' -f1,2)
    LATEST_SIZE=$(du -h "$LATEST" | cut -f1)
    
    echo "  Count: $POSTGRES_COUNT backups"
    echo "  Latest: $(basename "$LATEST")"
    echo "  Size: $LATEST_SIZE"
    echo "  Modified: $LATEST_TIME"
    
    # Check if backup is recent (within 24 hours)
    LATEST_EPOCH=$(date -d "$LATEST_TIME" +%s)
    CURRENT_EPOCH=$(date +%s)
    AGE=$((CURRENT_EPOCH - LATEST_EPOCH))
    AGE_HOURS=$((AGE / 3600))
    
    if [[ $AGE_HOURS -lt 24 ]]; then
      echo "  Status: ✅ Current (${AGE_HOURS}h old)"
    else
      echo "  Status: ⚠️  Stale (${AGE_HOURS}h old)"
    fi
  else
    echo "  Status: ⚠️  No backups found"
  fi
else
  echo "  Status: ❌ Directory not found"
fi

echo ""
echo "Redis Backups:"
echo "──────────────"
if [[ -d "$BACKUP_DIR/redis" ]]; then
  REDIS_COUNT=$(find "$BACKUP_DIR/redis" -name "dump_*.rdb" 2>/dev/null | wc -l)
  if [[ $REDIS_COUNT -gt 0 ]]; then
    LATEST=$(ls -t "$BACKUP_DIR/redis"/dump_*.rdb 2>/dev/null | head -1)
    LATEST_TIME=$(stat -c %y "$LATEST" | cut -d' ' -f1,2)
    LATEST_SIZE=$(du -h "$LATEST" | cut -f1)
    
    echo "  Count: $REDIS_COUNT snapshots"
    echo "  Latest: $(basename "$LATEST")"
    echo "  Size: $LATEST_SIZE"
    echo "  Modified: $LATEST_TIME"
    
    LATEST_EPOCH=$(date -d "$LATEST_TIME" +%s)
    CURRENT_EPOCH=$(date +%s)
    AGE=$((CURRENT_EPOCH - LATEST_EPOCH))
    AGE_HOURS=$((AGE / 3600))
    
    if [[ $AGE_HOURS -lt 24 ]]; then
      echo "  Status: ✅ Current (${AGE_HOURS}h old)"
    else
      echo "  Status: ⚠️  Stale (${AGE_HOURS}h old)"
    fi
  else
    echo "  Status: ⚠️  No snapshots found"
  fi
else
  echo "  Status: ❌ Directory not found"
fi

echo ""
echo "Volume Snapshots:"
echo "─────────────────"
if [[ -d "$BACKUP_DIR/volumes" ]]; then
  VOLUME_COUNT=$(find "$BACKUP_DIR/volumes" -name "*.tar.gz" 2>/dev/null | wc -l)
  if [[ $VOLUME_COUNT -gt 0 ]]; then
    LATEST=$(find "$BACKUP_DIR/volumes" -name "*.tar.gz" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    LATEST_TIME=$(stat -c %y "$LATEST" | cut -d' ' -f1,2)
    LATEST_SIZE=$(du -h "$LATEST" | cut -f1)
    
    echo "  Count: $VOLUME_COUNT snapshots"
    echo "  Latest: $(basename "$LATEST")"
    echo "  Size: $LATEST_SIZE"
    echo "  Modified: $LATEST_TIME"
    
    LATEST_EPOCH=$(date -d "$LATEST_TIME" +%s)
    CURRENT_EPOCH=$(date +%s)
    AGE=$((CURRENT_EPOCH - LATEST_EPOCH))
    AGE_HOURS=$((AGE / 3600))
    
    if [[ $AGE_HOURS -lt 24 ]]; then
      echo "  Status: ✅ Current (${AGE_HOURS}h old)"
    else
      echo "  Status: ⚠️  Stale (${AGE_HOURS}h old)"
    fi
  else
    echo "  Status: ⚠️  No snapshots found"
  fi
else
  echo "  Status: ❌ Directory not found"
fi

echo ""
echo "Storage Usage:"
echo "──────────────"
if [[ -d "$BACKUP_DIR" ]]; then
  TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
  echo "  Total: $TOTAL_SIZE"
  
  # Check available space
  AVAILABLE=$(df "$BACKUP_DIR" | tail -1 | awk '{print $4}')
  AVAILABLE_GB=$((AVAILABLE / 1024 / 1024))
  echo "  Available: ${AVAILABLE_GB}GB"
  
  if [[ $AVAILABLE_GB -lt 10 ]]; then
    echo "  Status: ⚠️  Low disk space"
  else
    echo "  Status: ✅ Sufficient space"
  fi
else
  echo "  Status: ❌ Backup directory not found"
fi

echo ""
echo "Git Configuration:"
echo "──────────────────"
if [[ -d "/home/akushnir/code-server/.git" ]]; then
  cd /home/akushnir/code-server
  BACKUP_TAGS=$(git tag | grep "^backup-" | wc -l)
  LATEST_TAG=$(git tag | grep "^backup-" | sort -V | tail -1)
  echo "  Backup tags: $BACKUP_TAGS"
  if [[ -n "$LATEST_TAG" ]]; then
    LATEST_TAG_DATE=$(git log -1 --format=%ai "$LATEST_TAG" 2>/dev/null || echo "unknown")
    echo "  Latest tag: $LATEST_TAG"
    echo "  Tagged: $LATEST_TAG_DATE"
    echo "  Status: ✅ Configuration tracked"
  else
    echo "  Status: ⚠️  No backup tags found"
  fi
else
  echo "  Status: ❌ Git repository not found"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║            Health check completed                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
