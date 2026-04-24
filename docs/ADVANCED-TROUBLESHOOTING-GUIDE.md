# Advanced Troubleshooting & Incident Response Guide

**Purpose**: Comprehensive troubleshooting and incident response procedures for production cluster  
**Audience**: Operations Engineers, SRE, DevOps, On-Call Engineers  
**Last Updated**: April 24, 2026  
**Status**: Production-Ready

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Service-Specific Issues](#service-specific-issues)
3. [Cluster Health Troubleshooting](#cluster-health-troubleshooting)
4. [Database Issues](#database-issues)
5. [Redis Cache Issues](#redis-cache-issues)
6. [Network & Load Balancing](#network--load-balancing)
7. [Certificate & TLS Issues](#certificate--tls-issues)
8. [Incident Response Playbooks](#incident-response-playbooks)
9. [Escalation Procedures](#escalation-procedures)

---

## Quick Diagnostics

### One-Minute Health Check

Run this to quickly assess cluster health:

```bash
#!/bin/bash
# Quick 1-minute cluster health check

echo "=== CLUSTER HEALTH CHECK ==="

# 1. Replica availability
for replica in 192.168.168.31 192.168.168.42; do
  if ssh -o ConnectTimeout=3 akushnir@$replica 'echo OK' &>/dev/null; then
    echo "✅ Replica $replica: SSH reachable"
  else
    echo "❌ Replica $replica: SSH UNREACHABLE"
  fi
done

# 2. Service availability
for replica in 192.168.168.31 192.168.168.42; do
  if curl -s -k https://192.168.168.31:443/health &>/dev/null; then
    echo "✅ Replica $replica: HTTPS health responding"
  else
    echo "⚠️  Replica $replica: HTTPS health check failed"
  fi
done

# 3. Load balancer status
if curl -s http://192.168.168.31:8080/health &>/dev/null; then
  echo "✅ Load balancer: Operational"
else
  echo "❌ Load balancer: NOT responding"
fi

# 4. Database replication
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec -T postgres-primary psql -U postgres -c \
  "SELECT slot_name, active FROM pg_replication_slots;" 2>/dev/null' | grep -q active && \
  echo "✅ Database replication: Active" || \
  echo "⚠️  Database replication: Check manually"

echo "=== END HEALTH CHECK ==="
```

**Run Time**: 30-60 seconds  
**Output**: Quick yes/no on critical systems

---

## Service-Specific Issues

### code-server Not Starting

**Symptoms**:
- Container status: `Exited (1)` or `Restarting`
- curl http://localhost:8443 times out
- Error logs: "Failed to bind port 8443"

**Diagnosis**:

```bash
# 1. Check container status
docker-compose ps code-server

# 2. View error logs
docker-compose logs code-server --tail 100 | grep -i error

# 3. Check port availability
netstat -tlnp | grep 8443

# 4. Verify configuration
docker-compose config | grep -A 20 "code-server:"
```

**Solutions**:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Port 8443 already in use | Another service/process bound to port | `lsof -i :8443` then kill process |
| Out of memory | Container memory limit exceeded | Increase `mem_limit` in docker-compose |
| Volume mount failed | NAS unmounted or inaccessible | `mount \| grep /mnt/nas` and remount if needed |
| Corrupt configuration | Config file parsing error | Restore from backup: `git checkout code-server`|

### code-server High Memory Usage

**Symptoms**:
- Memory > 85% of limit
- Performance degradation
- Potential OOMKill

**Diagnosis**:

```bash
# 1. Check container memory usage
docker stats code-server --no-stream

# 2. Check process-level memory
docker-compose exec code-server ps aux --sort=-%mem | head -5

# 3. Check specific process consuming memory
docker-compose exec code-server top -b -n 1 | head -20
```

**Solutions**:

```bash
# 1. Check for memory leak (restart test)
docker-compose restart code-server
docker stats code-server --no-stream
# If memory usage after restart is < 30%, it was a leak - resolved

# 2. If still high after restart, increase container limit
# Edit docker-compose.yml:
#   mem_limit: 4g  # Increase from 2g to 4g

# 3. Alternatively, identify memory-consuming process inside container
docker-compose exec code-server 'ps aux | sort -k 4 -rn | head -5'
# Then restart specific service or reload configuration
```

### Caddy/Reverse Proxy Not Working

**Symptoms**:
- curl http://localhost returns 502 Bad Gateway
- SSL certificate errors
- Redirect loops

**Diagnosis**:

```bash
# 1. Check Caddy status
docker-compose ps caddy

# 2. View Caddy logs
docker-compose logs caddy --tail 50

# 3. Validate Caddyfile syntax
docker-compose exec caddy caddy validate --config /etc/caddy/Caddyfile

# 4. Check upstream services
curl -I http://192.168.168.31:8443  # code-server
curl -I http://appsmith:80           # Appsmith
curl -I http://oauth2-proxy:4180     # OAuth2-proxy
```

**Solutions**:

| Issue | Fix |
|-------|-----|
| 502 Bad Gateway | Upstream service not responding - check `curl http://upstream:port` |
| SSL certificate error | Let's Encrypt rate limited (see #1694) or cert expired - check `openssl s_client` |
| Redirect loop | Check Caddyfile for circular routing rules |
| Slow response | Check upstream service performance (memory, CPU) |

---

## Cluster Health Troubleshooting

### Replica Not Responding

**Symptoms**:
- `ssh akushnir@192.168.168.31` times out
- Load balancer routing to only one replica
- Health check failing

**Diagnosis**:

```bash
# 1. Check network connectivity
ping 192.168.168.31  # Should respond

# 2. Check SSH port
timeout 3 bash -c 'echo > /dev/tcp/192.168.168.31/22' && echo "SSH port open" || echo "SSH port closed"

# 3. Check from working replica
ssh akushnir@192.168.168.42 'ping -c 2 192.168.168.31'

# 4. Check Docker daemon
ssh akushnir@192.168.168.31 'docker ps' 2>&1

# 5. Check disk space (common cause)
ssh akushnir@192.168.168.31 'df -h /' | tail -1
```

**Solutions**:

| Cause | Fix |
|-------|-----|
| Network disconnected | Check network switch/hardware, restart network interface |
| Docker daemon crashed | `ssh akushnir@192.168.168.31 'sudo systemctl restart docker'` |
| Disk full | Remove old Docker images/containers: `docker system prune -a` |
| SSH key issue | Verify SSH key in `~/.ssh/authorized_keys` on replica |
| OOM/System crash | SSH in and check: `free -h`, `dmesg \| tail -20` |

### Service Count Mismatch

**Symptoms**:
- Replica 1: 12 running services
- Replica 2: 10 running services
- Inconsistent behavior

**Diagnosis**:

```bash
# 1. Compare service counts
echo "Replica 31:" ; ssh akushnir@192.168.168.31 'docker compose ps -q | wc -l'
echo "Replica 42:" ; ssh akushnir@192.168.168.42 'docker compose ps -q | wc -l'

# 2. Compare which services differ
echo "=== R31 ===" ; ssh akushnir@192.168.168.31 'docker compose ps --format "table {{.Service}}"'
echo "=== R42 ===" ; ssh akushnir@192.168.168.42 'docker compose ps --format "table {{.Service}}"'

# 3. Check git diff (possible config drift)
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git diff HEAD docker-compose.yml'
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git diff HEAD docker-compose.yml'
```

**Solutions**:

```bash
# 1. Sync both replicas to same git commit
for replica in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$replica 'cd code-server-enterprise && \
    git fetch origin main && \
    git checkout origin/main && \
    docker compose pull && \
    docker compose up -d' &
done
wait
```

---

## Database Issues

### PostgreSQL Replication Lag High

**Symptoms**:
- `pg_stat_replication` shows lag > 10 MB
- Potential data loss on failover
- Performance degradation

**Diagnosis**:

```bash
# 1. Check replication lag
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn, \
          (restart_lsn - confirmed_flush_lsn) as lag_bytes FROM pg_replication_slots;"'

# 2. Check replication status
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \
  "SELECT pid, usename, application_name, client_addr, state FROM pg_stat_replication;"'

# 3. Check transaction load
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \
  "SELECT datname, numbackends FROM pg_stat_database ORDER BY numbackends DESC;"'
```

**Solutions**:

| Lag Level | Action |
|-----------|--------|
| < 1 MB | Normal, no action needed |
| 1-10 MB | Monitor, may indicate high write load |
| 10-100 MB | Investigate write load, consider scaling |
| > 100 MB | Critical - reduce write load immediately |

```bash
# Reduce replication lag:
# 1. Reduce write load (stop batch jobs, etc.)
# 2. Increase WAL sender resources
# 3. Monitor until lag returns to < 1 MB
```

### PostgreSQL Connection Pool Exhausted

**Symptoms**:
- "FATAL: remaining connection slots reserved for non-replication superuser"
- Applications unable to connect
- Query timeouts

**Diagnosis**:

```bash
# 1. Check active connections
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \
  "SELECT count(*) as total_connections FROM pg_stat_activity;"'

# 2. List top connection consumers
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \
  "SELECT datname, count(*) as connections FROM pg_stat_activity GROUP BY datname ORDER BY connections DESC;"'

# 3. Check idle connections
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \
  "SELECT pid, datname, state, query FROM pg_stat_activity WHERE state = '\''idle'\'' LIMIT 10;"'
```

**Solutions**:

```bash
# 1. Kill idle connections
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = '\''idle'\'' AND query_start < now() - interval 30 minutes;"'

# 2. Increase connection pool (docker-compose.yml):
# POSTGRES_MAX_CONNECTIONS=200

# 3. Restart PostgreSQL with new limit
docker-compose restart postgres-primary
docker-compose restart postgres-replica
```

---

## Redis Cache Issues

### Redis Memory Usage High

**Symptoms**:
- Redis memory > 80% of limit
- Eviction errors
- Cache misses increasing

**Diagnosis**:

```bash
# 1. Check Redis memory usage
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-session redis-cli INFO memory'

# 2. Check top keys by size
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-session redis-cli --scan | head -100'

# 3. Check expiration policy
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-session redis-cli CONFIG GET maxmemory-policy'
```

**Solutions**:

```bash
# 1. Adjust eviction policy (LRU is default)
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-session redis-cli CONFIG SET maxmemory-policy "allkeys-lru"'

# 2. Increase Redis memory limit (docker-compose.yml)
# mem_limit: 2g

# 3. Flush old sessions (be careful!)
# docker compose exec redis-session redis-cli FLUSHDB

# 4. Restart with fresh state
docker-compose restart redis-session
```

### Redis Sentinel Failover Failed

**Symptoms**:
- redis-sentinel not promoting replica
- Master still marked as down
- Manual failover required

**Diagnosis**:

```bash
# 1. Check Sentinel status
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-sentinel redis-cli -p 26379 SENTINEL masters'

# 2. Check monitored masters
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-sentinel redis-cli -p 26379 SENTINEL slaves redis-master'

# 3. Check Sentinel logs
docker-compose logs redis-sentinel --tail 50 | grep -i "failover\|error"
```

**Solutions**:

```bash
# 1. Manual failover (if needed)
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-sentinel redis-cli -p 26379 SENTINEL failover redis-master'

# 2. Reset Sentinel monitor (if stuck)
docker-compose restart redis-sentinel

# 3. Verify failover completed
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-session redis-cli INFO replication'
```

---

## Network & Load Balancing

### Load Balancer Not Routing Traffic

**Symptoms**:
- All traffic to one replica
- Other replica marked unhealthy
- Uneven load distribution

**Diagnosis**:

```bash
# 1. Check health check configuration
curl -I http://192.168.168.31:8080/health
curl -I http://192.168.168.42:8080/health

# 2. Check HAProxy stats page (if using HAProxy)
curl http://HAPROXY_IP:8080/stats | grep -i 'backend\|code-server'

# 3. Check Caddy reverse proxy status
ssh akushnir@192.168.168.31 'docker-compose logs caddy | grep -i "unhealthy\|health"'
```

**Solutions**:

```bash
# 1. Restart health check
docker-compose restart caddy

# 2. Verify both replicas are healthy
for replica in 192.168.168.31 192.168.168.42; do
  curl -I http://$replica:8080/health
done

# 3. Check Caddy configuration
docker-compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

---

## Certificate & TLS Issues

### TLS Certificate Expired

**Symptoms**:
- `curl https://ide.kushnir.cloud` shows expired cert error
- Browser warnings
- API clients rejecting connection

**Diagnosis**:

```bash
# 1. Check certificate expiration
openssl s_client -connect ide.kushnir.cloud:443 -servername ide.kushnir.cloud </dev/null 2>/dev/null | \
  openssl x509 -noout -dates

# 2. Check on replica directly
ssh akushnir@192.168.168.31 'openssl s_client -connect 192.168.168.31:443 -servername ide.kushnir.cloud </dev/null 2>/dev/null | openssl x509 -noout -dates'

# 3. Check certificate in Caddy
docker-compose exec caddy caddy list-modules | grep cert
```

**Solutions** (Related to #1694):

```bash
# 1. Manual renewal (if Let's Encrypt not working)
bash scripts/ops/p1-1694-tls-recovery.sh

# 2. Or wait for automatic renewal on April 25, 2026 11:29:47 UTC

# 3. Alternatively, use self-signed cert temporarily
bash scripts/ops/generate-self-signed-certs.sh
```

### Let's Encrypt Rate Limit Hit (Issue #1694)

**Symptoms**:
- HTTP 429 from Let's Encrypt
- "too many certificates already issued"
- HTTPS endpoints serving old/expired certs

**Diagnosis**:

```bash
# 1. Check current certificates
ssh akushnir@192.168.168.31 'ls -la ~/.local/share/caddy/certificates/ 2>/dev/null || echo "No certs found"'

# 2. Check Caddy logs for LE errors
docker-compose logs caddy | grep -i "let's encrypt\|429\|rate"

# 3. Check certificate dates
openssl s_client -connect ide.kushnir.cloud:443 </dev/null 2>/dev/null | openssl x509 -noout -dates
```

**Solutions**:

```bash
# See scripts/ops/execute-p1-1694-security-fix.sh for full remediation
# Scheduled automatic recovery: April 25, 2026 11:29:47 UTC

# Or immediate self-signed recovery:
bash scripts/ops/p1-1694-tls-recovery.sh
```

---

## Incident Response Playbooks

### Playbook 1: Complete Cluster Outage

**Scenario**: Both replicas down or unreachable

**Time-to-Recovery**: 15-30 minutes

**Steps**:

```bash
# Step 1: Confirm outage (< 1 min)
for replica in 192.168.168.31 192.168.168.42; do
  ping -c 1 $replica || echo "❌ $replica unreachable"
done

# Step 2: Identify cause (2-5 min)
# - Network failure: Contact networking team
# - Hardware failure: Physical inspection needed
# - Power loss: Check power supply / UPS status
# - Software hang: Check if SSH works, then restart docker daemon

# Step 3: Restart procedure
if [ "network issue" ]; then
  # Contact network ops
  exit 1
elif [ "docker crashed" ]; then
  ssh akushnir@192.168.168.31 'sudo systemctl restart docker'
  ssh akushnir@192.168.168.42 'sudo systemctl restart docker'
  sleep 60
elif [ "power issue" ]; then
  # Contact infrastructure team
  exit 1
fi

# Step 4: Verify recovery
bash scripts/ops/verify-deployment-state.sh
```

### Playbook 2: Single Replica Failure

**Scenario**: One replica unreachable, other still serving traffic

**Time-to-Recovery**: 5-10 minutes

**Steps**:

```bash
# Step 1: Confirm single replica down (< 1 min)
# This is normal operation - LB switches to healthy replica

# Step 2: Investigate failed replica (5 min)
ssh akushnir@$FAILED_REPLICA 'docker ps -a'  # Check containers
ssh akushnir@$FAILED_REPLICA 'df -h /'       # Check disk space
ssh akushnir@$FAILED_REPLICA 'free -h'       # Check memory

# Step 3: Restart failed replica
ssh akushnir@$FAILED_REPLICA 'docker compose restart'
sleep 30

# Step 4: Verify recovery
curl -I http://$FAILED_REPLICA:8080/health
```

### Playbook 3: Data Loss / Corruption

**Scenario**: Database corruption or data loss detected

**Time-to-Recovery**: 30-60 minutes

**Steps** (PostgreSQL-specific):

```bash
# Step 1: Stop all writes (immediately)
# Set read-only mode or disable APIs

# Step 2: Check replication status
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \
  "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datname = '\''mydb'\'';"'

# Step 3: Restore from backup
# Backup location: /mnt/nas/cold/backups/
ls -la /mnt/nas/cold/backups/ | tail -5

# Step 4: Perform point-in-time recovery (PITR)
# Instructions in docs/DATABASE-RECOVERY-PROCEDURES.md

# Step 5: Verify data integrity
# Run consistency checks and validate critical data
```

---

## Escalation Procedures

### Level 1: On-Call Engineer (< 15 min response)

**Responsibilities**:
- Acknowledge incident
- Run quick diagnostics
- Attempt standard troubleshooting

**If Unable to Resolve in 15 minutes → Escalate to Level 2**

### Level 2: Senior Engineer/SRE (< 30 min response)

**Responsibilities**:
- Deep diagnosis
- Advanced troubleshooting
- Potential failover/rebuild

**If Unable to Resolve in 30 minutes → Escalate to Level 3**

### Level 3: Infrastructure Team Lead

**Responsibilities**:
- Emergency decisions
- Hardware intervention
- Vendor escalation

**Contact**: 
- Slack: #ops-critical
- PagerDuty: ops-escalation
- Phone: [escalation number]

---

## Common Escalation Signals

| Signal | Escalate to Level | Action |
|--------|------------------|--------|
| Both replicas down | Level 2 | Check network/power/hardware |
| Data loss suspected | Level 2 | Stop writes, initiate recovery |
| Certificate chain broken | Level 1 | Try #1694 recovery script |
| Performance degradation | Level 1 | Check resource utilization |
| Cascading failures | Level 3 | Potential infrastructure issue |

---

## Additional Resources

- [Failover Runbook](FAILOVER-RUNBOOK-SIMPLIFIED.md)
- [Production Deployment Runbook](DEPLOYMENT-RUNBOOK-OPERATIONS.md)
- [Production SLA Metrics](PRODUCTION-SLA-METRICS.md)
- [Grafana Dashboard Setup](GRAFANA-DASHBOARD-SETUP.md)

---

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Status**: ✅ Production-Ready
