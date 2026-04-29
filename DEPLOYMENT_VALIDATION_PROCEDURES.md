# Deployment Validation Procedures

**Document Version**: 1.0  
**Last Updated**: April 29, 2026  
**Status**: READY FOR DEPLOYMENT  
**Maintained By**: Operations Team  

---

## Executive Summary

This document provides step-by-step validation procedures for the code-server enterprise platform deployment. It covers pre-deployment validation, real-time monitoring during deployment, post-deployment verification, and continuous health monitoring.

**Key Metrics Targets**:
- RTO (Recovery Time Objective): 2-3 minutes
- RPO (Recovery Point Objective): < 5 minutes
- Availability Target: 99.99%
- Container Health: ≥ 87/88 (98.9%)

---

## Part 1: Pre-Deployment Validation (T-7 Days)

### 1.1 Infrastructure Prerequisites

**Primary Host (192.168.168.31)**
```bash
# Verify host accessibility
ssh -o ConnectTimeout=5 akushnir@192.168.168.31 "uptime && echo 'OK'"

# Verify Docker daemon running
ssh akushnir@192.168.168.31 "docker ps -q | wc -l && echo 'Docker running'"

# Verify disk space (requires > 50GB)
ssh akushnir@192.168.168.31 "df -h / | tail -1 && df -h /var/lib/docker | tail -1"

# Verify Docker images available
ssh akushnir@192.168.168.31 "docker images | grep code-server | wc -l"
```

**Expected Results**:
- ✅ SSH connection successful
- ✅ Docker daemon responding  
- ✅ Disk space > 50 GB on both `/` and `/var/lib/docker`
- ✅ All required Docker images present (40+ images)

**Replica Host (192.168.168.42)**
- Same procedures as Primary Host
- Verify bidirectional connectivity: `ssh primary "ping -c 3 192.168.168.42"`

### 1.2 Database Prerequisites

**PostgreSQL Primary (192.168.168.31:5432)**
```bash
# Verify primary database exists and is accessible
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -h localhost -c 'SELECT datname FROM pg_database WHERE datname = \"code_server_db\";'
"

# Verify replication slot configuration
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c '
SELECT slot_name, slot_type, active, wal_status FROM pg_replication_slots;
'
"

# Verify max_wal_senders
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c 'SHOW max_wal_senders;'
"

# Verify WAL level
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c 'SHOW wal_level;'
"
```

**Expected Results**:
- ✅ Database `code_server_db` exists
- ✅ Replication slot 'replication_slot' exists and is active
- ✅ max_wal_senders = 10
- ✅ wal_level = replica

**PostgreSQL Replica (192.168.168.42:5432)**
```bash
# Verify standby mode active
ssh akushnir@192.168.168.42 "
docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'
"

# Verify hot standby enabled
ssh akushnir@192.168.168.42 "
docker exec code-server-postgres psql -U postgres -c 'SHOW hot_standby;'
"

# Verify standby.signal file present
ssh akushnir@192.168.168.42 "
docker exec code-server-postgres ls -la /var/lib/postgresql/data/standby.signal
"
```

**Expected Results**:
- ✅ pg_is_in_recovery() = TRUE
- ✅ hot_standby = on
- ✅ standby.signal file present (0 bytes, -rw-r--r--)

### 1.3 Network Connectivity

```bash
# Primary → Replica on port 5432 (replication)
ssh akushnir@192.168.168.31 "
nc -zv -w 3 192.168.168.42 5432 && echo 'Replication port open'
"

# Replica → Primary on port 5432 (failover scenario)
ssh akushnir@192.168.168.42 "
nc -zv -w 3 192.168.168.31 5432 && echo 'Replication port open'
"

# Check for any network ACLs or firewall issues
ssh akushnir@192.168.168.31 "
ping -c 1 -W 2 192.168.168.42 && echo 'Network OK'
"
```

**Expected Results**:
- ✅ Port 5432 open both directions
- ✅ Ping successful
- ✅ Network latency < 10ms

