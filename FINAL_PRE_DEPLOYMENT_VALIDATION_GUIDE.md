# Final Pre-Deployment Validation Guide

**Date:** April 30, 2026  
**Deployment:** May 1, 2026 09:00 UTC  
**Status:** 24 Hours Before Deployment  

---

## Quick Start

### Run This First (5 minutes)
```bash
# On primary server (192.168.168.31)
cd /home/ubuntu/code-server
bash final-infrastructure-validation.sh

# Review report
cat infrastructure-validation-report-*.txt
```

Expected output:
- ✅ All core checks passing (PostgreSQL, Redis, API, Monitoring)
- ✅ 87+ containers running
- ✅ Replication lag < 5 seconds
- ✅ Disk usage < 80%

---

## 10-Point Pre-Deployment Checklist

### ✅ 1. Connectivity Tests
**Run:** `ssh ubuntu@192.168.168.31 "echo OK"`

**Expected:**
- SSH to primary responds
- SSH to replica responds
- Cluster VIP reachable
- No timeout errors

**Troubleshoot if fails:**
```bash
# Check network connectivity
ping 192.168.168.31
ping 192.168.168.42
ping 192.168.168.250

# Check SSH keys
ssh-keygen -R 192.168.168.31
ssh ubuntu@192.168.168.31 -v
```

---

### ✅ 2. Container Status (87+ total)
**Run:** `docker-compose ps | grep Up | wc -l`

**Expected:**
- Primary: ≥ 43 containers Up
- Replica: ≥ 44 containers Up
- Total: ≥ 87 containers Up

**Troubleshoot if < 87:**
```bash
# List all containers
docker-compose ps

# Check for stuck/exited containers
docker-compose ps | grep -E "Exit|Exited"

# Restart all services
docker-compose down
docker-compose up -d

# Wait 2 minutes, then recount
sleep 120
docker-compose ps | grep -c Up
```

---

### ✅ 3. PostgreSQL Replication
**Run:** `docker exec code-server-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"`

**Expected:**
- Primary: `f` (false - not in recovery)
- Replica: `t` (true - in recovery mode)

**Verify replication slots on primary:**
```bash
docker exec code-server-postgres psql -U postgres -c \
  "SELECT slot_name, active FROM pg_replication_slots;"
# Should show: code-server-slot | t
```

**Troubleshoot if replica not in recovery:**
```bash
# On replica, run the replication fix
cd /home/ubuntu/code-server
bash orchestrate-postgresql-replication-fix.sh

# This takes ~20 minutes. DO NOT PROCEED without this!
```

---

### ✅ 4. Replication Lag Check
**Run on Primary:**
```bash
docker exec code-server-postgres psql -U postgres -c \
  "SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp())) \
   FROM pg_stat_replication;"
```

**Expected:**
- < 5 seconds: ✅ Good (proceed)
- 5-30 seconds: ⚠️ Monitor (acceptable)
- > 30 seconds: ❌ Critical (investigate)

**Troubleshoot if high lag:**
```bash
# Check replica logs
docker logs code-server-postgres --tail=50 | grep -i error

# Check network latency
ssh ubuntu@192.168.168.42 "ping -c 1 192.168.168.31"

# Check replica CPU/memory
ssh ubuntu@192.168.168.42 "top -b -n 1 | head -20"
```

---

### ✅ 5. Redis Connectivity
**Run:** `docker-compose exec redis redis-cli PING`

**Expected:**
- Primary: `PONG`
- Replica: `PONG`

**Check Redis memory:**
```bash
docker-compose exec redis redis-cli INFO memory | grep used_memory_human
# Should be reasonable (< 2GB for this deployment)
```

**Troubleshoot if not responding:**
```bash
# Check if Redis container is running
docker-compose ps redis

# Restart Redis
docker-compose restart redis

# Wait 10 seconds
sleep 10

# Test again
docker-compose exec redis redis-cli PING
```

---

### ✅ 6. API Server Health
**Run:** `curl http://localhost:8000/health`

**Expected:**
- HTTP 200 response
- Body contains: `{"status": "healthy"}`

**Test actual API call:**
```bash
curl http://localhost:8000/api/v1/status | jq '.'
# Should return API version and status
```

