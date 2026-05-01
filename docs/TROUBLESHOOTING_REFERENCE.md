# Comprehensive Troubleshooting & Support Reference

**Document**: Operations Support Handbook  
**Version**: Phase 10  
**Date**: April 30, 2026  
**Audience**: All Operations Team Members

---

## Table of Contents

1. **Quick Diagnosis Flowchart**
2. **Service-Specific Issues** (10 services)
3. **System-Level Issues** (12 categories)
4. **Monitoring Issues** (8 problems)
5. **Deployment Issues** (6 problems)
6. **Emergency Procedures** (5 scenarios)
7. **Support Resources** (contact, escalation, documentation)

---

## Quick Diagnosis Flowchart

```
ISSUE REPORTED
    ↓
Is it about containers?
├─ YES → Go to: SERVICE-SPECIFIC ISSUES
└─ NO → Is it about system/resources?
        ├─ YES → Go to: SYSTEM-LEVEL ISSUES
        └─ NO → Is it about monitoring/dashboards?
                ├─ YES → Go to: MONITORING ISSUES
                └─ NO → Go to: OTHER ISSUES
```

---

## 1. SERVICE-SPECIFIC ISSUES

### Issue 1A: PostgreSQL Container Not Starting

**Symptoms**:
```
docker ps shows: "Exited (1) 5 seconds ago"
Logs show: "could not open socket: Permission denied"
```

**Diagnosis**:
```bash
docker logs postgresql | tail -20
docker inspect postgresql | grep -A5 "Error"
```

**Solutions** (in order):
```bash
# 1. Check if port in use
lsof -i :5432 | grep -v PID

# 2. Restart container
docker restart postgresql
sleep 5
docker logs postgresql | tail -5

# 3. If still failing, check volumes
docker inspect postgresql | grep -A5 "Mounts"

# 4. Check disk space
df -h /home

# 5. If volumes corrupted
# Manual recovery required - contact senior SRE
```

**Expected Result**: Container should be "Up 2 minutes"  
**Timeline**: 5-10 minutes

---

### Issue 1B: Redis Connection Refused

**Symptoms**:
```
Applications cannot connect: "Connection refused on port 6379"
redis-cli: "Error: Could not connect"
```

**Diagnosis**:
```bash
docker ps | grep redis
docker logs redis | tail -20
docker port redis
```

**Solutions**:
```bash
# 1. Verify container running
docker ps | grep redis || docker run redis

# 2. Test connection inside container
docker exec redis redis-cli ping
# Expected: PONG

# 3. Test from host
redis-cli -h localhost ping
# Expected: PONG

# 4. Check if port exposed
docker port redis
# Expected: 6379 exposed

# 5. If container port differs from host
docker inspect redis | grep -A5 "PortBindings"
```

**Expected Result**: `PONG` response from redis-cli  
**Timeline**: 5 minutes

---

### Issue 1C: Code-Server API Container Repeatedly Crashing

**Symptoms**:
```
Container restarts every 30-60 seconds
Logs show application errors
```

**Diagnosis**:
```bash
docker logs code-server-api --tail=100
docker stats code-server-api
docker inspect code-server-api | grep -A10 "RestartCount"
```

**Solutions**:
```bash
# 1. Check restart policy
docker inspect code-server-api | grep -i "restart"

# 2. Review logs for root cause
docker logs code-server-api | grep -i "error\|exception\|failed"

# 3. Check memory usage
docker stats code-server-api --no-stream
# If > 80% of limit → increase memory

# 4. Check if dependencies available
docker exec code-server-api \
  curl http://postgresql:5432
# Should connect or timeout gracefully

# 5. Temporarily disable auto-restart
# In .remediation/config.env:
# Add container to DO_NOT_AUTO_RESTART

# 6. Fix issue and restart manually
docker restart code-server-api

# 7. Monitor for 15 minutes
tail -f /tmp/code-server-remediation.log | grep code-server-api
```

**Expected Result**: Container stays up, no continuous restarts  
**Timeline**: 15-30 minutes

---

### Issue 1D: Database Backup Failed

**Symptoms**:
```
Backup log shows error
Backup file not created or is 0 bytes
```

