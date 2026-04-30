# PHASE 2B WEEK1 RAPID RESPONSE TROUBLESHOOTING GUIDE

**Purpose:** Quick reference for 20+ common issues teams may encounter during Week 1-3 deployment  
**Audience:** Infrastructure Lead, Operations Lead, QA Lead, Monitoring Lead
**Usage:** Consult before escalating to CTO
**Escalation:** If troubleshooting doesn't resolve within 30 minutes → escalate to Operations Lead → CTO

---

## 🔧 ISSUE CATEGORIES

1. SSH/Network Connectivity (5 issues)
2. Docker & Containers (4 issues)
3. PostgreSQL & Replication (3 issues)
4. Redis & Cache (2 issues)
5. HA & Failover (2 issues)
6. Monitoring & Alerting (3 issues)
7. Performance & Resource (2 issues)

---

# 1️⃣ SSH & NETWORK CONNECTIVITY ISSUES

## Issue 1.1: SSH Connection Timeout to PRIMARY (192.168.168.31)

**Symptom:** `ssh: connect to host 192.168.168.31 port 22: Connection timed out`

**Root Causes:**
- Network routing issue
- SSH daemon not running on PRIMARY
- Firewall blocking port 22

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Check local network connectivity
ping -c 3 192.168.168.31
# If no response, check network cable / VPN connection

# Step 2: Check SSH service on PRIMARY (if you have console access)
# or check via REPLICA:
ssh ubuntu@192.168.168.42 "ping -c 1 192.168.168.31"

# Step 3: Check if REPLICA can reach PRIMARY
ssh ubuntu@192.168.168.42 "ssh ubuntu@192.168.168.31 echo 'OK' 2>&1 | head -1"

# Step 4: Verify SSH daemon is running on PRIMARY
ps aux | grep sshd
```

**Resolution:**
- **If REPLICA can reach PRIMARY but you can't:** Network routing issue on your local machine - contact network team
- **If REPLICA cannot reach PRIMARY:** PRIMARY network failure - escalate to Infrastructure Lead
- **If SSH daemon not responding:** SSH may have crashed - restart it or reboot PRIMARY

**Escalation Time:** If unresolved after 10 minutes → Infrastructure Lead

---

## Issue 1.2: SSH Connection Refused to REPLICA (192.168.168.42)

**Symptom:** `ssh: connect to host 192.168.168.42 port 22: Connection refused`

**Root Causes:**
- SSH daemon crashed
- Port 22 not listening
- Network configuration issue

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Test connectivity from PRIMARY
ssh ubuntu@192.168.168.31 "ping -c 1 192.168.168.42"

# Step 2: Check if REPLICA SSH is responding
ssh ubuntu@192.168.168.31 "nc -zv 192.168.168.42 22"
# Expected: Connection successful

# Step 3: If nc fails, SSH daemon may be crashed
ssh ubuntu@192.168.168.31 "docker exec [container_name] systemctl restart ssh"
```

**Resolution:**
- If PRIMARY can't reach REPLICA → REPLICA network interface down - reboot REPLICA
- If nc connection successful but ssh fails → SSH daemon issue - restart sshd
- If all else fails → REPLICA may have kernel panic - check logs and reboot

**Escalation Time:** If unresolved after 15 minutes → Infrastructure Lead

---

## Issue 1.3: High Network Latency Between Nodes (>20ms)

**Symptom:** Replication lag high, commands slow, monitoring shows latency spikes

**Root Causes:**
- Network congestion
- Physical switch issues
- Routing problem

**Quick Verification (5 minutes):**

```bash
# Check latency PRIMARY to REPLICA
ssh ubuntu@192.168.168.31 "ping -c 10 192.168.168.42 | grep avg"
# Expected: avg <5ms

# Check latency REPLICA to PRIMARY
ssh ubuntu@192.168.168.42 "ping -c 10 192.168.168.31 | grep avg"

# Check packet loss
ssh ubuntu@192.168.168.31 "ping -c 100 192.168.168.42 | grep '%'"
# Expected: 0% packet loss
```

**Resolution:**
- **Consistent high latency:** Likely network design issue - contact network team
- **Sporadic spikes:** Possible congestion - monitor traffic on network switch
- **One direction high, other normal:** Check routing on the affected node

**Escalation Time:** Document baseline and anomalies, escalate to network team if consistent

---

## Issue 1.4: DNS Resolution Failing

**Symptom:** `nslookup gitlab.example.com` fails or resolves to wrong IP

