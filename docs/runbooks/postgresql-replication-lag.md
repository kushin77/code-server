# Runbook: PostgreSQL Replication Lag (PostgreSQLReplicationLag)

**Alert**: `PostgreSQLReplicationLag` (> 100MB) | `PostgreSQLReplicationLagCritical` (> 500MB) | `PostgreSQLReplicationDown` (no slots)  
**Severity**: WARNING / CRITICAL  
**Component**: Database replication  
**Related Issue**: #569

## Overview

This alert fires when the standby replica database falls behind the primary, indicating replication stalls or connectivity issues. Large lag can result in data loss if primary fails.

## Quick Response

```bash
# 1. Check replication status on primary
docker-compose exec postgres psql -U codeserver -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"

# 2. Check standby status
docker-compose exec postgres psql -U codeserver -c \
  "SELECT client_addr, state, sync_state, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# 3. Check replication lag in bytes (Prometheus metric)
curl -s 'http://prometheus:9090/api/v1/query?query=pg_replication_lag_bytes' | jq '.data.result'

# 4. View PostgreSQL logs
docker-compose logs --tail 50 postgres | grep -iE "replication|wal|standby"
```

## Detailed Investigation

### Step 1: Verify Replication is Connected

```bash
# Primary: Check for active replication slots
docker-compose exec postgres psql -U codeserver -d codeserver -c \
  "SELECT * FROM pg_replication_slots;"

# Primary: Check replication statistics
docker-compose exec postgres psql -U codeserver -d codeserver -c \
  "SELECT client_addr, state, sync_state, reply_time FROM pg_stat_replication;"

# Primary: Check WAL sender processes
docker-compose exec postgres psql -U codeserver -d codeserver -c \
  "SELECT pid, usename, application_name, client_addr, state FROM pg_stat_activity WHERE state LIKE '%walsender%';"
```

### Step 2: Measure Lag

```bash
# Primary: LSN positions
docker-compose exec postgres psql -U codeserver -d codeserver -c \
  "SELECT pg_current_wal_lsn() AS primary_lsn;"

# Standby: LSN positions (must connect via replication user)
docker-compose exec postgres-replica psql -U replication -c \
  "SELECT pg_last_wal_receive_lsn() AS receive_lsn, pg_last_wal_replay_lsn() AS replay_lsn;"

# Compute lag in bytes
docker-compose exec postgres psql -U codeserver -d codeserver -c \
  "SELECT 
    pg_wal_lsn_diff(pg_current_wal_lsn(), (SELECT confirmed_flush_lsn FROM pg_replication_slots WHERE slot_name='replication_slot')) as lag_bytes;"
```

### Step 3: Common Causes

| Cause | Detection | Fix |
|-------|-----------|-----|
| **Network latency** | Ping standby: `ping <standby-ip>` shows high latency | Check network path, reduce background load |
| **Standby overloaded** | Standby CPU/disk high | Reduce queries on standby or increase resources |
| **WAL archiving slow** | Lots of unarchived WAL files: `ls /var/lib/postgresql/wal_archive \| wc -l` | Check archiving destination capacity |
| **Replication connection down** | No rows in `pg_stat_replication` | Restart standby: `docker-compose restart postgres-replica` |
| **Primary stalled** | Primary LSN not advancing | Check primary health, disk space, checkpoint progress |
| **Standby recovery slow** | Standby is catching up but slowly | Normal after restart — allow time or add resources |

### Step 4: Fix Replication Lag

```bash
# Option 1: Restart standby to force reconnect
docker-compose restart postgres-replica
sleep 30

# Monitor reconnection
watch -n 1 'docker-compose exec postgres psql -U codeserver -c "SELECT client_addr, state FROM pg_stat_replication;"'

# Option 2: Force checkpoint on primary to free WAL
docker-compose exec postgres psql -U codeserver -c "CHECKPOINT;"

# Option 3: If standby is severely lagged, re-initialize
docker-compose exec postgres-replica pg_basebackup -h postgres -U replication -D /var/lib/postgresql/data -v -W
# Then restart standby
```

### Step 5: Verify Recovery

```bash
# Monitor lag until it's < 100MB
for i in {1..10}; do
  echo "=== Check $i ==="
  docker-compose exec postgres psql -U codeserver -d codeserver -c \
    "SELECT (extract(epoch from now()) * 1000)::bigint as timestamp, pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) as lag_bytes FROM pg_replication_slots WHERE slot_name='replication_slot';"
  sleep 30
done

# When lag stabilizes < 100MB
docker-compose exec postgres psql -U codeserver -c "SELECT state, sync_state FROM pg_stat_replication;"
```

## Prevention

- **Monitor lag continuously**: Alert already configured (100MB warning, 500MB critical)
- **Network health**: Ensure 1Gbps+ link between primary and standby
- **Resource provisioning**: Both servers should have similar specs
- **WAL archiving**: Set up backup archiving to S3/NFS
- **Connection pooling**: Use pg_bouncer to limit connection count

## Configuration

```yaml
# docker-compose.yml — Standby recovery settings
environment:
  PGUSER: replication
  PGPASSWORD: <replication_password>
command: |
    -c wal_receiver_timeout=60s
    -c wal_retrieve_retry_interval=5s
    -c recovery_target_timeline=latest
```

## Failover Procedure (if lag becomes critical)

```bash
# 1. Promote standby to primary
docker-compose exec postgres-replica psql -U replication -c "SELECT pg_promote();"

# 2. Redirect applications to new primary
# Update DATABASE_URL / connection strings in .env

# 3. Re-initialize old primary as new standby
docker-compose restart postgres
# Standby will re-join automatically if replication slot exists
```

## Related Runbooks

- [Container Restart Investigation](container-restart-investigation.md) — Standby crashes
- [Disk Space Cleanup](disk-space-cleanup.md) — WAL archive full
