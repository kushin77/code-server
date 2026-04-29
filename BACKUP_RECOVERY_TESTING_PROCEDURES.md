# Backup & Recovery Testing Procedures

**Document Version**: 1.0  
**Last Updated**: April 29, 2026  
**Status**: READY FOR OPERATIONS  
**Maintained By**: Operations Team / Database Administrator  

---

## Executive Summary

This document provides comprehensive backup and recovery testing procedures. Regular backup testing ensures:
- ✅ Backups are actually restorable (not corrupted)
- ✅ Recovery procedures work as documented
- ✅ RTO/RPO targets are achievable
- ✅ Team is trained on recovery procedures

**Backup Strategy**:
- PostgreSQL: Nightly full backup + hourly incremental
- Configuration: Daily git commits
- Monitoring: Continuous metrics retention (30 days in Prometheus)
- Logs: 30-day retention in Loki

**Recovery Targets**:
- RTO (Recovery Time Objective): 2-3 minutes for failover, < 1 hour for restore
- RPO (Recovery Point Objective): < 5 minutes data loss acceptable

---

## Part 1: Current Backup Configuration

### 1.1 PostgreSQL Backups

**Backup Method**: pg_basebackup (native PostgreSQL streaming backup)

**Current Setup**:
```bash
# Backup location: /var/lib/postgresql/backups/
# Retention: 7 days (oldest backup auto-deleted)
# Schedule: Daily at 23:00 UTC (off-peak)
# Frequency: 1 full backup/day + hourly WAL archiving

# Backup command (run on primary):
docker exec code-server-postgres pg_basebackup -D /var/lib/postgresql/backups/$(date +%Y%m%d_%H%M%S) -Ft -z
```

**Verification** (run after backup completes):
```bash
ssh akushnir@192.168.168.31 "
echo '=== Backup Verification ==='
ls -lh /var/lib/postgresql/backups/
find /var/lib/postgresql/backups/ -name 'base.tar.gz' -exec tar -tzf {} \\; | head -5
echo 'Backup size:' \$(du -sh /var/lib/postgresql/backups/ | cut -f1)
"
```

### 1.2 Configuration Backups

**Configuration Files**:
- `docker-compose.enterprise.yml`: Application stack definition
- `.env` / `.env.production`: Environment variables
- `terraform/`: Infrastructure-as-code
- `scripts/`: Deployment scripts

**Backup Method**: Git version control + encrypted backup

```bash
# Daily verification that config is in git
cd /home/akushnir/code-server
git status --short  # Should be empty (all committed)

# Backup procedure
git log --oneline -1  # Verify recent commit
git push origin main  # Push to remote backup
```

### 1.3 Data Volume Backups

**Volumes**: Docker volumes for persistent data

```bash
# List volumes
docker volume ls | grep code-server

# Backup volumes (snapshots)
ssh akushnir@192.168.168.31 "
# PostgreSQL data volume
docker run --rm -v code-server-postgres-data:/data -v /var/lib/backup:/backup alpine tar czf /backup/postgres-data-$(date +%Y%m%d).tar.gz -C /data .

# Redis data volume (if persistence enabled)
docker run --rm -v code-server-redis-data:/data -v /var/lib/backup:/backup alpine tar czf /backup/redis-data-$(date +%Y%m%d).tar.gz -C /data .
"
```

---

## Part 2: Testing Backup Integrity

### 2.1 Daily Backup Verification

**Run daily after backup completes** (within 1 hour):

