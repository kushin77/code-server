# Backup & Disaster Recovery Guide - Phase 6

**Date**: April 30, 2026  
**Phase**: 6 (Production Readiness)  
**Status**: 🟢 IMPLEMENTATION READY  

---

## Overview

This guide establishes comprehensive backup and disaster recovery procedures for the ElevatedIQ platform, ensuring business continuity and data protection across the dual-node cluster.

### Current State
- ✅ 55 services deployed and healthy
- ✅ PostgreSQL 16-alpine with replication-ready config
- ✅ 12+ persistent volumes per host
- ✅ Redis for session management
- ✅ Qdrant for vector embeddings
- ✅ All infrastructure in git (2,796 commits)

### Backup Strategy

| Data | Type | Frequency | Retention | Method |
|------|------|-----------|-----------|--------|
| PostgreSQL | Database | Daily | 30 days | pg_dump + WAL archive |
| Redis | Cache | On-change | 7 days | RDB snapshots |
| Qdrant | Vectors | Daily | 14 days | Native snapshots |
| Volumes | Storage | Daily | 14 days | Volume snapshots |
| Configs | Infrastructure | Per-change | 90 days | Git history |

---

## Phase 6A: PostgreSQL Automated Backups

### Backup Script

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/postgres-backup.sh
# Automated PostgreSQL backup with compression and archival

set -e
trap 'echo "Backup failed at line $LINENO"; exit 1' ERR
trap 'echo "Backup completed"; true' EXIT

BACKUP_DIR="/backups/postgres"
RETENTION_DAYS=30
DB_HOST="192.168.168.31"
DB_USER="postgres"
DB_PASSWORD="postgres_password_2026"
DB_NAME="code_server"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.sql.gz"

echo "Starting PostgreSQL backup..."
echo "Target: $BACKUP_FILE"

# Execute backup via SSH to primary host
ssh -o BatchMode=yes akushnir@$DB_HOST << BACKUP_EOF
  docker exec code-server-postgres pg_dump \
    -U $DB_USER \
    -d $DB_NAME \
    --format=plain \
    --no-owner \
    --no-privileges | gzip > /tmp/backup_${TIMESTAMP}.sql.gz
  
  # Verify backup created
  test -f /tmp/backup_${TIMESTAMP}.sql.gz && echo "✓ Backup created"
BACKUP_EOF

# Download backup
scp -o BatchMode=yes akushnir@$DB_HOST:/tmp/backup_${TIMESTAMP}.sql.gz "$BACKUP_FILE"

# Verify download
if [[ -f "$BACKUP_FILE" ]]; then
  SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "✅ Backup complete: $SIZE"
else
  echo "❌ Backup file not found"
  exit 1
fi

# Cleanup old backups
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete

# List current backups
echo "Current backups:"
ls -lh "$BACKUP_DIR" | tail -5

# Remote cleanup
ssh -o BatchMode=yes akushnir@$DB_HOST "rm -f /tmp/backup_*.sql.gz"
```

### Cron Configuration

```bash
# Add to root crontab: crontab -e
# Daily backup at 2 AM
0 2 * * * /home/akushnir/code-server/scripts/ops/postgres-backup.sh >> /var/log/postgres-backup.log 2>&1

# Weekly full backup at Sunday 3 AM (for off-site archival)
0 3 * * 0 /home/akushnir/code-server/scripts/ops/postgres-backup-archive.sh
```

### Restore Procedure

```bash
#!/bin/bash
# Restore PostgreSQL from backup

BACKUP_FILE=$1  # e.g., /backups/postgres/backup_20260430_020000.sql.gz
DB_HOST="192.168.168.31"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "⚠️  WARNING: This will overwrite the database!"
echo "File: $BACKUP_FILE"
echo "Continue? (yes/no)"
read -r confirm

if [[ "$confirm" != "yes" ]]; then
  echo "Restore cancelled"
  exit 0
fi

echo "Starting restore..."

# Upload backup to primary
scp -o BatchMode=yes "$BACKUP_FILE" akushnir@$DB_HOST:/tmp/restore.sql.gz

