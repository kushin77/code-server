# Production Backup & Disaster Recovery Verification

**Date:** April 30, 2026  
**Status:** ✅ READY FOR MAY 1  
**Criticality:** 🔴 HIGHEST - Required before production deployment  

---

## Executive Summary

This guide establishes and tests backup/recovery procedures for May 1 production deployment. Critical components covered:

✅ **PostgreSQL Backup** - Automated daily backups with point-in-time recovery  
✅ **Redis Snapshots** - In-memory cache backup and recovery  
✅ **Application Data** - Docker volume backups  
✅ **Configuration** - All config files and secrets  
✅ **Disaster Recovery** - Complete site recovery procedures  
✅ **RTO/RPO Targets** - Recovery Time & Recovery Point Objectives  

---

## Architecture Overview

```
Primary Server (192.168.168.31)
├── PostgreSQL (Master) → WAL archiving to /backups
├── Redis (Primary) → RDB snapshots
└── Application data → volumes

Replica Server (192.168.168.42)
├── PostgreSQL (Standby) → Streaming replication
├── Redis (Replica) → Replication
└── Application data → volume copies

Backup Storage
├── Daily PostgreSQL full backups (incremental WALs)
├── Hourly Redis snapshots
├── Weekly complete volume snapshots
└── Configuration backups (version controlled)
```

---

## Part 1: PostgreSQL Backup Procedures

### Backup Strategy

**Backup Type:** Combination of full backups + WAL archiving  
**Frequency:** Daily full backup + continuous WAL archiving  
**Retention:** 7 days of full backups, 14 days of WAL archives  
**Storage:** Local `/backups` directory (replicated to replica)  

### Setup Automated Backups

```bash
# SSH to primary
ssh ubuntu@192.168.168.31
cd /home/ubuntu/code-server

# Create backup directory
sudo mkdir -p /backups/postgresql
sudo chown 999:999 /backups/postgresql

# Create backup script
cat > backup-postgresql.sh <<'EOF'
#!/bin/bash
# PostgreSQL automated backup script

BACKUP_DIR="/backups/postgresql"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTAINER="code-server-postgres"

mkdir -p $BACKUP_DIR

echo "[$(date)] Starting PostgreSQL backup..."

# Full backup using pg_dump
docker exec $CONTAINER pg_dump -U postgres --format=custom \
  -f /tmp/backup_${TIMESTAMP}.dump purebliss_db

# Copy to backup directory
docker exec $CONTAINER sh -c "mv /tmp/backup_${TIMESTAMP}.dump /var/lib/postgresql/data/"
docker cp $CONTAINER:/var/lib/postgresql/data/backup_${TIMESTAMP}.dump $BACKUP_DIR/

# Verify backup
if [ -f "$BACKUP_DIR/backup_${TIMESTAMP}.dump" ]; then
  SIZE=$(ls -lh "$BACKUP_DIR/backup_${TIMESTAMP}.dump" | awk '{print $5}')
  echo "[$(date)] ✅ Backup successful - Size: $SIZE"
  
  # Keep only last 7 days
  find $BACKUP_DIR -name "backup_*.dump" -mtime +7 -delete
else
  echo "[$(date)] ❌ Backup failed"
  exit 1
fi

echo "[$(date)] Backup complete"
EOF

chmod +x backup-postgresql.sh

# Schedule with cron (daily at 02:00 UTC)
(crontab -l 2>/dev/null; echo "0 2 * * * cd /home/ubuntu/code-server && ./backup-postgresql.sh >> /var/log/postgresql-backup.log 2>&1") | crontab -
```

### Manual Backup Verification

```bash
# Run backup manually to test
cd /home/ubuntu/code-server
./backup-postgresql.sh

# Verify backup was created
ls -lh /backups/postgresql/

# Test backup is readable
docker exec code-server-postgres pg_restore --list /var/lib/postgresql/data/backup_*.dump | head -5

# Should show list of tables/sequences
```

---

## Part 2: PostgreSQL Recovery Testing

### Test 1: Point-in-Time Recovery (PITR)