### 1.4 Required Services Status

```bash
# On Primary Host
ssh akushnir@192.168.168.31 "
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'postgres|redis|prometheus|grafana|vault|oauth|caddy|gitlab|control-plane' | sort
"

# On Replica Host
ssh akushnir@192.168.168.42 "
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'postgres|redis|prometheus|grafana|vault|oauth|caddy|control-plane' | sort
"
```

**Expected Results**:
- ✅ PostgreSQL running on both hosts
- ✅ Redis running and responsive
- ✅ Prometheus collecting metrics
- ✅ Grafana with Prometheus + Loki datasources
- ✅ Vault operational
- ✅ OAuth2-Proxy running
- ✅ Caddy reverse proxy running
- ✅ All health checks passing

### 1.5 Pre-Deployment Sign-Off Checklist

- [ ] Deployment Manager: All prerequisites verified
- [ ] Operations Manager: Team trained and ready
- [ ] Engineering Lead: Docker images and configurations validated
- [ ] Security: Vault and secrets manager verified
- [ ] Network: Connectivity and firewalls confirmed

**Document**: Capture sign-off in deployment log before proceeding

---

## Part 2: Real-Time Deployment Monitoring (T-0 to T+30 min)

### 2.1 T-0 to T+5 min: Pre-Deployment Status

**Activities** (Primary Host):
```bash
# Capture baseline metrics
DEPLOY_START=$(date -Iseconds)
ssh akushnir@192.168.168.31 "
echo '=== BASELINE METRICS ==='
docker ps -q | wc -l | xargs echo 'Container Count:'
docker ps --format '{{.Status}}' | grep -c 'Up' | xargs echo 'Healthy Containers:'
docker exec code-server-postgres psql -U postgres -c 'SELECT COUNT(*) as connections FROM pg_stat_activity;' 
docker exec code-server-redis redis-cli DBSIZE
" > /tmp/baseline_metrics.log

# Verify no pending changes
git status --short
```

**Monitoring Dashboard** (Grafana):
- Open http://192.168.168.31:3000 (Grafana)
- Open Prometheus dashboard: http://192.168.168.31:9090
- Open Loki logs: http://192.168.168.31:3100

### 2.2 T+5 min: Deployment Initiation

**Start Docker Compose**:
```bash
# On Primary Host
ssh akushnir@192.168.168.31 "
cd ~/code-server-enterprise
bash -lc 'set -a; source .env; source .env.production; set +a; docker-compose -f docker-compose.enterprise.yml up -d' 2>&1 | tee /tmp/deploy-primary.log
"

# On Replica Host
ssh akushnir@192.168.168.42 "
cd ~/code-server-enterprise
bash -lc 'set -a; source .env; source .env.production; set +a; docker-compose -f docker-compose.enterprise.yml up -d' 2>&1 | tee /tmp/deploy-replica.log
"
```

**Monitor Real-Time**:
```bash
# Watch container startup on Primary
watch -n 5 'ssh akushnir@192.168.168.31 "docker ps --format=\"table {{.Names}}\t{{.Status}}\" | head -20"'

# Monitor in Grafana:
# - Dashboard: "Container Health"
# - Metric: up{job="docker"} to see container status
```

### 2.3 T+10 min: Partial Deployment Check

**Container Status**:
```bash
# Check both hosts for container count
for HOST in 192.168.168.31 192.168.168.42; do
  echo "=== Host $HOST ==="
  ssh -o ConnectTimeout=5 akushnir@HOST "
    docker ps -q | wc -l | xargs echo 'Total:'
    docker ps --format '{{.Status}}' | grep -c 'Up' | xargs echo 'Healthy:'
  "
done

# Expected: ~40+ containers starting, ~35+ already healthy
```