**Root Causes:**
- DNS server down
- DNS cache stale
- DNS record doesn't exist

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Test DNS resolution
nslookup gitlab.example.com

# Step 2: Try alternate DNS
nslookup gitlab.example.com 8.8.8.8

# Step 3: Check DNS record
dig gitlab.example.com +short

# Step 4: Flush local DNS cache
sudo systemctl restart systemd-resolved

# Step 5: Check DNS TTL
dig gitlab.example.com | grep TTL
```

**Resolution:**
- If alternate DNS works → Update local DNS config
- If record doesn't exist → Create DNS record pointing to VIP (192.168.168.50)
- If TTL too high → Wait for expiry or manually flush cache

---

## Issue 1.5: Network Interface Down

**Symptom:** `eth0` or network interface not responding, no connectivity

**Root Causes:**
- Interface misconfigured
- Driver issue
- Physical cable disconnected

**Quick Troubleshooting (5 minutes):**

```bash
# Check interface status
ip link show

# Check if specific interface down
ssh ubuntu@192.168.168.31 "ip link show eth0"

# Restart interface
ssh ubuntu@192.168.168.31 "sudo ip link set eth0 down && sudo ip link set eth0 up"

# Check IP assigned
ssh ubuntu@192.168.168.31 "ip addr show eth0"
```

**Resolution:**
- If interface down → Restart with `ip link set` commands
- If no IP assigned → Check DHCP or static config
- If physical cable issue → Reseat cable or replace

---

# 2️⃣ DOCKER & CONTAINER ISSUES

## Issue 2.1: Docker Daemon Not Running

**Symptom:** `Cannot connect to Docker daemon` or `docker: permission denied`

**Root Causes:**
- Docker service crashed
- Docker socket permissions issue
- Daemon failed to start

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Check Docker status
ssh ubuntu@192.168.168.31 "systemctl status docker | head -5"

# Step 2: If not running, start it
ssh ubuntu@192.168.168.31 "sudo systemctl start docker"

# Step 3: Verify start was successful
ssh ubuntu@192.168.168.31 "sudo systemctl status docker | grep Active"
# Expected: Active: active (running)

# Step 4: Test docker command
ssh ubuntu@192.168.168.31 "docker ps | head -2"
```

**Resolution:**
- If `systemctl start docker` succeeds → Docker is back online
- If start fails → Check Docker logs: `journalctl -u docker -n 50`
- If permission denied → Add user to docker group: `sudo usermod -aG docker ubuntu`

**Escalation Time:** If unresolved after 10 minutes → Infrastructure Lead

---

## Issue 2.2: Container Exited Unexpectedly

**Symptom:** `docker ps` shows container with `Exited (X)` status

**Root Causes:**
- Application crash
- Out of memory
- Dependency failure (DB, network)
- Health check failure

**Quick Troubleshooting (10 minutes):**

```bash
# Step 1: Identify exited container
ssh ubuntu@192.168.168.31 "docker ps -a | grep Exited"

# Step 2: Check container logs
ssh ubuntu@192.168.168.31 "docker logs --tail 50 [container_name]"

# Step 3: Check exit code
ssh ubuntu@192.168.168.31 "docker ps -a --filter 'status=exited' --format 'table {{.Names}}\t{{.Status}}' | grep [container_name]"

# Step 4: Check system resources
ssh ubuntu@192.168.168.31 "free -h && df -h /"

# Step 5: Restart container
ssh ubuntu@192.168.168.31 "docker restart [container_name]"
```

**Resolution by Exit Code:**
- **Exit 1:** Application error - check logs and fix configuration
- **Exit 137:** Out of memory - increase Docker memory limit or reduce containers
- **Exit 139:** Segmentation fault - likely application bug - escalate to dev team
- **Other:** Escalate with logs to Infrastructure Lead

**Escalation Time:** If restart doesn't fix within 5 minutes → Infrastructure Lead

---

## Issue 2.3: Out of Disk Space on Container

**Symptom:** `docker: no space left on device` or `Write failed: No space left on device`

**Root Causes:**
- Docker overlay filesystem full
- Container logs taking up space
- Unused images/containers consuming space

**Quick Troubleshooting (10 minutes):**

