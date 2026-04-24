# Troubleshooting Guide - Production Deployment

**Objective**: Quick reference for common issues and their solutions  
**Owner**: Support Team  
**Last Updated**: April 20, 2026  
**Status**: Ready for production use

---

## Quick Reference - Issue Diagnosis

| Symptom | Likely Cause | See Section |
|---------|--------------|-------------|
| "Connection refused" on port 8080 | code-server not running | 1.1 |
| Cannot login (OAuth fails) | oauth2-proxy misconfigured | 2.1 |
| "Database connection error" | PostgreSQL down | 3.1 |
| Metrics missing from Prometheus | Scrape target down | 4.1 |
| Grafana dashboards empty | Datasource not configured | 4.2 |
| High CPU usage (>80%) | Runaway process | 5.1 |
| Disk full errors | Volume capacity exceeded | 5.2 |
| Services in restart loop | Resource exhaustion | 5.3 |
| "502 Bad Gateway" | Reverse proxy routing error | 6.1 |
| Slow performance (>5s response time) | Bottleneck identification | 5.4 |
| Missing files / data loss | Backup/restore issue | 7.1 |
| Security alert (suspicious activity) | Investigate logs | 8.1 |

---

## Section 1: Service Health Issues

### 1.1: Code-Server Not Running

**Symptoms**:
- Connection refused on port 8080
- "Cannot reach server" in browser
- Service shows "Exited" status

**Diagnosis**:
```bash
# Check service status
docker-compose ps code-server
# Expected: "Up (healthy)" or "Up"

# Check logs
docker-compose logs code-server | tail -50

# Check if port is in use
netstat -tulpn | grep 8080
```

**Solutions**:

**Solution A: Simple Restart**
```bash
docker-compose restart code-server
sleep 10
docker-compose ps code-server
```

**Solution B: Service Crashed (check logs)**
```bash
# View last 100 lines of logs
docker-compose logs code-server | tail -100

# Common issues:
# - "Out of memory" → increase memory limit
# - "Port already in use" → find and kill process on 8080
# - "Cannot write to /home/coder" → fix volume permissions

# Restart with clean state
docker-compose down -v code-server
docker-compose up -d code-server
```

**Solution C: Persistent Failure**
```bash
# Pull latest image
docker pull code-server-enterprise:dev

# Rebuild container
docker-compose up -d --force-recreate code-server

# Check resource limits
docker stats code-server
# Memory should be < allocated limit
```

**Prevention**:
- Monitor memory usage: `docker stats --no-stream`
- Set memory limits in docker-compose.yml
- Enable auto-restart: `restart: unless-stopped`

---

### 1.2: All Services Down

**Symptoms**:
- Multiple services showing "Exited" or "Restarting"
- System appears unresponsive
- Docker daemon error

**Diagnosis**:
```bash
# Check Docker daemon
docker ps
# If error: daemon not responding

# Check system resources
free -h  # memory
df -h    # disk space
top      # CPU usage

# Check service errors
docker-compose logs --tail=100
```

**Solutions**:

**Solution A: Docker Daemon Restart**
```bash
# Restart Docker daemon
sudo systemctl restart docker

# Wait for it to come up
sleep 10

# Restart services
docker-compose up -d

# Verify
docker-compose ps
```

**Solution B: Disk Space Full**
```bash
# Check which partition is full
df -h

# Clean up old images/containers
docker system prune -a --volumes

# Remove specific old image
docker rmi <image-id>

# Restart services
docker-compose up -d
```

**Solution C: Memory Exhaustion**
```bash
# Check memory usage
free -h

# Identify heavy process
top -o %MEM

# Restart least critical service first
docker-compose restart redis
docker-compose restart code-server
# Don't restart postgres (data risk)
```

---

### 1.3: Service Stuck in Restart Loop

**Symptoms**:
- Service continuously restarting
- "Exit code 1" or "Exit code 137" repeatedly
- Logs show crash immediately after startup

**Diagnosis**:
```bash
# Watch service status
watch -n 2 'docker-compose ps service-name'

# Check logs for error message
docker-compose logs service-name | grep -i "error\|fatal" | tail -20

# Common exit codes:
# 1 = Generic error (check logs)
# 137 = OOM killed (out of memory)
# 139 = SIGSEGV (segmentation fault)
```