**Troubleshoot if unhealthy:**
```bash
# Check logs
docker logs api-server --tail=50

# Check dependencies
docker-compose ps postgres redis

# Verify database connectivity
docker exec api-server curl http://postgres:5432/ 2>&1 | head

# Restart API
docker-compose restart api-server
sleep 10
curl http://localhost:8000/health
```

---

### ✅ 7. Monitoring System Active
**Run:** `curl http://localhost:9090/api/v1/targets`

**Expected:**
- Returns JSON with targets
- Multiple targets showing `"health":"up"`
- No excessively high latency

**Check AlertManager:**
```bash
curl http://localhost:9093

# Should return Alertmanager UI
```

**Check Grafana:**
```bash
curl http://localhost:3000

# Should contain "Grafana" in response
```

**Troubleshoot if Prometheus not scraping:**
```bash
# Check prometheus logs
docker logs prometheus --tail=50

# Verify prometheus config
docker exec prometheus cat /etc/prometheus/prometheus.yml | grep targets

# Restart prometheus
docker-compose restart prometheus
```

---

### ✅ 8. Backup Readiness
**Run:** `bash verify-backups.sh`

**Expected:**
- ✅ PostgreSQL backups found (< 24h)
- ✅ Redis snapshots found (< 24h)
- ✅ Available storage > 20%

**Check backup scripts are scheduled:**
```bash
# List cron jobs
crontab -l

# Should include:
# 0 2 * * * cd /home/ubuntu/code-server && ./backup-postgresql.sh
# 0 * * * * cd /home/ubuntu/code-server && ./backup-redis.sh
```

**Troubleshoot if no recent backups:**
```bash
# Create backup directories if missing
sudo mkdir -p /backups/postgresql /backups/redis
sudo chown 999:999 /backups/postgresql /backups/redis

# Run backups manually
./backup-postgresql.sh
./backup-redis.sh

# Verify
bash verify-backups.sh
```

---

### ✅ 9. Disk Space Check
**Run:** `df -h /`

**Expected:**
- Root disk usage: < 80%
- Available space: > 10GB

**Check backup storage:**
```bash
du -sh /backups/
# Should be reasonable (< 50GB)
```

**Troubleshoot if low disk space:**
```bash
# Find largest files
du -sh /* | sort -rh | head -10

# Clean docker images if needed
docker image prune -a

# Clean logs if needed
docker volume prune
```

---

### ✅ 10. Final System Load
**Run:** `uptime`

**Expected:**
- Load average: < 4.0
- CPU not maxed out
- Memory > 20% available

**Check container resource usage:**
```bash
docker stats --no-stream | head -20

# Look for:
# - No container using > 90% CPU
# - No container using > 80% memory
# - No container restarting frequently
```

**Troubleshoot if high load:**
```bash
# Check for hung processes
docker ps -a | grep -E "Restarting|Exit"

# Identify high-CPU containers
docker stats --no-stream | sort -k3 -rn | head

# Restart if needed
docker-compose restart <service>
```

---

## Pre-Deployment Verification Execution

### Timing: Run 24 Hours Before (April 30, 18:00 UTC)

```bash
# SSH to primary
ssh ubuntu@192.168.168.31

# Run full validation
cd /home/ubuntu/code-server
bash final-infrastructure-validation.sh verbose

# Expected: All green, 0 failures
# Exit code: 0 = ready, 1 = issues found

# Review detailed report
cat infrastructure-validation-report-*.txt
```

### Timing: Run 1 Hour Before (May 1, 08:00 UTC)

```bash
# Quick re-check before PostgreSQL replication fix
# (Run same validation script)
bash final-infrastructure-validation.sh

# Expected: Same results as 24h check
# Proceed if all checks still passing
```

### Timing: After Replication Fix (May 1, 08:30 UTC)

```bash
# Quick validation after orchestrate-postgresql-replication-fix.sh completes
bash final-infrastructure-validation.sh

# Expected: PostgreSQL replication now ACTIVE
# Replication lag < 5 seconds
# All other checks still passing

# If any failures: DO NOT PROCEED, escalate to L2
```

---

## Quick Diagnostics Reference

### If Container Count Wrong
```bash
# Count running containers
docker-compose ps | grep -c " Up "

# List problem containers
docker-compose ps | grep -v " Up "

# Check docker daemon
docker info | grep "Containers:"
```