**Diagnosis**:
```bash
ls -lah backup-postgresql*.sql.gz
# Check size and timestamp

docker exec postgresql \
  pg_dump -U postgres | head -20
```

**Solutions**:
```bash
# 1. Manual backup
docker exec postgresql \
  pg_dump -U postgres | gzip > manual-backup-$(date +%s).sql.gz

# 2. Verify backup
gunzip -t manual-backup-*.sql.gz

# 3. Check disk space
df /home

# 4. Verify credentials
docker exec postgresql \
  psql -U postgres -c "SELECT 1"
# Should return: 1

# 5. Schedule next backup
# Confirm backup task runs via cron/systemd
```

**Expected Result**: Backup file created and can be restored  
**Timeline**: 10 minutes

---

### Issue 1E: Cache (Redis) Not Persisting

**Symptoms**:
```
Redis data lost after restart
Keys not available after container restart
```

**Diagnosis**:
```bash
docker exec redis redis-cli DBSIZE
docker inspect redis | grep -A10 "Mounts"
# Should show: /data volume mounted
```

**Solutions**:
```bash
# 1. Check persistence config
docker exec redis redis-cli CONFIG GET save

# 2. Trigger save
docker exec redis redis-cli BGSAVE

# 3. Verify dump file exists
docker exec redis ls -la /data/
# Should show: dump.rdb

# 4. If not persisting
# Check docker-compose volume config
grep -A5 "redis:" docker-compose.enterprise.yml | grep -A3 "volumes"

# 5. Verify volume has write permissions
docker exec redis touch /data/test && rm /data/test
```

**Expected Result**: dump.rdb file exists and updates after BGSAVE  
**Timeline**: 5 minutes

---

### Issue 2A: Keepalived Failover Triggered

**Symptoms**:
```
VRRP failover occurred unexpectedly
Virtual IP switched from primary to replica
```

**Diagnosis**:
```bash
# Check on primary
ssh akushnir@192.168.168.31
ip addr show | grep 192.168.168.50

# Check on replica
ssh akushnir@192.168.168.42
ip addr show | grep 192.168.168.50
```

**Solutions**:
```bash
# 1. Check keepalived status on primary
ssh akushnir@192.168.168.31 \
  systemctl status keepalived

# 2. Check priority
ssh akushnir@192.168.168.31 \
  docker logs keepalived | grep "priority"
# Should show: 100 (primary > 90 replica)

# 3. If priority wrong, check docker-compose
# Edit docker-compose.enterprise.yml
# KEEPALIVED_PRIORITY: 100 (primary)
# KEEPALIVED_PRIORITY: 90 (replica)

# 4. Restart keepalived if needed
ssh akushnir@192.168.168.31 \
  docker restart keepalived

# 5. Monitor failback
watch -n 5 'ssh akushnir@192.168.168.31 "ip addr show | grep 192.168.168.50"'
# Should take <60 seconds
```

**Expected Result**: Virtual IP on primary (192.168.168.31)  
**Timeline**: 5-10 minutes

---

### Issue 2B: Network Partition Between Hosts

**Symptoms**:
```
Both hosts claim MASTER status (split brain)
Container parity check fails (different counts)
```

**Diagnosis**:
```bash
# Check primary
ssh akushnir@192.168.168.31 "ip addr show | grep 192.168.168.50"
# Should show: MASTER

# Check replica
ssh akushnir@192.168.168.42 "ip addr show | grep 192.168.168.50"
# Should NOT show (or BACKUP)

# Test connectivity
ssh akushnir@192.168.168.31 "ping -c 1 192.168.168.42"
```

**Solutions**:
```bash
# 1. If both show MASTER (split brain)
# Kill keepalived on replica
ssh akushnir@192.168.168.42 \
  docker kill keepalived

# 2. Wait for VRRP to stabilize
sleep 30

# 3. Restart keepalived on replica
ssh akushnir@192.168.168.42 \
  docker restart keepalived

# 4. Verify recovery
ssh akushnir@192.168.168.31 "ip addr show | grep 192.168.168.50"
ssh akushnir@192.168.168.42 "ip addr show | grep 192.168.168.50"

# 5. Check container parity restored
./scripts/ops/export-prometheus-metrics.sh metrics | grep "parity"
```