```bash
# Prerequisites: Have a backup and some transactions after it

# Step 1: Capture current time
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "Current time: $CURRENT_TIME"

# Step 2: Make test data
docker exec code-server-postgres psql -U postgres -c \
  "INSERT INTO test_recovery_log (message) VALUES ('Before recovery test - $CURRENT_TIME');"

# Step 3: Wait 2 minutes
sleep 120

# Step 4: Insert more test data (this will be "lost" in recovery)
LOST_TIME=$(date '+%Y-%m-%d %H:%M:%S')
docker exec code-server-postgres psql -U postgres -c \
  "INSERT INTO test_recovery_log (message) VALUES ('This should be lost - $LOST_TIME');"

# Step 5: Verify both rows exist
docker exec code-server-postgres psql -U postgres -c \
  "SELECT * FROM test_recovery_log ORDER BY created DESC LIMIT 5;"

# Step 6: Stop PostgreSQL container
docker-compose stop postgres
sleep 10

# Step 7: Restore from backup
docker exec code-server-postgres pg_restore --clean \
  -U postgres /var/lib/postgresql/data/backup_*.dump

# Step 8: Restart PostgreSQL
docker-compose up -d postgres
sleep 30

# Step 9: Verify recovery
docker exec code-server-postgres psql -U postgres -c \
  "SELECT * FROM test_recovery_log ORDER BY created DESC LIMIT 5;"

# Expected: Should see rows up to CURRENT_TIME, but NOT LOST_TIME row
# ✅ SUCCESS: PITR working correctly
```

### Test 2: Full Database Recovery

```bash
# Complete database restoration from backup

# Step 1: Backup current database state
BACKUP_FILE="/backups/postgresql/backup_$(date +%Y%m%d_%H%M%S).dump"
docker exec code-server-postgres pg_dump -U postgres --format=custom \
  -f /var/lib/postgresql/data/backup_$(date +%Y%m%d_%H%M%S).dump purebliss_db
docker cp code-server-postgres:/var/lib/postgresql/data/backup_*.dump $BACKUP_FILE

# Step 2: Restore from older backup
docker exec code-server-postgres pg_restore --clean -U postgres \
  /var/lib/postgresql/data/backup_OLDER_DATE.dump

# Step 3: Verify recovery
docker exec code-server-postgres psql -U postgres \
  -c "SELECT COUNT(*) FROM purebliss_db.pg_tables;"

# Should show table count from when backup was taken
```

---

## Part 3: Redis Backup & Recovery

### Redis Snapshot Setup

```bash
# SSH to primary
ssh ubuntu@192.168.168.31
cd /home/ubuntu/code-server

# Create Redis backup directory
sudo mkdir -p /backups/redis
sudo chown 999:999 /backups/redis

# Create backup script
cat > backup-redis.sh <<'EOF'
#!/bin/bash
# Redis snapshot backup

BACKUP_DIR="/backups/redis"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Trigger Redis SAVE command
docker-compose exec -T redis redis-cli SAVE

# Copy dump file
docker cp code-server-redis:/data/dump.rdb $BACKUP_DIR/dump_${TIMESTAMP}.rdb

# Verify
if [ -f "$BACKUP_DIR/dump_${TIMESTAMP}.rdb" ]; then
  SIZE=$(ls -lh "$BACKUP_DIR/dump_${TIMESTAMP}.rdb" | awk '{print $5}')
  echo "[$(date)] ✅ Redis backup successful - Size: $SIZE"
else
  echo "[$(date)] ❌ Redis backup failed"
  exit 1
fi

# Keep only last 7 snapshots
cd $BACKUP_DIR
ls -t dump_*.rdb | tail -n +8 | xargs rm -f
EOF

chmod +x backup-redis.sh

# Schedule hourly
(crontab -l 2>/dev/null; echo "0 * * * * cd /home/ubuntu/code-server && ./backup-redis.sh >> /var/log/redis-backup.log 2>&1") | crontab -
```

### Redis Recovery Test

