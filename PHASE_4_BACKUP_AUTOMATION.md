# PHASE 4: Backup & Disaster Recovery Automation

**Date:** April 30, 2026  
**Status:** PHASE 4 - Backup Infrastructure Implementation  
**Audience:** Operations Team, DevOps Engineers

---

## Executive Summary

Phase 4 establishes comprehensive automated backup and disaster recovery infrastructure for the code-server-enterprise production platform. The system protects all 13+ named Docker volumes, PostgreSQL database, Redis cache, and operational configurations through daily automated backups with point-in-time recovery capability.

### Objectives - PHASE 4
- ✅ Design multi-tier backup strategy
- ✅ Create automated backup scripts (PostgreSQL, Redis, volumes)
- ✅ Implement backup scheduling (cron/systemd)
- ✅ Document restore procedures
- ✅ Create disaster recovery runbooks
- ✅ Establish backup verification and monitoring
- ✅ Plan monthly recovery testing

---

## 1. Backup Architecture

### 1.1 Protected Data Assets

```
CRITICAL (Tier 1 - RPO: 1 hour)
├─ PostgreSQL Database (primary state)
│  ├─ Size: ~500MB-2GB
│  ├─ Backup: hourly pg_dump (compressed)
│  ├─ Retention: 30 days full
│  └─ RTO: <15 minutes
│
└─ Redis Cache (session/cache)
   ├─ Size: ~100-500MB
   ├─ Backup: hourly RDB snapshots
   ├─ Retention: 7 days
   └─ RTO: <5 minutes

OPERATIONAL (Tier 2 - RPO: 6 hours)
├─ Prometheus Metrics (monitoring data)
│  ├─ Size: ~5-10GB
│  ├─ Backup: daily snapshots
│  ├─ Retention: 30 days
│  └─ RTO: <30 minutes
│
├─ Loki Logs (aggregated logs)
│  ├─ Size: ~5-10GB
│  ├─ Backup: daily snapshots
│  ├─ Retention: 30 days
│  └─ RTO: <30 minutes
│
└─ Tempo Traces (distributed traces)
   ├─ Size: ~2-5GB
   ├─ Backup: daily snapshots
   ├─ Retention: 14 days
   └─ RTO: <30 minutes

CONFIGURATION (Tier 3 - RPO: 24 hours)
├─ Caddy TLS & Config (reverse proxy)
│  ├─ Size: ~10-50MB
│  ├─ Backup: daily archive
│  ├─ Retention: 90 days
│  └─ RTO: <5 minutes
│
├─ Docker Volumes (application data)
│  ├─ Qdrant, Ollama, Redpanda, etc.
│  ├─ Size: ~5-20GB
│  ├─ Backup: daily tar.gz
│  ├─ Retention: 30 days
│  └─ RTO: <1 hour
│
└─ Configuration Files (IaC)
   ├─ docker-compose.yml, .env, config/
   ├─ Backup: per-change to git
   ├─ Retention: infinite (git history)
   └─ RTO: <5 minutes
```

### 1.2 Storage Tiers

```
TIER 1: PRIMARY (Fast, Hot)
├─ Location: /backups/daily/ (local)
├─ Retention: 7 days full + 14 days incremental
├─ Purpose: Quick recovery (same-datacenter)
├─ Availability: 99.9% (local disk)
└─ Size: ~50-100GB

TIER 2: SECONDARY (Medium, Warm)
├─ Location: /mnt/nas-backup/ (NAS 192.168.168.56)
├─ Retention: 30 days full backups
├─ Purpose: Local failover/archival
├─ Availability: 99% (NAS replication)
└─ Size: ~500GB-1TB

TIER 3: TERTIARY (Slow, Cold) [Future]
├─ Location: AWS S3 / Cloud storage
├─ Retention: 90 days with lifecycle
├─ Purpose: Offsite disaster recovery
├─ Encryption: AES-256 at rest + TLS transit
└─ Size: ~2-5TB
```

