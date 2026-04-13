# LOCAL INCIDENT RESPONSE RUNBOOK
## Single-Host Emergency Recovery (192.168.168.31)

**Version:** 1.0 - Local Focus  
**Status:** ACTIVE  
**Target:** 192.168.168.31 (no cloud failover, local recovery only)  

---

## Quick Reference

### If Something IS Down
1. SSH: `ssh akushnir@192.168.168.31`
2. Check status: `docker-compose ps`
3. Find scenario below matching symptoms
4. Follow recovery steps
5. Verify: `docker-compose ps` all healthy

### Severity Classification (LOCAL)

| Level | Example | Action | SLA |
|-------|---------|--------|-----|
| **P1** | All users can't access Code-Server | Page on-call, restart service | < 5 min |
| **P2** | High error rate (>1%) or slow (<500ms p99) | Investigate + restart | < 15 min |
| **P3** | Single user affected or warning alerts | Log issue, investigate | < 4 hours |

---

## Immediate Response (First 5 Minutes)

```bash
# 1. SSH to host
ssh akushnir@192.168.168.31

# 2. Check everything
docker-compose ps

# Expected output:
# NAME                COMMAND                 STATUS
# caddy               "caddy run --config"    Up
# code-server         "/init"                 Up (healthy)
# postgres            "docker-entrypoint.s."  Up (healthy)
# redis               "redis-server"          Up (healthy)
# vault               "server"                Up
# ... (13 total)

# 3. Look for non-healthy status:
# - "Exited" = crashed
# - "Restarting" = restart loop
# - "unhealthy" = health check failed

# 4. Check logs for errors
docker-compose logs --tail=50 | grep -iE "error|exception|failed"

# 5. Determine priority
if [ "$(docker-compose ps code-server | grep -c healthy)" -eq 0 ]; then
  echo "P1: Code-Server DOWN - CRITICAL"
else
  echo "P2 or lower - investigate"
fi
```

---

## Common Scenarios & Recovery

### Scenario 1: Code-Server Down / Can't Connect

**Symptoms:**
- Users can't reach https://workspace.local
- `curl http://localhost:7680/` fails
- Browser shows "Connection refused"

**Diagnosis:**
```bash
# Check if container is running
docker-compose ps code-server
# If "Exited" or state is not "Up": container crashed

# Check logs
docker-compose logs code-server | tail -50
# Look for: OOMKilled, out of memory, panic, crash

# Check if it's a port binding issue
ss -tlnp | grep 7680  # should show caddy listening
```

**Recovery:**
```bash
# Option 1: Simple restart
docker-compose restart code-server
sleep 5
docker-compose ps code-server  # verify it's healthy

# Option 2: If restart fails, check resource availability
docker stats --no-stream code-server
# MEMORY% > 90%? = out of memory issue
# CPU% > 100%? = CPU bound

# Option 3: If OOM, restart all
docker-compose down
sleep 10
docker-compose up -d
sleep 30
docker-compose ps  # all should be healthy

# Option 4: If still failing, check if disk is full
df -h /data  # if > 90% used: delete old data
du -sh /data/* | sort -h  # check what's big
```

**SLA:** < 5 minutes recovery

---

### Scenario 2: High Error Rate / 500 Errors

**Symptoms:**
- Alert: "HighErrorRate"
- Users report "Internal Server Error"
- Logs show >1% error rate

**Diagnosis:**
```bash
# Which service is erroring?
docker-compose logs --tail=100 | grep -iE "error|exception" | head -20

# Check specific service
for svc in code-server postgres redis ollama; do
  echo "=== $svc ==="
  docker-compose logs $svc --tail=20 | grep -iE "error|failed"
done

# Database connection issue?
docker-compose logs code-server | grep -iE "postgres|database|connection"

# Cache issue?
docker-compose logs code-server | grep -iE "redis|cache"
```

**Recovery:**
```bash
# If database error:
docker-compose restart postgres
sleep 10
docker-compose ps postgres  # verify healthy

# If redis error:
docker-compose restart redis
sleep 5

# If code-server error (application bug):
docker-compose restart code-server

# If multiple services: restart all
docker-compose down
sleep 10
docker-compose up -d
sleep 30

# Monitor error rate recovery
watch -n 5 'curl -s "http://localhost:9090/api/v1/query?query=rate(errors_total[5m])" | jq ".data.result[].value[1]"'
# Should see < 1% after recovery
```

**SLA:** < 10 minutes investigation + recovery

---

### Scenario 3: High Latency / Slow Responses

**Symptoms:**
- p99 latency > 500ms
- Users report "slow to load"
- Alert: "HighLatency"

**Diagnosis:**
```bash
# Check if it's Ollama (expected to be slow for LLM inference)
docker-compose logs code-server | grep ollama | tail -5
# If user just ran LLM: expected, no action needed

# Check resource usage
docker stats --no-stream

# If CPU > 80%:
echo "CPU-bound, may be inference"

# If MEMORY% > 80%:
echo "Memory constrained"

# If disk I/O high:
iostat -x 1 2 | grep -E "r/s|w/s|%util"

# Check database query performance
docker-compose exec postgres \
  psql -c "SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 3"
```