**Solutions**:

**Solution A: Configuration Error**
```bash
# Check docker-compose.yml syntax
docker-compose config > /dev/null
# If error: fix YAML syntax

# Check environment variables
docker-compose exec postgres env | grep POSTGRES
# Verify all required vars are set
```

**Solution B: Resource Limits**
```bash
# Check current limits in docker-compose.yml
grep -A5 "deploy:" docker-compose.yml

# Increase limits temporarily
docker-compose down
# Edit docker-compose.yml to increase memory limit
# Example: change "8g" to "16g"
docker-compose up -d

# Monitor memory
docker stats service-name
```

**Solution C: Dependency Not Ready**
```bash
# Check if dependencies are running
docker-compose ps postgres redis

# If dependencies not running:
docker-compose up -d postgres redis
sleep 10

# Then start service
docker-compose up -d service-name
```

---

## Section 2: Authentication Issues

### 2.1: OAuth Login Fails

**Symptoms**:
- Click "Login" → stuck on Google login screen
- "Error 401 - Unauthorized"
- Redirect loop

**Diagnosis**:
```bash
# Check oauth2-proxy logs
docker-compose logs oauth2-proxy | tail -50

# Check if oauth2-proxy is running
docker-compose ps oauth2-proxy

# Test oauth2-proxy health
curl -sk https://localhost:4180/ping

# Check redirect URI configuration
docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/oauth2-proxy.cfg | grep -i redirect
```

**Solutions**:

**Solution A: OAuth Client ID/Secret Wrong**
```bash
# Get credentials from environment
docker-compose exec oauth2-proxy env | grep OAUTH

# Verify in GCP Console:
# 1. Go to: Google Cloud Console > APIs & Services > Credentials
# 2. Find OAuth 2.0 Client ID for code-server
# 3. Check: Authorized redirect URIs includes https://your-domain/oauth2/callback

# If wrong, update in .env file:
OAUTH_CLIENT_ID="correct-client-id"
OAUTH_CLIENT_SECRET="correct-client-secret"

# Restart service
docker-compose restart oauth2-proxy
```

**Solution B: Redirect URI Mismatch**
```bash
# Check what redirect URI is configured
docker-compose logs oauth2-proxy | grep -i redirect

# Expected format: https://your-domain/oauth2/callback

# If wrong:
# 1. Update GCP OAuth Client settings
# 2. Add correct redirect URIs in Google Console
# 3. Restart oauth2-proxy
docker-compose restart oauth2-proxy
```

**Solution C: oauth2-proxy Not Running**
```bash
# Restart oauth2-proxy
docker-compose restart oauth2-proxy
sleep 10

# Check if healthy
docker-compose ps oauth2-proxy

# If still failing, check logs for root cause
docker-compose logs oauth2-proxy | tail -100
```

---

### 2.2: Session Expires Too Quickly

**Symptoms**:
- Logged out after 5-10 minutes
- Need to re-authenticate constantly
- Session expires despite activity

**Diagnosis**:
```bash
# Check session timeout configuration
docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/oauth2-proxy.cfg | grep -i timeout

# Check OAuth token expiry
curl -sk https://localhost/api/v1/user -H "Authorization: Bearer $TOKEN"
# Check token age in response

# Check environment variables
docker-compose exec code-server env | grep -i timeout
```

**Solutions**:

**Solution A: Session Timeout Too Short**
```bash
# Default: 24 hours
# To increase:

# Edit .env or docker-compose.yml
SESSION_TIMEOUT="48h"

# Restart services
docker-compose restart oauth2-proxy code-server

# Verify change
docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/oauth2-proxy.cfg | grep timeout
```

**Solution B: OAuth Token Expiry**
```bash
# Check Google OAuth token lifetime
# Some OIDC providers have short token expiry (1 hour)

# Workaround: Enable token refresh
# Edit oauth2-proxy configuration:
OAUTH_PROVIDER="oidc"
OIDC_ISSUER_URL="https://accounts.google.com"
OIDC_AUDIENCE="your-client-id"
SESSION_STORE_TYPE="redis"  # Use Redis for distributed sessions

docker-compose restart oauth2-proxy
```

---

## Section 3: Database Issues

### 3.1: PostgreSQL Connection Error