```bash
# Step 1: Check available disk space
ssh ubuntu@192.168.168.31 "df -h / | tail -1"
# If <5GB available, disk is full

# Step 2: Find large files
ssh ubuntu@192.168.168.31 "du -sh /var/lib/docker/* 2>/dev/null"

# Step 3: Clean up Docker
ssh ubuntu@192.168.168.31 "docker system prune -a --volumes"

# Step 4: Check logs
ssh ubuntu@192.168.168.31 "du -sh /var/lib/docker/containers/*/[container-id]/*-json.log"

# Step 5: Truncate large logs
ssh ubuntu@192.168.168.31 "truncate -s 0 /var/lib/docker/containers/[container-id]/*-json.log"
```

**Resolution:**
- Clean up unused Docker artifacts first
- Truncate large logs
- If still full, expand storage (requires infrastructure changes)

**Escalation Time:** If unresolved after 15 minutes → Infrastructure Lead

---

## Issue 2.4: Docker Image Pull Timeout

**Symptom:** `docker pull [image]` hangs or times out

**Root Causes:**
- Registry unreachable
- Network bandwidth issue
- Registry service down

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Check connectivity to registry
curl -I https://registry.gitlab.com/v2/

# Step 2: Check image exists
curl -I https://registry.gitlab.com/v2/kushin77/phase2b/[image_name]/manifests/[tag]

# Step 3: Manually pull with verbose output
ssh ubuntu@192.168.168.31 "docker pull --verbose registry.gitlab.com/kushin77/phase2b/[image]:[tag] 2>&1 | tail -20"

# Step 4: Check network bandwidth
speedtest-cli
```

**Resolution:**
- If registry unreachable → Check Internet connectivity and DNS
- If pull slow → Wait longer (>15 minutes for 5GB+)
- If consistently fails → Image may not exist - verify tag name

**Escalation Time:** If >30 minutes for single image pull → Infrastructure Lead

---

# 3️⃣ POSTGRESQL & REPLICATION ISSUES

## Issue 3.1: Replication Lag > 5 seconds

**Symptom:** `Replication lag: 10 seconds` shown in monitoring

**Root Causes:**
- High write volume on PRIMARY
- REPLICA CPU/disk overloaded
- Network latency

**Quick Diagnosis (5 minutes):**

```bash
# Step 1: Check replication status on PRIMARY
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT client_addr, state, sync_state, write_lag FROM pg_stat_replication;'"

# Step 2: Check REPLICA lag directly
ssh ubuntu@192.168.168.42 "docker exec gitlab_db psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (now() - pg_last_wal_receive_lsn_time())) as lag_seconds;'"

# Step 3: Check REPLICA CPU/Memory
ssh ubuntu@192.168.168.42 "top -n1 -b | head -10"

# Step 4: Check disk I/O
ssh ubuntu@192.168.168.42 "iostat -x 1 2"
```

**Resolution:**
- **If PRIMARY is writing heavily:** This is expected during initial data load - monitor
- **If REPLICA CPU high:** Reduce other workloads or increase CPU allocation
- **If REPLICA I/O high:** Increase disk speed or reduce write volume
- **If network lag high:** See Issue 1.3

**Action:** If lag consistently <10s, acceptable. If >30s, escalate to Infrastructure Lead.

---

## Issue 3.2: Replication Connection Broken

**Symptom:** `pg_stat_replication` shows no rows or `sync_state = 'potential'`

**Root Causes:**
- REPLICA crashed
- Network broken between nodes
- Replication configuration error

**Quick Troubleshooting (10 minutes):**

```bash
# Step 1: Verify REPLICA is running
ssh ubuntu@192.168.168.42 "docker ps | grep gitlab_db"

# Step 2: Check PostgreSQL logs on REPLICA
ssh ubuntu@192.168.168.42 "docker logs gitlab_db 2>&1 | tail -20"

# Step 3: Verify network connectivity
ssh ubuntu@192.168.168.31 "nc -zv 192.168.168.42 5432"

# Step 4: Restart PostgreSQL on REPLICA
ssh ubuntu@192.168.168.42 "docker restart gitlab_db"

# Step 5: Verify replication reconnected
sleep 10
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT count(*) FROM pg_stat_replication;'"
```

**Resolution:**
- If REPLICA not running → Restart Docker and PostgreSQL
- If network down → Check network configuration
- If logs show auth error → Check credentials
- After restart, verify 5 passes → Replication restored

**Escalation Time:** If replication doesn't restore after restart within 5 minutes → Infrastructure Lead

---

## Issue 3.3: PostgreSQL Won't Start

**Symptom:** `docker ps` shows db container exited or startup errors

**Root Causes:**
- Corrupted data files
- Incompatible configuration
- Disk full

**Quick Troubleshooting (15 minutes):**

```bash
# Step 1: Check logs
ssh ubuntu@192.168.168.31 "docker logs --tail 100 gitlab_db | grep -i error"

