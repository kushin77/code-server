# Production Troubleshooting Guide v1.0.0

**Document Version**: 1.0.0  
**Last Updated**: May 1, 2026  
**Severity Levels**: 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low

---

## Quick Diagnosis Flow

```
Issue Detected
    ↓
1. Check platform status (full-deployment-test.sh)
    ↓ (Is platform responsive?)
├─ NO  → See "Platform Down" section
└─ YES → See specific symptom below
         ├─ Services unhealthy? → Service Health section
         ├─ Performance slow? → Performance Degradation section
         ├─ Database issues? → Database Replication section
         ├─ Network problems? → Network Connectivity section
         └─ Observability issues? → Observability Stack section
```

---

## 🔴 CRITICAL ISSUES

### Platform Completely Down

**Symptoms**:
- Cannot SSH to either host (192.168.168.31 or .42)
- No containers running (`docker ps` returns empty)
- All services unreachable (web consoles offline)

**Diagnosis** (run from deployment host):
```bash
# Test connectivity to primary
ssh -o ConnectTimeout=5 ops@192.168.168.31 "docker ps" || echo "PRIMARY UNREACHABLE"

# Test connectivity to replica
ssh -o ConnectTimeout=5 ops@192.168.168.42 "docker ps" || echo "REPLICA UNREACHABLE"

# Check last terraform state
cd /home/akushnir/code-server && terraform state list
```

**Resolution Steps**:

**If both hosts unreachable** (infrastructure failure):
1. Contact infrastructure team (datacenter networking)
2. Verify IP routing to 192.168.168.0/24 subnet
3. Check if hosts are powered on (IPMI/physical console)
4. Restart both hosts if necessary
5. Run: `cd /home/akushnir/code-server && scripts/ops/full-deployment-test.sh --dry-run`

**If only primary unreachable** (single host failure):
1. SSH to replica host (192.168.168.42)
2. Verify replica services are running:
   ```bash
   docker ps --format "{{.Names}}\t{{.Status}}" | head -20
   ```
3. Manually activate replica:
   ```bash
   # Promote replica to primary (manual failover)
   docker exec keepalived-replica ip addr add 192.168.168.50 dev eth0 || true
   ```
4. Update application connection strings to point to 192.168.168.42 directly
5. Repair primary host and reintegrate

**Recovery Validation**:
```bash
# After recovery, run full validation
scripts/ops/full-deployment-test.sh

# Verify database replication (from primary)
docker exec postgresql-primary psql -U postgres -c "SELECT name, state FROM pg_stat_replication;"
```

---

### All Database Connections Failing

**Symptoms**:
- PostgreSQL service shows healthy but queries timeout
- "Connection refused" errors on port 5432
- Applications log: `FATAL: remaining connection slots are reserved`

**Diagnosis**:
```bash
# Check PostgreSQL connection limit
docker exec postgresql-primary psql -U postgres -c "SHOW max_connections;"
docker exec postgresql-primary psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Check for stuck connections
docker exec postgresql-primary psql -U postgres -c \
  "SELECT usename, state, wait_event FROM pg_stat_activity WHERE state = 'active';"
```

**Resolution**:

**If connection pool exhausted**:
1. Identify and kill idle connections:
   ```bash
   docker exec postgresql-primary psql -U postgres -c \
     "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND query_start < now() - interval '10 min';"
   ```
2. Check if any application is leaking connections (logs)
3. Increase connection pool:
   ```bash
   # Edit docker-compose.prod.yml and set:
   # POSTGRES_MAX_CONNECTIONS=200
   docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml -f docker-compose.prod.yml restart postgresql-primary
   ```

**If database is truly down**:
1. Check logs: `docker logs postgresql-primary | tail -50`
2. Verify disk space: `docker exec postgresql-primary df -h /var/lib/postgresql`
3. If out of space, implement cleanup:
   ```bash
   docker exec postgresql-primary psql -U postgres -c "VACUUM ANALYZE;"
   ```

---

### Redis Cache Layer Failed