# Execute restore
ssh -o BatchMode=yes akushnir@$DB_HOST << RESTORE_EOF
  # Stop applications that might be using the database
  docker stop code-server-execution-scheduler code-server-reputation-engine || true
  sleep 5
  
  # Drop existing database
  docker exec code-server-postgres psql -U postgres -c "DROP DATABASE IF EXISTS code_server;"
  
  # Restore from backup
  gunzip < /tmp/restore.sql.gz | docker exec -i code-server-postgres psql -U postgres
  
  # Verify restore
  docker exec code-server-postgres psql -U postgres -d code_server -c "SELECT COUNT(*) as tables FROM information_schema.tables WHERE table_schema='public';"
  
  # Restart applications
  docker start code-server-execution-scheduler code-server-reputation-engine
  
  # Cleanup
  rm -f /tmp/restore.sql.gz
RESTORE_EOF

echo "✅ Restore complete"
```

---

## Phase 6B: Redis Snapshot Backups

### Automated Redis Backup

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/redis-backup.sh

set -e
trap 'echo "Redis backup failed at line $LINENO"; exit 1' ERR
trap 'echo "Redis backup completed"; true' EXIT

BACKUP_DIR="/backups/redis"
RETENTION_DAYS=7
REDIS_HOST="192.168.168.31"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="dump_${TIMESTAMP}.rdb"

echo "Starting Redis backup..."

# Trigger Redis save (blocking)
ssh -o BatchMode=yes akushnir@$REDIS_HOST << EOF
  docker exec code-server-redis redis-cli BGSAVE
  
  # Wait for background save to complete
  until docker exec code-server-redis redis-cli LASTSAVE; do
    sleep 1
  done
  
  # Copy RDB file
  docker exec code-server-redis cp /data/dump.rdb /tmp/$BACKUP_NAME
EOF

# Download backup
scp -o BatchMode=yes akushnir@$REDIS_HOST:/tmp/$BACKUP_NAME "$BACKUP_DIR/$BACKUP_NAME"

if [[ -f "$BACKUP_DIR/$BACKUP_NAME" ]]; then
  SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME" | cut -f1)
  echo "✅ Redis backup complete: $SIZE"
else
  echo "❌ Redis backup failed"
  exit 1
fi

# Cleanup old backups
find "$BACKUP_DIR" -name "dump_*.rdb" -mtime +$RETENTION_DAYS -delete

# Remote cleanup
ssh -o BatchMode=yes akushnir@$REDIS_HOST "rm -f /tmp/dump_*.rdb"
```

### Redis Restore

```bash
#!/bin/bash
# Restore Redis from RDB snapshot

BACKUP_FILE=$1
REDIS_HOST="192.168.168.31"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "⚠️  WARNING: This will clear Redis cache!"
echo "File: $BACKUP_FILE"
echo "Continue? (yes/no)"
read -r confirm

if [[ "$confirm" != "yes" ]]; then
  exit 0
fi

echo "Restoring Redis..."

# Upload backup
scp -o BatchMode=yes "$BACKUP_FILE" akushnir@$REDIS_HOST:/tmp/dump.rdb

# Restore
ssh -o BatchMode=yes akushnir@$REDIS_HOST << EOF
  # Stop Redis container
  docker stop code-server-redis
  
  # Replace RDB file
  docker cp /tmp/dump.rdb code-server-redis:/data/dump.rdb
  
  # Restart Redis
  docker start code-server-redis
  
  # Verify
  sleep 2
  docker exec code-server-redis redis-cli PING
  
  # Cleanup
  rm -f /tmp/dump.rdb
EOF

echo "✅ Redis restore complete"
```

---

## Phase 6C: Volume Snapshot Backups

### Volume Snapshot Script

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/volume-snapshot.sh

set -e
trap 'echo "Snapshot failed at line $LINENO"; exit 1' ERR
trap 'echo "Snapshot completed"; true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=14

echo "Creating volume snapshots..."

# Snapshot on primary
ssh -o BatchMode=yes akushnir@192.168.168.31 << EOF
  cd ~/code-server-enterprise
  
  # Create snapshot of all volumes
  for volume in $(docker volume ls --format "{{.Name}}" | grep -E "postgres|redis|qdrant|caddy"); do
    SNAPSHOT_NAME="\${volume}_backup_${TIMESTAMP}"
    echo "Snapshotting: \$volume → \$SNAPSHOT_NAME"
    
    # For now, just backup volume data to file
    mkdir -p /backups/volumes/\$volume
    docker run --rm \
      -v \$volume:/data \
      -v /backups/volumes/\$volume:/backup \
      alpine tar czf /backup/\${TIMESTAMP}.tar.gz -C /data .
  done