# Step 2: Check disk space
ssh ubuntu@192.168.168.31 "df -h /var/lib/docker/volumes/gitlab_db_data/_data"

# Step 3: Try restarting
ssh ubuntu@192.168.168.31 "docker restart gitlab_db"
sleep 10
ssh ubuntu@192.168.168.31 "docker ps | grep gitlab_db"

# Step 4: Check recovery logs
ssh ubuntu@192.168.168.31 "docker logs gitlab_db 2>&1 | grep -i recovery"
```

**Resolution:**
- **Disk full:** Free up space (see Issue 2.3)
- **Corrupted data:** May need restore from backup - escalate to DBA
- **Configuration error:** Check postgresql.conf for syntax errors

**Escalation Time:** If restart doesn't work within 10 minutes → DBA/Infrastructure Lead

---

# 4️⃣ REDIS & CACHE ISSUES

## Issue 4.1: Redis Connection Refused

**Symptom:** `redis-cli: Can't connect to Redis` or connection timeout

**Root Causes:**
- Redis not running
- Port 6379 not listening
- Network issue

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Check Redis container
ssh ubuntu@192.168.168.31 "docker ps | grep redis"

# Step 2: Check if running
ssh ubuntu@192.168.168.31 "docker ps -a | grep gitlab_redis"

# Step 3: Start if stopped
ssh ubuntu@192.168.168.31 "docker start gitlab_redis"

# Step 4: Test connectivity
ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli PING"
# Expected: PONG

# Step 5: Check port
ssh ubuntu@192.168.168.31 "docker port gitlab_redis"
```

**Resolution:**
- If not running → Start container
- If PING fails → Check logs: `docker logs gitlab_redis | tail -20`
- If port not mapped → Recreate container with correct port mapping

**Escalation Time:** If unresolved after 10 minutes → Infrastructure Lead

---

## Issue 4.2: Redis Memory Full

**Symptom:** `OOM command not allowed when used memory > 'maxmemory'.` or cache performance degraded

**Root Causes:**
- maxmemory limit too low
- Cache not evicting old data
- Memory leak in application

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Check memory usage
ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli INFO memory | grep used"

# Step 2: Check maxmemory policy
ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli CONFIG GET maxmemory"

# Step 3: Check keys count
ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli DBSIZE"

# Step 4: Flush old data
ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli FLUSHDB ASYNC"

# Step 5: Increase maxmemory in config
# Edit docker-compose file and set: -c maxmemory 8gb
```

**Resolution:**
- If ASYNC FLUSH works → Memory is back online
- If maxmemory too low → Increase it
- If persistent → May need external caching or optimize application

**Escalation Time:** If unresolved after 10 minutes → Operations Lead

---

# 5️⃣ HA & FAILOVER ISSUES

## Issue 5.1: VIP Not Responding

**Symptom:** `ping 192.168.168.50` fails or times out

**Root Causes:**
- Keepalived crashed
- Both PRIMARY and REPLICA down
- Network routing issue

**Quick Troubleshooting (10 minutes):**

```bash
# Step 1: Check Keepalived on PRIMARY
ssh ubuntu@192.168.168.31 "docker ps | grep keepalived"

# Step 2: Check Keepalived status
ssh ubuntu@192.168.168.31 "docker exec gitlab_keepalived systemctl status keepalived"

# Step 3: Check VRRP status
ssh ubuntu@192.168.168.31 "docker exec gitlab_keepalived ip addr show | grep 192.168.168.50"

# Step 4: Check logs
ssh ubuntu@192.168.168.31 "docker logs gitlab_keepalived 2>&1 | tail -30"

# Step 5: Check REPLICA Keepalived
ssh ubuntu@192.168.168.42 "docker ps | grep keepalived"
```

**Resolution:**
- If Keepalived not running → Start it: `docker start gitlab_keepalived`
- If logs show BACKUP state everywhere → One node must take MASTER - check priority
- If both show MASTER → VRRP split brain - restart both keepalived services
- If VIP still doesn't respond → Network configuration issue

**Escalation Time:** If unresolved after 15 minutes → Infrastructure Lead

---

## Issue 5.2: Failover Not Working

**Symptom:** PRIMARY goes down but services don't fail over to REPLICA

**Root Causes:**
- Keepalived not configured for failover
- REPLICA not in BACKUP state
- Network misconfiguration

**Quick Troubleshooting (10 minutes):**