**Recovery:**
```bash
# For Ollama inference latency (expected):
# No recovery needed, document as expected behavior

# For database slowness:
# Check if connection pool exhausted
docker-compose exec postgres \
  psql -c "SELECT count(*) FROM pg_stat_activity WHERE state='active'"
# If > 20 connections: might be pool exhausted

# Try restart:
docker-compose restart code-server

# Or increase pool size in .env and restart

# For memory pressure:
# Check what's using memory
docker stats --all --no-stream | sort -k4 -h | tail -5

# If specific container using > 80%:
docker-compose restart <container>
```

**SLA:** < 10 minutes (may be expected behavior)

---

### Scenario 4: Database Connection Issues

**Symptoms:**
- Error: "connection pool is full" or "timeout acquiring connection"
- All database queries failing
- Code-Server can't load config

**Diagnosis:**
```bash
# Check PostgreSQL status
docker-compose ps postgres
# If not "healthy": restart

# Check active connections
docker-compose exec postgres \
  psql -c "SELECT count(*) as connections FROM pg_stat_activity"

# Check max connections setting
docker-compose exec postgres \
  psql -c "SHOW max_connections"

# See what's holding connections
docker-compose exec postgres \
  psql -c "SELECT application_name, count(*) FROM pg_stat_activity GROUP BY application_name"
```

**Recovery:**
```bash
# Kill idle connections
docker-compose exec postgres \
  psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND query_start < now() - interval '10 minutes'"

# Restart code-server (close all connections)
docker-compose restart code-server
sleep 10

# If still failing: restart PostgreSQL
docker-compose restart postgres
sleep 10
docker-compose exec postgres pg_isready  # verify
```

**SLA:** < 5 minutes

---

### Scenario 5: Disk Full

**Symptoms:**
- Error: "No space left on device"
- Alert: "DiskSpaceCritical"
- Docker writes failing
- Service restarts looping

**Diagnosis:**
```bash
# Check disk usage
df -h /data

# What's using space?
du -sh /data/* | sort -h | tail -10

# Usually: PostgreSQL or Elasticsearch
# Check size of each:
du -sh /data/postgres
du -sh /data/elasticsearch
du -sh /data/ollama  # models can be huge
```

**Recovery - FAST (10 minutes):**

```bash
# Option 1: Delete old logs (immediate)
find /data/elasticsearch -name "*.log" -mtime +30 -delete

# Option 2: Clear old Elasticsearch indices
curl -X DELETE "localhost:9200/logs-*-2026-01-*"  # delete old month
curl -X DELETE "localhost:9200/logs-*-2026-02-*"

# Option 3: PostgreSQL VACUUM (free space)
docker-compose exec postgres \
  psql -c "VACUUM FULL ANALYZE"

# Option 4: Delete old Ollama models (if necessary)
docker-compose exec ollama ollama rm <model-name>

# Verify space freed
df -h /data

# If still > 90%: PANIC, need manual cleanup
```

**Recovery - PROPER (later):**
```bash
# 1. Plan to expand storage
# Add disk volume to host (VM provisioning)
# Or add secondary storage mount

# 2. Reduce retention policies
# Edit .env, change:
# LOG_RETENTION_DAYS from 365 to 90
# Or from 730 to 90

# 3. Enable auto-cleanup cron
crontab -e
# Add: 0 2 * * * find /data -name "*.log" -mtime +90 -delete
# Add: 0 3 * * * curl -X DELETE "localhost:9200/logs-*-$(date -d '60 days ago' +%Y-%m-*)/?allow_no_indices=true"
```

**SLA:** < 15 minutes (involves manual deletion)

---

### Scenario 6: Vault Issues / Secrets Not Loading

**Symptoms:**
- OAuth2-Proxy can't start (missing secrets)
- Code-Server missing API keys
- Error: "secret not found" or "vault is sealed"

**Diagnosis:**
```bash
# Check Vault status
docker-compose ps vault
docker-compose logs vault | tail -20

# Check if Vault is sealed
docker-compose exec vault vault status | grep "Sealed"
# Should show: Sealed       false

# Check if secrets exist
docker-compose exec vault vault kv list secret/production/

# Check if oauth2-proxy can read secrets
docker-compose logs oauth2-proxy | grep -iE "vault|secret|error"
```

**Recovery:**
```bash
# If Vault is sealed: UNSEAL IT
docker-compose exec vault vault operator unseal <key-1>
docker-compose exec vault vault operator unseal <key-2>
docker-compose exec vault vault operator unseal <key-3>
# Use 3 of 5 keys stored in secure location

# If secrets missing: reload them
docker-compose exec vault \
  vault kv put secret/production/google/oauth \
    client-id='your-value' \
    client-secret='your-value'

# Restart services that need the secrets
docker-compose restart oauth2-proxy
docker-compose restart code-server
```