### 1.3 RTO/RPO Targets

| Service | RTO | RPO | Backup Frequency |
|---------|-----|-----|------------------|
| PostgreSQL | <15 min | <1 hour | Hourly |
| Redis | <5 min | <1 hour | Hourly |
| Prometheus | <30 min | <6 hours | Daily |
| Loki | <30 min | <6 hours | Daily |
| Caddy/TLS | <5 min | <24 hours | Daily |
| Volumes | <1 hour | <24 hours | Daily |

---

## 2. Backup Script Implementation

### 2.1 PostgreSQL Backup (`backup-postgres.sh`)

Creates hourly logical backups of PostgreSQL with compression.

**Key Features:**
- pg_dump with custom format (compressed)
- Parallel jobs (4x) for faster backup
- Verification of backup integrity
- Automatic cleanup of old backups
- Logging to /var/log/code-server-backup-postgres.log
- Error handling and exit traps

**Schedule:** Every hour (0 minutes past each hour)  
**Retention:** 30 days full backups on primary, 60 days on NAS

### 2.2 Redis Backup (`backup-redis.sh`)

Creates hourly RDB snapshots of Redis cache.

**Key Features:**
- BGSAVE (non-blocking) for production safety
- Gzip compression of RDB file
- Docker volume copy from container
- Data integrity verification (key count check)
- 7-day local retention
- 14-day NAS retention

**Schedule:** Every hour (15 minutes past each hour)  
**Retention:** 7 days local, 14 days NAS

### 2.3 Volume Backup (`backup-volumes.sh`)

Creates daily tar.gz archives of all Docker volumes.

**Volumes Backed Up:**
- caddy_data, caddy_config
- prometheus_data, grafana_data
- loki_data, alertmanager_data
- qdrant_data, redis_data, redpanda_data
- ollama_models, tempo_data

**Key Features:**
- Alpine Linux container for tar operations
- Gzip compression (level 9)
- Per-volume tar files
- Automatic NAS replication
- 30-day retention on primary
- 60-day retention on NAS

**Schedule:** Daily at 2:00 AM  
**Retention:** 30 days local, 60 days NAS

---

## 3. Automated Scheduling

### 3.1 Cron Jobs

Location: `/etc/cron.d/code-server-backups`

```bash
# PostgreSQL: Hourly full backups
0 * * * * root /bin/bash /home/akushnir/code-server/scripts/backup/backup-postgres.sh

# Redis: Hourly backups  
15 * * * * root /bin/bash /home/akushnir/code-server/scripts/backup/backup-redis.sh

# Docker Volumes: Daily at 2 AM
0 2 * * * root /bin/bash /home/akushnir/code-server/scripts/backup/backup-volumes.sh

# Backup Verification: Daily at 4 AM
0 4 * * * root /bin/bash /home/akushnir/code-server/scripts/backup/verify-backups.sh

# Daily Report: 5 AM
0 5 * * * root /bin/bash /home/akushnir/code-server/scripts/backup/backup-report.sh
```

### 3.2 Systemd Timer (Alternative)

For systems preferring systemd timers over cron:

```ini
# /etc/systemd/system/code-server-backup-postgres.timer
[Unit]
Description=Code Server PostgreSQL Hourly Backup
Requires=code-server-backup-postgres.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

---

## 4. Restore Procedures

### 4.1 PostgreSQL Full Restore

```bash
# Find backup file
ls -lh /backups/daily/postgres/ | tail -5

# Restore to original database
BACKUP_FILE="/backups/daily/postgres/postgres_backup_20260430_140000.sql.gz"
pg_restore \
  -h localhost \
  -p 5432 \
  -U postgres \
  -d postgres \
  --verbose \
  --jobs=4 \
  "$BACKUP_FILE"

# Time: ~5-15 minutes depending on size
```

### 4.2 PostgreSQL Point-in-Time Restore

```bash
# Find backup closest to desired time
RESTORE_TIME="2026-04-30 12:00:00"
BACKUP_FILE=$(find /backups/daily/postgres -name "*.sql.gz" -newermt "2026-04-30" | head -1)