**Symptoms**:
- Redis service container shows unhealthy
- Applications see: "Connection refused on 6379"
- Sessions not persisting (users logged out)

**Diagnosis**:
```bash
# Check Redis health
docker exec redis-primary redis-cli PING

# Check memory usage
docker exec redis-primary redis-cli INFO memory

# Check replication status
docker exec redis-primary redis-cli INFO replication
```

**Resolution**:

**If Redis memory full**:
```bash
# Set eviction policy (LRU)
docker exec redis-primary redis-cli CONFIG SET maxmemory-policy allkeys-lru

# Or increase memory limit
# Edit docker-compose and set:
# - "--maxmemory 4gb"
docker-compose restart redis-primary
```

**If Redis crashed**:
```bash
# Restart Redis
docker restart redis-primary

# Wait 10 seconds for replica to sync
sleep 10

# Verify replication
docker exec redis-primary redis-cli INFO replication
```

**If persistence corrupted**:
```bash
# Clear corrupted RDB file
docker exec redis-primary rm /data/dump.rdb || true

# Restart (will rebuild from replica)
docker restart redis-primary
```

---

## 🟠 HIGH PRIORITY ISSUES

### Database Replication Broken

**Symptoms**:
- Primary running but replica not receiving updates
- `pg_stat_replication` shows 0 replicas on primary
- Data diverges between primary and replica

**Diagnosis**:
```bash
# From primary
docker exec postgresql-primary psql -U postgres -c \
  "SELECT * FROM pg_stat_replication \G"

# Check replication slots
docker exec postgresql-primary psql -U postgres -c \
  "SELECT slot_name, restart_lsn FROM pg_replication_slots;"

# Check WAL level
docker exec postgresql-primary psql -U postgres -c "SHOW wal_level;"
```

**Resolution**:

**If replica lagging severely**:
1. Check replica status:
   ```bash
   docker exec postgresql-replica psql -U postgres -c "SELECT now() - pg_last_xact_replay_time();"
   ```
2. If lag > 1 hour, rebuild replica:
   ```bash
   # Stop replica
   docker stop postgresql-replica
   
   # Remove corrupted data
   docker exec postgresql-replica rm -rf /var/lib/postgresql/data/*
   
   # Restart (will perform pg_basebackup from primary)
   docker start postgresql-replica
   
   # Monitor progress
   docker logs -f postgresql-replica | grep -i basebackup
   ```

**If replication slot full**:
1. Check slot status:
   ```bash
   docker exec postgresql-primary psql -U postgres -c \
     "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"
   ```
2. Drop unused slots:
   ```bash
   docker exec postgresql-primary psql -U postgres -c \
     "SELECT pg_drop_replication_slot('old_slot_name');"
   ```

**If WAL files accumulating**:
```bash
# Check WAL directory size
docker exec postgresql-primary du -sh /var/lib/postgresql/pg_wal

# Force checkpoint
docker exec postgresql-primary psql -U postgres -c "CHECKPOINT;"

# Remove old WAL files
docker exec postgresql-primary psql -U postgres -c \
  "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0');"
```

---

### Keepalived Failover Not Working

**Symptoms**:
- Primary fails but VIP (192.168.168.50) doesn't move to replica
- Applications timeout trying to reach 192.168.168.50
- Manual failover required (service interruption)

**Diagnosis**:
```bash
# Check Keepalived status on primary
docker exec keepalived-primary ip addr show | grep 192.168.168.50

# Check Keepalived status on replica
docker exec keepalived-replica ip addr show | grep 192.168.168.50

# Check VRRP protocol
docker logs keepalived-primary | tail -20 | grep -i vrrp

# Check priority
docker exec keepalived-primary docker-entrypoint.sh && grep -i priority /etc/keepalived/keepalived.conf
```

**Resolution**:

**If VIP stuck on unhealthy primary**:
1. Manually move VIP to replica:
   ```bash
   # On replica
   docker exec keepalived-replica sudo ip addr add 192.168.168.50/24 dev eth0
   
   # Test connectivity
   ssh ops@192.168.168.50 "docker ps" && echo "Failover successful"
   ```

