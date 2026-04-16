# Runbook: PostgreSQL Replication Lag

**Alerts**: 
- `PostgreSQLReplicationLagWarning` (lag > 30s, MEDIUM)
- `PostgreSQLReplicationLagCritical` (lag > 120s, HIGH)
- `PostgreSQLReplicationBroken` (replication stopped, CRITICAL)

**SLO Impact**: RPO (Recovery Point Objective) exceeded  
**Time to Resolution**: < 10 minutes (Warning), < 2 minutes (Critical)  
**Data Loss Risk**: Proportional to lag duration

---

## Symptoms

- Alert: "PostgreSQL replication lag is Xs (threshold: 30s)"
- Grafana panel `pg_replication_lag_seconds` showing > 30s
- Manual check: `pg_stat_replication` shows high `write_lag` value
- If primary fails, standby missing 30s+ of transactions

---

## Root Causes

1. **Network bandwidth exhausted** - Primary can't send WAL fast enough
2. **Standby resources maxed** - Replica can't apply changes fast enough (CPU/disk/memory)
3. **Standby falling behind** - Replica processing is slow (long-running queries)
4. **WAL archiving backup** - Too much WAL data buffered (not cleaned up)
5. **Replication slot full** - Primary can't send because slot is full
6. **Network latency** - Primary waits for replica ACK (sync replication)
7. **Broken replication connection** - Network issue, but lag still reports

---

## Immediate Diagnosis

### Step 1: SSH to Primary Host

```bash
ssh akushnir@primary.prod.internal
cd /home/akushnir/code-server-enterprise
```

### Step 2: Check Replication Status

```bash
# Connect to primary PostgreSQL
docker exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Expected output (if replication healthy):
# usename | application_name | state | lsn | flush_lsn | write_lag | flush_lag | replay_lag
# --------|------------------|-------|-----|-----------|-----------|-----------|----------
# repuser | walreceiver      | streaming | ... | ... | 50ms | 60ms | 100ms

# If NO ROWS returned: Replication is BROKEN (see "Replication Broken" section)
```

### Step 3: Check Replica Status

```bash
# SSH to replica
ssh akushnir@replica.prod.internal

# Check if replica is in recovery mode
docker exec postgres psql -U postgres -c "SELECT pg_is_in_recovery(), NOW();"

# Expected: (t, 2026-04-18 12:00:00)  ← "t" means in recovery/standby mode

# Check replica's LSN position
docker exec postgres psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();"

# Compare to primary's current LSN
ssh akushnir@primary.prod.internal \
  docker exec postgres psql -U postgres -c "SELECT pg_current_wal_lsn();"

# If replica's LSN >> behind primary's LSN: Replication is LAGGING
```

### Step 4: Measure Exact Lag

```bash
# On primary, measure lag in bytes
docker exec postgres psql -U postgres -c "
  SELECT 
    '0/' || lpad(to_hex(write_lag), 8, '0') as write_lag_bytes,
    write_lag::text,
    flush_lag::text,
    replay_lag::text
  FROM pg_stat_replication
  WHERE application_name = 'walreceiver'
  LIMIT 1;
"

# Expected (healthy): replay_lag < 1 second
# Warning: replay_lag > 30 seconds
# Critical: replay_lag > 120 seconds
```

---

## Troubleshooting

### If Lag is 30-60 seconds (Warning Threshold)

#### Check Network Bandwidth

```bash
# On primary
iftop -i eth0  # Real-time bandwidth usage
# or
sar -n DEV 1 10  # Over 10 seconds

# If network near capacity (> 80% of link speed), lag is due to network saturation
```

#### Check Replica Load

```bash
# On replica
docker stats postgres --no-stream
# Check CPU and memory

# If CPU maxed (> 90%), replica can't apply WAL fast enough:
# 1. Check for long-running queries
docker exec postgres psql -U postgres -c "
  SELECT pid, query, query_start, state FROM pg_stat_activity
  WHERE state != 'idle' AND query NOT LIKE '%pg_stat%';"

# 2. Kill slow queries if safe:
docker exec postgres psql -U postgres -c "
  SELECT pg_terminate_backend(pid) 
  FROM pg_stat_activity 
  WHERE state != 'idle' AND query_start < NOW() - interval '10 minutes';"

# 3. Check disk I/O
docker exec replica iostat -x 1 10
```

#### Reduce Primary Write Rate (Temporary)

```bash
# If lag is due to primary flooding replica, can temporarily reduce write rate:
# (Do NOT do this permanently — defeats replication purpose)
# 1. Identify heavy writers
docker exec postgres psql -U postgres -c "
  SELECT usename, count(*) FROM pg_stat_statements 
  GROUP BY usename ORDER BY count DESC;"

# 2. Throttle if safe (e.g., pause backup jobs)
# 3. Monitor lag — should decrease within 2-5 minutes
```

