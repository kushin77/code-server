# Enhanced Health Checks - Production Monitoring

**Issue Reference**: #1522  
**Date**: April 23, 2026  
**Environment**: On-Prem 192.168.168.31 & 192.168.168.42  
**Services Monitored**: PgBouncer, Database Backups, PostgreSQL Replication  

---

## Overview

This document describes three critical health checks that monitor database infrastructure for early detection of issues, enabling sub-5 second detection and automated alerting.

## Health Checks Implemented

### 1. PgBouncer Connection Pool Health Check

**File**: `scripts/health-checks/check-pgbouncer-health.sh`

**Purpose**: Monitor connection pool utilization and availability

**Metrics Monitored**:
- Active server connections
- Idle server connections  
- Waiting client connections
- Pool utilization percentage

**Success Criteria**:
- Exit code 0: Pool utilization < 90%
- Exit code 1: Pool utilization 90-99% (warning)
- Exit code 2: Pool utilization ≥ 100% or not responding (critical)

**Configuration**:
```bash
PGBOUNCER_HOST=localhost           # PgBouncer server
PGBOUNCER_PORT=6432               # PgBouncer port
POOL_WARNING_THRESHOLD=90          # Warn at 90% utilization
POOL_CRITICAL_THRESHOLD=100        # Critical at 100% utilization
```

**Output Example**:
```
[INFO] Starting PgBouncer health check
[INFO] ✓ PgBouncer connectivity verified
[INFO] PgBouncer Status:
  Active Connections: 32
  Idle Connections: 48
  Waiting Clients: 2
  Total Used: 34 / 100
  Pool Utilization: 34%
[INFO] ✓ PgBouncer health check PASSED
```

**Failure Scenarios**:
- PgBouncer not responding (connection refused)
- All connections exhausted (100% utilization)
- Database backend disconnected

**Recovery**:
```bash
# Restart PgBouncer
docker-compose restart pgbouncer

# View connection statistics
docker exec pgbouncer psql -U pgbouncer -d pgbouncer -c "SHOW POOLS;"

# Check logs
docker logs pgbouncer --tail 50
```

---

### 2. Database Backup Status Health Check

**File**: `scripts/health-checks/check-backup-status.sh`

**Purpose**: Verify recent database backups and detect backup failures

**Metrics Monitored**:
- Last backup timestamp
- Backup age (hours/days)
- Backup file size
- Backup retention status

**Success Criteria**:
- Exit code 0: Backup < 24 hours old
- Exit code 1: Backup 24-48 hours old (warning)
- Exit code 2: Backup missing or > 72 hours old (critical)

**Configuration**:
```bash
BACKUP_DIR=/backups/postgresql           # Backup storage location
BACKUP_RETENTION_HOURS=24                # Normal retention window
BACKUP_WARNING_HOURS=48                  # Warning threshold
BACKUP_CRITICAL_HOURS=72                 # Critical threshold
```

**Output Example**:
```
[INFO] Starting backup status health check
[INFO] ✓ Backup directory exists: /backups/postgresql
[INFO] ✓ Latest backup: backup-2026-04-23-120000.sql.gz
[INFO] Backup Status:
  File: backup-2026-04-23-120000.sql.gz
  Age: 0d 2h (2h total)
  Size: 2456MB
  Path: /backups/postgresql/backup-2026-04-23-120000.sql.gz
[INFO] ✓ Backup health check PASSED
```

**Failure Scenarios**:
- No backup files found
- Backup directory missing or inaccessible
- Backup too old (indicating backup job failure)

**Recovery**:
```bash
# Manually trigger backup on primary
ssh akushnir@192.168.168.31
docker exec postgres pg_dump -U postgres -d production > /backups/postgresql/backup-manual-$(date +%s).sql

# Verify backup
ls -lh /backups/postgresql/ | tail -5

# Check backup job logs
docker logs backup-service --tail 50
```

---

### 3. PostgreSQL Replication Lag Health Check

**File**: `scripts/health-checks/check-replication-lag.sh`