# Restore and verify
pg_restore -h localhost -d test_db "$BACKUP_FILE"
psql -d test_db -c "SELECT NOW();"  # Verify timestamp
```

### 4.3 Redis Restore

```bash
# Stop Redis
docker-compose stop redis

# Restore RDB file
BACKUP_FILE="/backups/daily/redis/redis_backup_latest.rdb.gz"
gunzip -c "$BACKUP_FILE" > /tmp/dump.rdb
docker cp /tmp/dump.rdb code-server-redis:/data/dump.rdb

# Restart Redis
docker-compose start redis
docker-compose exec redis redis-cli PING

# Time: <5 minutes
```

### 4.4 Volume Restore

```bash
# List available backups
ls -lh /backups/daily/volumes/

# Restore specific volume
VOLUME="prometheus_data"
BACKUP="/backups/daily/volumes/prometheus_data_20260430_020000.tar.gz"

docker run --rm \
  -v ${VOLUME}:/volume_data \
  -v /backups/daily/volumes:/backups \
  alpine:latest \
  tar -xzf /backups/daily/volumes/prometheus_data_20260430_020000.tar.gz \
  -C /volume_data

# Time: ~5-15 minutes depending on size
```

---

## 5. Disaster Recovery Scenarios

### Scenario 1: Complete Primary Host Failure (RTO: <2 hours)

**Goal:** Failover all services to replica host

**Steps:**
1. SSH to replica host (192.168.168.42)
2. Start all services: `docker-compose up -d`
3. Restore latest PostgreSQL backup
4. Restore latest Redis backup
5. Verify Keepalived VIP failover (should reach replica now)
6. Run health checks: `curl https://kushnir.cloud/health`
7. Monitor service startup logs

**Expected Timeline:**
- Services start: 2-3 minutes
- Database restore: 5-15 minutes
- Redis restore: 2-5 minutes
- Total RTO: <30 minutes

### Scenario 2: Database Corruption (RTO: <20 minutes)

**Goal:** Restore PostgreSQL from known good backup while keeping other services running

**Steps:**
1. Identify symptoms: Application errors, data inconsistency
2. Find latest good backup: `ls -ltr /backups/daily/postgres/ | tail -1`
3. Create temporary test restore: `pg_restore -d test_restore /backups/daily/postgres/postgres_backup_20260430_140000.sql.gz`
4. Verify test restore has correct data
5. Swap databases: `ALTER DATABASE postgres RENAME TO corrupt; ALTER DATABASE test_restore RENAME TO postgres;`
6. Restart application services: `docker-compose restart appsmith ollama`
7. Verify application functionality

**Expected Timeline:**
- Identify issue: 2-5 minutes
- Restore backup: 5-15 minutes  
- Verify and swap: 2-3 minutes
- Total RTO: <30 minutes

### Scenario 3: TLS Certificate Expiration (RTO: <10 minutes)

**Goal:** Restore Caddy configuration and certificates

**Steps:**
1. Identify issue: HTTPS errors, certificate expired
2. Stop Caddy: `docker-compose stop caddy`
3. Restore Caddy volume: `docker run --rm -v caddy_data:/volume_data -v /backups:/backups alpine tar -xzf /backups/daily/volumes/caddy_data_latest.tar.gz -C /volume_data`
4. Verify certificate: `openssl x509 -in /path/to/cert -text -noout`
5. Restart Caddy: `docker-compose start caddy`
6. Verify HTTPS: `curl -v https://kushnir.cloud`

**Expected Timeline:**
- Identify issue: 1 minute
- Restore backup: 2-3 minutes
- Restart and verify: 2-3 minutes
- Total RTO: <10 minutes

### Scenario 4: Ransomware/Data Corruption (RTO: <4 hours)

**Goal:** Full cluster restore from known-clean backup

