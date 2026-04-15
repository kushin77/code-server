# Alert Runbook: PostgreSQL Replication Failures

**Alerts**: `PostgreSQLReplication{LagWarning,LagCritical,Broken}`  
**Severity**: WARNING (lag > 30s), CRITICAL (lag > 120s or broken)  
**SLA**: WARNING (2 hours), CRITICAL (1 hour)  
**Owner**: Database/SRE Team  

---

## Problem

PostgreSQL replication from primary (`192.168.168.31`) to replica (`192.168.168.42`) is degraded or broken:
- **Replication Lag**: Replica is behind primary by N seconds
  - If primary fails with lag > 2 min, data loss occurs
  - Users may read stale data on replica
- **Replication Broken**: Replica no longer receiving WAL (Write-Ahead Log) from primary
  - Immediate data loss risk if primary fails
  - Manual intervention required to restore replication

---

## Immediate Investigation (< 5 minutes)

### 1. Check Primary PostgreSQL Status

```bash
# SSH to primary (192.168.168.31)
ssh akushnir@192.168.168.31

# Check postgres running
docker-compose ps postgres

# Check replication slots on primary
docker exec postgres psql -U postgres -c "
  SELECT slot_name, slot_type, active FROM pg_replication_slots;
"

# Check WAL sender status (primary side)
docker exec postgres psql -U postgres -c "
  SELECT pid, usename, backend_start, state, write_lsn, flush_lsn, replay_lsn
  FROM pg_stat_replication;
"
```

### 2. Check Replica PostgreSQL Status

```bash
# SSH to replica (192.168.168.42)
ssh akushnir@192.168.168.42

# Check postgres running
docker-compose ps postgres

# Check replication lag
docker exec postgres psql -U postgres -c "
  SELECT now() - pg_last_xact_replay_timestamp() as replication_lag;
"

# Check if replica is in recovery (standby) mode
docker exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should return 't' (true) for replica

# Check recovery process status
docker exec postgres psql -U postgres -c "
  SELECT received_lsn, replayed_lsn, primary_conninfo FROM pg_stat_wal_receiver;
"
```

### 3. Check Network Connectivity

```bash
# From replica, test connection to primary
ssh akushnir@192.168.168.42

# Test network connectivity
ping -c 5 192.168.168.31
curl -s http://192.168.168.31:9090/-/ready | head -20

# Check if replication user can connect
docker exec postgres psql -U replication -h 192.168.168.31 -d postgres -c "SELECT version();"
```

---

## Common Root Causes & Fixes

### Cause 1: Replication User Connection Failing

**Symptoms**:
- `pg_stat_wal_receiver` shows NULL status
- Logs: "Connection refused" or "Authentication failed"
- Replica postgres logs: "could not connect to replication server"

**Fix**:
```bash
# On replica, check replication connection details
docker exec postgres psql -U postgres -c "
  SELECT * FROM pg_stat_wal_receiver;
"

# If connection failing, check:
# 1. Primary postgres is accepting connections
ssh akushnir@192.168.168.31
docker exec postgres psql -U postgres -c "SHOW max_wal_senders;"

# 2. Replication user exists and has correct password
docker exec postgres psql -U postgres -c "
  SELECT * FROM pg_roles WHERE rolname = 'replication';
"

# 3. Network connectivity between hosts
docker exec postgres ping -c 1 192.168.168.31

# If password or connection is wrong, reset on primary:
ssh akushnir@192.168.168.31
docker exec postgres psql -U postgres -c "
  ALTER USER replication WITH PASSWORD 'new-secure-password';
"

# Update replica standby.signal or recovery.conf:
ssh akushnir@192.168.168.42
vi /var/lib/postgresql/data/postgresql.conf
# Update: primary_conninfo = 'host=192.168.168.31 ... password=new-secure-password'

# Restart replica postgres
docker-compose down postgres
docker-compose up -d postgres
docker logs postgres  # Watch for successful connection
```

### Cause 2: Primary Disk or Memory Issue

**Symptoms**:
- `pg_stat_replication` on primary shows empty or disconnected senders
- Primary CPU or I/O at 100%
- Logs: "Disk full" or "out of memory"

**Fix**:
```bash
# On primary, check disk space
ssh akushnir@192.168.168.31
df -h /var/lib/postgresql/

# Check PostgreSQL process memory
docker stats postgres  # Look at MEM%

# Check WAL archive (may be full)
ls -lh /var/lib/postgresql/pg_wal/ | tail -20
du -sh /var/lib/postgresql/pg_wal/

# If WAL archive is full:
# 1. Check checkpoint progress
docker exec postgres psql -U postgres -c "
  SELECT name, setting FROM pg_settings WHERE name LIKE '%checkpoint%';
"

# 2. Manually trigger checkpoint
docker exec postgres psql -U postgres -c "CHECKPOINT;"

# 3. Monitor WAL cleanup
watch 'ls /var/lib/postgresql/pg_wal/ | wc -l'

# If primary is low on disk:
df -h /
# Delete old backups or logs to free space
find /mnt/backups -mtime +30 -delete
```

### Cause 3: Excessive Write Workload on Primary