### If Lag is 120+ seconds (Critical)

#### Check Replication Slot Status

```bash
# On primary, check replication slot
docker exec postgres psql -U postgres -c "
  SELECT slot_name, slot_type, active, restart_lsn, confirmed_flush_lsn
  FROM pg_replication_slots;"

# If restart_lsn much behind confirmed_flush_lsn:
# Slot is full, holding WAL files → network/replica issue preventing ACK

# Force cleanup (ONLY if confirmed replica is truly down):
docker exec postgres psql -U postgres -c "
  SELECT pg_drop_replication_slot('replication_slot_name');"
```

#### Force Replica Resync

```bash
# If lag is too high and won't recover, may need to force resync:
# 1. On replica, stop it
docker-compose -f /home/akushnir/code-server-enterprise/docker-compose.yml stop postgres

# 2. On primary, send new base backup
docker exec postgres pg_basebackup -h 192.168.168.31 -U replication -D /tmp/backup -Ft -z

# 3. On replica, restore base backup
docker exec postgres pg_basebackup -h 192.168.168.31 -U replication -D /var/lib/postgresql/data -Ft -z --verbose

# 4. On replica, start PostgreSQL
docker-compose -f /home/akushnir/code-server-enterprise/docker-compose.yml start postgres

# 5. Monitor lag
docker exec postgres psql -U postgres -c "SELECT replay_lag FROM pg_stat_replication LIMIT 1;" --watch=1
```

### If Replication is Broken (Lag Stopped Updating)

**CRITICAL**: Replication has failed. No new data being replicated.

```bash
# On replica, check connection to primary
docker exec replica nc -zv primary.prod.internal 5432
# Should output: "Connection to primary.prod.internal port 5432 [tcp/postgresql] succeeded!"

# If connection fails:
# 1. Check network connectivity
docker exec replica ping primary.prod.internal

# 2. Check replication user exists and can authenticate
docker exec primary psql -U postgres -c "SELECT * FROM pg_user WHERE usename = 'replication';"

# 3. Check pg_hba.conf allows replication connections
docker exec primary cat /var/lib/postgresql/pg_hba.conf | grep replication

# 4. Check replica recovery.conf (or postgresql.conf)
docker exec replica grep -i "primary_conninfo\|standby_mode" /var/lib/postgresql/data/recovery.conf

# On replica, manually trigger recovery:
docker exec replica psql -U postgres -c "SELECT pg_wal_replay_resume();"

# Then restart PostgreSQL
docker-compose restart postgres
```

---

## Recovery Actions

### For Lag > 30s (Warning)

1. ✅ Diagnose using steps above
2. ✅ If network saturated: Reduce primary write rate or upgrade network
3. ✅ If replica slow: Identify long-running queries, increase resources, or kill blocking queries
4. ✅ Monitor for 5 minutes: `docker exec postgres psql -U postgres -c "SELECT replay_lag FROM pg_stat_replication LIMIT 1;" --watch=1`
5. ✅ Alert clears when lag < 30s

### For Lag > 120s (Critical)

1. ⚠️ **IMMEDIATE**: Page on-call DBA — data loss risk is real
2. ✅ If replication truly broken: Restart replica replication (see "Replication Broken" steps)
3. ✅ If lag won't reduce: Plan primary failover with manual recovery
4. ✅ Post-incident: Increase replica resources or optimize primary workload

---

## Prevention

### 1. Right-size Replica Resources

```yaml
# In docker-compose.yml, ensure replica has sufficient CPU/memory
services:
  postgres:
    cpus: 4.0  # At least 50% of primary
    mem_limit: 32g  # Match primary
```

### 2. Monitor Replication Regularly

```bash
# Add to monitoring checks
0 * * * * docker exec postgres psql -U postgres -c "SELECT replay_lag FROM pg_stat_replication LIMIT 1;" >> /var/log/replication-lag.log
```

### 3. Benchmark Network Bandwidth

```bash
# Periodically test network throughput
docker exec primary iperf3 -s &
docker exec replica iperf3 -c primary.prod.internal

# Ensure bidirectional throughput is sufficient for WAL throughput
```

---

## Related Alerts

- `PostgreSQLDown` - Primary or replica offline
- `PostgreSQLReplicationBroken` - Replication connection lost
- `HostCPUUsageHigh` (on replica) - Replica can't keep up
- `DiskSpaceWarningReplica` - Replica disk full (can't write WAL)

---

*Last Updated: April 18, 2026*  
*On-Call Contact: @database-team*