2. Fix primary Keepalived configuration:
   ```bash
   # On primary, check health check script
   docker logs keepalived-primary | grep -i "health check"
   
   # Verify PostgreSQL port accessible
   docker exec keepalived-primary nc -zv 127.0.0.1 5432
   ```

3. If health check failing, restart Keepalived:
   ```bash
   docker restart keepalived-primary
   sleep 5
   # Check if VIP moved
   docker exec keepalived-primary ip addr show | grep 192.168.168.50
   ```

**If Keepalived not starting**:
1. Check configuration syntax:
   ```bash
   docker exec keepalived-primary keepalived -t -f /etc/keepalived/keepalived.conf
   ```
2. Check logs:
   ```bash
   docker logs keepalived-primary --tail 50
   ```
3. Regenerate config and restart:
   ```bash
   docker-compose restart keepalived-primary
   ```

---

### Redpanda Message Loss / Lag

**Symptoms**:
- Applications unable to publish to Redpanda
- Consumer lag growing continuously
- "Broker unavailable" errors

**Diagnosis**:
```bash
# Check broker health
docker exec redpanda-primary rpk cluster info

# Check topic status
docker exec redpanda-primary rpk topic list

# Check consumer lag
docker exec redpanda-primary rpk group describe my-consumer-group
```

**Resolution**:

**If broker disk full**:
```bash
# Check disk usage
docker exec redpanda-primary df -h /var/lib/redpanda

# Identify large topics
docker exec redpanda-primary rpk topic describe my-topic

# Delete oldest messages (retention cleanup)
docker exec redpanda-primary rpk topic alter my-topic --set retention.ms=86400000
```

**If consumer lag critical**:
```bash
# Reset consumer group offset (WARNING: data loss)
docker exec redpanda-primary rpk group seek my-consumer-group --to-offset=latest my-topic

# Or restart consumer application
docker restart consumer-app-container
```

**If broker not responding**:
```bash
# Restart broker
docker restart redpanda-primary

# Monitor startup
docker logs -f redpanda-primary | grep -i "started"

# Verify cluster reformation
docker exec redpanda-primary rpk cluster info
```

---

## 🟡 MEDIUM PRIORITY ISSUES

### High Memory Usage

**Symptoms**:
- Docker host running out of memory
- Services OOMKilled (killed after running for hours)
- Performance degradation

**Diagnosis**:
```bash
# Check host memory
free -h

# Check Docker memory stats
docker stats --no-stream

# Check specific service memory
docker stats --no-stream | grep postgresql-primary

# Check application heap usage (if instrumented)
docker exec my-service jps -lv | grep -i memory
```

**Resolution**:

**If specific service using too much**:
1. Restart service:
   ```bash
   docker restart postgresql-primary
   ```
2. If restarts don't help, check logs for memory leak:
   ```bash
   docker logs postgresql-primary | grep -i memory
   ```
3. Increase host memory (vertical scaling)

**If overall host memory pressure**:
1. Identify top memory consumers:
   ```bash
   docker stats --no-stream | sort -k 4 -hr | head -10
   ```
2. Consider stopping non-essential services:
   ```bash
   docker stop appsmith  # non-critical development service
   ```
3. Scale to larger host instance if needed

**Memory pressure symptoms**:
- Kernel page cache eviction messages in dmesg
- Services responding slowly
- High disk I/O (swapping)

---

### High CPU Usage

**Symptoms**:
- Host CPU at 80-100% continuously
- Slow application responses
- Dashboard showing performance degradation

**Diagnosis**:
```bash
# Check top CPU consumers
docker stats --no-stream | sort -k 3 -hr | head -10

# Check system CPU context switches
vmstat 1 5 | tail -4

# Check if database performing full table scans
docker exec postgresql-primary psql -U postgres -c \
  "SELECT query, calls FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
```

**Resolution**:

**If database queries slow**:
1. Analyze slow query log:
   ```bash
   docker exec postgresql-primary psql -U postgres -c \
     "SET log_statement = 'all'; SET log_duration = on;"
   ```