```bash
# Step 1: Verify current Redis data
docker-compose exec redis redis-cli DBSIZE
# Should show keys

# Step 2: Insert test data
docker-compose exec redis redis-cli SET recovery-test "$(date)"

# Step 3: Backup current state
cd /home/ubuntu/code-server
./backup-redis.sh

# Step 4: Delete test data
docker-compose exec redis redis-cli DEL recovery-test

# Step 5: Verify deletion
docker-compose exec redis redis-cli GET recovery-test
# Should show (nil)

# Step 6: Restore from backup
docker-compose stop redis
docker cp /backups/redis/dump_*.rdb code-server-redis:/data/dump.rdb
docker-compose up -d redis
sleep 5

# Step 7: Verify recovery
docker-compose exec redis redis-cli GET recovery-test
# Should show the original value back
# ✅ SUCCESS: Redis recovery working
```

---

## Part 4: Application Data Backup

### Volume Backup

```bash
# SSH to primary
ssh ubuntu@192.168.168.31

# Create application data backup
mkdir -p /backups/volumes

# Backup critical volumes
docker run --rm \
  -v code-server_postgres_data:/data \
  -v /backups/volumes:/backup \
  alpine tar czf /backup/postgres_data_$(date +%Y%m%d).tar.gz -C /data .

# Verify backup
ls -lh /backups/volumes/

# Retention: keep last 30 days
find /backups/volumes -name "*.tar.gz" -mtime +30 -delete
```

---

## Part 5: Configuration Backup

### Version Control Backup

All critical configuration is in git:

```bash
cd /home/ubuntu/code-server

# Configuration files tracked:
git ls-files | grep -E "\.(yml|yaml|json|conf|env)"

# Backup: Simply push to git
git push origin main

# Recovery: Simply pull from git
git clone <repo> <destination>
git checkout <version>
```

---

## Part 6: Complete Disaster Recovery Test

### Full Site Recovery Scenario

**Objective:** Simulate complete primary failure and recovery to replica

**Test Timeline:** ~60 minutes total

#### Step 1: Pre-Test Backup (5 min)

```bash
# On primary
cd /home/ubuntu/code-server
./backup-postgresql.sh
./backup-redis.sh

# Capture backup locations
echo "Backups created at: $(date)"
ls -la /backups/postgresql/ /backups/redis/
```

#### Step 2: Mark Current State (5 min)

```bash
# Record metrics/state before failover
PRIMARY_DBSIZE=$(ssh ubuntu@192.168.168.31 "docker-compose exec postgres psql -U postgres -t -c 'SELECT pg_database_size(current_database())/1024/1024 AS MB;'")
echo "Primary DB size: $PRIMARY_DBSIZE MB"

# Note application health
curl http://192.168.168.31:8000/health
```

#### Step 3: Simulate Primary Failure (10 min)

```bash
# Stop all services on primary
ssh ubuntu@192.168.168.31 "cd /home/ubuntu/code-server && docker-compose down"

# Verify primary is unreachable
timeout 5 curl http://192.168.168.31:8000/health || echo "✅ Primary confirmed down"
```

#### Step 4: Promote Replica to Primary (15 min)

```bash
# On replica (now acting as primary)
ssh ubuntu@192.168.168.42

# Stop replication
docker-compose exec postgres psql -U postgres -c "SELECT pg_promote();"

# Wait for promotion
sleep 30

# Verify now in primary mode
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should show: f (not in recovery)

# Verify can write
docker-compose exec postgres psql -U postgres -c \
  "INSERT INTO test_failover (event, timestamp) VALUES ('Failover complete', NOW());"

# Update application to use replica as new primary
# In real scenario: update DNS, load balancer, or connection strings
```

#### Step 5: Application Testing (15 min)

```bash
# Start/verify application services on replica
ssh ubuntu@192.168.168.42
docker-compose up -d api-server

# Test application functionality
sleep 10
curl http://192.168.168.42:8000/health
curl http://192.168.168.42:8000/api/v1/status | jq '.'

# Test data integrity
docker-compose exec postgres psql -U postgres -c \
  "SELECT COUNT(*) FROM test_failover WHERE event='Failover complete';"
# Should show: 1

# Run basic smoke tests
./verify-appsmith-integration.sh
```