**Symptoms**:
- "FATAL: database... does not exist"
- "ECONNREFUSED" on port 5432
- "role 'synapse' does not exist"

**Diagnosis**:
```bash
# Check if PostgreSQL is running
docker-compose ps postgres

# Check PostgreSQL logs
docker-compose logs postgres | tail -50

# Try connecting directly
docker-compose exec postgres psql -U postgres -c "\l"
# Should list databases

# Check if synapse_db exists
docker-compose exec postgres psql -U postgres -c "\l" | grep synapse
```

**Solutions**:

**Solution A: PostgreSQL Not Running**
```bash
# Start PostgreSQL
docker-compose up -d postgres

# Wait for healthy status
docker-compose ps postgres
# Should show "(healthy)"

# If keeps restarting, check logs
docker-compose logs postgres | tail -100
```

**Solution B: Database Doesn't Exist**
```bash
# Create missing database
docker-compose exec postgres createdb -U postgres synapse_db

# Create user if missing
docker-compose exec postgres psql -U postgres -c "CREATE USER synapse WITH PASSWORD 'password';"

# Grant privileges
docker-compose exec postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE synapse_db TO synapse;"
```

**Solution C: Role/User Missing**
```bash
# List existing roles
docker-compose exec postgres psql -U postgres -c "\du"

# If synapse role missing:
docker-compose exec postgres psql -U postgres -c "CREATE ROLE synapse WITH LOGIN PASSWORD '$POSTGRES_PASSWORD';"

# Grant privileges
docker-compose exec postgres psql -U postgres -d synapse_db -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO synapse;"
```

---

### 3.2: Database Performance Slow

**Symptoms**:
- Queries taking >5 seconds
- IDE slow to load
- "Database timeout" errors

**Diagnosis**:
```bash
# Check database size
docker-compose exec postgres psql -U postgres -c "SELECT pg_size_pretty(pg_database_size('synapse_db'));"

# Check number of connections
docker-compose exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Check slow queries
docker-compose exec postgres psql -U postgres -d synapse_db -c "SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
```

**Solutions**:

**Solution A: Too Many Connections**
```bash
# Close idle connections
docker-compose exec postgres psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='synapse_db' AND state='idle' AND state_change < NOW() - INTERVAL '1 hour';"

# Increase max connections
docker-compose down
# Edit docker-compose.yml, increase: max_connections=2000
docker-compose up -d postgres
```

**Solution B: Missing Indexes**
```bash
# Analyze query performance
docker-compose exec postgres psql -U postgres -d synapse_db -c "EXPLAIN ANALYZE SELECT * FROM events WHERE room_id='!room:example.com';"

# If seq scan (slow), create index
docker-compose exec postgres psql -U postgres -d synapse_db -c "CREATE INDEX idx_events_room_id ON events(room_id);"
```

**Solution C: Autovacuum Running**
```bash
# Check if autovacuum is running
docker-compose exec postgres psql -U postgres -c "SELECT datname, last_autovacuum FROM pg_stat_user_tables LIMIT 10;"

# If running too frequently, adjust:
docker-compose exec postgres psql -U postgres -d synapse_db -c "ALTER TABLE events SET (autovacuum_vacuum_scale_factor = 0.05);"
```

---

## Section 4: Monitoring Issues

### 4.1: Prometheus Scrape Failures

**Symptoms**:
- "X targets down" in Prometheus UI
- Metrics missing for some services
- "Connection refused" in scrape logs

**Diagnosis**:
```bash
# Check Prometheus scrape targets
curl -sk https://localhost:9090/api/v1/targets | jq '.data'

# Find down targets
curl -sk https://localhost:9090/api/v1/targets | jq '.data | select(.health=="down")'

# Check scrape logs
docker-compose logs prometheus | grep -i "error\|scrape" | tail -20
```

**Solutions**:

**Solution A: Target Service Down**
```bash
# Example: synapse target down
# 1. Verify service is running
docker-compose ps synapse

# 2. If not running, start it
docker-compose up -d synapse

# 3. Wait 30 seconds for scrape to succeed
sleep 30

# 4. Verify in Prometheus UI
curl -sk https://localhost:9090/api/v1/targets | grep synapse
```