### If PostgreSQL Replication Fails
```bash
# Check replication status
psql -U postgres -c "SELECT * FROM pg_stat_replication;"
psql -U postgres -c "SELECT pg_is_in_recovery();"

# Check standby signal
docker exec code-server-postgres ls -la /var/lib/postgresql/data/standby.signal

# Check ownership
docker exec code-server-postgres stat /var/lib/postgresql/data/standby.signal
```

### If API Not Responding
```bash
# Check if API container running
docker ps | grep api-server

# Check API logs
docker logs api-server --tail=100

# Test database from API container
docker exec api-server bash -c "psql -h postgres -U postgres -c 'SELECT 1;'"
```

### If Replication Lag High
```bash
# Check WAL sender on primary
psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"

# Check WAL receiver on replica
psql -U postgres -c "SELECT * FROM pg_stat_wal_receiver;"

# Check network latency
ssh ubuntu@192.168.168.42 "ping -c 10 192.168.168.31 | tail -3"
```

---

## Decision Tree: Ready for Deployment?

```
START: Run final-infrastructure-validation.sh
  |
  ├─ Failures = 0? → GO TO STEP 2
  │
  └─ Failures > 0? → STOP, Fix issues, Re-run validation
      |
      ├─ PostgreSQL replication issue? → Run orchestrate-postgresql-replication-fix.sh
      ├─ Container issue? → docker-compose restart <service>
      ├─ Network issue? → Check connectivity, verify IPs
      ├─ Disk issue? → Clean up files, extend storage
      └─ Other? → Check logs, escalate to L2

STEP 2: PostgreSQL Replication Active?
  |
  ├─ YES (pg_is_in_recovery = t)? → GO TO STEP 3
  │
  └─ NO? → Run replication fix, Re-run validation

STEP 3: All Backups Recent (< 24h)?
  |
  ├─ YES? → GO TO STEP 4
  │
  └─ NO? → Run backup scripts manually, Verify completion

STEP 4: Monitoring System Up?
  |
  ├─ YES (Prometheus, Grafana, AlertManager)? → GO TO STEP 5
  │
  └─ NO? → Check logs, Restart monitoring services

STEP 5: Team Assembled & Standing By?
  |
  ├─ YES? → READY FOR DEPLOYMENT ✅
  │
  └─ NO? → Wait for team, Proceed only when all present

DEPLOYMENT APPROVED: May 1, 09:00 UTC 🚀
```

---

## Rollback Decision Criteria

### DO NOT DEPLOY If:
- ❌ PostgreSQL replication not ACTIVE (pg_is_in_recovery ≠ t)
- ❌ More than 87 containers DOWN (< 87 total Up)
- ❌ API not responding (health check fails)
- ❌ Replication lag > 60 seconds
- ❌ Disk usage > 85%
- ❌ Monitoring system not operational
- ❌ Backup system not ready
- ❌ Team not assembled

### PROCEED WITH CAUTION If:
- ⚠️ Replication lag 30-60 seconds (monitor closely)
- ⚠️ 85-87 containers running (1-3 containers down, may restart)
- ⚠️ Disk usage 80-85% (proceed, but monitor)
- ⚠️ Any warning-level checks (escalate to L2 for approval)

### FULL GO AHEAD If:
- ✅ All validation checks passing
- ✅ PostgreSQL replication ACTIVE with < 5s lag
- ✅ 87+ containers running
- ✅ API responding
- ✅ Monitoring operational
- ✅ Backups recent and verified
- ✅ All team members present and ready

---

## Post-Deployment (First Hour)

After deployment starts, continue monitoring:

```bash
# Every 5 minutes for first 30 minutes
while true; do
  bash final-infrastructure-validation.sh
  sleep 300
done

# Check for any alerts
curl http://localhost:9090/api/v1/alerts

# Monitor replication lag
docker exec code-server-postgres psql -U postgres -c \
  "SELECT NOW(), pg_last_xact_replay_timestamp();"

# Monitor error rates
curl http://localhost:8000/api/v1/errors?interval=5m
```

---

## Success Criteria (Post-Deployment)

**First Hour:**
- ✅ No critical alerts firing
- ✅ API responding to requests
- ✅ Replication lag < 100ms
- ✅ Error rate < 1%

**First 24 Hours:**
- ✅ Uptime > 99.5%
- ✅ Error rate < 0.1%
- ✅ Response time P95 < 1 second
- ✅ Replication lag consistently < 100ms

---

**Remember:** Final validation script takes ~10-15 minutes to run. Plan accordingly!

