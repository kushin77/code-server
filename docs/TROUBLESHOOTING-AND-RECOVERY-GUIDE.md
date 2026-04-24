# Production Troubleshooting & Recovery Guide

**Purpose**: Quick diagnostic procedures for common production issues  
**Audience**: Operations Engineers, On-Call SRE, DevOps  
**Updated**: April 24, 2026  
**Severity Levels**: P0 (Outage) → P4 (Degradation)

---

## Issue Diagnostic Flowchart

```
⚠️ Issue Reported
    ↓
    ├─ "Cannot access IDE"? → See: IDE Access Failures
    ├─ "Portal down"? → See: Portal & OAuth Issues
    ├─ "Database slow"? → See: Database Performance Issues
    ├─ "Memory high"? → See: Resource Exhaustion
    ├─ "SSL/TLS error"? → See: Certificate & TLS Issues
    ├─ "Replica unavailable"? → See: Replica Failover Issues
    └─ "Unknown error"? → See: General Diagnostics (START HERE)
```

---

## General Diagnostics

### Step 1: Cluster Health Assessment (30 seconds)

```bash
# Check both replicas are responding
for host in 192.168.168.31 192.168.168.42; do
  echo "=== $host ==="
  ssh akushnir@$host 'docker-compose ps | grep -E "STATE|healthy|Up"'
done

# Check load balancer routing
curl -s -w "HTTP %{http_code}\n" https://kushnir.cloud/health
curl -s -w "HTTP %{http_code}\n" https://ide.kushnir.cloud/health

# Check DNS resolution
nslookup kushnir.cloud
nslookup ide.kushnir.cloud
```

### Step 2: Service Status

```bash
# Connect to primary replica
ssh akushnir@192.168.168.31

# Check all services running
docker-compose ps

# Expected output should show all services as "Up" or "healthy"
# If any show "Exited" or "unhealthy" → investigate that service
```

### Step 3: Error Log Collection

```bash
# Collect recent errors from all services
docker-compose logs --since 30m | grep -i "error\|failed\|critical"

# Check specific service logs
docker-compose logs --tail 100 caddy
docker-compose logs --tail 100 code-server
docker-compose logs --tail 100 postgres-primary

# Check syslog for infrastructure issues
sudo tail -100 /var/log/syslog | grep -i "docker\|systemd\|kernel"
```

### Step 4: Confirm Issue Scope

```bash
# Is R31 affected?
ssh akushnir@192.168.168.31 'curl -s https://localhost/health'

# Is R42 affected?
ssh akushnir@192.168.168.42 'curl -s https://localhost/health'

# If one replica is healthy → issue is isolated
# If both down → cluster-wide issue
```

---

## IDE Access Failures

### Symptom: "Connection refused" or "Timeout"

**Severity**: P1 (if all replicas affected) or P2 (if one replica)

#### Diagnosis

```bash
# Test HTTPS connectivity
curl -v https://ide.kushnir.cloud/health

# Test HTTP fallback (if HTTPS broken)
curl -v http://ide.kushnir.cloud/health

# Test direct connection to replica
curl -v https://192.168.168.31/health

# Check Caddy routing
docker-compose logs -f caddy | grep -i "ide\|code-server"

# Check Code-Server status
docker-compose ps code-server
```

#### Resolution by Cause

**Cause 1: Caddy not routing properly**
```bash
# Fix: Reload Caddy configuration
docker-compose restart caddy

# Verify routing restored
curl -v https://ide.kushnir.cloud/health  # Should return 200
```

**Cause 2: Code-Server container crashed**
```bash
# Check logs
docker-compose logs code-server --tail 50

# Restart service
docker-compose restart code-server

# Wait for startup (typically 30-60 seconds)
sleep 60

# Verify health endpoint
curl -s https://localhost:8443/api/v1/applications/overview | jq .status
```

**Cause 3: Port conflict**
```bash
# Find what's listening on port 8443
netstat -tlnp | grep 8443

# If something else is using port, stop it
kill -9 <pid>

# Restart code-server
docker-compose restart code-server
```

**Cause 4: Out of disk space**
```bash
# Check disk usage
df -h

# If root filesystem > 90% full:
docker system prune --all --force    # Remove unused images/containers
docker volume prune --force           # Remove unused volumes

# Restart services
docker-compose down && docker-compose up -d
```

---

## Portal & OAuth Issues

### Symptom: "Redirect loop" at Google login

**Severity**: P1 (Portal inaccessible)

#### Diagnosis