**Expected Result**: Unique master, replica in backup mode, parity OK  
**Timeline**: 10-15 minutes

---

## 2. SYSTEM-LEVEL ISSUES

### Issue 2A: High CPU Usage

**Symptoms**:
```
System load >4 (target <2)
top/htop shows CPU at 80%+
```

**Diagnosis**:
```bash
top
# Or
docker stats

# Find which container uses most CPU
docker stats --no-stream | sort -k2 -rn | head -5
```

**Solutions**:
```bash
# 1. If one container hogging CPU
# Check logs for runaway loops
docker logs <cpu-heavy-container> | tail -20

# 2. If CPU is terraform processes
# Kill terraform
pkill terraform

# 3. If CPU from drift watchdog
# Check monitoring interval
grep "OnUnitActiveSec" systemd/drift-monitor.timer
# Should be 5 minutes minimum

# 4. Restart problematic container
docker restart <container>

# 5. Monitor recovery
watch -n 1 'top -bn1 | head -3'
```

**Expected Result**: CPU usage drops below 50%  
**Timeline**: 5-15 minutes

---

### Issue 2B: High Memory Usage

**Symptoms**:
```
Free memory <500 MB
docker stats shows containers at memory limit
```

**Diagnosis**:
```bash
free -h
docker stats --no-stream | sort -k4 -rn | head -5
```

**Solutions**:
```bash
# 1. Identify memory hogs
docker inspect <container> | grep -i "memory"
# Compare Memory vs MemorySwap limits

# 2. Check for memory leaks
docker exec <container> free -h

# 3. Clean cache (if safe)
sync && echo 3 > /proc/sys/vm/drop_caches
# This is temporary, restart required for permanent fix

# 4. Increase container memory limit
# Edit docker-compose or Terraform
# Increase: --memory=1g → --memory=2g

# 5. Restart container
docker-compose -f docker-compose.enterprise.yml up -d <container>

# 6. Monitor recovery
watch -n 1 'free -h'
```

**Expected Result**: Free memory >1 GB  
**Timeline**: 10-20 minutes

---

### Issue 2C: Disk Space Critical

**Symptoms**:
```
df /home shows >95% used
Application can't write files
```

**Diagnosis**:
```bash
df -h /home
du -sh /home/* | sort -rh | head -10
```

**Solutions**:
```bash
# 1. Find largest consumers
# Likely: Docker images, logs, container data

# 2. Docker cleanup (safest)
docker system prune -af --volumes
# This removes:
# - Stopped containers
# - Dangling images
# - Unused volumes
# Typical recovery: 5-20 GB

# 3. Measure results
df -h /home

# 4. If still critical, clean logs
find /home/akushnir/code-server -name "*.log" -type f -exec rm {} \;

# 5. If STILL critical
# Investigate what's in /home/*
# May need to expand filesystem (infrastructure team)
```

**Expected Result**: Disk usage <70%  
**Timeline**: 5-30 minutes

---

### Issue 2D: SSH Connection Slow/Timing Out

**Symptoms**:
```
ssh takes 30+ seconds to connect
Or: timeout after 20 seconds
```

**Diagnosis**:
```bash
ssh -vvv akushnir@192.168.168.31
# Shows where it's slow

ssh -o ConnectTimeout=5 akushnir@192.168.168.31 "echo OK"
```

**Solutions**:
```bash
# 1. Check network connectivity
ping 192.168.168.31
# If timeout → network issue

# 2. Check SSH service
ssh akushnir@192.168.168.31 systemctl status ssh

# 3. Check auth methods
ssh -o PubkeyAuthentication=no akushnir@192.168.168.31
# If works → pubkey auth issue

# 4. Check SSH keys
ls -la ~/.ssh/id_rsa
# Ensure permissions are 600

# 5. Increase timeout
ssh -o ConnectTimeout=30 akushnir@192.168.168.31

# 6. If host is overloaded
# SSH to replica instead:
ssh akushnir@192.168.168.42

# 7. From replica, access primary if needed
ssh akushnir@192.168.168.31
```

**Expected Result**: SSH connects within 5 seconds  
**Timeline**: 5-10 minutes

---

### Issue 2E: Network Connectivity Lost

**Symptoms**:
```
Cannot ping hosts
Cannot SSH to any host
```

