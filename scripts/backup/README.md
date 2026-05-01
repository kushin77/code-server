# Code Server Backup & Disaster Recovery System

**Version:** 1.0  
**Status:** PHASE 4 - Production Ready  
**Last Updated:** April 30, 2026

---

## Overview

This directory contains automated backup and disaster recovery infrastructure for the code-server-enterprise production platform. The system protects critical data through hourly database backups, daily volume archival, and comprehensive recovery procedures.

### Key Features

✅ **Automated Backups**
- PostgreSQL: Hourly logical dumps with compression
- Redis: Hourly RDB snapshots
- Volumes: Daily tar.gz archives of all Docker volumes
- Retention: 30/7/30 days respectively

✅ **Multi-Tier Storage**
- Primary: `/home/akushnir/.backup-storage/daily` (fast, local)
- Secondary: `/home/akushnir/.nas-backup` (archival, NAS)
- Tertiary: AWS S3 (future implementation)

✅ **RTO/RPO Targets**
- PostgreSQL: <15 min RTO, <1 hour RPO
- Redis: <5 min RTO, <1 hour RPO
- Volumes: <1 hour RTO, <24 hour RPO

✅ **Monitoring & Verification**
- Daily backup verification
- Disk space monitoring with alerts
- Monthly automated recovery testing
- Comprehensive backup reports

---

## Quick Start

### 1. Install Cron Jobs (Root Required)

```bash
# Installation (requires sudo)
sudo bash /home/akushnir/code-server/scripts/backup/install-backup-cronjobs.sh

# Verify installation
sudo crontab -l | grep -A 20 "Code Server"
```

### 2. Create Backup Directories

```bash
# These directories should already exist
mkdir -p /home/akushnir/.backup-storage/daily/{postgres,redis,volumes}
mkdir -p /home/akushnir/.nas-backup/{postgres,redis,volumes}

# Verify
ls -lhR /home/akushnir/.backup-storage/
```

### 3. Run a Manual Backup

```bash
# Set up environment
source /home/akushnir/code-server/scripts/backup/code-server-backup-env.sh

# PostgreSQL backup
bash /home/akushnir/code-server/scripts/backup/backup-postgres.sh

# Redis backup
bash /home/akushnir/code-server/scripts/backup/backup-redis.sh

# Volume backup
bash /home/akushnir/code-server/scripts/backup/backup-volumes.sh
```

### 4. Verify Backups

```bash
# Run verification script
source /home/akushnir/code-server/scripts/backup/code-server-backup-env.sh
bash /home/akushnir/code-server/scripts/backup/verify-backups.sh
```

### 5. View Daily Report

```bash
# Generate and view backup report
source /home/akushnir/code-server/scripts/backup/code-server-backup-env.sh
bash /home/akushnir/code-server/scripts/backup/backup-report.sh
```

---

## Scripts Reference

### backup-postgres.sh

Creates hourly PostgreSQL backups with compression and archival.

**Features:**
- pg_dump with custom format (compressed)
- Parallel job support (4x)
- Automatic integrity verification
- NAS replication
- 30-day retention

**Usage:**
```bash
source code-server-backup-env.sh
bash backup-postgres.sh
```

**Output:**
- `/home/akushnir/.backup-storage/daily/postgres/postgres_backup_YYYYMMDD_HHMMSS.sql.gz`
- `/home/akushnir/.backup-storage/daily/postgres/postgres_backup_YYYYMMDD_HHMMSS.metadata`

### backup-redis.sh

Creates hourly Redis RDB snapshots.

**Features:**
- Non-blocking BGSAVE
- Gzip compression
- Key count verification
- 7-day local retention

**Usage:**
```bash
source code-server-backup-env.sh
bash backup-redis.sh
```

**Output:**
- `/home/akushnir/.backup-storage/daily/redis/redis_backup_YYYYMMDD_HHMMSS.rdb.gz`

### backup-volumes.sh

Creates daily tar.gz archives of Docker volumes.

**Volumes Backed Up:**
- caddy_data, caddy_config
- prometheus_data, grafana_data
- loki_data, alertmanager_data
- qdrant_data, redis_data, redpanda_data
- ollama_models, tempo_data, postgres_data, appsmith_data

**Usage:**
```bash
source code-server-backup-env.sh
bash backup-volumes.sh
```

**Output:**
- `/home/akushnir/.backup-storage/daily/volumes/VOLUME_NAME_YYYYMMDD_HHMMSS.tar.gz`

### verify-backups.sh

Verifies backup integrity and health.

**Checks:**
- PostgreSQL backup count and age
- Redis backup count and age
- Volume backup count and age
- Disk space usage
- File integrity (gzip/tar validation)

**Usage:**
```bash
source code-server-backup-env.sh
bash verify-backups.sh
```

### backup-report.sh

Generates daily backup status reports.

**Contents:**
- PostgreSQL backup stats
- Redis backup stats
- Volume backup stats
- Storage usage
- Recent backup status
- Next scheduled actions