```bash
# Check oauth2-proxy-portal logs
docker-compose logs oauth2-proxy-portal -f

# Look for: CSRF token errors, cookie errors, redirect loops

# Check proxy configuration
docker-compose config | grep -A 20 "oauth2-proxy-portal:"

# Verify cookie domain
echo $OAUTH2_PROXY_COOKIE_DOMAIN

# Test proxy directly
curl -v http://localhost:4180/oauth2/auth
```

#### Resolution

**Cause 1: SameSite cookie issue (CSRF rejection)**
```bash
# Fix: Update docker-compose.yml or .env
OAUTH2_PROXY_COOKIE_SAMESITE=none
OAUTH2_PROXY_COOKIE_SECURE=true
OAUTH2_PROXY_COOKIE_DOMAIN=.kushnir.cloud

# Restart proxy
docker-compose restart oauth2-proxy-portal

# Test
curl -v https://kushnir.cloud/  # Should redirect to Google, not loop
```

**Cause 2: Whitelist domain mismatch**
```bash
# Verify whitelist-domains configured
docker-compose exec oauth2-proxy-portal grep "whitelist-domains" /etc/oauth2-proxy/oauth2-proxy.cfg

# Should be: .kushnir.cloud

# If wrong, update config and restart
docker-compose restart oauth2-proxy-portal
```

**Cause 3: Redis session store unreachable**
```bash
# Check Redis connectivity
docker-compose exec oauth2-proxy-portal redis-cli -h redis-primary ping

# If fails: "Could not connect to Redis"
docker-compose restart redis-primary redis-sentinel

# Restart oauth2-proxy
docker-compose restart oauth2-proxy-portal
```

### Symptom: "Session lost after navigation"

**Severity**: P2 (Usability issue)

#### Diagnosis

```bash
# Check session timeout
docker-compose config | grep "session_lifetime\|cookie_expire"

# Check Redis session store
docker-compose exec redis-primary redis-cli KEYS "oauth2_proxy*" | wc -l

# If 0 keys → sessions not being stored
```

#### Resolution

```bash
# Increase session lifetime
OAUTH2_PROXY_COOKIE_EXPIRE=2592000  # 30 days

# Verify Redis is cluster-wide
# Both replicas should connect to same Redis instance

# Restart oauth2-proxy on both replicas
for host in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$host 'cd code-server-enterprise && \
    docker-compose restart oauth2-proxy-portal'
done
```

---

## Database Performance Issues

### Symptom: "Database queries slow"  or "Replication lag high"

**Severity**: P2 (Performance degradation)

#### Diagnosis

```bash
# Check replication lag
ssh akushnir@192.168.168.31 'docker-compose exec postgres-primary psql -U postgres -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn, write_lag FROM pg_replication_slots;"'

# Check slow queries
docker-compose exec postgres-primary psql -U postgres -c \
  "SELECT query, calls, total_time FROM pg_stat_statements \
   ORDER BY total_time DESC LIMIT 5;"

# Check connections
docker-compose exec postgres-primary psql -U postgres -c \
  "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"

# Check lock waits
docker-compose exec postgres-primary psql -U postgres -c \
  "SELECT * FROM pg_locks WHERE NOT granted;"
```

#### Resolution

**Cause 1: High replication lag (> 1 MB)**
```bash
# Symptom: Standby falling behind

# Check why replica is slow
docker-compose exec postgres-replica psql -U postgres -c \
  "SELECT now() - pg_postmaster_start_time() AS uptime;"

# If replica just restarted, lag is normal (will catch up)
# Wait 5-10 minutes

# If lag continues growing:

# 1. Check network between replicas
ping -c 10 192.168.168.42  # From R31

# 2. Increase replication buffer
# Edit postgresql.conf: wal_keep_size = 2GB

# 3. Restart primary after config change
docker-compose restart postgres-primary
```

**Cause 2: Slow queries blocking database**
```bash
# Identify slow query
docker-compose exec postgres-primary psql -U postgres -c \
  "SELECT query, calls, total_time \
   FROM pg_stat_statements \
   WHERE total_time > 1000 \
   ORDER BY total_time DESC LIMIT 1;"

# Check query plan (EXPLAIN)
docker-compose exec postgres-primary psql -U postgres -c \
  "EXPLAIN ANALYZE SELECT ..." 

# Solutions:
# - Add index: CREATE INDEX idx_name ON table(column);
# - Optimize query: Rewrite with better joins
# - Increase work_mem: postgres.conf: work_mem = 256MB
```