```bash
# Step 1: Verify REPLICA is in BACKUP state
ssh ubuntu@192.168.168.42 "docker exec gitlab_keepalived systemctl status keepalived | grep BACKUP"

# Step 2: Simulate PRIMARY failure
ssh ubuntu@192.168.168.31 "docker stop gitlab_keepalived"

# Step 3: Monitor REPLICA
ssh ubuntu@192.168.168.42 "watch -n1 'docker exec gitlab_keepalived ip addr show | grep 192.168.168.50'"

# Step 4: Verify VIP works on REPLICA
ping -c 1 192.168.168.50

# Step 5: Restart PRIMARY Keepalived
ssh ubuntu@192.168.168.31 "docker start gitlab_keepalived"
```

**Resolution:**
- If failover works → Issue was transient, document and monitor
- If REPLICA doesn't take VIP → Check keepalived config
- If failover takes >30 seconds → Normal for Keepalived, acceptable
- If failover never happens → Critical issue, escalate immediately

**Escalation Time:** If failover doesn't occur within 30 seconds of PRIMARY failure → CTO

---

# 6️⃣ MONITORING & ALERTING ISSUES

## Issue 6.1: Prometheus Scrape Failing

**Symptom:** `Prometheus: X targets down` or alerts show `[Unknown]` values

**Root Causes:**
- Target endpoint down
- Network connectivity issue
- Target configuration wrong

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Check Prometheus targets
curl -s http://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down")'

# Step 2: Test individual target manually
curl http://192.168.168.31:9187/metrics | head -20

# Step 3: Check Prometheus config
ssh ubuntu@192.168.168.31 "docker exec prometheus cat /etc/prometheus/prometheus.yml | grep -A5 'scrape_configs'"

# Step 4: Reload Prometheus config
curl -X POST http://192.168.168.31:9090/-/reload
```

**Resolution:**
- If target down → Restart the service exporting metrics
- If endpoint changed → Update prometheus.yml and reload
- If network issue → Check connectivity to target
- After fix, targets should report `health="up"` within 1 minute

**Escalation Time:** If >5 targets down → Escalate to Monitoring Lead

---

## Issue 6.2: Grafana Dashboard Not Updating

**Symptom:** Grafana dashboard shows stale data or `No data` in graphs

**Root Causes:**
- Prometheus not scraping
- Dashboard query wrong
- Data source misconfigured

**Quick Troubleshooting (5 minutes):**

```bash
# Step 1: Check Prometheus is running
curl -s http://192.168.168.31:9090/-/healthy

# Step 2: Test query manually
curl -s 'http://192.168.168.31:9090/api/v1/query?query=up'

# Step 3: Check Grafana data source
curl -s -H "Authorization: Bearer [API_KEY]" http://192.168.168.31:3000/api/datasources

# Step 4: Refresh Grafana dashboard
# Go to dashboard → refresh button (top-right)
```

**Resolution:**
- If Prometheus down → Restart it
- If data source unreachable → Check URL and network
- If query wrong → Fix PromQL syntax
- After fix, graphs should update within 15-60 seconds

**Escalation Time:** If dashboard still empty after 5 minutes → Monitoring Lead

---

## Issue 6.3: AlertManager Not Sending Alerts

**Symptom:** `AlertManager shows alerts but no notifications received` (Slack/Email)

**Root Causes:**
- Alert routing misconfigured
- Notification channel down
- Credentials wrong

**Quick Troubleshooting (10 minutes):**

```bash
# Step 1: Check active alerts in AlertManager
curl http://192.168.168.31:9093/api/v1/alerts

# Step 2: Check AlertManager config
ssh ubuntu@192.168.168.31 "docker exec alertmanager cat /etc/alertmanager/config.yml"

# Step 3: Test Slack webhook (if using Slack)
curl -X POST [SLACK_WEBHOOK_URL] -d '{"text":"Test alert"}'

# Step 4: Check AlertManager logs
ssh ubuntu@192.168.168.31 "docker logs alertmanager 2>&1 | tail -50"
```

**Resolution:**
- If Slack webhook invalid → Update with correct URL
- If routing rule wrong → Update config.yml and reload
- If credentials expired → Refresh credentials
- Test alert manually to verify chain works

**Escalation Time:** If alerts still not sending after 10 minutes → Monitoring Lead

---

# 7️⃣ PERFORMANCE & RESOURCE ISSUES

## Issue 7.1: High CPU Usage on PRIMARY

**Symptom:** `top` shows CPU >80%, application slow

**Root Causes:**
- High query load
- Inefficient query
- Too many containers

**Quick Troubleshooting (10 minutes):**

```bash
# Step 1: Check CPU usage
ssh ubuntu@192.168.168.31 "top -n1 -b | head -20"