**Verify Critical Services**:
```bash
# PostgreSQL heartbeat on both hosts
for HOST in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$HOST "
    docker exec code-server-postgres psql -U postgres -c 'SELECT now();' >/dev/null 2>&1 && echo 'PostgreSQL OK on '$HOST || echo 'PostgreSQL FAILED on '$HOST
  "
done

# Redis connectivity
for HOST in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$HOST "
    docker exec code-server-redis redis-cli PING || echo 'Redis FAILED on '$HOST
  "
done
```

### 2.4 T+15 min: API Endpoint Checks

**Verify Service Endpoints**:
```bash
# Prometheus metrics
curl -s http://192.168.168.31:9090/api/v1/query?query=up | jq '.data.result | length' | xargs echo 'Prometheus targets:'

# Grafana dashboards
curl -s -u admin:admin http://192.168.168.31:3000/api/dashboards/home | jq '.dashboard.panels | length' | xargs echo 'Grafana panels:'

# Loki logs
curl -s http://192.168.168.31:3100/loki/api/v1/label/job/values | jq 'length' | xargs echo 'Loki jobs:'

# PostgreSQL replication status
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c 'SELECT usename, client_addr, state FROM pg_stat_replication;'
"
```

**Expected Results**:
- ✅ Prometheus: 40+ targets active
- ✅ Grafana: 20+ dashboard panels
- ✅ Loki: 30+ log streams
- ✅ PostgreSQL replication: Client connected (192.168.168.42)

### 2.5 T+20 min: Container Health Verification

**Full Container Status**:
```bash
# On Primary
ssh akushnir@192.168.168.31 "
echo '=== PRIMARY HOST CONTAINERS ==='
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Size}}' | sort
echo ''
echo '=== CONTAINER EXIT CODES ==='
docker ps -a --format 'table {{.Names}}\t{{.ExitCode}}' | grep -v ' 0' | tail -20
"

# On Replica
ssh akushnir@192.168.168.42 "
echo '=== REPLICA HOST CONTAINERS ==='
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Size}}' | sort
echo ''
echo '=== CONTAINER EXIT CODES ==='
docker ps -a --format 'table {{.Names}}\t{{.ExitCode}}' | grep -v ' 0' | tail -20
"
```

**Target**: All containers with exit code 0, 87/88 running (1 graceful shutdown acceptable)

### 2.6 T+25 min: Replication Status Check

```bash
# Verify replication is flowing
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c '
SELECT 
  usename, 
  client_addr, 
  state, 
  sync_state,
  write_lag,
  flush_lag,
  replay_lag
FROM pg_stat_replication;
'
"

# Verify WAL position sync
ssh akushnir@192.168.168.31 "
echo '=== PRIMARY WAL POSITION ==='
docker exec code-server-postgres psql -U postgres -c 'SELECT pg_current_wal_lsn();'
"

ssh akushnir@192.168.168.42 "
echo '=== REPLICA WAL POSITION ==='
docker exec code-server-postgres psql -U postgres -c 'SELECT pg_last_wal_replay_lsn();'
"
```

**Expected Results**:
- ✅ Replication state = streaming
- ✅ sync_state = async
- ✅ WAL positions within 100MB of each other
- ✅ No lag > 1 second

### 2.7 T+30 min: Deployment Complete Validation

**Service Availability Check**:
```bash
# Check all critical services responding
declare -A SERVICES=(
  ["Prometheus"]="http://192.168.168.31:9090/-/healthy"
  ["Grafana"]="http://192.168.168.31:3000/api/health"
  ["Loki"]="http://192.168.168.31:3100/ready"
  ["Vault"]="http://192.168.168.31:8200/v1/sys/health"
  ["Caddy"]="https://192.168.168.31:9443/health"
)

for SERVICE in "${!SERVICES[@]}"; do
  URL="${SERVICES[$SERVICE]}"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "$URL" || echo "000")
  if [[ "$HTTP_CODE" =~ ^(200|429|503)$ ]]; then
    echo "✅ $SERVICE ($HTTP_CODE)"
  else
    echo "❌ $SERVICE ($HTTP_CODE)"
  fi
done
```