**Cause 3: Too many connections**
```bash
# Reduce stale connections
docker-compose exec postgres-primary psql -U postgres -c \
  "SELECT pid, usename, state FROM pg_stat_activity \
   WHERE state = 'idle' AND query_start < now() - interval '1 hour';" 

# Terminate idle connections
docker-compose exec postgres-primary psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
   WHERE state = 'idle' AND query_start < now() - interval '1 hour';"

# Restart connection pooler
docker-compose restart code-server  # Releases database connections
```

---

## Resource Exhaustion

### Symptom: "High memory usage" or "CPU maxed out"

**Severity**: P1 (if causing service degradation)

#### Diagnosis

```bash
# Memory usage per service
docker stats --no-stream | grep -E "CONTAINER|postgres|redis|caddy|code-server"

# Top processes
ps aux --sort=-%mem | head -10

# Disk usage
du -sh /var/lib/docker/containers/*
du -sh /var/lib/postgresql/data

# inode usage
df -i
```

#### Resolution

**Cause 1: Prometheus storing too much data**
```bash
# Check retention
docker-compose config | grep retention

# Reduce retention period
PROMETHEUS_RETENTION_DAYS=7  # Down from 15

# Restart Prometheus
docker-compose down prometheus
docker-compose up -d prometheus

# Clean old data
rm -rf /var/lib/prometheus/wal  # Will rebuild

# Verify memory freed
docker stats prometheus --no-stream
```

**Cause 2: Redis memory full (eviction)**
```bash
# Check memory usage
docker-compose exec redis-primary INFO memory

# Reduce max memory
REDIS_MAX_MEMORY=1gb  # Down from 2gb

# Or increase eviction
docker-compose exec redis-primary CONFIG SET maxmemory-policy allkeys-lru

# Restart redis
docker-compose restart redis-primary redis-sentinel
```

**Cause 3: Code-Server workspace cache bloated**
```bash
# Check workspace size
du -sh /root/.local/share/code-server/

# Clear cache
rm -rf /root/.local/share/code-server/cache
rm -rf /root/.local/share/code-server/CachedExtensionVSIXs

# Restart code-server
docker-compose restart code-server
```

---

## Certificate & TLS Issues

### Symptom: "SSL certificate error" or "CERTIFICATE_VERIFY_FAILED"

**Severity**: P0 (if blocking all HTTPS access)

#### Diagnosis

```bash
# Check certificate details
openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud

# Check cert expiry
echo | openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud 2>/dev/null \
  | openssl x509 -noout -dates

# Check Caddy acme status
docker-compose logs caddy | grep -i "acme\|certificate"

# Check certificate in container
docker-compose exec caddy ls -la /data/caddy/certificates/
```

#### Resolution

**Cause 1: Let's Encrypt rate limit (HTTP 429)**

See: `/memories/repo/april-24-2026-letsencrypt-ratelimit-blocker.md`

**Expiry Time**: April 25, 2026 11:29:47 UTC

**Workarounds**:
```bash
# Option 1: Wait for rate limit expiry (April 25)
# Caddy will auto-renew on next restart

# Option 2: Use self-signed cert temporarily
# In docker-compose.yml, comment ACME renewal
# Mount pre-generated self-signed cert

# Option 3: Run Caddy without HTTPS
# Remove ':443' from Caddyfile
# Restart: docker-compose restart caddy
```

**Cause 2: Cert renewal failing**
```bash
# Force renewal (dangerous - can trigger rate limit)
docker-compose exec caddy caddy reload

# Check Caddy config is valid
docker-compose exec caddy caddy validate --config /etc/caddy/Caddyfile

# Restart Caddy with fresh config
docker-compose down caddy
docker-compose up -d caddy

# Monitor logs
docker-compose logs -f caddy | grep -i "acme\|certificate"
```

**Cause 3: Self-signed cert in production**
```bash
# Generate self-signed cert (temporary)
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# Mount in Caddy
# In docker-compose.yml:
volumes:
  - ./cert.pem:/data/caddy/cert.pem
  - ./key.pem:/data/caddy/key.pem

# Test with curl -k (insecure flag)
curl -k https://kushnir.cloud/health
```

---

## Replica Failover Issues

### Symptom: "Replica not responding" or "Failover stuck"

**Severity**: P1 (High Availability broken)

#### Diagnosis