**Solution B: Wrong Metrics Port**
```bash
# Check Prometheus config for correct port
cat prometheus.yml | grep -A3 "job_name: synapse"

# Common port mistakes:
# Synapse metrics: :8008/_synapse/metrics (not :8008)
# Caddy metrics: :2019/metrics (not :2019)

# If wrong, edit prometheus.yml and restart
docker-compose restart prometheus
```

**Solution C: Firewall Blocking**
```bash
# Verify target is reachable
docker-compose exec prometheus curl -v http://synapse:8008/_synapse/metrics

# If "connection refused":
# 1. Verify service listening on port
docker-compose exec synapse netstat -tulpn | grep 8008

# 2. Verify network connectivity
docker-compose exec prometheus ping synapse

# 3. Check firewall rules
sudo iptables -L -n | grep 8008
```

---

### 4.2: Grafana Dashboards Empty

**Symptoms**:
- "No Data" on all charts
- Time range selector shows no data
- Graphs are blank

**Diagnosis**:
```bash
# Check Prometheus datasource connection
# In Grafana: Configuration > Data Sources > Prometheus
# Click "Test" - should succeed

# Check if Prometheus has data
curl -sk 'https://localhost:9090/api/v1/query?query=up' | jq '.data.result | length'
# Should return > 0

# Check dashboard queries
# In Grafana: Open dashboard > Inspect > Check queries
```

**Solutions**:

**Solution A: Datasource Not Configured**
```bash
# In Grafana UI:
# 1. Go to: Configuration > Data Sources
# 2. Add new > Prometheus
# 3. URL: http://prometheus:9090
# 4. Click "Save & Test"

# Or via API:
curl -sk -X POST https://localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
    "access": "proxy",
    "isDefault": true
  }' -u admin:admin123
```

**Solution B: Dashboard Queries Wrong**
```bash
# Check individual panel query:
# In Grafana: Open dashboard > Click panel > Edit
# Verify query syntax: rate(http_requests_total[5m])

# Common errors:
# - Metric name typo: http_request_total (missing 's')
# - Non-existent metric: check Prometheus targets
# - Time range too old: data may not exist

# Test in Prometheus first:
curl -sk 'https://localhost:9090/api/v1/query?query=up&time=now'
```

---

## Section 5: Performance Issues

### 5.1: High CPU Usage

**Symptoms**:
- CPU > 80% consistently
- System slow/unresponsive
- Services occasionally killed (OOM)

**Diagnosis**:
```bash
# Check system CPU
top -b -n 1 | head -20

# Check per-container CPU
docker stats --no-stream

# Find hottest process
ps aux --sort=-%cpu | head -10

# Check Prometheus metrics
curl -sk 'https://localhost:9090/api/v1/query?query=rate(process_cpu_seconds_total[5m])'
```

**Solutions**:

**Solution A: Restart Heavy Service**
```bash
# Identify heavy service (from docker stats)
# Example: code-server using 60% CPU

# Restart it
docker-compose restart code-server

# Monitor CPU drop
docker stats code-server --no-stream
```

**Solution B: Reduce Thread Count**
```bash
# If Node.js service (code-server) high CPU:
# Reduce worker threads
docker-compose down

# Edit docker-compose.yml
environment:
  - UV_THREADPOOL_SIZE=2  # Reduce from 4

docker-compose up -d
```

**Solution C: Database Query Optimization**
```bash
# If PostgreSQL high CPU:
# Kill long-running queries
docker-compose exec postgres psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query_start < NOW() - INTERVAL '5 minutes' AND state != 'idle';"

# Analyze and optimize slow queries
docker-compose exec postgres psql -U postgres -d synapse_db -c "SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5;"
```

---

### 5.2: Disk Space Full

**Symptoms**:
- "No space left on device" errors
- Services crash/restart
- Files cannot be written

**Diagnosis**:
```bash
# Check disk usage
df -h

# Find large files
du -sh /* | sort -h

# Check Docker volumes
docker system df

# Check specific volume
docker inspect <volume-name> | jq '.[0].Mountpoint'
ls -lh <mount-point>
```

**Solutions**:

**Solution A: Clean Docker System**
```bash
# Remove stopped containers
docker container prune -f

# Remove unused images
docker image prune -a -f

# Remove unused volumes
docker volume prune -f

# Check freed space
df -h
```