**Symptoms**:
- Replication lag slowly increasing over time (10s → 30s → 120s)
- Logs on primary show high write volume
- Replica CPU at max trying to replay changes

**Fix**:
```bash
# Check write rate on primary
docker exec postgres psql -U postgres -c "
  SELECT schemaname, tablename, seq_scan, seq_tup_read, idx_scan, idx_tup_fetch
  FROM pg_stat_user_tables
  ORDER BY seq_tup_read + idx_tup_fetch DESC LIMIT 5;
"

# Check for long-running transactions (can block replication)
docker exec postgres psql -U postgres -c "
  SELECT pid, usename, application_name, state, query_start
  FROM pg_stat_activity
  WHERE state != 'idle'
  ORDER BY query_start;
"

# Kill long-running queries if safe
docker exec postgres psql -U postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE state != 'idle' AND query_start < now() - interval '1 hour';
"

# Monitor replica catchup
ssh akushnir@192.168.168.42
watch 'docker exec postgres psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() as lag;"'

# Once caught up, lag should stabilize near 0
```

### Cause 4: Replication Slot Corrupted

**Symptoms**:
- Primary WAL sender keeps disconnecting and reconnecting
- Logs: "replication slot does not exist" or "WAL segment not found"
- Replication lag oscillates between 0 and 120+ seconds

**Fix**:
```bash
# On primary, check replication slots
ssh akushnir@192.168.168.31
docker exec postgres psql -U postgres -c "
  SELECT slot_name, active, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;
"

# If slot exists but inactive, drop and recreate
docker exec postgres psql -U postgres -c "
  SELECT pg_drop_replication_slot('replication_slot_name');
"

# On replica, force resync from scratch:
ssh akushnir@192.168.168.42

# Stop postgres
docker-compose down postgres

# Remove old WAL/base files (WARNING: data loss if done on primary!)
sudo rm -rf /var/lib/postgresql/data/*

# Start postgres - will start streaming WAL from primary
docker-compose up -d postgres

# Monitor progress
docker logs postgres --follow | grep -i "streaming\|wal\|consistent"

# Should complete within minutes/hours depending on database size
```

### Cause 5: Standby WAL Receiver Stuck

**Symptoms**:
- `pg_stat_wal_receiver` shows OLD `received_lsn` timestamp
- Replica not advancing in replay
- Logs: "WAL receiver timeout" or "Connection timeout"

**Fix**:
```bash
# On replica, restart the WAL receiver
ssh akushnir@192.168.168.42

docker-compose down postgres
sleep 10
docker-compose up -d postgres

# Monitor WAL receiver reconnection
docker logs postgres --follow

# Verify replica is now replaying:
docker exec postgres psql -U postgres -c "
  SELECT received_lsn, replayed_lsn FROM pg_stat_wal_receiver;
"
# replayed_lsn should be advancing

# Monitor lag convergence
while true; do
  docker exec postgres psql -U postgres -c \
    "SELECT now() - pg_last_xact_replay_timestamp() as lag;"
  sleep 5
done
```

---

## Verification

After fixing, verify replication health:

```bash
# 1. Primary side - check replication is active
ssh akushnir@192.168.168.31
docker exec postgres psql -U postgres -c "
  SELECT pid, state, sync_state, backend_start FROM pg_stat_replication;
"
# Should show 1 active replication connection with sync_state='sync' or 'async'

# 2. Replica side - check lag is minimal
ssh akushnir@192.168.168.42
docker exec postgres psql -U postgres -c "
  SELECT now() - pg_last_xact_replay_timestamp() as replication_lag;
"
# Should be < 1 second (0 seconds if idle)

# 3. Verify replica is still standby
docker exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Must return 't' (true)

# 4. Check alerts clear
curl -s http://localhost:9093/api/v1/alerts | \
  jq '.data[] | select(.labels.alertname | test("PostgreSQL"))'
# Should be empty or show state=firing=false
```

---

## Escalation (If Still Broken)

If replication not recovering after 1 hour:

1. **Check for PostgreSQL bugs/corruption**:
   ```bash
   docker exec postgres pg_dump -U postgres --pre-data > /tmp/test_dump.sql
   echo $?  # Should be 0
   ```

2. **Consider full replica rebuild**:
   ```bash
   # On primary, take base backup
   docker exec postgres pg_basebackup -D /tmp/basebackup -Ft -z

   # Transfer to replica host and restore (involves downtime)
   # Requires coordination with team
   ```

3. **Page DBA/Database team**:
   - Slack: @dba-oncall
   - PagerDuty: Critical incident
   - Include: Replication status, lag value, error logs

---

## Prevention

**Monitor replication proactively**:
```bash
# Query lag regularly
watch 'docker exec postgres psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp();"'

# Set up Prometheus alerts for:
# - Lag > 30 seconds (warning)
# - Lag > 2 minutes (critical)
# - Replication broken (critical)
```

**Regular replication tests**:
```bash
# Weekly: Verify replica can be promoted to primary
# Weekly: Test failover procedures
# Monthly: Test data restore from replica backup
```

---

**Document**: docs/runbooks/postgresql-replication.md  
**Last Updated**: 2026-04-15  
**Approved By**: Database Lead  