```bash
# Check replica health from LB perspective
ssh akushnir@192.168.168.31 'docker-compose ps'
ssh akushnir@192.168.168.42 'docker-compose ps'

# Check load balancer sees both replicas
curl http://192.168.168.31:8080/stats  # HAProxy stats

# Test direct connection to replica
ping 192.168.168.31
ping 192.168.168.42

# Check SSH connectivity
ssh akushnir@192.168.168.31 'echo OK'
ssh akushnir@192.168.168.42 'echo OK'
```

#### Resolution

**Cause 1: Replica crashed or network partition**
```bash
# Force failover to other replica
# On standby, promote to primary
ssh akushnir@192.168.168.42 'cd code-server-enterprise && \
  docker-compose exec postgres-replica pg_ctl promote'

# Verify new primary is accepting writes
ssh akushnir@192.168.168.42 'docker-compose exec postgres-replica psql -U postgres -c \
  "SELECT pg_is_in_recovery();"'
# Should return: f (false)

# Verify services switched to new primary
curl -s https://kushnir.cloud/health  # Should return 200
```

**Cause 2: Health check endpoint down but services running**
```bash
# Check if health endpoint is the problem
docker-compose exec caddy curl -s http://code-server:8443/api/v1/applications/overview

# If that works, update health check path in LB config

# Or restart Caddy to reset routing
docker-compose restart caddy
```

**Cause 3: Both replicas down**
```bash
# This is a P0 outage
# Need to bring replicas back up

# SSH to host (requires physical access or OOB management)
ssh akushnir@192.168.168.31

# Check disk space
df -h

# Check systemd status
sudo systemctl status docker

# Restart Docker daemon if needed
sudo systemctl restart docker

# Start docker-compose
cd code-server-enterprise
docker-compose up -d

# Wait for services to start (5-10 minutes)
# Monitor logs
docker-compose logs -f
```

---

## Network & Connectivity Issues

### Symptom: "Cannot reach replica" or "Network timeout"

**Severity**: P1 (if affecting production traffic)

#### Diagnosis

```bash
# Test network path to replica
traceroute 192.168.168.31
traceroute 192.168.168.42

# Check packet loss
ping -c 100 192.168.168.31 | grep loss

# Check network interfaces
ssh akushnir@192.168.168.31 'ip addr show'

# Check routing table
ssh akushnir@192.168.168.31 'ip route show'

# Check firewall rules
ssh akushnir@192.168.168.31 'sudo iptables -L -n -v'
```

#### Resolution

**Cause 1: Firewall blocking traffic**
```bash
# Check if port 443 is open
sudo nmap -p 443 192.168.168.31

# If blocked, open port
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp

# Reload firewall
sudo ufw reload
```

**Cause 2: Network interface down**
```bash
# Check interface status
ssh akushnir@192.168.168.31 'ip link show'

# If interface down, bring it up
ssh akushnir@192.168.168.31 'sudo ip link set eth0 up'

# Or restart networking
ssh akushnir@192.168.168.31 'sudo systemctl restart networking'
```

**Cause 3: DNS resolution failing**
```bash
# Test DNS
nslookup kushnir.cloud
dig kushnir.cloud

# If fails, check DNS server
cat /etc/resolv.conf

# Update DNS if needed
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Test again
curl https://kushnir.cloud/health
```

---

## Escalation Path

### If issue persists after Step 5+ remediation attempts:

1. **Check GitHub Issues** for related problems
   ```bash
   gh issue list --repo kushin77/code-server --state open --search "is:issue label:bug"
   ```

2. **Create incident issue**
   ```bash
   gh issue create --repo kushin77/code-server \
     --title "INCIDENT: $issue_description" \
     --label "P0,incident" \
     --body "... detailed diagnostics ..."
   ```

3. **Contact on-call SRE**
   - Slack: #ops-incidents
   - PagerDuty: Production rotation

4. **Document for postmortem**
   - What failed
   - Timeline of events
   - Root cause (if identified)
   - Prevention plan

---

## Prevention Checklist

**Weekly**: 
- [ ] Review error logs for patterns
- [ ] Check disk usage trends
- [ ] Verify backups completing
- [ ] Test failover on standby replica

**Monthly**:
- [ ] Load test cluster (simulate peak)
- [ ] Disaster recovery drill (restore from backup)
- [ ] Certificate renewal validation
- [ ] Database integrity check

**Quarterly**:
- [ ] Infrastructure security audit
- [ ] Network connectivity verification
- [ ] Performance baseline update
- [ ] Runbook review & update

---

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Emergency Contact**: #ops-incidents (Slack)  
**Related Docs**: Failover Runbook, Deployment Runbook, SLA Metrics