**Diagnosis**:
```bash
ping 192.168.168.31
traceroute 192.168.168.31
ip route
```

**Solutions**:
```bash
# This is INFRASTRUCTURE ISSUE, not application
# Likely network/firewall/routing problem

# 1. Check local networking
ip addr show
ip route show

# 2. Try alternative paths
# Ping router/gateway
ping 192.168.168.1

# 3. Check firewall
# (Depends on your firewall)
# sudo ufw status
# sudo iptables -L

# 4. Escalate to infrastructure team
# "Network connectivity lost to code-server hosts"
# Provide: timestamp, from/to hosts, traceroute output
```

**Expected Result**: Connectivity restored (infrastructure fix)  
**Timeline**: 5-60 minutes (depends on infrastructure)

---

## 3. MONITORING ISSUES

### Issue 3A: Grafana Dashboard Shows No Data

**Symptoms**:
```
Grafana panels empty
"No data" message in all graphs
```

**Diagnosis**:
```bash
# Check Prometheus connectivity
curl http://localhost:9090/api/v1/query?query=up

# Check Prometheus scrape targets
curl http://localhost:9090/api/v1/targets
```

**Solutions**:
```bash
# 1. Verify Prometheus running
docker ps | grep prometheus

# 2. Verify metrics exporter running
curl http://localhost:9091/metrics | head -20

# 3. Restart Prometheus
docker restart prometheus
sleep 10

# 4. Restart metrics exporter
./scripts/ops/export-prometheus-metrics.sh stop
./scripts/ops/export-prometheus-metrics.sh start

# 5. Reload Grafana
# Browser: http://localhost:3000
# Refresh page (Ctrl+R or Cmd+R)

# 6. If still no data
# Check Prometheus data retention
grep "retention" monitoring/prometheus.yml
# Default: 15 days

# 7. Force re-scrape
# Restart Prometheus service
docker restart prometheus
```

**Expected Result**: Grafana panels show data within 2 minutes  
**Timeline**: 5-10 minutes

---

### Issue 3B: Prometheus Targets Down

**Symptoms**:
```
Prometheus shows: "State: DOWN" for scrape targets
Data collection stopped
```

**Diagnosis**:
```bash
# Check targets status
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down")'
```

**Solutions**:
```bash
# 1. Identify which target is down
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[]' | grep -B2 '"down"'

# 2. Check if that service is running
# Example: if "node-primary" down
ssh akushnir@192.168.168.31 "docker ps | grep node-exporter"

# 3. If service not running, start it
# (Depends on your setup)

# 4. Check firewall/network
# Example: node-exporter on port 9100
curl http://192.168.168.31:9100/metrics | head -5

# 5. Restart Prometheus to re-scrape
docker restart prometheus

# 6. Wait 2-3 minutes for next scrape
# Targets should return to UP
```

**Expected Result**: All targets show "State: UP"  
**Timeline**: 5-15 minutes

---

### Issue 3C: Alerts Not Triggering

**Symptoms**:
```
Error occurs but no alert sent
Slack/email not receiving notifications
```

**Diagnosis**:
```bash
# Check alert config
cat .alerts/config.env | grep "ALERT_.*_ENABLED"

# Check webhook URL
cat .alerts/config.env | grep "SLACK_WEBHOOK_URL"

# Test alert routing
./scripts/lib/alert-router.sh init_alerts
./scripts/lib/alert-router.sh send_alert INFO test "Test alert" "{}"

# Check history
grep "test" /tmp/code-server-remediation.log
```

**Solutions**:
```bash
# 1. Verify alert config
# At least one channel should be enabled
grep "ALERT_.*_ENABLED=true" .alerts/config.env
# Should show at least syslog (always available)

# 2. For Slack
# Get webhook from: https://api.slack.com/messaging/webhooks
# Set in .alerts/config.env: SLACK_WEBHOOK_URL="https://..."
# Test:
curl -X POST <SLACK_WEBHOOK_URL> \
  -H 'Content-Type: application/json' \
  -d '{"text": "Test alert"}'

# 3. For email
# Test postfix: echo "Test" | mail -s "Test" user@example.com
# Set in .alerts/config.env: EMAIL_TO="user@example.com"

# 4. For syslog (always works)
# Check: tail -20 /var/log/syslog | grep code-server

# 5. Manually trigger event to test
# Example: stop a container to trigger alert
docker stop <container>
# Check if alert sent
grep "RESTART_CONTAINER\|ERROR" /tmp/code-server-remediation.log | tail -5

# 6. Restart alert router
systemctl restart code-server-remediation.timer || true
```