**SLA:** < 10 minutes (if keys available)

---

### Scenario 7: Service Restart Loop

**Symptoms:**
- Docker ps shows "Restarting" status
- Service restarts every 10-30 seconds
- Logs show crash immediately on startup

**Diagnosis:**
```bash
# Check logs for crash reason
docker-compose logs <service-name> | tail -50

# Common causes:
# 1. Missing dependency (port already in use)
ss -tlnp | grep <port>  # check if port in use

# 2. Bad configuration
# Check if config file is valid

# 3. Missing secret/permission
# Check if service can read secrets from Vault

# 4. Out of resources
# Check CPU/memory: docker stats
```

**Recovery:**
```bash
# Stop the crashing service
docker-compose stop <service-name>

# Check and fix config
# - Fix port binding
# - Fix secret references
# - Fix permissions

# Or restart from clean state
docker-compose down <service-name>
docker volume prune -f  # CAREFUL: deletes unused volumes
docker-compose up -d <service-name>

# Monitor startup
docker-compose logs -f <service-name> | head -50
```

**SLA:** < 10 minutes

---

## Self-Healing Procedures

### Auto-Restart on Failure

Docker Compose has restart policies configured. Services auto-restart on failure:

```yaml
# In docker-compose.yml:
services:
  code-server:
    restart_policy:
      condition: on-failure
      delay: 5s
      max_attempts: 3
```

This means:
- Service crashes → automatic restart within 5 seconds
- If crashes again → restart up to 3 times
- If still failing after 3 restarts → stay stopped (need manual intervention)

### Check Restart Count

```bash
docker-compose ps | grep -E "code-server|postgres|redis"
# If you see "(3)" or higher: too many restarts, investigate

# Or check detailed info:
docker inspect code-server | jq '.RestartCount'  # should be 0
```

---

## Post-Incident Checklist

After resolving any incident:

- [ ] Document what happened
- [ ] Note exact time duration (MTTR)
- [ ] List recovery steps that worked
- [ ] Identify if this can be prevented differently
- [ ] Update this runbook with new learnings

---

## Emergency Contacts (Local)

- **DevOps Lead:** [akushnir] (192.168.168.31 access)
- **On-Call Engineer:** [rotate weekly]
- **Database Admin:** [optional, if separate]
- **Status Page:** http://workspace.local/status (if available)

---

## Tools & Commands (Always Useful)

```bash
# Health check all services
docker-compose ps

# View all logs (last 100 lines)
docker-compose logs --tail=100

# Follow logs real-time (specific service)
docker-compose logs -f code-server

# Execute command in container
docker-compose exec postgres psql -c "SELECT COUNT(*) FROM pg_stat_activity"

# Restart all services
docker-compose down && sleep 10 && docker-compose up -d

# Check resource usage
docker stats --no-stream

# Inspect container
docker inspect <container-name>

# Get container IP
docker-compose exec code-server hostname -I

# Health check endpoint (if Caddy running)
curl -v http://localhost/health
```

---

## When to Escalate

**Escalate to team immediately if:**
- [ ] Both PostgreSQL and Redis down (data layer failure)
- [ ] Host storage full (>95%)
- [ ] Host network unreachable (SSH fails)
- [ ] Multiple services in restart loop
- [ ] Can't recover in < 30 minutes
- [ ] Data corruption suspected

**Escalation procedure:**
1. Stop trying
2. Document current state: `docker-compose ps > /tmp/incident-state.txt`
3. Save logs: `docker-compose logs > /tmp/incident-logs.txt`
4. Call DevOps lead
5. Prepare for manual recovery or data restore

---

## Disaster Recovery Fallback

If nothing works:

```bash
# NUCLEAR OPTION (last resort)
cd ~/code-server-enterprise

# Backup current state (in case we need to debug)
mkdir -p /tmp/incident-backup-$(date +%s)
docker-compose logs > /tmp/incident-backup-*/logs.txt

# Full restart
docker-compose down
sleep 30
docker-compose up -d
sleep 60
docker-compose ps

# Check health
curl -v http://localhost/health

# If still failing: restore from backup
# See LOCAL-DEPLOYMENT-CHECKLIST.md Phase 4: Restore Validation
```

---

## Prevention Tips

To avoid common incidents:

1. **Monitor disk space daily**
   - Set alert when > 80% used
   - Auto-cleanup old logs weekly

2. **Monitor memory usage**
   - Alert if service > 80% memory
   - Restart service if memory leak detected

3. **Test backup/restore monthly**
   - Know that recovery works
   - Can find issues before disaster

4. **Review logs weekly**
   - Spot warnings before they become errors
   - Identify patterns

5. **Update health checks**
   - Configure meaningful health endpoints
   - Detect failures faster

---

**Status:** READY FOR LOCAL OPERATIONS ✅