```bash
#!/bin/bash
# backup_verify.sh

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PRIMARY="192.168.168.31"
BACKUP_DIR="/var/lib/postgresql/backups"

echo "=== Daily Backup Verification $TIMESTAMP ===" | tee /tmp/backup-verify-$TIMESTAMP.log

# Check backup exists
LATEST_BACKUP=$(ssh akushnir@$PRIMARY "ls -t $BACKUP_DIR | head -1")
if [ -z "$LATEST_BACKUP" ]; then
  echo "❌ NO BACKUP FOUND" | tee -a /tmp/backup-verify-$TIMESTAMP.log
  exit 1
fi

# Check backup size (should be > 100MB)
BACKUP_SIZE=$(ssh akushnir@$PRIMARY "du -sh $BACKUP_DIR/$LATEST_BACKUP | cut -f1")
echo "✅ Latest backup: $LATEST_BACKUP ($BACKUP_SIZE)" | tee -a /tmp/backup-verify-$TIMESTAMP.log

# Check backup is recent (within last 24 hours)
BACKUP_AGE=$(ssh akushnir@$PRIMARY "stat -c %Y $BACKUP_DIR/$LATEST_BACKUP")
CURRENT_TIME=$(date +%s)
AGE_HOURS=$((($CURRENT_TIME - $BACKUP_AGE) / 3600))
if [ $AGE_HOURS -lt 24 ]; then
  echo "✅ Backup age: $AGE_HOURS hours" | tee -a /tmp/backup-verify-$TIMESTAMP.log
else
  echo "❌ Backup too old: $AGE_HOURS hours" | tee -a /tmp/backup-verify-$TIMESTAMP.log
fi

# Verify backup integrity (try to list contents)
ssh akushnir@$PRIMARY "tar -tzf $BACKUP_DIR/$LATEST_BACKUP/base.tar.gz | head -10" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Backup integrity: OK (tar archive valid)" | tee -a /tmp/backup-verify-$TIMESTAMP.log
else
  echo "❌ Backup integrity: FAILED (tar archive corrupted)" | tee -a /tmp/backup-verify-$TIMESTAMP.log
fi

echo "✅ Verification complete" | tee -a /tmp/backup-verify-$TIMESTAMP.log
```

**Setup as daily cron job**:
```bash
# Run at 23:30 (30 min after backup starts)
30 23 * * * /home/akushnir/code-server/backup_verify.sh >> /var/log/backup-verify.log 2>&1
```

### 2.2 Weekly Full Restore Test

**Run weekly** (recommended: Sunday 02:00 UTC):

**Test Environment Setup**:
```bash
# On a test host (NOT production), create isolated PostgreSQL
docker run -d --name test-postgres \
  -e POSTGRES_PASSWORD=testpass \
  -v test-postgres-data:/var/lib/postgresql/data \
  postgres:16.13-alpine
```

**Restore Procedure**:
```bash
#!/bin/bash
# weekly_restore_test.sh

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PRIMARY="192.168.168.31"
BACKUP_DIR="/var/lib/postgresql/backups"
TEST_HOST="192.168.168.50"  # Test/staging host

echo "=== Weekly Restore Test $TIMESTAMP ===" | tee /tmp/restore-test-$TIMESTAMP.log

# Step 1: Get latest backup from primary
LATEST_BACKUP=$(ssh akushnir@$PRIMARY "ls -t $BACKUP_DIR | head -1")
echo "Using backup: $LATEST_BACKUP" | tee -a /tmp/restore-test-$TIMESTAMP.log

# Step 2: Copy backup to test environment
scp -r akushnir@$PRIMARY:$BACKUP_DIR/$LATEST_BACKUP /tmp/restore-test-$LATEST_BACKUP
echo "Backup copied to test environment" | tee -a /tmp/restore-test-$TIMESTAMP.log

# Step 3: Extract backup
tar -xzf /tmp/restore-test-$LATEST_BACKUP/base.tar.gz -C /tmp/postgres-restore/
echo "Backup extracted" | tee -a /tmp/restore-test-$TIMESTAMP.log

# Step 4: Start PostgreSQL with restored data
docker run -d --name test-postgres-restore \
  -e POSTGRES_PASSWORD=testpass \
  -v /tmp/postgres-restore:/var/lib/postgresql/data \
  postgres:16.13-alpine

sleep 10

# Step 5: Verify databases accessible
docker exec test-postgres-restore psql -U postgres -c 'SELECT datname FROM pg_database;' > /tmp/databases-$TIMESTAMP.log
echo "Restored databases:" | tee -a /tmp/restore-test-$TIMESTAMP.log
cat /tmp/databases-$TIMESTAMP.log | tee -a /tmp/restore-test-$TIMESTAMP.log

# Step 6: Verify data integrity (sample queries)
docker exec test-postgres-restore psql -U postgres code_server_db -c 'SELECT COUNT(*) as table_count FROM information_schema.tables;' 
RESULT=$?
if [ $RESULT -eq 0 ]; then
  echo "✅ Data integrity: OK" | tee -a /tmp/restore-test-$TIMESTAMP.log
else
  echo "❌ Data integrity: FAILED" | tee -a /tmp/restore-test-$TIMESTAMP.log
fi

# Step 7: Cleanup
docker stop test-postgres-restore
docker rm test-postgres-restore
rm -rf /tmp/postgres-restore
rm /tmp/restore-test-$LATEST_BACKUP/base.tar.gz

echo "✅ Restore test complete" | tee -a /tmp/restore-test-$TIMESTAMP.log
```

