# Advanced Troubleshooting Scenarios

**Document Version**: 1.0  
**Last Updated**: April 29, 2026  
**Status**: READY FOR OPERATIONS  
**Maintained By**: Operations Team / Engineering Support  

---

## Executive Summary

This document covers complex troubleshooting scenarios that may require multi-service investigation, root cause analysis, and coordinated fixes. Each scenario includes:
- Symptoms (what the user observes)
- Root causes (possible explanations)
- Investigation procedures (step-by-step diagnosis)
- Resolution strategies (multiple approaches)
- Prevention measures (avoid recurring)

**Severity Levels**:
- 🔴 CRITICAL: Service down, data at risk, user-facing impact
- 🟠 HIGH: Degraded performance, intermittent failures
- 🟡 MEDIUM: Minor issues, workarounds available
- 🟢 LOW: Informational, no operational impact

---

## Scenario 1: PostgreSQL Replication Lag Increasing

**Severity**: 🟠 HIGH  
**Symptoms**:
- Replication lag > 30 seconds (target < 5 seconds)
- Replica shows WARNING: `"xlog location requested xxx is ahead of WAL location xxx"`
- Backup jobs taking longer than normal
- Slow transactions on primary appear on replica with 60+ second delay

**Root Causes** (in order of likelihood):
1. Primary experiencing high write load (transaction velocity > 10,000/sec)
2. Replica CPU/Disk I/O bottleneck (can't apply WAL fast enough)
3. Network bandwidth saturation between hosts
4. WAL file size increased (large batch operations)
5. Replication slot blocked by long-running query on primary
6. Disk fill on replica preventing WAL application

### Investigation Procedures

**Step 1: Check Primary Load**
```bash
# On Primary (192.168.168.31)
ssh akushnir@192.168.168.31 "
echo '=== Transaction Rate ==='
docker exec code-server-postgres psql -U postgres -c '
SELECT 
  xact_commit + xact_rollback as transactions_per_sec
FROM pg_stat_database 
WHERE datname = \"code_server_db\"
\\\\g (3)  -- Repeat every 3 seconds
'
"

# Result interpretation:
# - < 5,000 tx/sec: Normal
# - 5,000-10,000 tx/sec: Elevated
# - > 10,000 tx/sec: High load (likely cause)
```

**Step 2: Check Replica Performance**
```bash
# On Replica (192.168.168.42)
ssh akushnir@192.168.168.42 "
echo '=== WAL Application Rate ==='
docker exec code-server-postgres psql -U postgres -c '
SELECT pg_last_wal_replay_lsn() as wal_position;
' 
# Run 2-3 times with 5 second intervals - should advance ~50MB per second

echo '=== Replica CPU/Disk ==='
top -bn1 -p \$(docker inspect -f '{{.State.Pid}}' code-server-postgres) | grep code-server
iostat -x 1 3 | grep sda

echo '=== Replica Memory Pressure ==='
free -h
docker exec code-server-postgres psql -U postgres -c 'SHOW shared_buffers;'
"
```

**Step 3: Check WAL Generation Rate**
```bash
# On Primary
ssh akushnir@192.168.168.31 "
echo '=== WAL Generation (compare 2x) ==='
docker exec code-server-postgres psql -U postgres -c 'SELECT pg_current_wal_lsn();'
sleep 10
docker exec code-server-postgres psql -U postgres -c 'SELECT pg_current_wal_lsn();'
# Difference in bytes ÷ 10 seconds = generation rate
"
```

**Step 4: Check Replication Slot Status**
```bash
# On Primary
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c '
SELECT 
  slot_name,
  active,
  retained_bytes,
  wal_status
FROM pg_replication_slots;
'
"
# If wal_status = 'unreserved': Slot cannot keep up, risk of data loss
```

**Step 5: Check Query Hold-ups**
```bash
# On Primary - identify long-running queries blocking replication
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c '
SELECT 
  pid,
  usename,
  query,
  query_start,
  EXTRACT(EPOCH FROM (NOW() - query_start)) as duration_sec
FROM pg_stat_activity
WHERE query NOT LIKE \"autovacuum%\" 
  AND duration_sec > 60
ORDER BY duration_sec DESC;
'
"
```

### Resolution Strategies

**If High Transaction Load (Root Cause #1)**:
```bash
# Option 1: Distribute load across replicas
# - Direct read traffic to read replicas (if available)
# - Scale replica count from 1 to 3-5
# - See CAPACITY_PLANNING_SCALING_GUIDE.md

# Option 2: Increase Primary Resources
docker-compose -f docker-compose.enterprise.yml stop code-server-postgres
# Infrastructure team: Add CPU cores to primary

# Option 3: Optimize queries generating excessive WAL
# - Review application logs for batch insert patterns
# - Break large transactions into smaller ones
# - Implement write batching on application side
```

**If Replica Bottleneck (Root Cause #2)**:
```bash
# Option 1: Scale replica resources
ssh akushnir@192.168.168.42 "
# Increase shared_buffers for replica
docker exec code-server-postgres psql -U postgres -c '
ALTER SYSTEM SET shared_buffers = \"8GB\";
'
docker restart code-server-postgres
"

# Option 2: Improve disk I/O
# - Check for competing I/O (backups, log rotation)
# - Schedule backups during off-peak
# - Enable SSD for WAL journal (fastest disk)

# Option 3: Disable non-essential features on replica
# - Disable autovacuum during peak hours
# - Disable index creation during high replication lag
```

**If Network Saturation (Root Cause #3)**:
```bash
# Option 1: Increase network bandwidth
# - Upgrade from 1 Gbps to 10 Gbps if available
# - Use dedicated network for replication traffic

# Option 2: Compress replication stream
# - Not directly supported in PostgreSQL
# - Workaround: Use SSH tunnel with compression
#   ssh -C (enable compression)

# Option 3: Schedule large operations off-peak
# - Move bulk imports to night hours
# - Schedule backups during off-peak

# Option 4: Verify other services not saturating network
ssh akushnir@192.168.168.31 "
iftop -n -t -N -P -L 10  # Top 10 network consumers
nethogs -t -c | head -20
"
```

### Prevention Measures

```bash
# 1. Set up alerting for replication lag
# In AlertManager, add:
# - alert: ReplicationLagHigh
#   expr: replication_lag_seconds > 30
#   for: 5m
#   action: Page on-call engineer

# 2. Monitor WAL generation rate in Prometheus
# Add metric:
# - wal_generation_rate_mb_per_sec

# 3. Implement query timeout policy
docker exec code-server-postgres psql -U postgres -c '
ALTER SYSTEM SET statement_timeout = \"600000\";  -- 10 minutes
ALTER SYSTEM SET lock_timeout = \"30000\";         -- 30 seconds
'

# 4. Regular replica catchup verification
# Add to cron job (run hourly):
REPLICATION_LAG=\$(ssh akushnir@192.168.168.31 "
  docker exec code-server-postgres psql -U postgres -c '
  SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT;
  ' | tail -1
)
if [ "\$REPLICATION_LAG" -gt 30 ]; then
  # Alert or trigger corrective action
fi
```

---

## Scenario 2: Cascading Container Failures

**Severity**: 🔴 CRITICAL  
**Symptoms**:
- Multiple containers (5-10+) restart simultaneously
- Pattern: One service fails, dependent services fail next
- Error logs show connection refused errors in dependent services
- Platform gradually loses functionality over 30-60 seconds

**Root Causes** (in order of likelihood):
1. Central service down (PostgreSQL, Redis) - causes all dependents to fail
2. Shared network resource exhausted (connection pool, file descriptor limit)
3. Disk full - PostgreSQL cannot write, all services using DB fail
4. Memory OOM (Out of Memory) - random kills cascade
5. Docker daemon restart - all containers lose state
6. Network partition - containers can't communicate

### Investigation Procedures

**Step 1: Check if Central Service Down**
```bash
# Check the "big three" core services
for HOST in 192.168.168.31 192.168.168.42; do
  echo "=== $HOST ==="
  
  # PostgreSQL
  ssh akushnir@$HOST "
    docker exec code-server-postgres psql -U postgres -c 'SELECT 1;' && echo '✅ PostgreSQL' || echo '❌ PostgreSQL DOWN'
  "
  
  # Redis
  ssh akushnir@$HOST "
    docker exec code-server-redis redis-cli PING && echo '✅ Redis' || echo '❌ Redis DOWN'
  "
  
  # Prometheus (monitoring)
  ssh akushnir@$HOST "
    docker exec code-server-prometheus curl -s http://localhost:9090/-/healthy && echo '✅ Prometheus' || echo '❌ Prometheus DOWN'
  "
done
```

**Step 2: Check Restart Loop**
```bash
# Identify containers in restart loop
ssh akushnir@192.168.168.31 "
docker ps -a --format 'table {{.Names}}\t{{.State}}\t{{.Status}}' | grep -E 'Restarting|Exited'

# Check restart count
docker inspect \$(docker ps -a -q) --format '{{.Name}}\t{{.RestartCount}}' | sort -t '\t' -k2 -rn | head -10
"
```

**Step 3: Check System Resources**
```bash
# Check disk space (most common in cascades)
ssh akushnir@192.168.168.31 "
echo '=== Disk ==='
df -h / /var/lib/docker
du -sh /var/lib/docker/*/

echo '=== Memory ==='
free -h
docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}' | head -10

echo '=== File Descriptors ==='
ulimit -n
lsof | wc -l
"
```

**Step 4: Review Docker Daemon Logs**
```bash
ssh akushnir@192.168.168.31 "
# Docker daemon logs (last 50 lines)
sudo tail -50 /var/log/docker.log 2>/dev/null || journalctl -u docker | tail -50

# Look for:
# - 'OOM' messages (Out of Memory)
# - 'File descriptor limit' errors
# - 'Cannot connect to' messages
# - 'Disk quota exceeded' errors
"
```

**Step 5: Check Container Exit Codes**
```bash
# Exit codes indicate failure type:
# - 0: Graceful exit
# - 1: Application error (check logs)
# - 143: Killed by SIGTERM (graceful shutdown)
# - 137: Killed by OOM (memory issue)
# - 125: Docker runtime error (resource limits)

ssh akushnir@192.168.168.31 "
docker ps -a --format '{{.Names}}: {{.ExitCode}}' | grep -v ': 0' | head -20
"
```

### Resolution Strategies

**If PostgreSQL Down**:
```bash
# Option 1: Restart PostgreSQL
ssh akushnir@192.168.168.31 "
docker restart code-server-postgres
sleep 10
# Other containers should recover
"

# Option 2: If doesn't recover, check storage
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c 'SELECT * FROM pg_database;'
# If fails: Restore from backup
"

# Option 3: Fail over to replica (if primary corrupted)
# See Scenario 4: Complete Primary Failure
```

**If Redis Down**:
```bash
# Option 1: Restart Redis
ssh akushnir@192.168.168.31 "
docker restart code-server-redis
sleep 5
# Dependent services (cache, sessions) should recover
"

# Option 2: Check Redis data integrity
ssh akushnir@192.168.168.31 "
docker exec code-server-redis redis-cli --rdb /tmp/redis-backup.rdb 2>&1
docker exec code-server-redis redis-cli SHUTDOWN NOSAVE
docker restart code-server-redis
"
```

**If Disk Full**:
```bash
# Immediate action: Free disk space
ssh akushnir@192.168.168.31 "
# Emergency cleanup
docker system prune --all --force  # Remove unused images/containers
docker volume prune --force        # Remove unused volumes

# PostgreSQL WAL cleanup
docker exec code-server-postgres pg_archivecleanup /var/lib/postgresql/wal -d

# Old logs cleanup
find /var/log -type f -name '*.log' -mtime +30 -delete

# Check progress
df -h /var/lib/docker
"

# Long-term: Add storage
# Infrastructure team: Expand /var/lib/docker filesystem
```

**If Memory OOM**:
```bash
# Identify memory hogs
ssh akushnir@192.168.168.31 "
docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}\t{{.MemLimit}}' | sort -t 'G' -k2 -rn
"

# Option 1: Increase container memory limits
docker-compose -f docker-compose.enterprise.yml down
# Edit docker-compose.enterprise.yml - increase mem_limit
docker-compose -f docker-compose.enterprise.yml up -d

# Option 2: Enable swap (short-term workaround)
sudo swapon -s
if [ -z "\$(swapon -s | tail -1)" ]; then
  # No swap - enable it
  sudo dd if=/dev/zero of=/var/swapfile bs=1G count=16
  sudo chmod 600 /var/swapfile
  sudo mkswap /var/swapfile
  sudo swapon /var/swapfile
fi

# Option 3: Restart services sequentially (load balance startup)
for SVC in postgres redis prometheus grafana; do
  docker restart code-server-\$SVC
  sleep 30  # Wait for stabilization
done
```

**If Docker Daemon Crashed**:
```bash
# Restart Docker daemon
ssh akushnir@192.168.168.31 "
sudo systemctl restart docker
sleep 10
# Docker starts all containers with restart policy

# Verify recovery
docker ps | wc -l  # Should show 40+ containers
"
```

### Prevention Measures

```bash
# 1. Set resource limits on all containers
# In docker-compose.enterprise.yml:
services:
  code-server-postgres:
    mem_limit: 16g
    memswap_limit: 16g
    cpu_limit: '4'
  # (repeat for all services)

# 2. Enable monitoring alerts
# - Disk usage > 80%: WARNING
# - Disk usage > 95%: CRITICAL
# - Memory usage > 85%: WARNING
# - Container restart rate: > 2 per 5 min: CRITICAL

# 3. Regular health checks
watch -n 300 "
  docker ps | wc -l
  docker stats --no-stream | awk 'NR>1 {print \$1}' | xargs -I {} docker logs {} --tail 5 | grep -i error | wc -l
"

# 4. Automatic recovery with restart policies
# All containers should have:
# restart_policy:
#   condition: on-failure
#   max_retries: 5
#   delay: 5s
```

---

## Scenario 3: Data Corruption Detected

**Severity**: 🔴 CRITICAL  
**Symptoms**:
- PostgreSQL check fails: `WARNING pg_database_table "public.table_name" page verification failed`
- Data doesn't match between primary and replica
- Application errors on specific queries: "could not access relation"
- pg_dump fails partway through with I/O errors

**Root Causes**:
1. Hardware failure (bit flip in disk/RAM)
2. Abrupt power loss during write
3. File system corruption
4. Bug in PostgreSQL or kernel
5. Shared buffer/WAL file corruption

### Investigation & Recovery

```bash
# Step 1: Verify extent of corruption
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres << 'SQL'
  -- Find corrupted tables
  REINDEX DATABASE code_server_db;  -- Force rebuild all indexes
  -- If this fails, corruption is severe
SQL
"

# Step 2: If corruption confirmed, BEGIN RESTORE
# 1. Stop primary PostgreSQL
docker stop code-server-postgres

# 2. Restore from backup (see Scenario: Backup Restore)
# 3. Verify replica caught up before promoting

# Step 3: If corruption on replica only
# 1. Rebuild replica from primary:
docker rm code-server-postgres-replica
# Then redeploy replica from docker-compose
```

---

## Scenario 4: Complete Primary Failure (Host Down)

**Severity**: 🔴 CRITICAL  
**Symptoms**:
- SSH connection timeout to 192.168.168.31
- All containers on primary unresponsive
- Network unreachable
- Physical host down (power failure, kernel panic)

### Failover Procedure

```bash
# Step 1: Confirm primary is down
ssh -o ConnectTimeout=3 akushnir@192.168.168.31 "uptime" 
# If times out → Primary confirmed down

# Step 2: Promote replica to primary
ssh akushnir@192.168.168.42 "
docker exec code-server-postgres psql -U postgres -c 'SELECT pg_promote();'
# This promotes replica to standalone primary (not reversible without resync)
"

# Step 3: Verify promotion
ssh akushnir@192.168.168.42 "
docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'
# Should return FALSE (now a primary)
"

# Step 4: Update application connection strings
# Point all services to new primary at 192.168.168.42:5432
# Update docker-compose.enterprise.yml on replica host

# Step 5: Wait for primary recovery
# When primary hardware is repaired:
# 1. Deploy new replica to primary host
# 2. Configure replication from new primary
# 3. Sync data

# Step 6: Full recovery (infrastructure support required)
```

---

## Scenario 5: Network Partition (Split-Brain)

**Severity**: 🟠 HIGH  
**Symptoms**:
- Primary and replica both claim to be primary
- Replication resets every 30 seconds
- Network latency extremely high (>1 second)
- Intermittent connection failures between hosts

### Investigation & Recovery

```bash
# Step 1: Check network connectivity
for HOST in 192.168.168.31 192.168.168.42; do
  echo "Pinging $HOST from other..."
  ssh akushnir@$HOST "ping -c 3 192.168.168.42 2>&1 | tail -2"
done

# Step 2: Check routing
ssh akushnir@192.168.168.31 "route -n | grep 192.168.168"
ssh akushnir@192.168.168.42 "route -n | grep 192.168.168"

# Step 3: If primary and replica both acting as primary:
# This is DANGEROUS - dual-write corruption possible

# Stop writing to replica immediately
ssh akushnir@192.168.168.42 "
# Block write connections except from designated application
iptables -A INPUT -p tcp --dport 5432 -j DROP  # Temporary
"

# Fix network (infrastructure team)
# Once fixed, rebuild replica from primary backup
```

---

## Scenario 6: Slow Query Performance Degradation

**Severity**: 🟡 MEDIUM → 🟠 HIGH  
**Symptoms**:
- API response times increased 5x (100ms → 500ms)
- Application reports database queries slow
- Grafana shows query latency spikes
- Users report timeouts

### Investigation

```bash
# Step 1: Identify slow queries
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres << 'SQL'
  -- Query execution statistics
  SELECT 
    query,
    calls,
    mean_time,
    max_time,
    stddev_time
  FROM pg_stat_statements
  WHERE mean_time > 1000  -- > 1 second
  ORDER BY mean_time DESC
  LIMIT 20;
SQL
"

# Step 2: Analyze specific slow query
SLOW_QUERY="SELECT * FROM large_table WHERE indexed_column = value"
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres << 'SQL'
  EXPLAIN ANALYZE $SLOW_QUERY;
SQL
"

# Step 3: Check index usage
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres << 'SQL'
  SELECT 
    schemaname,
    tablename,
    indexname,
    idx_blks_hit,
    idx_blks_read
  FROM pg_stat_user_indexes
  WHERE idx_blks_read > 0
  ORDER BY idx_blks_read DESC
  LIMIT 20;
SQL
"

# Step 4: Check table statistics
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres << 'SQL'
  ANALYZE;  -- Update statistics
  SELECT * FROM pg_stat_user_tables WHERE n_dead_tup > 1000;
SQL
"

# Step 5: Check resource contention
ssh akushnir@192.168.168.31 "
top -bn1 -p \$(docker inspect -f '{{.State.Pid}}' code-server-postgres) | head -5
iostat -x 1 3 | grep -E 'avg-cpu|sda'
"
```

### Resolution

```bash
# Option 1: Create missing index
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres << 'SQL'
  CREATE INDEX CONCURRENTLY idx_tablename_column ON public.tablename(column);
  -- Concurrent indexing doesn't lock table
SQL
"

# Option 2: Vacuum/Analyze to update statistics
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres << 'SQL'
  VACUUM ANALYZE public.large_table;
SQL
"

# Option 3: Increase shared_buffers (cache more data)
docker-compose -f docker-compose.enterprise.yml stop code-server-postgres
# Edit docker-compose.enterprise.yml
# Change POSTGRES_INITDB_ARGS shared_buffers from 16G to 24G
docker-compose -f docker-compose.enterprise.yml up -d code-server-postgres

# Option 4: Rewrite slow query for better execution plan
# Work with application development team
```

---

## Scenario 7: Certificate Expiry / TLS Errors

**Severity**: 🟡 MEDIUM → 🔴 CRITICAL (near expiry)  
**Symptoms**:
- Browser shows "Certificate Expired" or "Invalid Certificate"
- HTTPS connections fail
- Clients see "x509: certificate has expired"
- API calls receive 403 errors

### Investigation

```bash
# Check certificate expiry on Caddy
ssh akushnir@192.168.168.31 "
docker exec code-server-caddy openssl s_client -connect localhost:443 < /dev/null 2>/dev/null | \
grep -E 'notBefore|notAfter'

# Alternative: Check from outside
echo | openssl s_client -connect 192.168.168.31:443 2>/dev/null | \
grep -E 'notBefore|notAfter'
"
```

### Resolution

```bash
# Option 1: Renew certificate (if using Let's Encrypt)
ssh akushnir@192.168.168.31 "
docker exec code-server-caddy caddy renew 2>&1
docker exec code-server-caddy caddy reload 2>&1
"

# Option 2: If using self-signed (test/internal)
ssh akushnir@192.168.168.31 "
# Generate new self-signed certificate (valid 365 days)
openssl req -x509 -newkey rsa:4096 -keyout /tmp/key.pem -out /tmp/cert.pem -days 365 -nodes

# Update Caddy configuration and reload
docker exec code-server-caddy caddy reload
"

# Verify certificate renewed
echo | openssl s_client -connect 192.168.168.31:443 2>/dev/null | grep notAfter
```

---

## Quick Escalation Flowchart

```
CRITICAL ISSUE DETECTED
├─ Can connect to primary?
│  ├─ NO → Scenario 4: Primary Failure (Failover)
│  └─ YES → Can connect to PostgreSQL?
│     ├─ NO → Check container status + restart
│     └─ YES → Scenario 2: Cascading Failures?
│
├─ Is replication healthy?
│  ├─ NO → Scenario 1: Replication Lag (Investigate)
│  └─ YES → Check application services
│
├─ Are API endpoints responding?
│  ├─ NO → Scenario 6: Slow Query? (Investigate)
│  └─ YES → User issue (not platform issue)
│
└─ If still unclear → Scenario 2: Cascading Failures
   (Most likely multiple failures simultaneously)
```

---

## Support Escalation Procedures

| Issue | L1 | L2 | L3 |
|-------|----|----|----| 
| Container restart | ✅ | | |
| Replication lag | ✅ | ✅ | |
| Slow queries | ✅ | ✅ | |
| Data corruption | | ✅ | ✅ |
| Network partition | | | ✅ |
| Hardware failure | | | ✅ |

**L1 (Operations)**: Containers, logs, restarts, monitoring  
**L2 (Database Admin)**: Replication, performance, backups  
**L3 (Engineering Lead)**: Code issues, architecture, infrastructure  

---

**Document History**

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | April 29, 2026 | Initial advanced troubleshooting scenarios |

---

**Related Documents**:
- OPERATIONS_HANDOFF_GUIDE.md (Section: Troubleshooting)
- PRODUCTION_DEPLOYMENT_CHECKLIST.md
- CAPACITY_PLANNING_SCALING_GUIDE.md