# Step 2: Identify process using CPU
ssh ubuntu@192.168.168.31 "ps aux --sort=-%cpu | head -10"

# Step 3: Check if specific container using CPU
ssh ubuntu@192.168.168.31 "docker stats --no-stream | sort -k3 -r"

# Step 4: Check database load
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT * FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 5;'"

# Step 5: Monitor over time
ssh ubuntu@192.168.168.31 "iostat -x 1 5"
```

**Resolution:**
- If specific query high → Optimize query or add index
- If container using too much → Restart container or reduce load
- If system-wide → Reduce number of concurrent connections
- Monitor baseline after fixes to verify improvement

**Escalation Time:** If CPU stays >90% for >5 minutes → Infrastructure Lead

---

## Issue 7.2: Out of Memory on PRIMARY

**Symptom:** `free -h` shows <1GB available, services slow or crash

**Root Causes:**
- Container memory limits too low
- Memory leak in application
- Too many containers

**Quick Troubleshooting (10 minutes):**

```bash
# Step 1: Check memory status
ssh ubuntu@192.168.168.31 "free -h"

# Step 2: Check memory by container
ssh ubuntu@192.168.168.31 "docker stats --no-stream | sort -k4 -r"

# Step 3: Check for memory leaks
ssh ubuntu@192.168.168.31 "docker stats --no-stream gitlab_unicorn | tail -1"

# Step 4: Check swap usage
ssh ubuntu@192.168.168.31 "free -h | grep Swap"

# Step 5: Restart high-memory container
ssh ubuntu@192.168.168.31 "docker restart gitlab_unicorn"
```

**Resolution:**
- If specific container using too much → Increase limit or optimize application
- If swap high → Reduce workload or add physical memory
- If restart helps → Schedule periodic restarts
- Monitor memory trend - if keeps rising, deeper investigation needed

**Escalation Time:** If OOM kills processes → Infrastructure Lead

---

# 📊 QUICK REFERENCE MATRIX

| Issue | First Check | Quick Fix | Escalate If |
|-------|------------|----------|------------|
| **SSH timeout** | `ping 192.168.168.31` | Check network | No response in 2 attempts |
| **Docker down** | `systemctl status docker` | `systemctl start docker` | Still down after restart |
| **Replication lag >30s** | Check REPLICA CPU/disk | Reduce workload | Lag >60s for 5 min |
| **Replication broken** | `docker restart gitlab_db` | Restart DB | Still broken after restart |
| **VIP not responding** | Check Keepalived PRIMARY | Start Keepalived | Still down after 5 min |
| **Failover failing** | Check REPLICA Keepalived | Verify BACKUP state | Failover doesn't happen in 30s |
| **Prometheus targets down** | `curl` test endpoint | Restart service | >5 targets down |
| **Grafana stale data** | Test Prometheus query | Check datasource | Still stale after 5 min |
| **High CPU >80%** | Identify process `ps aux --sort=-%cpu` | Optimize query | CPU stays >90% for 5 min |
| **OOM memory full** | Check container usage | Increase limits/restart | Still OOM after restart |

---

# 🛑 EMERGENCY PROCEDURES

**If Multiple Services Down:**
1. Check Prometheus/Grafana dashboard for system health
2. Run health checks on both nodes (docker ps, ping, systemctl)
3. If PRIMARY down → Trigger failover (stop Keepalived on PRIMARY)
4. If both nodes down → Page on-call engineer immediately
5. Reference: PHASE_2B_CONTINGENCY_ROLLBACK_PROCEDURES.md

**If Critical System Unresponsive:**
1. Do NOT immediately reboot (data loss risk)
2. Collect logs: `docker logs [service] > /tmp/debug.log`
3. Verify backup exists and is recent
4. Consult with DBA before any destructive action
5. Escalate to CTO for approval on any recovery procedure

---

# 📞 ESCALATION CONTACTS

- **Infrastructure Lead:** [Name] [Phone]
- **Operations Lead:** [Name] [Phone]
- **Database Specialist:** [Name] [Phone]
- **Monitoring Lead:** [Name] [Phone]
- **CTO/Technical Lead:** [Name] [Phone]
- **On-Call Emergency:** [Escalation number]

---

**Last Updated:** April 30, 2026  
**Next Review:** May 5, 2026 (after Week 1 execution)