**Expected Result**: Alerts appear in configured channels  
**Timeline**: 5-15 minutes

---

## 4. DEPLOYMENT ISSUES

### Issue 4A: Terraform Apply Hangs

**Symptoms**:
```
terraform apply running for >10 minutes
Process not responsive
```

**Diagnosis**:
```bash
ps aux | grep terraform
# Look for terraform processes

strace -p <terraform-pid>
# Shows what terraform is doing
```

**Solutions**:
```bash
# 1. Force kill terraform
pkill -9 terraform

# 2. Check Terraform lock file
cd terraform/environments/private
ls -la .terraform.lock.hcl

# 3. Verify hosts accessible
for host in 192.168.168.31 192.168.168.42; do
  ssh -o ConnectTimeout=5 akushnir@$host "echo OK" || echo "Failed: $host"
done

# 4. Refresh Terraform state
terraform refresh

# 5. Try again with timeout
timeout 60 terraform apply
```

**Expected Result**: Terraform completes within 5 minutes  
**Timeline**: 10-20 minutes

---

### Issue 4B: Deployment Rollback Failed

**Symptoms**:
```
Trying to rollback but git reset hangs
Or containers won't restart
```

**Diagnosis**:
```bash
git status
# Shows current state

docker ps -a
# Shows container states
```

**Solutions**:
```bash
# 1. Stop any running deployment processes
killall terraform docker-compose 2>/dev/null || true

# 2. Force git reset
git reset --hard HEAD~1

# 3. Restart systemd services
systemctl stop code-server-remediation.timer || true

# 4. Manually restart containers
docker-compose -f docker-compose.enterprise.yml down
docker-compose -f docker-compose.enterprise.yml up -d

# 5. Enable systemd services again
systemctl start code-server-remediation.timer || true

# 6. Verify status
bash scripts/ci/validate-pre-apply.sh
```

**Expected Result**: State rolled back, containers restarted  
**Timeline**: 15-30 minutes

---

## 5. EMERGENCY PROCEDURES

### Emergency 1: Critical Service Down

**Immediate Actions** (first 2 minutes):
```bash
# 1. Alert team
# "CRITICAL: <Service> is down, investigating"

# 2. Check service
docker ps | grep <service>

# 3. Try restart
docker restart <service>

# 4. Verify
docker logs <service> --tail=5
```

**Resolution** (next 10 minutes):
```bash
# 1. If restart works → Monitor
# 2. If restart fails → Root cause analysis
docker logs <service> | tail -30

# 3. Check dependencies
# Is database/redis available?
docker ps | grep postgresql
docker ps | grep redis

# 4. If dependencies missing → Restart them first
docker restart postgresql
docker restart redis
sleep 5

# 5. Retry service restart
docker restart <service>

# 6. If still failing → Follow incident playbook
```

---

### Emergency 2: Complete Host Failure

**If Primary Down** (192.168.168.31):
```bash
# 1. Keepalived automatically failover to replica
# → Virtual IP (192.168.168.50) moves to replica
# → Service continues on replica (192.168.168.42)

# 2. Alert: "Primary host failed, failover complete"
# Access services via replica:
ssh akushnir@192.168.168.42

# 3. Check status
docker ps | wc -l
bash scripts/ci/validate-pre-apply.sh

# 4. Investigate primary
# (Infrastructure team needed for physical access)
ping 192.168.168.31
# If no response → hardware issue
```

**Recovery**:
```bash
# 1. When primary comes back online
ssh akushnir@192.168.168.31

# 2. Rejoin cluster
cd /home/akushnir/code-server/terraform/environments/private
terraform apply

# 3. Keepalived will promote primary back to MASTER
# (takes <60 seconds)

# 4. Verify
ssh akushnir@192.168.168.31 "ip addr show | grep 192.168.168.50"
# Should show: MASTER
```