**Solution B: Rotate/Archive Old Data**
```bash
# If Prometheus too large:
# Edit docker-compose.yml
environment:
  - '--storage.tsdb.retention.time=30d'  # Down from 90d

# Restart
docker-compose restart prometheus

# Old data will be pruned (wait 30+ min)
```

**Solution C: Add More Storage**
```bash
# Mount additional volume
# Edit docker-compose.yml:
volumes:
  postgres-data:
    driver: local
  postgres-backup:  # NEW
    driver: local

# Restart
docker-compose up -d

# Move data to new volume
docker-compose exec postgres cp -r /var/lib/postgresql/data/* /backup/
```

---

### 5.3: Out of Memory (OOM) Kills

**Symptoms**:
- Service killed with "Exit code 137"
- Logs: "Killed" (no error message)
- Random service crashes

**Diagnosis**:
```bash
# Check kernel logs for OOM kill
dmesg | tail -50

# Check memory limits
docker inspect code-server | jq '.[0].HostConfig.Memory'

# Monitor memory realtime
watch 'free -h && docker stats --no-stream | grep -E "NAME|MEMORY"'

# Check which container is growing
docker stats --no-stream --all
```

**Solutions**:

**Solution A: Increase Memory Limit**
```bash
# Edit docker-compose.yml
code-server:
  deploy:
    resources:
      limits:
        memory: 16g  # Up from 8g

docker-compose down
docker-compose up -d

# Verify
docker inspect code-server | jq '.[0].HostConfig.Memory'
```

**Solution B: Add System Swap**
```bash
# Create swap (temporary, not permanent fix)
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Check swap
free -h

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**Solution C: Reduce Service Count**
```bash
# If running full stack (monitoring + tracing + AI):
# Run core only
COMPOSE_PROFILES= docker-compose up -d

# Re-add profiles gradually
COMPOSE_PROFILES=monitoring docker-compose up -d
```

---

### 5.4: Slow Performance (>5 sec response time)

**Symptoms**:
- IDE slow to load/respond
- API calls taking >1 second
- Dashboards take >5 seconds to load

**Diagnosis**:
```bash
# Measure response time
time curl -sk https://localhost:8080/ > /dev/null
# Record "real" time

# Check network latency
ping 192.168.168.31

# Check service latency
curl -w "@curl-time-format.txt" -o /dev/null -s https://localhost/

# Check database query time
docker-compose exec postgres psql -U postgres -d synapse_db -c "EXPLAIN ANALYZE SELECT * FROM events LIMIT 10;"

# Check Prometheus scrape duration
curl -sk https://localhost:9090/api/v1/targets | jq '.data | map(select(.job=="synapse")) | .[0].scrapePool.samples'
```

**Solutions**:

**Solution A: Network Latency Issue**
```bash
# Measure ping time
ping -c 10 192.168.168.31 | grep "min/avg/max"

# Should be < 5ms for local network
# If higher: network issue, not application

# Test DNS resolution time
time nslookup code-server.example.com

# Should be < 100ms
# If higher: DNS slow, check /etc/resolv.conf
```

**Solution B: Reverse Proxy Bottleneck**
```bash
# Check Caddy status
docker-compose logs caddy | tail -20

# Check if Caddy is proxying correctly
curl -v https://localhost:8080/

# Measure direct vs proxied
time curl -sk http://localhost:8080/ > /dev/null  # Direct
time curl -sk https://localhost/ide > /dev/null    # Via Caddy

# If proxied much slower: Caddy issue
# Restart Caddy
docker-compose restart caddy
```

**Solution C: Database Query Slow**
```bash
# Identify slow query
docker-compose exec postgres psql -U postgres -d synapse_db -c "SELECT mean_exec_time, query FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 3;"

# Example: slow query on large table
# Add index
docker-compose exec postgres psql -U postgres -d synapse_db -c "CREATE INDEX idx_events_user_id ON events(user_id);"

# Check if index used
docker-compose exec postgres psql -U postgres -d synapse_db -c "EXPLAIN (ANALYZE) SELECT * FROM events WHERE user_id='@user:example.com';"
# Should show "Index Scan", not "Seq Scan"
```

---

## Section 6: Network & Routing Issues

### 6.1: 502 Bad Gateway Error

**Symptoms**:
- "502 Bad Gateway" in browser
- All requests to IDE returning 502
- Reverse proxy error logs

**Diagnosis**:
```bash
# Check Caddy health
docker-compose ps caddy