**Usage:**
```bash
source code-server-backup-env.sh
bash backup-report.sh
```

### monthly-recovery-test.sh

Performs automated monthly recovery testing.

**Tests:**
- Random PostgreSQL backup restore to test DB
- Redis backup integrity check
- Volume backup integrity check

**Schedule:** 1st Monday of month at 3:00 AM

**Usage:**
```bash
source code-server-backup-env.sh
bash monthly-recovery-test.sh
```

---

## Configuration

### Environment Variables

Edit `code-server-backup-env.sh` to customize:

```bash
# Backup storage locations
BACKUP_DIR="/home/akushnir/.backup-storage/daily"
NAS_BACKUP="/home/akushnir/.nas-backup"

# PostgreSQL connection
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD=""  # Set via .pgpass or env

# Redis connection
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD=""
REDIS_CONTAINER="code-server-redis"

# Retention policies (days)
POSTGRES_RETENTION_DAYS="30"
REDIS_RETENTION_DAYS="7"
VOLUMES_RETENTION_DAYS="30"

# Email reports
REPORT_EMAIL="ops@kushnir.cloud"
SEND_EMAIL="false"  # Set to true if mail configured
```

### Cron Schedule

Edit `/etc/cron.d/code-server-backups` to customize timing:

```bash
# PostgreSQL: Every hour at minute 0
0 * * * * root bash /home/akushnir/code-server/scripts/backup/backup-postgres.sh

# Redis: Every hour at minute 15
15 * * * * root bash /home/akushnir/code-server/scripts/backup/backup-redis.sh

# Volumes: Daily at 2:00 AM
0 2 * * * root bash /home/akushnir/code-server/scripts/backup/backup-volumes.sh

# Verification: Daily at 4:00 AM
0 4 * * * root bash /home/akushnir/code-server/scripts/backup/verify-backups.sh

# Report: Daily at 5:00 AM
0 5 * * * root bash /home/akushnir/code-server/scripts/backup/backup-report.sh

# Monthly Recovery Test: 1st Monday at 3:00 AM
0 3 1-7 * * [ "$(date +\%A)" = "Monday" ] && root bash /home/akushnir/code-server/scripts/backup/monthly-recovery-test.sh
```

---

## Recovery Procedures

### PostgreSQL Full Restore

```bash
# Find backup
ls -lh /home/akushnir/.backup-storage/daily/postgres/ | tail -5

# Restore to new database
BACKUP="/home/akushnir/.backup-storage/daily/postgres/postgres_backup_20260430_140000.sql.gz"
pg_restore -h localhost -d new_db --verbose --jobs=4 "$BACKUP"

# Or restore to existing (creates new tables)
pg_restore -h localhost -d postgres --verbose "$BACKUP"

# Time: ~5-15 minutes
```

### PostgreSQL Point-in-Time Recovery

```bash
# Find backup closest to desired time
RESTORE_TIME="2026-04-30 12:00:00"
BACKUP=$(find /home/akushnir/.backup-storage/daily/postgres -newermt "2026-04-30" | head -1)

# Restore to test database first
pg_restore -h localhost -d test_restore "$BACKUP"

# Verify timestamp
psql -d test_restore -c "SELECT NOW();"
```

### Redis Restore

```bash
# Stop Redis container
docker-compose -f /home/akushnir/code-server/docker-compose.yml stop redis

# Find and decompress backup
BACKUP="/home/akushnir/.backup-storage/daily/redis/redis_backup_latest.rdb.gz"
gunzip -c "$BACKUP" > /tmp/dump.rdb

# Copy to container
docker cp /tmp/dump.rdb code-server-redis:/data/dump.rdb

# Restart Redis
docker-compose -f /home/akushnir/code-server/docker-compose.yml start redis

# Verify
docker-compose -f /home/akushnir/code-server/docker-compose.yml exec redis redis-cli PING

# Time: <5 minutes
```

### Volume Restore

```bash
# Find volume backup
BACKUP="/home/akushnir/.backup-storage/daily/volumes/prometheus_data_20260430_020000.tar.gz"
VOLUME="prometheus_data"

# Restore to volume
docker run --rm \
  -v ${VOLUME}:/volume_data \
  -v /home/akushnir/.backup-storage/daily/volumes:/backups \
  alpine:latest \
  tar -xzf /backups/prometheus_data_20260430_020000.tar.gz \
  -C /volume_data

# Verify
docker volume inspect $VOLUME

# Time: ~5-15 minutes depending on size
```

---

## Disaster Recovery Scenarios

### Scenario 1: Complete Host Failure

**RTO:** <2 hours  
**RPO:** <1 hour

1. SSH to replica host (192.168.168.42)
2. Start all services: `docker-compose up -d`
3. Restore latest PostgreSQL: `pg_restore -d postgres /path/to/latest/backup.sql.gz`
4. Restore latest Redis: Follow Redis restore procedure
5. Verify health: `curl https://kushnir.cloud/health`