**Deployment Completion Criteria**:
- [ ] 87/88 containers running and healthy
- [ ] PostgreSQL replication active and synced
- [ ] All monitoring endpoints responsive
- [ ] Zero containers with exit code > 0 (except graceful shutdowns)
- [ ] Network connectivity between hosts verified
- [ ] No error messages in docker-compose logs

---

## Part 3: Post-Deployment Verification (T+30 min to T+24 hours)

### 3.1 Hour 1 Post-Deployment

**Database Integrity Check**:
```bash
# Verify database integrity
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres << 'SQL'
  -- Check for table locks or issues
  SELECT * FROM pg_stat_activity WHERE query NOT LIKE '%autovacuum%' AND state != 'idle';
  
  -- Verify no replication lag
  SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT AS replication_lag_sec;
  
  -- Check connection count
  SELECT usename, count(*) FROM pg_stat_activity GROUP BY usename;
SQL
"
```

**Application Health**:
```bash
# Verify business logic services responding
for SERVICE in multimodal-ai edge-agent agent-runtime execution-scheduler reputation-engine; do
  PORT=$(grep -A 2 "\"$SERVICE\"" docker-compose.enterprise.yml | grep "ports" | grep -oP '(?<=:)\d+' | head -1)
  CONTAINER="code-server-$SERVICE"
  HEALTH=$(ssh akushnir@192.168.168.31 "docker exec $CONTAINER curl -s http://localhost:$PORT/health 2>/dev/null | jq -r '.status // \"unknown\"' 2>/dev/null || echo 'error'")
  echo "$SERVICE: $HEALTH"
done
```

### 3.2 Hours 2-4 Post-Deployment

**Monitoring Metrics Review**:
```bash
# Access Grafana dashboards and review:
# 1. Container Resources (CPU, Memory, Disk)
# 2. Network I/O
# 3. Database Connections
# 4. API Response Times
# 5. Error Rates
# 6. Disk Free Space

# Command-line verification:
ssh akushnir@192.168.168.31 "
echo '=== SYSTEM RESOURCES ==='
free -h | grep Mem
df -h / | tail -1
docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}' | head -20
"
```

### 3.3 Daily Post-Deployment (Days 2-7)

**Daily Checklist**:
- [ ] Review error logs (Loki): `{job="docker"}` and filter for errors
- [ ] Verify PostgreSQL replication lag < 5 seconds
- [ ] Confirm container restart count = 0 (except planned restarts)
- [ ] Verify backup job completed successfully
- [ ] Check disk space on both hosts > 20% free
- [ ] Verify no SELinux/AppArmor denials
- [ ] Review any alerts triggered (AlertManager UI)
- [ ] Verify failover test successful (if scheduled)

---

## Part 4: Continuous Health Monitoring

### 4.1 Automated Health Check Script

Create `/home/akushnir/code-server/health-check.sh`:

```bash
#!/bin/bash
set -e

TIMESTAMP=$(date -Iseconds)
PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"
LOG_FILE="/tmp/health-check-$TIMESTAMP.log"

echo "=== HEALTH CHECK $TIMESTAMP ===" | tee $LOG_FILE

# Container counts
for HOST in $PRIMARY $REPLICA; do
  TOTAL=$(ssh -o ConnectTimeout=3 akushnir@$HOST "docker ps -q | wc -l" 2>/dev/null || echo "0")
  HEALTHY=$(ssh -o ConnectTimeout=3 akushnir@$HOST "docker ps --format '{{.Status}}' | grep -c Up" 2>/dev/null || echo "0")
  echo "[$HOST] Containers: $HEALTHY/$TOTAL" | tee -a $LOG_FILE
done

# PostgreSQL replication lag
REPL_LAG=$(ssh akushnir@$PRIMARY "
docker exec code-server-postgres psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT;' 2>/dev/null | tail -1
" || echo "error")
echo "[PostgreSQL] Replication Lag: ${REPL_LAG}s" | tee -a $LOG_FILE

# Disk usage
for HOST in $PRIMARY $REPLICA; do
  DISK=$(ssh -o ConnectTimeout=3 akushnir@$HOST "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null || echo "unknown")
  echo "[$HOST] Disk Usage: $DISK" | tee -a $LOG_FILE
done

echo "✅ Health check complete" | tee -a $LOG_FILE
```