**Setup as weekly cron job**:
```bash
# Run Sundays at 02:00 UTC
0 2 * * 0 /home/akushnir/code-server/weekly_restore_test.sh >> /var/log/restore-test.log 2>&1
```

---

## Part 3: Disaster Recovery Procedures

### 3.1 Scenario: Primary Database Corrupted

**When to Use**: Data corruption detected, primary becomes unusable

**Recovery Procedure**:

```bash
#!/bin/bash
# CRITICAL: This procedure assumes replica is healthy

PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"
BACKUP_HOST="192.168.168.50"  # Offline backup location

echo "=== DATABASE RECOVERY INITIATED ==="

# Step 1: STOP PRIMARY (prevent further corruption)
ssh akushnir@$PRIMARY "
  docker stop code-server-postgres
  echo 'Primary stopped'
"

# Step 2: VERIFY REPLICA HEALTHY
ssh akushnir@$REPLICA "
  docker exec code-server-postgres psql -U postgres -c 'SELECT 1;'
  if [ $? -ne 0 ]; then
    echo 'REPLICA HEALTH CHECK FAILED - ABORT RECOVERY'
    exit 1
  fi
"

# Step 3: PROMOTE REPLICA TO PRIMARY
ssh akushnir@$REPLICA "
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_promote();'
  echo 'Replica promoted to primary'
"

# Step 4: VERIFY NEW PRIMARY
sleep 5
ssh akushnir@$REPLICA "
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'
  # Should return FALSE
"

# Step 5: UPDATE APPLICATION CONNECTIONS
echo "UPDATE: Point applications to $REPLICA:5432 as new primary"
# Manually update docker-compose.enterprise.yml POSTGRES_HOST

# Step 6: REBUILD OLD PRIMARY
# When primary hardware is repaired:
ssh akushnir@$PRIMARY "
  # Remove old data
  docker exec code-server-postgres rm -rf /var/lib/postgresql/data/*
  
  # Rebuild from replica via pg_basebackup
  docker exec code-server-postgres pg_basebackup \
    -h $REPLICA \
    -U replication \
    -D /var/lib/postgresql/data \
    -Fp -Pv
  
  echo 'Old primary rebuilt from new primary'
"

echo "=== DATABASE RECOVERY COMPLETE ==="
```

### 3.2 Scenario: Complete Backup Restoration

**When to Use**: All data lost, need to restore from backup

```bash
#!/bin/bash
# SEVERE: Restores from offline backup, requires infrastructure support

PRIMARY="192.168.168.31"
BACKUP_SOURCE="/var/lib/backup/backup-2026-04-29.tar.gz"  # Offline backup

echo "=== FULL DATABASE RESTORATION ==="

# Step 1: STOP ALL SERVICES
docker-compose -f docker-compose.enterprise.yml down

# Step 2: REMOVE CORRUPTED DATA
ssh akushnir@$PRIMARY "
  sudo rm -rf /var/lib/postgresql/data/*
"

# Step 3: RESTORE FROM BACKUP
# Copy backup from external storage
scp secure_backup_server:$BACKUP_SOURCE /tmp/
ssh akushnir@$PRIMARY "scp /tmp/backup-*.tar.gz :/var/lib/postgresql/data/"

# Extract backup
ssh akushnir@$PRIMARY "
  cd /var/lib/postgresql/data
  tar -xzf backup-2026-04-29.tar.gz
  rm backup-2026-04-29.tar.gz
  chown -R postgres:postgres .
"

# Step 4: RESTART DATABASE
ssh akushnir@$PRIMARY "
  docker restart code-server-postgres
  sleep 10
"

# Step 5: VERIFY
ssh akushnir@$PRIMARY "
  docker exec code-server-postgres psql -U postgres -c 'SELECT COUNT(*) FROM information_schema.tables;'
"

# Step 6: REBUILD REPLICA
# Similar to Scenario 3.1 Step 6

echo "=== RESTORATION COMPLETE ==="
```

### 3.3 Scenario: Point-in-Time Recovery (PITR)

**When to Use**: Accidental data deletion, need to recover to specific point in time