**Steps:**
1. Isolate primary host (disconnect network)
2. Identify last-known good backup timestamp
3. On replica, restore all databases and volumes from that timestamp
4. Activate replica as primary via Keepalived
5. Run comprehensive verification tests
6. Audit logs to identify attack vector
7. Patch vulnerabilities and rebuild primary
8. Rejoin primary to cluster

**Expected Timeline:**
- Detection and isolation: 5-15 minutes
- Full restore (all DBs + volumes): 1-2 hours
- Verification and activation: 30-60 minutes
- Total RTO: <4 hours

---

## 6. Backup Monitoring & Alerting

### 6.1 Prometheus Monitoring

Add to alert rules:

```yaml
- alert: PostgreSQLBackupMissing
  expr: time() - backup_postgres_last_success_timestamp > 3600 * 2  # 2 hours
  for: 30m
  labels:
    severity: high
    service: postgres
  annotations:
    summary: "PostgreSQL backup missing (>2 hours old)"
    description: "Last successful PostgreSQL backup: {{ $value | humanizeDuration }} ago"

- alert: BackupDiskSpaceWarning
  expr: node_filesystem_avail_bytes{mountpoint="/backups"} < 10737418240  # 10GB
  for: 10m
  labels:
    severity: warning
    service: backup
  annotations:
    summary: "Backup disk space below 10GB"
    description: "Available: {{ $value | humanize1024 }}B"

- alert: BackupDiskSpaceCritical
  expr: node_filesystem_avail_bytes{mountpoint="/backups"} < 5368709120  # 5GB
  for: 5m
  labels:
    severity: critical
    service: backup
  annotations:
    summary: "Backup disk space below 5GB - IMMEDIATE ACTION REQUIRED"
```

### 6.2 Backup Health Dashboard

Add to Grafana:

```
Title: Backup Status & Health

Panels:
1. Last Backup Timestamps
   - PostgreSQL: Last success time
   - Redis: Last success time
   - Volumes: Last success time

2. Backup Sizes Trend
   - PostgreSQL size over 30 days
   - Redis size over 7 days
   - Volumes size over 30 days

3. Backup Storage Usage
   - Pie chart: /backups usage
   - Pie chart: /mnt/nas-backup usage

4. Recovery Test Results
   - Last 10 recovery tests
   - Pass/fail status
   - Recovery time

5. Backup Failures
   - Recent backup errors
   - Error types
   - Resolution status
```

---

## 7. Recovery Testing

### 7.1 Monthly Recovery Drill

**First Monday of each month at 3 AM:**

```bash
#!/bin/bash
# Monthly backup recovery test

BACKUP=$(find /backups/daily/postgres -mtime -7 -type f | shuf | head -1)
TEST_DB="restore_test_$(date +%s)"

echo "Recovery Test: $(date)"
echo "Backup: $BACKUP"

# Create test database
createdb -h localhost -U postgres "$TEST_DB" || exit 1

# Restore backup
pg_restore -h localhost -d "$TEST_DB" "$BACKUP" 2>&1 || exit 1

# Verify
TABLES=$(psql -h localhost -d "$TEST_DB" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")

if [ "$TABLES" -gt 0 ]; then
  echo "✅ PASS: Restored $TABLES tables"
  dropdb -h localhost -U postgres "$TEST_DB"
  echo "0"  # Success exit code
else
  echo "❌ FAIL: No tables found"
  echo "1"  # Failure exit code
fi
```

**Expected Results:**
- Runs 1st Monday at 3 AM
- Tests random backup from last 7 days
- Verifies table restoration
- Sends report to ops@kushnir.cloud
- Creates alert if test fails

### 7.2 Quarterly Full Restore Simulation

**Every 3 months (90-day test rotation):**

1. Full database restore to isolated test environment
2. All volume restoration
3. Service startup and health checks
4. Data verification against source
5. Performance benchmarking
6. Document issues and resolutions

---

## 8. Backup Report Structure

**Daily Report Contents:**