2. Create missing indexes:
   ```bash
   docker exec postgresql-primary psql -U postgres -c \
     "CREATE INDEX idx_table_column ON table(column);"
   ```
3. Run VACUUM to analyze statistics:
   ```bash
   docker exec postgresql-primary psql -U postgres -c "VACUUM ANALYZE;"
   ```

**If application spinning**:
1. Check for infinite loops in application logs
2. Increase log verbosity to identify problem query
3. Restart service if necessary:
   ```bash
   docker restart application-service
   ```

**If Prometheus scraping overloaded**:
1. Increase scrape interval:
   ```bash
   # Edit prometheus config
   # Change: scrape_interval: 15s to 30s
   docker restart prometheus
   ```

---

### Disk Space Critical

**Symptoms**:
- Docker unable to create new containers
- Database not accepting writes
- Log files not rotating

**Diagnosis**:
```bash
# Check disk usage
df -h /

# Check which directory consuming most space
du -sh /* | sort -hr

# Check Docker image/volume sizes
docker system df

# Check specific volumes
docker volume ls -q | xargs -I {} sh -c 'echo "Volume: {}" && docker volume inspect {} | grep Mountpoint'
```

**Resolution**:

**If Docker consuming too much**:
1. Remove unused images:
   ```bash
   docker image prune -a --force
   ```
2. Remove unused volumes:
   ```bash
   docker volume prune --force
   ```
3. Clean Docker system cache:
   ```bash
   docker system prune --all --force
   ```

**If database growing too large**:
1. Implement retention policies:
   ```bash
   # Archive old data
   docker exec postgresql-primary psql -U postgres -c \
     "DELETE FROM events WHERE created_at < now() - interval '90 days';"
   ```
2. Run VACUUM to reclaim space:
   ```bash
   docker exec postgresql-primary psql -U postgres -c "VACUUM FULL;"
   ```

**If logs consuming space**:
1. Rotate logs manually:
   ```bash
   logrotate -f /etc/logrotate.d/docker
   ```
2. Limit container log size:
   ```yaml
   # Add to docker-compose.yml:
   logging:
     options:
       max-size: "100m"
       max-file: "3"
   ```

---

### Prometheus Not Scraping Metrics

**Symptoms**:
- Grafana dashboards show "No Data"
- Prometheus targets showing DOWN status
- Metrics older than 5 minutes

**Diagnosis**:
```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# Check for scrape errors
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down")'

# Check Prometheus scrape config
docker exec prometheus cat /etc/prometheus/prometheus.yml | grep -A 10 "scrape_configs:"
```

**Resolution**:

**If targets showing DOWN**:
1. Test endpoint manually:
   ```bash
   # Get target URL from Prometheus UI
   curl -s http://localhost:8090/metrics | head -5
   ```
2. If target unreachable, restart service:
   ```bash
   docker restart code-server-ide
   ```
3. If metrics endpoint doesn't exist, add instrumentation to application

**If scrape interval too frequent**:
1. Reduce scrape frequency:
   ```yaml
   # Edit prometheus.yml:
   scrape_interval: 30s  # instead of 15s
   ```
2. Restart Prometheus:
   ```bash
   docker restart prometheus
   ```

**If Prometheus database full**:
1. Check retention settings:
   ```bash
   docker exec prometheus prometheus --help | grep retention
   ```
2. Reduce retention period:
   ```bash
   # Edit docker-compose.yml:
   # Add: --storage.tsdb.retention.time=7d
   docker-compose restart prometheus
   ```

---

### Loki Log Ingestion Failing

**Symptoms**:
- Loki service running but no logs appear in Grafana
- "No logs found" in Loki UI
- Services sending logs but Loki not receiving

**Diagnosis**:
```bash
# Check Loki health
curl -s http://localhost:3100/loki/api/v1/status/buildinfo | jq .

# Check Loki storage
docker exec loki du -sh /loki

# Test log push (should return 204)
curl -X POST -H "Content-Type: application/json" \
  http://localhost:3100/loki/api/v1/push \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s%N)'","test message"]]}]}'
```