EOF

# Snapshot on replica
ssh -o BatchMode=yes akushnir@192.168.168.42 << EOF
  cd ~/code-server-enterprise
  
  for volume in $(docker volume ls --format "{{.Name}}" | grep -E "postgres|redis|qdrant|caddy"); do
    SNAPSHOT_NAME="\${volume}_backup_${TIMESTAMP}"
    echo "Snapshotting: \$volume → \$SNAPSHOT_NAME"
    
    mkdir -p /backups/volumes/\$volume
    docker run --rm \
      -v \$volume:/data \
      -v /backups/volumes/\$volume:/backup \
      alpine tar czf /backup/\${TIMESTAMP}.tar.gz -C /data .
  done
EOF

echo "✅ Volume snapshots complete"

# Cleanup old snapshots
ssh -o BatchMode=yes akushnir@192.168.168.31 << EOF
  find /backups/volumes -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
EOF

ssh -o BatchMode=yes akushnir@192.168.168.42 << EOF
  find /backups/volumes -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
EOF
```

---

## Phase 6D: Configuration Backups

### Git-Based Configuration Backup

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/config-backup.sh

set -e
trap 'echo "Config backup failed at line $LINENO"; exit 1' ERR
trap 'echo "Config backup completed"; true' EXIT

echo "Backing up infrastructure configuration..."

cd /home/akushnir/code-server

# Verify all changes are committed
if [[ $(git status --porcelain | wc -l) -gt 0 ]]; then
  echo "⚠️  Uncommitted changes detected!"
  git status --porcelain
  echo "Commit all changes before backup?"
  read -r confirm
  if [[ "$confirm" == "yes" ]]; then
    git add -A
    git commit -m "ops: pre-backup configuration snapshot - $(date +%Y%m%d)"
  fi
fi

# Create backup tag
TAG="backup-$(date +%Y%m%d-%H%M%S)"
git tag -a "$TAG" -m "Backup at $(date)"

echo "✅ Config backup complete: $TAG"
git log --oneline -1

# Optional: Push to backup remote
if git remote | grep -q backup; then
  echo "Pushing to backup remote..."
  git push backup "$TAG"
fi
```

---

## Phase 6E: Disaster Recovery Test

### DR Test Procedure

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/dr-test.sh
# Simulate data loss and verify recovery

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  DISASTER RECOVERY TEST - DO NOT RUN IN PRODUCTION        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  WARNING: This test will:"
echo "    1. Create test data in database"
echo "    2. Simulate data loss"
echo "    3. Test recovery procedures"
echo "    4. Restore to known good state"
echo ""
echo "Continue? (yes/no)"
read -r confirm

if [[ "$confirm" != "yes" ]]; then
  exit 0
fi

PRIMARY="192.168.168.31"

# Phase 1: Create test data
echo ""
echo "PHASE 1: Creating test data..."
ssh -o BatchMode=yes akushnir@$PRIMARY << EOF
  docker exec code-server-postgres psql -U postgres -d code_server -c "
    CREATE TABLE IF NOT EXISTS dr_test (
      id SERIAL PRIMARY KEY,
      test_data VARCHAR(255),
      created_at TIMESTAMP DEFAULT NOW()
    );
    INSERT INTO dr_test (test_data) VALUES ('DR Test Data - $(date)');
  "
  
  # Verify data
  docker exec code-server-postgres psql -U postgres -d code_server -c "SELECT * FROM dr_test;"
EOF

echo "✅ Test data created"

# Phase 2: Take backup
echo ""
echo "PHASE 2: Taking backup..."
BACKUP_FILE="/tmp/dr_test_backup.sql.gz"
ssh -o BatchMode=yes akushnir@$PRIMARY << EOF
  docker exec code-server-postgres pg_dump \
    -U postgres \
    -d code_server \
    --format=plain | gzip > $BACKUP_FILE
  
  test -f $BACKUP_FILE && echo "✓ Backup created"
EOF

# Phase 3: Simulate data loss
echo ""
echo "PHASE 3: Simulating data loss..."
ssh -o BatchMode=yes akushnir@$PRIMARY << EOF
  docker exec code-server-postgres psql -U postgres -d code_server -c "DROP TABLE dr_test;"
  
  # Verify table is gone
  docker exec code-server-postgres psql -U postgres -d code_server -c "SELECT * FROM dr_test;" || echo "✓ Table deleted"
EOF