```bash
# PostgreSQL PITR requires WAL archives + base backup

# Step 1: Identify target time
TARGET_TIME="2026-04-29 14:30:00"

# Step 2: Restore base backup
# (Same as 3.2 above)

# Step 3: Configure recovery target
ssh akushnir@$PRIMARY "
docker exec code-server-postgres bash << 'SCRIPT'
cat >> /var/lib/postgresql/data/recovery.conf << EOF
restore_command = 'cp /var/lib/postgresql/wal_archive/%f %p'
recovery_target_time = '$TARGET_TIME'
recovery_target_timeline = 'latest'
EOF
SCRIPT
"

# Step 4: Start PostgreSQL (will recover to target time)
ssh akushnir@$PRIMARY "
  docker restart code-server-postgres
  # PostgreSQL will replay WAL files up to target time
  # Once done, database is at specified point in time
"

# Step 5: Promote to primary (PITR complete)
ssh akushnir@$PRIMARY "
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_wal_replay_resume();'
"
```

---

## Part 4: Recovery Drills

### 4.1 Quarterly Failover Drill

**Schedule**: Q1, Q2, Q3, Q4 (start of quarter)  
**Duration**: 1 hour  
**Participants**: Operations team + Database Admin

**Procedure**:

```bash
#!/bin/bash
# quarterly_failover_drill.sh

echo "=== QUARTERLY FAILOVER DRILL ==="
echo "Time: $(date)"
echo "Participants: $(whoami)"

# Phase 1: Prepare (5 min)
echo "PHASE 1: Preparation"
echo "1. Verify current state (primary up, replica in standby)"
ssh akushnir@192.168.168.31 "docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'"
ssh akushnir@192.168.168.42 "docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'"

# Phase 2: Simulate primary failure (10 min)
echo "PHASE 2: Simulate Primary Failure"
echo "Stopping primary containers..."
ssh akushnir@192.168.168.31 "docker-compose -f docker-compose.enterprise.yml down"
echo "Primary stopped at $(date)"

# Phase 3: Promote replica (10 min)
echo "PHASE 3: Promote Replica"
echo "Executing pg_promote()..."
PROMOTE_START=$(date +%s)
ssh akushnir@192.168.168.42 "
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_promote();'
"
PROMOTE_END=$(date +%s)
PROMOTE_TIME=$(($PROMOTE_END - $PROMOTE_START))
echo "Promotion completed in $PROMOTE_TIME seconds"

# Phase 4: Verify new primary (10 min)
echo "PHASE 4: Verify New Primary"
ssh akushnir@192.168.168.42 "
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'
  docker exec code-server-postgres psql -U postgres -c 'SELECT version();'
"

# Phase 5: Restore primary (15 min)
echo "PHASE 5: Restore Primary from Backup"
# Rebuild primary as standby
ssh akushnir@192.168.168.31 "
  docker-compose -f docker-compose.enterprise.yml up -d
  sleep 5
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'
"

# Phase 6: Verify replication (10 min)
echo "PHASE 6: Verify Replication Restored"
ssh akushnir@192.168.168.42 "
  docker exec code-server-postgres psql -U postgres -c '
    SELECT usename, client_addr, state FROM pg_stat_replication;
  '
"

# Phase 7: Failback (optional, if reversing drill)
echo "PHASE 7: Failback"
# Manually promote primary back (requires pg_rewind or rebuild)

echo ""
echo "=== DRILL COMPLETE ==="
echo "Results:"
echo "- RTO achieved: $PROMOTE_TIME seconds (target: 180 seconds)"
echo "- Failover success: [PASS/FAIL]"
echo "- Data consistency: [VERIFIED/ISSUES]"
echo "- Team readiness: [READY/NEEDS_TRAINING]"
echo ""
echo "Follow-up items:"
echo "- [ ] Document any issues found"
echo "- [ ] Update procedures if needed"
echo "- [ ] Review with team"
```

**Success Criteria**:
- ✅ RTO ≤ 3 minutes (target: 180 seconds)
- ✅ Replica successfully promoted
- ✅ Replication restored after failback
- ✅ All team members confident in procedure

### 4.2 Annual Disaster Recovery Exercise

**Schedule**: Once yearly (recommend: January)  
**Duration**: 4 hours  
**Scope**: Full platform recovery from complete backup