**Resolution**:

**If Loki not receiving logs**:
1. Check application log shipper configuration:
   ```bash
   docker logs fluent-bit | head -20
   ```
2. Verify Loki endpoint accessible:
   ```bash
   docker exec fluent-bit nc -zv loki 3100
   ```
3. Restart log shipper:
   ```bash
   docker restart fluent-bit
   ```

**If Loki storage full**:
1. Check index size:
   ```bash
   docker exec loki du -sh /loki/index
   ```
2. Reduce retention:
   ```bash
   # Edit loki configuration:
   # Set: retention_deletes_enabled: true
   #      retention_period: 72h
   docker restart loki
   ```

**If Loki database corrupted**:
```bash
# Rebuild index
docker exec loki /loki/cmd/loki -config.file=/etc/loki/config.yml -boltdb.shipper.index-cache-validity=0

# Restart
docker restart loki
```

---

### Grafana Dashboards Not Updating

**Symptoms**:
- Grafana dashboards frozen (showing old data)
- Graphs not refreshing
- "Query timeout" errors in dashboard

**Diagnosis**:
```bash
# Check Grafana health
curl -s http://localhost:3000/api/health | jq .

# Check data source connectivity
curl -s http://localhost:3000/api/datasources | jq '.[] | {name, url, health}'

# Check query logs
docker logs grafana | tail -30 | grep -i error
```

**Resolution**:

**If data source connection failing**:
1. Verify datasource URL accessible:
   ```bash
   docker exec grafana nc -zv prometheus 9090
   docker exec grafana nc -zv loki 3100
   ```
2. Reconnect datasource in Grafana UI:
   - Configuration → Data Sources → Select datasource → Save & Test
3. If still failing, check Grafana logs:
   ```bash
   docker logs grafana --tail 50 | grep -i datasource
   ```

**If queries timing out**:
1. Increase query timeout:
   - Dashboard settings → Edit dashboard JSON
   - Find: `"timeoutMs": 30000`
   - Increase to `60000` or `120000`
2. Simplify queries (reduce time range or aggregation)

**If Grafana unresponsive**:
1. Restart service:
   ```bash
   docker restart grafana
   ```
2. Check admin password if login failing:
   ```bash
   docker exec grafana grafana-cli admin reset-admin-password newpassword
   ```

---

## 🟢 LOW PRIORITY ISSUES

### Docker Network Issues

**Symptoms**:
- Services can't reach each other by hostname
- DNS resolution failing for service names
- Intermittent connection timeouts

**Diagnosis**:
```bash
# Check Docker network
docker network inspect code-server-network | jq '.Containers | keys'

# Test DNS resolution
docker exec code-server-ide getent hosts postgresql-primary

# Test network connectivity
docker exec code-server-ide nc -zv postgresql-primary 5432

# Check network MTU
docker network inspect code-server-network | jq '.Options.com.docker.network.driver.mtu'
```

**Resolution**:

**If service not in network**:
1. Verify service defined in docker-compose:
   ```bash
   docker-compose config | grep "services:" -A 50
   ```
2. Reconnect service:
   ```bash
   docker network disconnect code-server-network service-name
   docker network connect code-server-network service-name
   ```

**If DNS failing**:
1. Check Docker resolver:
   ```bash
   docker exec code-server-ide cat /etc/resolv.conf
   ```
2. Restart Docker daemon:
   ```bash
   sudo systemctl restart docker
   ```

**If MTU too small (path MTU discovery issues)**:
1. Set larger MTU:
   ```bash
   docker network create --opt com.docker.network.driver.mtu=9000 new-network
   ```

---

### Container Performance Degradation

**Symptoms**:
- Service response time slowly increasing
- Memory usage growing over time (memory leak)
- Restart temporarily fixes performance

**Diagnosis**:
```bash
# Check container uptime and resource trends
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}" | sort

# Check for memory leaks in specific service
docker exec service-name top -b -n 1 | head -10

# Check for open file descriptors
docker exec service-name lsof | wc -l
```