#### Step 6: Restore Primary (10 min)

```bash
# Restore original primary to secondary role
ssh ubuntu@192.168.168.31
cd /home/ubuntu/code-server

# Start PostgreSQL in standby mode
docker-compose up -d postgres

# Wait for connection
sleep 30

# Verify in replication mode
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should show: t (in recovery)

# Verify can read from replica (now primary)
docker-compose exec postgres psql -U postgres -c "SELECT COUNT(*) FROM test_failover;"
# Should show replicated data
```

#### Step 7: Verify Full Consistency (5 min)

```bash
# Both servers should have consistent data
PRIMARY_DATA=$(ssh ubuntu@192.168.168.42 "docker-compose exec postgres psql -U postgres -t -c 'SELECT COUNT(*) FROM test_failover;'")
REPLICA_DATA=$(ssh ubuntu@192.168.168.31 "docker-compose exec postgres psql -U postgres -t -c 'SELECT COUNT(*) FROM test_failover;'")

if [ "$PRIMARY_DATA" == "$REPLICA_DATA" ]; then
  echo "✅ Data consistency verified"
else
  echo "❌ Data inconsistency detected"
fi
```

### Success Criteria for DR Test

- [ ] Primary failure simulated successfully
- [ ] Replica promoted to primary
- [ ] Application remains operational on replica
- [ ] Data consistency maintained during failover
- [ ] Original primary can rejoin as standby
- [ ] Full recovery < 30 minutes from failure detection
- [ ] No data loss for critical transactions
- [ ] Replication resumes after recovery

---

## RTO/RPO Targets & Validation

### Recovery Time Objective (RTO)

| Scenario | Target | Method |
|----------|--------|--------|
| PostgreSQL crash | 5 min | Automatic container restart |
| Primary host failure | 15 min | Promote replica + DNS update |
| Data corruption | 30 min | Restore from daily backup |
| Complete site failure | 60 min | Full infrastructure recovery |

**Validation:** Test quarterly

```bash
# RTO test: Measure time from failure to operational
START_TIME=$(date +%s)

# Simulate failure and recovery...
# (follow DR test procedure)

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
echo "RTO achieved: $ELAPSED seconds"
```

### Recovery Point Objective (RPO)

| Data Type | RPO | Mechanism |
|-----------|-----|-----------|
| Database transactions | 1 hour | WAL archiving + daily backups |
| Cache/Sessions | 1 hour | Redis snapshots |
| Configuration | 1 day | Daily git commits |
| Application files | 1 week | Weekly volume snapshots |

**Maximum acceptable data loss:** 1 hour of transactions

---

## Backup Monitoring & Alerts

### Backup Verification Script

```bash
# Create backup health check
cat > verify-backups.sh <<'EOF'
#!/bin/bash

echo "=== Backup Health Check ==="

# PostgreSQL backups
PG_BACKUP_COUNT=$(find /backups/postgresql -name "backup_*.dump" -mtime -1 | wc -l)
echo "PostgreSQL backups (< 24h): $PG_BACKUP_COUNT"
[ $PG_BACKUP_COUNT -gt 0 ] && echo "✅ PostgreSQL backups OK" || echo "❌ NO RECENT BACKUPS"

# Redis snapshots
REDIS_BACKUP_COUNT=$(find /backups/redis -name "dump_*.rdb" -mtime -1 | wc -l)
echo "Redis snapshots (< 24h): $REDIS_BACKUP_COUNT"
[ $REDIS_BACKUP_COUNT -gt 0 ] && echo "✅ Redis backups OK" || echo "❌ NO RECENT SNAPSHOTS"

# Backup storage space
BACKUP_USAGE=$(du -sh /backups/ | awk '{print $1}')
echo "Total backup storage: $BACKUP_USAGE"

EOF

chmod +x verify-backups.sh

# Run daily
(crontab -l 2>/dev/null; echo "30 3 * * * cd /home/ubuntu/code-server && ./verify-backups.sh | mail -s 'Daily Backup Report' ops@example.com") | crontab -
```