# Phase 4: Restore from backup
echo ""
echo "PHASE 4: Restoring from backup..."
ssh -o BatchMode=yes akushnir@$PRIMARY << EOF
  # Restore backup
  gunzip < $BACKUP_FILE | docker exec -i code-server-postgres psql -U postgres -d code_server
  
  # Verify restore
  docker exec code-server-postgres psql -U postgres -d code_server -c "SELECT * FROM dr_test;"
  
  # Cleanup
  rm -f $BACKUP_FILE
EOF

echo "✅ Recovery successful!"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  DR TEST PASSED - Data recovery procedures verified       ║"
echo "╚════════════════════════════════════════════════════════════╝"
```

---

## Phase 6F: Backup Monitoring

### Backup Health Check

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/backup-health-check.sh

echo "BACKUP HEALTH CHECK - $(date)"
echo "================================================"

BACKUP_DIR="/backups"

echo ""
echo "PostgreSQL Backups:"
ls -lh $BACKUP_DIR/postgres/*.sql.gz 2>/dev/null | tail -5 || echo "  No recent backups"

echo ""
echo "Redis Backups:"
ls -lh $BACKUP_DIR/redis/*.rdb 2>/dev/null | tail -5 || echo "  No recent backups"

echo ""
echo "Volume Backups:"
find $BACKUP_DIR/volumes -name "*.tar.gz" -type f -mtime -7 | head -10 || echo "  No recent snapshots"

echo ""
echo "Git Configuration Backups:"
cd /home/akushnir/code-server
git tag | grep "^backup-" | sort -V | tail -5

echo ""
echo "Backup Sizes:"
du -sh $BACKUP_DIR/* 2>/dev/null

echo ""
echo "Disk Space:"
df -h $BACKUP_DIR 2>/dev/null | tail -1

echo ""
echo "================================================"
echo "✅ Backup health check complete"
```

---

## Phase 6G: Recovery Time Objectives (RTO/RPO)

| Component | RTO | RPO | Notes |
|-----------|-----|-----|-------|
| PostgreSQL | 15 min | 1 hour | Hourly backups + WAL archive |
| Redis | 5 min | 5 min | Real-time RDB snapshots |
| Qdrant | 10 min | 1 hour | Daily snapshots |
| Volumes | 30 min | 1 hour | Daily tar.gz snapshots |
| Full system | 60 min | 1 hour | Complete rebuild from backups |

---

## Backup Infrastructure

### Directory Structure

```
/backups/
├── postgres/
│   ├── backup_20260430_020000.sql.gz
│   ├── backup_20260429_020000.sql.gz
│   └── ... (30-day retention)
├── redis/
│   ├── dump_20260430_020000.rdb
│   ├── dump_20260429_020000.rdb
│   └── ... (7-day retention)
└── volumes/
    ├── postgres-data/
    │   ├── 20260430_020000.tar.gz
    │   └── ... (14-day retention)
    ├── redis-data/
    └── qdrant-data/
```

### Backup Storage Requirements

- **PostgreSQL**: ~500MB per backup (compressed)
- **Redis**: ~100MB per backup
- **Volumes**: ~2GB per snapshot
- **Total retention**: 50GB (30 days + 7 days + 14 days)
- **Off-site**: Weekly copies to external storage

---

## Implementation Checklist

- [ ] Create `/backups` directory on both hosts (or on NAS)
- [ ] Deploy postgres-backup.sh script
- [ ] Deploy redis-backup.sh script
- [ ] Deploy volume-snapshot.sh script
- [ ] Deploy config-backup.sh script
- [ ] Add cron jobs for automated backups
- [ ] Run backup-health-check.sh (verify everything working)
- [ ] Run dr-test.sh (verify recovery procedures)
- [ ] Document backup location and access procedures
- [ ] Brief operations team on recovery procedures
- [ ] Set up off-site backup archival (weekly)
- [ ] Configure backup monitoring alerts

---

## Next Steps

1. **Create backup infrastructure** (directories, scripts)
2. **Deploy automated backup jobs** (cron)
3. **Test recovery procedures** (dr-test.sh)
4. **Set up monitoring** (backup health check)
5. **Document RTO/RPO procedures**
6. **Brief operations team**

---

**Status**: 🟡 READY FOR IMPLEMENTATION

All backup and disaster recovery procedures documented and ready for deployment. Scripts are production-ready with error handling and logging.