**Resolution**:

**If memory leak suspected**:
1. Enable memory profiling (if application supports):
   ```bash
   docker exec service-name curl -s http://localhost:6060/debug/pprof/heap | head -20
   ```
2. Implement periodic restarts:
   ```yaml
   # Add to docker-compose.yml service definition:
   restart: unless-stopped
   ```
3. Use Kubernetes liveness probes (future migration)

**If file descriptor leak**:
1. Check ulimit:
   ```bash
   docker exec service-name ulimit -n
   ```
2. Increase limits:
   ```yaml
   ulimits:
     nofile:
       soft: 65536
       hard: 65536
   ```
3. Restart service:
   ```bash
   docker-compose restart service-name
   ```

---

### Application Logs Noise / Too Verbose

**Symptoms**:
- Log files growing very large (>1GB/day)
- Console output overwhelming
- Disk filling with logs

**Resolution**:

**Reduce log verbosity**:
1. Set application log level:
   ```bash
   docker exec code-server-ide \
     curl -X POST http://localhost:8090/debug/loglevel \
     -d '{"level":"warn"}'
   ```

**Implement log rotation**:
```yaml
# Add to docker-compose.yml:
logging:
  driver: "json-file"
  options:
    max-size: "50m"
    max-file: "5"
    labels-regex: "service=.*"
```

**Archive old logs**:
```bash
tar -czf logs-backup-$(date +%Y%m%d).tar.gz /var/log/containers/*.log
rm /var/log/containers/*.log
```

---

## Performance Tuning

### Query Performance (PostgreSQL)

**Symptoms**: Database queries taking >1 second

**Tuning steps**:
```bash
# 1. Check if indexes exist
docker exec postgresql-primary psql -U postgres -d mydb -c \
  "SELECT schemaname, tablename, indexname FROM pg_indexes WHERE tablename='slow_table';"

# 2. Create missing indexes
docker exec postgresql-primary psql -U postgres -d mydb -c \
  "CREATE INDEX idx_users_email ON users(email);"

# 3. Analyze table statistics
docker exec postgresql-primary psql -U postgres -d mydb -c \
  "ANALYZE users;"

# 4. Check query plan
docker exec postgresql-primary psql -U postgres -d mydb -c \
  "EXPLAIN ANALYZE SELECT * FROM users WHERE email='test@example.com';"
```

---

### Connection Pool Optimization

**For Applications Consuming Too Many Connections**:

```bash
# Check current connections
docker exec postgresql-primary psql -U postgres -c \
  "SELECT sum(numbackends) FROM pg_stat_database;"

# Implement connection pooling (PgBouncer)
docker run -d --name pgbouncer \
  -e PGHOST=postgresql-primary \
  -e PGPORT=5432 \
  pgbouncer:latest

# Connect applications through PgBouncer (localhost:6432)
```

---

## Escalation Procedures

| Issue | Severity | Escalation Path | Contact |
|-------|----------|-----------------|---------|
| **Platform down >30 min** | 🔴 Critical | Immediate call tree | ops@kushnir.cloud |
| **Data loss risk** | 🔴 Critical | Immediate call tree | security@kushnir.cloud |
| **Performance <50% normal** | 🟠 High | Engineering lead | devops@kushnir.cloud |
| **Single service down** | 🟡 Medium | On-call engineer | #incidents Slack |
| **Warning logs only** | 🟢 Low | Next standup | Documentation update |

---

## Additional Resources

- **OPERATIONAL_RUNBOOK.md** - Daily procedures
- **ARCHITECTURE_OVERVIEW.md** - System design
- **OPERATIONS_QUICK_REFERENCE.md** - Quick commands
- **Application Logs**: `/var/log/containers/`
- **Metrics Dashboard**: http://192.168.168.31:3000 (Grafana)
- **Trace Visualization**: http://192.168.168.31:3200 (Tempo)

---

**Last Updated**: May 1, 2026  
**Author**: Deployment Automation  
**Status**: Production Ready ✅
