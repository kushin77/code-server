#!/bin/bash
# Backup Health Verification Script
# Run daily (or on demand) to check backup system health
# Usage: ./verify-backups.sh

set -euo pipefail

trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'true' EXIT

BACKUP_BASE="/backups"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Backup System Health Check"
echo "Date: $(date)"
echo "========================================="
echo

# Check PostgreSQL backups
echo -n "PostgreSQL backups (< 24h):     "
PG_BACKUP_COUNT=$(find $BACKUP_BASE/postgresql -name "backup_*.dump" -mtime -1 2>/dev/null | wc -l)
PG_BACKUP_SIZE=$(du -sh $BACKUP_BASE/postgresql 2>/dev/null | awk '{print $1}')

if [ $PG_BACKUP_COUNT -gt 0 ]; then
  echo -e "${GREEN}✅ $PG_BACKUP_COUNT backups found${NC} ($PG_BACKUP_SIZE)"
else
  echo -e "${RED}❌ NO RECENT BACKUPS${NC}"
fi

# Check PostgreSQL latest backup timestamp
if [ -f "$BACKUP_BASE/postgresql/.last_backup_timestamp" ]; then
  PG_LAST=$(cat $BACKUP_BASE/postgresql/.last_backup_timestamp)
  echo "  Last backup: $PG_LAST"
else
  echo "  ⚠️  No timestamp file found"
fi

echo

# Check Redis snapshots
echo -n "Redis snapshots (< 24h):        "
REDIS_BACKUP_COUNT=$(find $BACKUP_BASE/redis -name "dump_*.rdb" -mtime -1 2>/dev/null | wc -l)
REDIS_BACKUP_SIZE=$(du -sh $BACKUP_BASE/redis 2>/dev/null | awk '{print $1}')

if [ $REDIS_BACKUP_COUNT -gt 0 ]; then
  echo -e "${GREEN}✅ $REDIS_BACKUP_COUNT snapshots found${NC} ($REDIS_BACKUP_SIZE)"
else
  echo -e "${RED}❌ NO RECENT SNAPSHOTS${NC}"
fi

# Check Redis latest snapshot timestamp
if [ -f "$BACKUP_BASE/redis/.last_backup_timestamp" ]; then
  REDIS_LAST=$(cat $BACKUP_BASE/redis/.last_backup_timestamp)
  echo "  Last snapshot: $REDIS_LAST"
else
  echo "  ⚠️  No timestamp file found"
fi

echo

# Check backup storage space
echo -n "Total backup storage used:      "
BACKUP_TOTAL=$(du -sh $BACKUP_BASE 2>/dev/null | awk '{print $1}')
echo "$BACKUP_TOTAL"

# Check available space
echo -n "Available space on /backups:    "
AVAILABLE=$(df -h $BACKUP_BASE 2>/dev/null | tail -1 | awk '{print $4}')
USAGE_PERCENT=$(df $BACKUP_BASE 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$USAGE_PERCENT" -lt 80 ]; then
  echo -e "${GREEN}✅ ${AVAILABLE}${NC} (${USAGE_PERCENT}% used)"
elif [ "$USAGE_PERCENT" -lt 90 ]; then
  echo -e "${YELLOW}⚠️  ${AVAILABLE}${NC} (${USAGE_PERCENT}% used - monitor)"
else
  echo -e "${RED}❌ ${AVAILABLE}${NC} (${USAGE_PERCENT}% used - CRITICAL)"
fi

echo

# Check PostgreSQL container health
echo -n "PostgreSQL container:          "
if docker-compose ps code-server-postgres 2>/dev/null | grep -q "Up"; then
  echo -e "${GREEN}✅ Running${NC}"
else
  echo -e "${RED}❌ Not running${NC}"
fi

# Test PostgreSQL connectivity
if docker exec code-server-postgres psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
  echo -e "  ${GREEN}✅ Connection OK${NC}"
else
  echo -e "  ${RED}❌ Connection failed${NC}"
fi

echo

# Check Redis container health
echo -n "Redis container:               "
if docker-compose ps code-server-redis 2>/dev/null | grep -q "Up"; then
  echo -e "${GREEN}✅ Running${NC}"
else
  echo -e "${RED}❌ Not running${NC}"
fi

# Test Redis connectivity
if docker-compose exec -T code-server-redis redis-cli PING > /dev/null 2>&1; then
  echo -e "  ${GREEN}✅ Connection OK${NC}"
else
  echo -e "  ${RED}❌ Connection failed${NC}"
fi

echo

# Summary
echo "========================================="
if [ $PG_BACKUP_COUNT -gt 0 ] && [ $REDIS_BACKUP_COUNT -gt 0 ]; then
  echo -e "${GREEN}✅ Backup system HEALTHY${NC}"
  exit 0
else
  echo -e "${RED}❌ Backup system ISSUES DETECTED${NC}"
  exit 1
fi