Run via cron: `*/5 * * * * /home/akushnir/code-server/health-check.sh`

### 4.2 Critical Alerts

**Configure AlertManager** to notify on:
1. Container exit (exit code != 0)
2. Replication lag > 30 seconds
3. Disk usage > 85%
4. Memory usage > 90%
5. CPU usage > 95%
6. PostgreSQL down (PING fails)
7. Redis down (PING fails)
8. Network latency > 50ms between hosts

### 4.3 Weekly Verification Tasks

- [ ] Failover drill (promote replica, verify services, failback)
- [ ] Backup verification (restore from backup to test environment)
- [ ] Security scan (check for exposed credentials, updated CVEs)
- [ ] Performance review (identify bottlenecks, optimization opportunities)
- [ ] Team training (ensure new team members familiar with procedures)

---

## Part 5: Troubleshooting During Deployment

### 5.1 Container Fails to Start

**Symptoms**: Container created but not running (Exit Code != 0)

**Investigation**:
```bash
# Check logs
docker logs code-server-<service-name> --tail 100

# Check constraints (CPU, memory)
docker inspect code-server-<service-name> | jq '.HostConfig | {CpuQuota, MemoryLimit}'

# Check dependencies (linked containers, volumes)
docker ps -a --filter name=<service-name>
```

**Resolution**:
- Review environment variables in `docker-compose.enterprise.yml`
- Verify volume mounts exist and have correct permissions
- Check port conflicts: `lsof -i :PORT` or `netstat -tlnp | grep PORT`
- Increase resource limits if OOMKilled

### 5.2 Replication Not Active

**Symptoms**: `pg_is_in_recovery() = FALSE` on replica

**Investigation**:
```bash
# Check standby.signal file
docker exec code-server-postgres ls -la /var/lib/postgresql/data/standby.signal

# Check PostgreSQL logs
docker logs code-server-postgres | grep -i "standby\|recovery\|wal"

# Check primary connectivity
docker exec code-server-postgres psql -U replication -h 192.168.168.31 -c 'SELECT 1'
```

**Resolution**:
- Recreate standby.signal: `docker exec code-server-postgres touch /var/lib/postgresql/data/standby.signal`
- Restart PostgreSQL container: `docker restart code-server-postgres`
- Verify replication user credentials match in `docker-compose.enterprise.yml`

### 5.3 High Latency Between Hosts

**Symptoms**: `replication_lag > 5 seconds`

**Investigation**:
```bash
# Check network round-trip time
ping -c 10 -w 3 192.168.168.42 | grep avg

# Check network interface stats
ethtool -S eth0 | grep -E 'rx_errors|tx_errors'

# Check for packet loss in iptables/firewall
iptables -L -n -v | grep DROP
```

**Resolution**:
- Contact infrastructure team to investigate network
- Temporarily reduce `max_wal_senders` if excessive I/O
- Check for other high-traffic processes using network

### 5.4 Disk Space Critical

**Symptoms**: Containers fail with "No space left on device"

**Investigation**:
```bash
# Find large files/directories
du -sh /* | sort -rh | head -10
du -sh /var/lib/docker/*/

# Check inode usage
df -i /
```

**Resolution**:
- Clean Docker images: `docker image prune -a --force`
- Clean logs: `docker container prune -f`
- Rotate PostgreSQL WAL archives (if not needed): `docker exec code-server-postgres pg_archivecleanup ...`

---

## Part 6: Deployment Rollback Procedures

### 6.1 Quick Rollback (< 15 min)

**Applicable if**: Deployment fails within first 15 minutes