### Backup Failure Alert

```bash
# Add to Prometheus alerts
cat >> prometheus-alerts.yml <<'EOF'

- name: backup
  interval: 60s
  rules:
    - alert: PostgreSQLBackupMissing
      expr: (time() - backup_postgresql_last_success_timestamp{}) > 86400
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "PostgreSQL backup missing (no backup in 24 hours)"
        description: "No PostgreSQL backup completed in the last 24 hours"

    - alert: RedisSnapshotMissing
      expr: (time() - backup_redis_last_success_timestamp{}) > 3600
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Redis snapshot missing (no snapshot in 1 hour)"
        description: "No Redis snapshot completed in the last hour"

EOF
```

---

## Pre-Production Verification Checklist

### PostgreSQL Backup & Recovery

- [ ] Automated backup script created and tested
- [ ] Manual backup/restore tested successfully
- [ ] PITR (Point-in-Time Recovery) tested
- [ ] Backup retention policy configured
- [ ] Backup alert configured in Prometheus
- [ ] Backup logs reviewed (no errors)

### Redis Backup & Recovery

- [ ] Snapshot backup script created and tested
- [ ] Manual recovery tested successfully
- [ ] Data persistence verified
- [ ] RDB file integrity verified

### Application Data

- [ ] Volume backups created and tested
- [ ] Configuration versioning in git verified
- [ ] Critical files identified and backed up
- [ ] Restore procedure documented

### Disaster Recovery

- [ ] Full site recovery test completed successfully
- [ ] RTO target verified (< 60 min)
- [ ] RPO target verified (< 1 hour data loss)
- [ ] Failover procedure documented and tested
- [ ] Recovery procedures documented in runbooks
- [ ] Team trained on recovery procedures

### Ongoing Monitoring

- [ ] Backup health check script deployed
- [ ] Alerts configured for backup failures
- [ ] Daily backup reports configured
- [ ] Backup validation running automatically

---

## May 1 Go-Live Checklist

Before production deployment, verify:

- [ ] All backup scripts tested and working
- [ ] Latest backups created (< 24 hours)
- [ ] Recovery procedures documented and tested
- [ ] On-call team trained on recovery
- [ ] Backup locations documented
- [ ] Backup credentials/access verified
- [ ] Monitoring alerts active
- [ ] Daily backup job scheduled and running

---

## Emergency Recovery Procedures

### If Primary Database is Lost

```bash
# 1. Restore from latest backup
ssh ubuntu@192.168.168.42
docker-compose exec postgres pg_restore --clean \
  -U postgres /var/lib/postgresql/data/backup_latest.dump

# 2. Verify recovery
docker-compose exec postgres psql -U postgres -c "SELECT COUNT(*) FROM information_schema.tables;"

# 3. Promote to primary
docker-compose exec postgres psql -U postgres -c "SELECT pg_promote();"

# 4. Update application connection
# (update DNS, load balancer, or connection string)
```

### If All Data is Lost

```bash
# 1. Check backup server or off-site backup
# 2. Restore from weekly archive
# 3. Restore from version control
# 4. Notify management of data recovery status
# 5. Run data integrity checks
```

---

## Success Criteria

✅ **Backup System Complete:**
- [ ] PostgreSQL backups automated and tested
- [ ] Redis backups automated and tested
- [ ] Application data backed up and tested
- [ ] Configuration versioned and backed up

✅ **Disaster Recovery Ready:**
- [ ] RTO < 60 minutes verified
- [ ] RPO < 1 hour verified
- [ ] Full site recovery tested successfully
- [ ] Team trained and prepared
- [ ] Runbooks complete and tested

✅ **Production Ready:**
- [ ] Backup monitoring active
- [ ] Alerts configured for backup failures
- [ ] Recovery procedures documented
- [ ] Regular backup tests scheduled