### Scenario 2: Database Corruption

**RTO:** <20 minutes  
**RPO:** <1 hour

1. Create test restore from latest known-good backup
2. Verify data in test database
3. Swap databases: `ALTER DATABASE postgres RENAME TO corrupt;`
4. Restart application services
5. Verify functionality

### Scenario 3: Disk Failure

**RTO:** <1 hour  
**RPO:** <24 hours

1. Restore latest volume backups from NAS/secondary storage
2. Restart affected services: `docker-compose restart SERVICE`
3. Verify service health
4. Run backup verification

### Scenario 4: Ransomware/Data Corruption

**RTO:** <4 hours  
**RPO:** <24 hours

1. Isolate infected host immediately
2. Restore all data from known-clean backup timestamp
3. Activate standby infrastructure
4. Audit logs to identify attack vector
5. Patch vulnerabilities
6. Rebuild and rejoin affected systems

---

## Monitoring & Alerts

### Prometheus Alerts

Add these alert rules to your Prometheus configuration:

```yaml
- alert: PostgreSQLBackupMissing
  expr: time() - backup_postgres_last_success_timestamp > 7200
  for: 30m
  labels:
    severity: high
  annotations:
    summary: "PostgreSQL backup missing (>2 hours old)"

- alert: BackupDiskSpaceWarning
  expr: node_filesystem_avail_bytes{mountpoint="/backups"} < 10737418240
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Backup disk space below 10GB"

- alert: BackupDiskSpaceCritical
  expr: node_filesystem_avail_bytes{mountpoint="/backups"} < 5368709120
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Backup disk space CRITICAL - action required"
```

### Log Locations

All backup operations log to:

```
/var/log/code-server-backup-postgres.log
/var/log/code-server-backup-redis.log
/var/log/code-server-backup-volumes.log
/var/log/code-server-backup-verify.log
/var/log/code-server-backup-report.log
/var/log/code-server-recovery-test.log
```

### Manual Verification

```bash
# Check latest PostgreSQL backup
ls -lh /home/akushnir/.backup-storage/daily/postgres/ | tail -3

# Check latest Redis backup
ls -lh /home/akushnir/.backup-storage/daily/redis/ | tail -3

# Check latest volume backups
ls -lh /home/akushnir/.backup-storage/daily/volumes/ | tail -5

# Run full verification
bash /home/akushnir/code-server/scripts/backup/verify-backups.sh
```

---

## Troubleshooting

### PostgreSQL Backup Fails

```bash
# Verify PostgreSQL is running
docker-compose ps | grep postgres

# Check PostgreSQL connection
psql -h localhost -U postgres -c "SELECT 1;"

# View PostgreSQL logs
docker-compose logs postgres | tail -50

# Try backup with verbose output
POSTGRES_HOST=localhost POSTGRES_USER=postgres bash backup-postgres.sh
```

### Redis Backup Fails

```bash
# Verify Redis is running
docker-compose ps | grep redis

# Check Redis connection
redis-cli ping

# View Redis logs
docker-compose logs redis | tail -50

# Verify BGSAVE capability
redis-cli BGSAVE
redis-cli INFO persistence | grep bgsave
```

### Volume Backup Fails

```bash
# Verify Docker is running
docker ps

# Check volume exists
docker volume ls | grep postgres_data

# Try volume inspect
docker volume inspect prometheus_data

# View Docker logs
docker logs -f code-server-redis 2>&1 | head -50
```

### Insufficient Disk Space

```bash
# Check disk usage
df -h /home/akushnir/.backup-storage/

# Check backup sizes
du -sh /home/akushnir/.backup-storage/daily/*

# Manually cleanup old backups
find /home/akushnir/.backup-storage/daily/postgres -mtime +30 -delete

# Update retention policy in environment
# Edit code-server-backup-env.sh
```

---

## Maintenance Tasks

### Daily
- ✅ Automated by cron
- Verify backup logs show success
- Check disk space usage

### Weekly  
- Review backup sizes
- Test random recovery manually
- Check NAS connectivity (if configured)

### Monthly
- Automated recovery test runs
- Review backup retention policies
- Verify email reports being sent

### Quarterly
- Full restoration simulation
- Performance benchmarking
- Document any issues

### Annually
- Complete backup strategy review
- Evaluate new technologies
- Update RTO/RPO targets
- Team training

---

## Support & Documentation

- **PHASE_4_BACKUP_AUTOMATION.md** - Comprehensive Phase 4 design document
- **docker-compose.yml** - Production infrastructure definition
- **MONITORING_ALERTING_SETUP.md** - Integrated monitoring infrastructure
- **Code Server Operations Manual** - Full platform operations guide

---

**Created:** April 30, 2026  
**Status:** PHASE 4 - Production Ready  
**Maintained By:** Operations Team