```
CODE-SERVER BACKUP REPORT
Date: 2026-04-30
====================================

BACKUPS COMPLETED (Last 24 Hours):
✅ PostgreSQL: 24/24 hourly backups
   Size: 12.5 GB (avg 520 MB each)
   Last: 2026-04-30 23:00 (12 MB compressed)

✅ Redis: 24/24 hourly backups
   Size: 1.2 GB (avg 50 MB each)
   Last: 2026-04-30 23:15 (45 MB compressed)

✅ Volumes: 1/1 daily backup
   Size: 8.3 GB
   Last: 2026-04-30 02:00
   Files: 13 volumes

STORAGE USAGE:
/backups/daily:      48.2 GB (82% capacity)
/mnt/nas-backup:     312.5 GB (65% capacity)

BACKUP VERIFICATION:
✅ All backups valid
✅ Integrity checks passed
✅ Compression successful

ISSUES:
None

NEXT ACTIONS:
1. Monitor disk space (approaching 85%)
2. Review retention policies
3. Schedule May archival

Recovery Test Status:
✅ Last test: 2026-04-01 (PASSED)
⏰ Next test: 2026-05-06

Contact: ops@kushnir.cloud
```

---

## 9. Maintenance & Optimization

### 9.1 Monthly Maintenance Tasks

- [ ] Review backup sizes for anomalies
- [ ] Verify NAS backup replication
- [ ] Check disk space availability
- [ ] Test random recovery
- [ ] Update retention policies
- [ ] Review alert thresholds
- [ ] Document any issues

### 9.2 Quarterly Optimization

- [ ] Analyze backup compression ratios
- [ ] Identify data growth trends
- [ ] Plan storage expansion if needed
- [ ] Review backup performance
- [ ] Optimize script efficiency
- [ ] Update disaster recovery procedures

### 9.3 Annual Review

- [ ] Full backup strategy review
- [ ] Evaluate new backup technologies
- [ ] Plan cloud backup migration
- [ ] Update RTO/RPO targets
- [ ] Train team on procedures
- [ ] Audit backup compliance

---

## 10. Verification Checklist

**Pre-Deployment:**
- [ ] Backup scripts tested locally
- [ ] Cron/systemd timers configured
- [ ] Backup directories created and writable
- [ ] NAS connectivity verified
- [ ] Database backups working
- [ ] Redis backups working
- [ ] Volume backups working

**Post-Deployment:**
- [ ] First backup completed successfully
- [ ] Backup files present and valid
- [ ] Retention policies working
- [ ] Email reports being sent
- [ ] Monitoring alerts configured
- [ ] Recovery test planned
- [ ] Team trained on procedures

---

## Summary

Phase 4 Backup Automation delivers:

✅ **Automated Backups:**
- PostgreSQL: Hourly full dumps (compressed, 30-day retention)
- Redis: Hourly snapshots (7-day retention)
- Volumes: Daily tar archives (30-day retention)

✅ **Multi-tier Storage:**
- Primary: /backups/daily (50-100GB, fast recovery)
- Secondary: /mnt/nas-backup (500GB-1TB, archival)
- Tertiary: Cloud S3 (future, 90-day cold storage)

✅ **RTO/RPO Targets:**
- PostgreSQL: <15min RTO, <1hr RPO
- Redis: <5min RTO, <1hr RPO
- Volumes: <1hr RTO, <24hr RPO

✅ **Disaster Recovery:**
- Complete failover procedures documented
- Point-in-time recovery capability
- Monthly recovery testing
- Comprehensive runbooks for all scenarios

✅ **Monitoring & Reporting:**
- Daily backup reports sent to ops team
- Prometheus alerts for backup failures
- Grafana dashboards for backup status
- Monthly recovery drills automated

**Status: READY FOR IMPLEMENTATION**

---

**Document Version:** 1.0  
**Created:** April 30, 2026  
**Status:** PHASE 4 - Ready for Deployment  
**Next:** Implementation & Verification