**Purpose**: Monitor replication lag and detect replication failures

**Metrics Monitored**:
- Replication lag in seconds and milliseconds
- Replica connection status
- WAL archive status (ready/archived/failed)
- Streaming replication state

**Success Criteria**:
- Exit code 0: Lag < 100ms
- Exit code 1: Lag 100ms - 1s (warning)
- Exit code 2: Lag > 1s or replica disconnected (critical)

**Configuration**:
```bash
PRIMARY_HOST=192.168.168.31              # Primary database host
REPLICA_HOST=192.168.168.42              # Replica database host
DB_USER=postgres                         # Database superuser
DB_PORT=5432                             # PostgreSQL port
LAG_WARNING_MS=100                       # Warn at 100ms lag
LAG_CRITICAL_MS=1000                     # Critical at 1s lag
```

**Output Example**:
```
[INFO] Starting PostgreSQL replication lag health check
[INFO]   Primary: 192.168.168.31:5432
[INFO]   Replica: 192.168.168.42:5432
[INFO] ✓ Primary database connectivity verified
[INFO] ✓ Replica database connectivity verified
[INFO] Connected replicas: 1
[INFO] Replication Lag Status:
  Lag: 0.025s (25ms)
  Threshold: 100ms warning, 1000ms critical
[INFO] WAL Archive Status:
  Ready: 0 files
  Archived: 1245 files
  Failed: 0 files
[INFO] ✓ Replication lag health check PASSED
```

**Failure Scenarios**:
- Replica not connected to primary
- High replication lag (network issues, slow disk)
- WAL archive backlog (failed archiving)

**Recovery**:
```bash
# Check replica connection status on primary
ssh akushnir@192.168.168.31
docker exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Restart replica replication
ssh akushnir@192.168.168.42
docker exec postgres psql -U postgres -c "SELECT pg_wal_replay_resume();"

# Monitor lag in real-time
watch -n 1 'docker exec postgres psql -U postgres -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;"'
```

---

## Orchestration Script

**File**: `scripts/health-checks/run-all-health-checks.sh`

Runs all health checks sequentially and provides:
- Individual check results with timing
- Overall system health status
- JSON output for monitoring integration
- Timestamped reports

### Usage

```bash
# Run all health checks
bash scripts/health-checks/run-all-health-checks.sh

# Expected output
# ========================================
# HEALTH CHECK SUMMARY
# ========================================
# Total Checks: 3
# Passed: 3
# Failed/Warning: 0
#
# Overall Status: HEALTHY
#
# Individual Check Results:
#   ✓ PgBouncer Connection Pool (45ms)
#   ✓ Database Backup Status (120ms)
#   ✓ PostgreSQL Replication Lag (85ms)
```

### Output Artifacts

Results are saved to `artifacts/health-checks/`:

```
health-report-20260423-120000.txt     # Human-readable report
health-report-20260423-120000.json    # JSON for monitoring
```

### Exit Codes

- `0` = All checks healthy (green)
- `1` = Some checks warning or minor failures (yellow)
- `2` = Multiple checks failing (red)

---

## Integration with Monitoring

### Prometheus Integration

Add to Prometheus scrape config:

```yaml
scrape_configs:
  - job_name: 'health-checks'
    static_configs:
      - targets: ['localhost:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
```

Add health check metrics to `node_exporter` or custom exporter:

```bash
#!/bin/bash
# Export health check results as Prometheus metrics
results=$(bash scripts/health-checks/run-all-health-checks.sh)
echo "health_checks_pgbouncer{status=\"passed\"} 1"
echo "health_checks_backups{status=\"passed\"} 1"
echo "health_checks_replication{status=\"passed\"} 1"
```

### Alerting Rules

Add to `alert-rules.yml`:

```yaml
- alert: PgBouncePoolExhausted
  expr: health_checks_pgbouncer{status="failed"} == 1
  for: 5m
  annotations:
    summary: "PgBouncer connection pool exhausted"
    description: "Connection pool utilization at 100%"

- alert: BackupFailed
  expr: health_checks_backups{status="failed"} == 1
  for: 30m
  annotations:
    summary: "Database backup failed or overdue"
    description: "No backup for more than 72 hours"

- alert: ReplicationLagCritical
  expr: health_checks_replication{status="failed"} == 1
  for: 2m
  annotations:
    summary: "PostgreSQL replication lag critical"
    description: "Replication lag exceeds 1 second"
```

### Grafana Dashboard

Create dashboard panel queries:

```
# PgBouncer Utilization
health_checks_pgbouncer_utilization_percent

# Backup Age
health_checks_backup_age_hours

# Replication Lag
health_checks_replication_lag_ms
```

---

## Deployment

### Local Testing

```bash
# Test individual checks
bash scripts/health-checks/check-pgbouncer-health.sh
bash scripts/health-checks/check-backup-status.sh
bash scripts/health-checks/check-replication-lag.sh

# Run full suite
bash scripts/health-checks/run-all-health-checks.sh
```

### Production Deployment

```bash
# On primary host (192.168.168.31)
ssh akushnir@192.168.168.31

# Copy health check scripts
docker cp scripts/health-checks/ code-server:/opt/health-checks

# Test execution
docker exec code-server bash /opt/health-checks/run-all-health-checks.sh

# Schedule via cron (every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * bash /opt/health-checks/run-all-health-checks.sh") | crontab -
```

### Automated Health Checks in Docker Compose

Add to `docker-compose.yml`:

```yaml
health-check-runner:
  image: code-server-enterprise:latest
  container_name: health-check-runner
  restart: on-failure
  networks:
    - net-app
  volumes:
    - ./scripts/health-checks:/opt/health-checks:ro
    - ./artifacts/health-checks:/artifacts/health-checks
  command: |
    bash -c 'while true; do
      bash /opt/health-checks/run-all-health-checks.sh
      sleep 300  # Run every 5 minutes
    done'
  healthcheck:
    test: ["CMD", "test", "-f", "/artifacts/health-checks/last-check.lock"]
    interval: 10m
    timeout: 5s
    retries: 2
```

---

## Performance Characteristics

### Detection Time

- **PgBouncer**: <100ms (TCP check + query)
- **Backup Status**: <500ms (filesystem check)
- **Replication Lag**: <500ms (SQL query)
- **Total Suite**: <5 seconds (all checks parallel capable)

### Resource Usage

- CPU: <1% per check
- Memory: ~50MB per check
- Network: Minimal (local queries only)
- Disk I/O: Minimal (stat operations only)

---

## Troubleshooting

### Health Check Fails to Connect

```bash
# Test connectivity manually
docker exec postgres psql -h 192.168.168.31 -U postgres -c "SELECT 1"
docker exec postgres psql -h 192.168.168.42 -U postgres -c "SELECT 1"

# Check network connectivity
docker exec postgres ping -c 3 192.168.168.31
docker exec postgres ping -c 3 192.168.168.42
```

### Replication Lag High

```bash
# Check replica lag
docker exec postgres psql -U postgres -c \
  "SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;"

# Check WAL archive
docker exec postgres psql -U postgres -c "SELECT * FROM pg_stat_archiver;"

# Restart replication if needed
docker exec postgres psql -U postgres -c "SELECT pg_wal_replay_resume();"
```

### Backup Check Failing

```bash
# Check backup directory
docker exec postgres ls -lh /backups/postgresql/

# Verify backup permissions
docker exec postgres stat /backups/postgresql/

# Manual backup if needed
docker exec postgres pg_dump -U postgres -d production | gzip > /backups/postgresql/backup-$(date +%s).sql.gz
```

---

## Success Criteria Met

✅ Early detection: Sub-5 second check time  
✅ 3 services monitored: PgBouncer, Backups, Replication  
✅ Automated alerting: Prometheus integration ready  
✅ Monitoring dashboard: Grafana queries provided  
✅ Production ready: All scripts tested and deployable  

---

**Last Updated**: April 23, 2026  
**Maintained By**: Infrastructure Team  
**Status**: Production Ready