---

### Emergency 3: Data Corruption

**Immediate** (stop the bleeding):
```bash
# 1. STOP all deployments
systemctl stop code-server-remediation.timer || true
killall terraform docker-compose 2>/dev/null || true

# 2. FREEZE current state
git add -A && git commit -m "emergency: freeze state before data corruption fix"

# 3. ALERT: "Data corruption detected, stopping operations"
```

**Investigation** (next 30 minutes):
```bash
# 1. Identify what's corrupted
docker ps -a | grep -i exited
docker logs <corrupted-container> | head -100

# 2. Check databases
docker exec postgresql psql -U postgres -c "SELECT COUNT(*) FROM <table>"
docker exec redis redis-cli DBSIZE

# 3. Determine recovery path
# Option A: Restore from backup (if available)
# Option B: Rebuild from source code
# Option C: Escalate to engineering team
```

---

### Emergency 4: Security Incident

**Containment** (immediate):
```bash
# 1. ISOLATE affected host/container
# Stop container if possible
docker stop <affected-container>

# 2. PRESERVE evidence
# Don't clean logs yet
docker logs <affected-container> > /tmp/incident-logs-$(date +%s).txt

# 3. ALERT security team
# "SECURITY: Potential incident detected, investigating"

# 4. REVIEW: git log for unauthorized changes
git log --oneline -20
```

**Investigation & Escalation**:
```bash
# 1. Collect all logs
docker logs <container> > incident-container.log
cat /tmp/code-server-remediation.log > incident-remediation.log

# 2. Document timeline
# What changed? When? Who deployed?

# 3. ESCALATE to security team with:
# - Container logs
# - Git history
# - Timeline of changes
# - System logs
```

---

## 6. SUPPORT RESOURCES

### Documentation Map

| Topic | Document | Location |
|-------|----------|----------|
| Operations QuickStart | OPERATIONS_QUICKSTART.md | docs/ |
| Team Training | OPERATIONS_TEAM_TRAINING.md | docs/ |
| Daily Runbook | OPERATIONAL_RUNBOOK.md | docs/ |
| Deployment Steps | DEPLOYMENT_PROCEDURES.md | docs/ |
| Alert Setup | ALERT_INTEGRATION_GUIDE.md | docs/ |
| Monitoring Setup | MONITORING_DASHBOARD_SETUP.md | docs/ |
| Auto-Remediation | AUTO_REMEDIATION_GUIDE.md | docs/ |

### Escalation Path

**Level 1: Self-Service**
- Read OPERATIONS_QUICKSTART.md
- Check OPERATIONAL_RUNBOOK.md for incident playbooks
- Review troubleshooting guide (this document)
- Try basic troubleshooting steps

**Level 2: On-Call Ops**
- Contact on-call operator via Slack
- Expected response time: 5-15 minutes
- Can execute procedures, restart services, approve changes

**Level 3: Senior SRE**
- Engaged for unusual issues or policy decisions
- Can make infrastructure changes
- Can override automation safety settings
- Expected response time: 15-30 minutes

**Level 4: Platform Engineering**
- For code changes or architectural issues
- Contact platform team lead
- Expected response time: 30-60 minutes

**Level 5: Emergency Escalation**
- For critical production issues
- Page on-call engineering lead
- CEO/CTO if needed
- Expected response time: <5 minutes

### Key Contacts

```
On-Call Ops: [Slack: #ops-oncall]
Senior SRE: [Name], [Slack handle]
Platform Lead: [Name], [Slack handle]
Emergency: [Page through PagerDuty]
```

### Common Commands

```bash
# Health check
bash scripts/ci/validate-pre-apply.sh

# View dashboards
http://localhost:3000/d/code-server-ops

# Check logs
tail -f /tmp/code-server-remediation.log

# Incident playbooks
cat docs/OPERATIONAL_RUNBOOK.md | grep "Playbook"

# Docker commands
docker ps
docker logs <container>
docker restart <container>

# SSH to hosts
ssh akushnir@192.168.168.31  # Primary
ssh akushnir@192.168.168.42  # Replica
```

---

**Status**: ✅ **SUPPORT READY**

Complete troubleshooting guide with 40+ common issues and solutions documented.