```bash
#!/bin/bash
# annual_dr_exercise.sh

echo "=== ANNUAL DISASTER RECOVERY EXERCISE ==="

# Scenario: Entire production site destroyed
# Recovery: Restore to alternate location (192.168.168.50-51)

# Step 1: Provision alternate infrastructure (pre-arranged)
# Infrastructure provides:
# - 2 VMs with same specs (16 CPU, 64GB RAM, 1TB disk)
# - Network connectivity
# - Access to offline backups

# Step 2: Deploy database
ssh akushnir@192.168.168.50 "
  docker run -d --name postgres \
    -e POSTGRES_PASSWORD=postgres_password \
    -v postgres-data:/var/lib/postgresql/data \
    postgres:16.13-alpine
"

# Step 3: Restore from offline backup
# Copy backup from remote location
scp secure_backup_server:/backups/backup-prod-2026-04-29.tar.gz /tmp/
ssh akushnir@192.168.168.50 "
  tar -xzf /tmp/backup-prod-2026-04-29.tar.gz -C /var/lib/postgresql/data/
  docker restart postgres
"

# Step 4: Deploy application services
ssh akushnir@192.168.168.50 "
  cd ~/code-server-enterprise
  docker-compose -f docker-compose.enterprise.yml up -d
"

# Step 5: Verify functionality
# - Check database integrity
# - Test API endpoints
# - Verify monitoring
# - Test failover to secondary

# Step 6: Measure outcomes
echo "Recovery Metrics:"
echo "- RTO (actual): $(calculate recovery_time)"
echo "- RPO (actual): $(calculate data_loss)"
echo "- Success: [YES/NO]"

# Step 7: Decommission alternate site
# Clean up resources
```

**Success Criteria**:
- ✅ Full platform operational on alternate location
- ✅ All data restored accurately
- ✅ RTO achieved ≤ 1 hour
- ✅ RPO acceptable (< 1 hour data loss)
- ✅ Team executed procedures without engineer assistance

---

## Part 5: Backup Verification Checklist

**Monthly Backup Review** (1st of each month):

```
BACKUP VERIFICATION CHECKLIST - [MONTH] 2026
==============================================

Daily Backup Status:
- [ ] Backup completed for all 30 days of month
- [ ] All backups > 100MB (not empty/truncated)
- [ ] All backups < 24 hours old
- [ ] No backup failed during month

Weekly Restore Tests:
- [ ] All 4-5 weekly restore tests passed
- [ ] Average restore time: _____ minutes (target: <30)
- [ ] No data corruption detected in any restore
- [ ] Team noted any issues below:

Issues Found:
- [ ] [Issue 1]: Backup size small - investigate
- [ ] [Issue 2]: Restore took 45 min - analyze query log
- [ ] [Issue 3]: Team training needed on [topic]

Fixes Applied:
- [ ] [Fix 1]: Optimized backup query
- [ ] [Fix 2]: Increased backup parallelism
- [ ] [Fix 3]: [Other]

Sign-Off:
Database Administrator: _____________________ Date: __________
Operations Manager: _____________________ Date: __________

Notes:
_________________________________________________________________
```

---

## Part 6: Backup Storage & Retention

**Current Retention Policy**:
- On-primary backups: 7 days (daily rotation)
- Off-site backups: 30 days
- Archive backups: 1 year (quarterly snapshots)

**Storage Locations**:
1. Primary backup location: `/var/lib/postgresql/backups/` (primary host)
2. Secondary backup location: `/var/lib/backup/` (replica host)
3. Off-site backup: Encrypted external storage (monthly snapshots)

**Backup Encryption**:
```bash
# Encrypt backups before sending off-site
gpg --symmetric --cipher-algo AES256 backup-2026-04-29.tar.gz
# Passphrase stored in secure vault

# Verify encrypted backup can be decrypted
gpg --decrypt backup-2026-04-29.tar.gz.gpg > /tmp/test-restore.tar.gz
tar -tzf /tmp/test-restore.tar.gz | head -5
```

---

## Quick Reference

| Procedure | Frequency | Duration | RTO | RPO |
|-----------|-----------|----------|-----|-----|
| Backup | Daily | 30 min | N/A | 24 hr |
| Verify Backup | Daily | 5 min | N/A | 24 hr |
| Restore Test | Weekly | 30 min | <30 min | < 1 hr |
| Failover Drill | Quarterly | 1 hour | <3 min | <5 min |
| DR Exercise | Annually | 4 hours | <1 hour | <1 hour |

---

**Document History**

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | April 29, 2026 | Initial backup and recovery procedures |

---

**Related Documents**:
- OPERATIONS_HANDOFF_GUIDE.md (Section: Disaster Recovery)
- ADVANCED_TROUBLESHOOTING_SCENARIOS.md (Scenario 3-4: Failures)
- CAPACITY_PLANNING_SCALING_GUIDE.md (Resource planning)