# Check Caddy logs
docker-compose logs caddy | tail -50

# Check if upstream (code-server) is running
docker-compose ps code-server

# Test direct connection to code-server
curl -sk http://code-server:8080/ | head

# Test through Caddy
curl -sk https://localhost/ | head

# Check Caddy configuration
cat Caddyfile | grep -A5 code-server
```

**Solutions**:

**Solution A: Upstream Service Down**
```bash
# If code-server not running
docker-compose up -d code-server

# Wait for healthy status
docker-compose ps code-server

# Try again
curl -sk https://localhost/
```

**Solution B: Network Connectivity Issue**
```bash
# Check network connectivity between Caddy and upstream
docker-compose exec caddy ping code-server
# Should respond with times

# If no response: network issue
# Check docker networks
docker network ls
docker network inspect code-server-enterprise_default

# If service on different network, update Caddy config
# Caddyfile should reference correct network
```

**Solution C: Caddy Configuration Error**
```bash
# Validate Caddyfile syntax
docker-compose exec caddy caddy validate --config /etc/caddy/Caddyfile

# If syntax error: fix Caddyfile

# Check reverse proxy rules
docker-compose exec caddy cat /etc/caddy/Caddyfile | grep -A5 "reverse_proxy"

# Restart Caddy to apply changes
docker-compose restart caddy
```

---

## Section 7: Data & Backup Issues

### 7.1: Missing Files / Data Loss

**Symptoms**:
- Files edited before are gone
- Database queries return empty
- Workspace state lost

**Diagnosis**:
```bash
# Check if backup exists
ls -lh /var/lib/backups/

# Check database contents
docker-compose exec postgres psql -U postgres -d synapse_db -c "SELECT COUNT(*) FROM events;"

# Check file storage
docker volume inspect code-server-workspace | jq '.[0].Mountpoint'
ls -la <mount-point>

# Check if volume was deleted
docker volume ls | grep -i workspace
```

**Solutions**:

**Solution A: Restore from Backup**
```bash
# List available backups
ls -lh /var/lib/backups/synapse-backup-*.sql.gz | tail -5

# Restore from latest backup
docker-compose down

# Restore database
gunzip -c /var/lib/backups/synapse-backup-$(date +%Y%m%d).sql.gz | \
  docker-compose exec -T postgres psql -U postgres

# Restart services
docker-compose up -d

# Verify data restored
docker-compose exec postgres psql -U postgres -d synapse_db -c "SELECT COUNT(*) FROM events;"
```

**Solution B: Files in Workspace Volume**
```bash
# Check if volume still exists
docker volume inspect code-server-workspace

# If exists, mount to temp container and copy out
docker run --rm -v code-server-workspace:/data alpine:latest find /data -type f

# If doesn't exist, check if renamed
docker volume ls | grep workspace

# If lost, restore from backup location (if NAS backup exists)
```

**Solution C: Accidental Delete**
```bash
# Check recycle bin / trash (if filesystem supports it)
ls -la /path/to/volume/.Trash-1000/

# If file in trash, restore
mv /path/to/volume/.Trash-1000/file.txt /path/to/volume/

# Check filesystem snapshots (if LVM/ZFS)
zfs list -t snapshot
zfs rollback <snapshot>
```

---

## Section 8: Security Issues

### 8.1: Suspicious Activity Detected

**Symptoms**:
- Unexpected login attempts in logs
- Unknown user accessing system
- Unusual traffic patterns

**Diagnosis**:
```bash
# Check OAuth logs
docker-compose logs oauth2-proxy | grep -i "error\|unauthorized" | tail -20

# Check audit logs
docker-compose exec postgres psql -U postgres -d synapse_db \
  -c "SELECT * FROM audit_log WHERE created_at > NOW() - INTERVAL '1 hour' ORDER BY created_at DESC LIMIT 20;"

# Check auth failures
docker-compose logs code-server | grep -i "failed\|unauthorized"

# Check network traffic (if netstat available)
netstat -tuln | grep ESTABLISHED
```

**Solutions**:

**Solution A: Failed Login Attempts**
```bash
# Review audit log for pattern
docker-compose exec postgres psql -U postgres -d synapse_db \
  -c "SELECT user_id, COUNT(*) FROM audit_log WHERE action='login_failed' GROUP BY user_id ORDER BY COUNT DESC;"