**Steps**:
```bash
# On both hosts, shut down containers
ssh akushnir@192.168.168.31 'docker-compose -f ~/code-server-enterprise/docker-compose.enterprise.yml down'
ssh akushnir@192.168.168.42 'docker-compose -f ~/code-server-enterprise/docker-compose.enterprise.yml down'

# Revert git changes (if code was modified)
git revert HEAD  # or git reset --hard <previous-commit>

# Restart with previous version
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose -f docker-compose.enterprise.yml up -d'
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose -f docker-compose.enterprise.yml up -d'

# Verify rollback
sleep 10
# Run health checks from Part 4.1
```

### 6.2 Partial Rollback (15-60 min)

**Applicable if**: Specific service failed, others are running

**Steps**:
```bash
# Rollback individual service
docker-compose -f docker-compose.enterprise.yml up -d --no-deps code-server-<service-name>

# Verify service came up
docker logs code-server-<service-name> --tail 50
```

### 6.3 Database Rollback (if needed)

**DO NOT RUN unless specifically instructed**

```bash
# If data was corrupted during deployment
# 1. Restore from backup (see OPERATIONS_HANDOFF_GUIDE.md)
# 2. Test restoration on replica first
# 3. Promote replica if primary is damaged
```

---

## Deployment Sign-Off Template

```
DEPLOYMENT VALIDATION SIGN-OFF
Date: _______________
Deployment Window: T-0 to T+30 min
Total Containers Started: 87/88 (or specify count)

Phase Completion:
[X] Pre-Deployment (T-7 days) - All prerequisites met
[X] Deployment Initiation (T+0 to T+5 min) - Docker Compose started
[X] Deployment Progress (T+5 to T+20 min) - Containers coming online
[X] Deployment Verification (T+20 to T+30 min) - All services verified
[X] Post-Deployment (T+30 min to T+24h) - Continuous monitoring active

Critical Metrics:
- Containers Running: 87/88 ✅ (or ❌ with note)
- PostgreSQL Replication: ACTIVE ✅ (or ❌ with note)
- Disk Space Primary: >20GB ✅
- Disk Space Replica: >20GB ✅
- Network Latency: <10ms ✅
- CPU Usage: <80% ✅
- Memory Usage: <80% ✅

Issues Encountered: (describe any)
_______________________________________________________________________

Resolution Applied: (describe any)
_______________________________________________________________________

Sign-Off:
Deployment Manager: _____________________ Date: __________
Operations Manager: _____________________ Date: __________
Engineering Lead: _____________________ Date: __________

Notes:
_______________________________________________________________________
```

---

## Quick Reference: Command Index

| Task | Command |
|------|---------|
| Check container count | `docker ps -q \| wc -l` |
| Check healthy containers | `docker ps --format '{{.Status}}' \| grep -c Up` |
| View PostgreSQL replication | `docker exec code-server-postgres psql -U postgres -c 'SELECT * FROM pg_stat_replication;'` |
| Check replication lag | `SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT;` |
| Monitor container startup | `watch -n 5 'docker ps --format="table {{.Names}}\t{{.Status}}"'` |
| View Docker Compose logs | `docker-compose logs -f code-server-<service>` |
| Emergency replication restart | `docker restart code-server-postgres` |
| Check network connectivity | `nc -zv -w 3 192.168.168.42 5432` |
| View disk usage | `df -h /` |
| View memory usage | `free -h` |
| Restart all containers | `docker-compose -f docker-compose.enterprise.yml down && docker-compose -f docker-compose.enterprise.yml up -d` |

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | April 29, 2026 | Initial deployment validation procedures |

---

**Next Steps for Operations Team**:
1. Review all procedures in this document
2. Walk through procedures in test environment (if available)
3. Prepare deployment log template (sample provided above)
4. Train all team members on deployment day activities
5. Schedule deployment window (recommend off-peak hours)
6. Set up monitoring dashboards for real-time visibility

**Support Contact**:
- Deployment Issues: [Engineering Lead Contact]
- Database Issues: [Database Administrator Contact]
- Network Issues: [Network Administrator Contact]
- Infrastructure Issues: [Infrastructure Administrator Contact]