# If repeated attempts from same user:
# 1. Contact user (may have lost password)
# 2. Reset password via admin console
# 3. Monitor for further attempts

# Block if malicious:
# Add to firewall rules (IP-level)
sudo iptables -A INPUT -s <malicious-ip> -j DROP
```

**Solution B: Compromised Credentials**
```bash
# If user account compromised:
# 1. Force password reset
docker-compose exec postgres psql -U postgres -d synapse_db \
  -c "UPDATE users SET password_reset_required=true WHERE username='username';"

# 2. Revoke active sessions
docker-compose exec redis redis-cli -a "${REDIS_PASSWORD}" DEL session:username:*

# 3. Review audit log for unauthorized actions
docker-compose exec postgres psql -U postgres -d synapse_db \
  -c "SELECT * FROM audit_log WHERE user_id='username' AND created_at > NOW() - INTERVAL '24 hours';"

# 4. Assess damage (files modified, data leaked)
```

**Solution C: DDoS/Abuse**
```bash
# If under DDoS attack:
# 1. Block source IPs
sudo iptables -A INPUT -s <attacker-ip> -j DROP

# 2. Rate limit in Caddy
# Edit Caddyfile:
@high_load {
  header User-Agent *bot*
}
handle @high_load {
  rate_limit 10/s
}

docker-compose restart caddy

# 3. Enable fail2ban (if available)
fail2ban-client set sshd banip <attacker-ip>

# 4. Check logs for impact
docker-compose logs caddy | grep -c "429"  # Rate limited requests
```

---

## Emergency Procedures

### Emergency: Complete System Failure

**If everything is down:**

```bash
# 1. Verify host is accessible
ping 192.168.168.31

# 2. SSH to host
ssh akushnir@192.168.168.31

# 3. Check basic system health
top
free -h
df -h

# 4. Restart Docker daemon
sudo systemctl restart docker

# 5. Bring up critical services first
cd code-server-enterprise
docker-compose up -d postgres redis

# 6. Wait for dependencies
sleep 30

# 7. Bring up remaining services
docker-compose up -d

# 8. Verify recovery
docker-compose ps

# 9. Test critical functionality
curl -sk https://localhost:8080/healthz
```

**If data is lost:**
```bash
# Restore from backup
gunzip -c /var/lib/backups/synapse-backup-latest.sql.gz | \
  docker-compose exec -T postgres psql -U postgres

# Verify restore
docker-compose exec postgres psql -U postgres -d synapse_db \
  -c "SELECT COUNT(*) FROM events;"
```

### Emergency: Security Breach

```bash
# 1. Isolate system
# Restrict network access to known IPs only
sudo iptables -F  # Flush rules
sudo iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT
sudo iptables -A INPUT -j DROP

# 2. Backup evidence
cp -r /var/log /var/log.backup-$(date +%Y%m%d)

# 3. Rotate all credentials
# - Update OAuth client secret
# - Reset database password
# - Regenerate all API keys

# 4. Restart clean
docker-compose down -v  # Be careful - removes volumes!
# OR if data backup exists:
# Restore from backup first

# 5. Monitor closely
tail -f docker-compose logs oauth2-proxy code-server

# 6. Notify stakeholders
```

---

## Getting Help

### When to Escalate

Contact infrastructure team if:
- Issue persists after 15 minutes of troubleshooting
- Needs root access (iptables, systemd, etc.)
- Involves database recovery
- Security concern (potential breach)
- Multiple services failing simultaneously

### Information to Provide

When reporting issue:
```bash
# 1. Symptoms
"Cannot login - OAuth redirect fails"

# 2. Error messages
docker-compose logs oauth2-proxy | grep -i error | tail

# 3. Service status
docker-compose ps

# 4. System health
free -h
df -h
docker stats --no-stream

# 5. Reproduction steps
"1. Navigate to https://localhost/
 2. Click login
 3. Stuck on Google OAuth page"

# 6. Recent changes
git log --oneline -10
```

---

**Document Version**: 1.0  
**Last Updated**: April 20, 2026  
**Status**: Ready for production use  
**Next Review**: May 20, 2026
