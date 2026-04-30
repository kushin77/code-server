# PHASE 2B DEPLOYMENT COMMAND CHECKLISTS BY ROLE

**Purpose:** Exact commands for each team role to copy-paste during deployment execution  
**Format:** Command-ready with sign-off lines for tracking
**Usage:** Follow sequence day-by-day during Week 1-3

---

# 🏗️ INFRASTRUCTURE LEAD COMMAND CHECKLIST

## WEEK 1 PRE-DEPLOYMENT (May 1, 04:00-05:00 UTC)

### Step 1: Primary Node Health Check (10 minutes)

```bash
# Command 1: SSH connectivity
ssh -v ubuntu@192.168.168.31 "echo 'PRIMARY SSH OK'"
```
**Expected:** Connection successful, command executes  
**Sign-Off:** [ ] PASS  **Time:** _____  **Operator:** _____________

```bash
# Command 2: Disk space
ssh ubuntu@192.168.168.31 "df -h / | tail -1"
```
**Expected:** >50GB available  
**Result:** _____________  
**Sign-Off:** [ ] PASS  

```bash
# Command 3: Memory status
ssh ubuntu@192.168.168.31 "free -h | grep Mem"
```
**Expected:** >32GB total, <25% used  
**Result:** _____________  
**Sign-Off:** [ ] PASS  

```bash
# Command 4: Network connectivity
ssh ubuntu@192.168.168.31 "ping -c 1 8.8.8.8 && ping -c 1 192.168.168.42"
```
**Expected:** Both pings successful  
**Sign-Off:** [ ] PASS  

```bash
# Command 5: Docker daemon status
ssh ubuntu@192.168.168.31 "systemctl is-active docker"
```
**Expected:** active  
**Sign-Off:** [ ] PASS  

### Step 2: Replica Node Health Check (10 minutes)

```bash
# Command 6: SSH connectivity
ssh -v ubuntu@192.168.168.42 "echo 'REPLICA SSH OK'"
```
**Expected:** Connection successful  
**Sign-Off:** [ ] PASS  **Time:** _____

```bash
# Command 7: Disk space
ssh ubuntu@192.168.168.42 "df -h / | tail -1"
```
**Expected:** >50GB available  
**Sign-Off:** [ ] PASS  

```bash
# Command 8: Memory status
ssh ubuntu@192.168.168.42 "free -h | grep Mem"
```
**Expected:** >32GB total, <25% used  
**Sign-Off:** [ ] PASS  

```bash
# Command 9: Network connectivity
ssh ubuntu@192.168.168.42 "ping -c 1 192.168.168.31 && ping -c 1 192.168.168.50"
```
**Expected:** Both pings successful  
**Sign-Off:** [ ] PASS  

```bash
# Command 10: Docker daemon status
ssh ubuntu@192.168.168.42 "systemctl is-active docker"
```
**Expected:** active  
**Sign-Off:** [ ] PASS  

### Step 3: Database Verification (10 minutes)

```bash
# Command 11: PostgreSQL version on PRIMARY
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT version();'"
```
**Expected:** PostgreSQL 12+ displayed  
**Sign-Off:** [ ] PASS  **Time:** _____

```bash
# Command 12: Replication status
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT slot_name, active FROM pg_replication_slots;'"
```
**Expected:** gitlab_replica active=t  
**Sign-Off:** [ ] PASS  

```bash
# Command 13: Database size
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT pg_size_pretty(pg_database_size(\"gitlab_db\"));'"
```
**Expected:** Size displayed (2-5GB typical)  
**Result:** _____________  
**Sign-Off:** [ ] PASS  

```bash
# Command 14: Replica connection status
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT client_addr, state FROM pg_stat_replication;'"
```
**Expected:** Replica connected, state=streaming  
**Sign-Off:** [ ] PASS  

```bash
# Command 15: Replica recovery status
ssh ubuntu@192.168.168.42 "docker exec gitlab_db psql -U postgres -c 'SELECT pg_is_in_recovery();'"
```
**Expected:** t (true)  
**Sign-Off:** [ ] PASS  

### Step 4: HA & VIP Verification (10 minutes)

```bash
# Command 16: VIP ping test
ping -c 1 192.168.168.50
```
**Expected:** Reply from 192.168.168.50  
**Sign-Off:** [ ] PASS  **Time:** _____

```bash
# Command 17: Keepalived status on PRIMARY
ssh ubuntu@192.168.168.31 "docker exec gitlab_keepalived systemctl is-active keepalived"
```
**Expected:** active  
**Sign-Off:** [ ] PASS  

```bash
# Command 18: Keepalived status on REPLICA
ssh ubuntu@192.168.168.42 "docker exec gitlab_keepalived systemctl is-active keepalived"
```
**Expected:** active  
**Sign-Off:** [ ] PASS  

```bash
# Command 19: PRIMARY Keepalived role
ssh ubuntu@192.168.168.31 "docker exec gitlab_keepalived systemctl status keepalived | grep -i MASTER"
```
**Expected:** MASTER (or found in output)  
**Sign-Off:** [ ] PASS  

```bash
# Command 20: REPLICA Keepalived role
ssh ubuntu@192.168.168.42 "docker exec gitlab_keepalived systemctl status keepalived | grep -i BACKUP"
```
**Expected:** BACKUP (or found in output)  
**Sign-Off:** [ ] PASS  

### Step 5: Container & Services (10 minutes)

```bash
# Command 21: Container count on PRIMARY
ssh ubuntu@192.168.168.31 "cd /opt/gitlab && docker-compose ps | grep -E 'Up|Exited' | wc -l"
```
**Expected:** 87+ containers  
**Result:** _____________  
**Sign-Off:** [ ] PASS  **Time:** _____

```bash
# Command 22: Container count on REPLICA
ssh ubuntu@192.168.168.42 "cd /opt/gitlab && docker-compose ps | grep -E 'Up|Exited' | wc -l"
```
**Expected:** 88 containers  
**Result:** _____________  
**Sign-Off:** [ ] PASS  

```bash
# Command 23: Critical services on PRIMARY
ssh ubuntu@192.168.168.31 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'gitlab_unicorn|gitlab_db|gitlab_redis|gitlab_nginx'"
```
**Expected:** All 4 services running (Up)  
**Sign-Off:** [ ] PASS  

### INFRASTRUCTURE LEAD FINAL SIGN-OFF

**All 23 commands passed:** [ ] YES  [ ] NO

**Any failures noted:** 
```
_________________________________________________________________
_________________________________________________________________
```

**Infrastructure Lead Signature:** _________________________ **Time:** _________

---

## WEEK 1 DAILY MAINTENANCE (May 2-12, 09:30 UTC each day)

### Daily Health Check Script (5 minutes)

```bash
# Run this exact script every morning
#!/bin/bash
echo "=== $(date) === Infrastructure Daily Check"
echo "PRIMARY Containers:"
ssh ubuntu@192.168.168.31 "docker ps | wc -l" | tail -1

echo "REPLICA Containers:"
ssh ubuntu@192.168.168.42 "docker ps | wc -l" | tail -1

echo "PostgreSQL Primary Version:"
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT version();' 2>&1 | head -1"

echo "PostgreSQL Replica Recovery:"
ssh ubuntu@192.168.168.42 "docker exec gitlab_db psql -U postgres -c 'SELECT pg_is_in_recovery();' 2>&1"

echo "Redis Primary PING:"
ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli PING"

echo "VIP Ping:"
ping -c 1 192.168.168.50 2>&1 | grep -E "Reply|Destination"

echo "Replication Lag:"
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (now() - pg_last_wal_receive_lsn_time())) as lag_sec;' 2>&1"

echo "=== End Check ==="
```

**Save as:** `/home/ubuntu/daily-health-check.sh`

**Run daily:**
```bash
bash /home/ubuntu/daily-health-check.sh
```

**Sign-Off:** [ ] PASS  **Date:** ______  **Operator:** ________________

---

# 🛠️ OPERATIONS LEAD COMMAND CHECKLIST

## WEEK 1 DEPLOYMENT SUPPORT (May 1-12)

### Daily Standup Preparation (10 minutes at 09:50 UTC)

```bash
# Command 1: Check infrastructure status
curl -s http://192.168.168.31:9090/api/v1/targets \
  | jq '.data | {activeTargets: .activeTargets | length, downTargets: .droppedTargets | length}'
```
**Expected:** activeTargets: 8+, downTargets: 0  
**Result:** _____________  
**Sign-Off:** [ ] PASS  **Time:** _____

```bash
# Command 2: Check for active alerts
curl -s http://192.168.168.31:9093/api/v1/alerts | jq '.data | length'
```
**Expected:** 0 (no active alerts) or document any firing  
**Result:** _____________  
**Sign-Off:** [ ] PASS  

```bash
# Command 3: Verify Grafana accessible
curl -s http://192.168.168.31:3000/api/health | jq '.status'
```
**Expected:** ok  
**Sign-Off:** [ ] PASS  

### Backup Verification (Daily at 16:00 UTC)

```bash
# Command 4: List latest backups
ssh ubuntu@192.168.168.31 "ls -lht /backups/*.dump 2>/dev/null | head -3"
```
**Expected:** Recent backup file(s) listed  
**Result:** _____________  
**Sign-Off:** [ ] PASS  

```bash
# Command 5: Verify backup integrity
ssh ubuntu@192.168.168.31 "file /backups/$(ls -t /backups/*.dump 2>/dev/null | head -1)"
```
**Expected:** PostgreSQL custom format dump  
**Result:** _____________  
**Sign-Off:** [ ] PASS  

### Contingency Trigger Check (Continuous during deployment)

```bash
# Command 6: Check if multiple services down (if ANY true, escalate to CTO)
# Multiple containers exited?
ssh ubuntu@192.168.168.31 "docker ps -a | grep Exited | wc -l"
# If >2, escalate

# Replication broken?
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT count(*) FROM pg_stat_replication;'"
# If 0, escalate

# Data corruption signs?
ssh ubuntu@192.168.168.31 "docker logs gitlab_db 2>&1 | grep -i 'corruption\|error' | head -5"
# If found, escalate
```

**All checks normal:** [ ] YES  [ ] NO (describe escalation needed)  
**Escalation:** _________________________________________________________________

---

# 🔍 QA/TEST LEAD COMMAND CHECKLIST

## WEEK 1 TESTING PHASES (May 1-12)

### Phase 1: Container Startup Test (May 1, Days 1-4)

```bash
# Command 1: Verify all containers running
ssh ubuntu@192.168.168.31 "docker ps | wc -l"
```
**Expected:** 87+ containers  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

```bash
# Command 2: Check for any exited containers
ssh ubuntu@192.168.168.31 "docker ps -a | grep Exited"
```
**Expected:** No output (no exited containers)  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

### Phase 2: Database Integrity Test (May 5-6)

```bash
# Command 3: Test database connectivity
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT COUNT(*) FROM pg_tables;'"
```
**Expected:** Positive number (tables exist)  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

```bash
# Command 4: Verify data consistency between PRIMARY and REPLICA
PRIMARY_COUNT=$(ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT COUNT(*) FROM pg_tables;'")
REPLICA_COUNT=$(ssh ubuntu@192.168.168.42 "docker exec gitlab_db psql -U postgres -c 'SELECT COUNT(*) FROM pg_tables;'")
if [ "$PRIMARY_COUNT" == "$REPLICA_COUNT" ]; then
  echo "Data consistent"
else
  echo "Data mismatch: PRIMARY=$PRIMARY_COUNT REPLICA=$REPLICA_COUNT"
fi
```
**Expected:** Data consistent  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

### Phase 3: Replication Sync Test (May 7)

```bash
# Command 5: Check replication lag
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (now() - pg_last_wal_receive_lsn_time())) as lag_sec;'"
```
**Expected:** <5 seconds  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

### Phase 4: Services Responsive Test (May 8)

```bash
# Command 6: Test HTTP connectivity to VIP
curl -v http://192.168.168.50/ 2>&1 | head -10
```
**Expected:** HTTP 200 or 302 response (not connection refused)  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

```bash
# Command 7: Test Redis connectivity
ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli PING"
```
**Expected:** PONG  
**Assertion:** [ ] PASS  [ ] FAIL

### Phase 5: Load Test (May 9)

```bash
# Command 8: Install ApacheBench if needed
which ab || sudo apt-get install -y apache2-utils

# Command 9: Run load test
ab -n 6000 -c 20 http://192.168.168.50/
```
**Expected:** 6000 requests completed, <1% failed  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

### Phase 6: Health Checks (May 10)

```bash
# Command 10: Verify health endpoints
curl -s http://192.168.168.50/health | head -5
```
**Expected:** JSON response with healthy status  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

### Phase 7: Integration Test (May 11)

```bash
# Command 11: End-to-end workflow test
# (Specific to your application - example below)
curl -X POST http://192.168.168.50/api/test -d '{"test":"data"}'
```
**Expected:** 200 response, data processed successfully  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

### Phase 8: Regression Test (May 12)

```bash
# Command 12: Check logs for new errors
ssh ubuntu@192.168.168.31 "docker logs --since 24h gitlab_unicorn 2>&1 | grep -i error | wc -l"
```
**Expected:** 0 or acceptable number (document baseline)  
**Result:** _____________  
**Assertion:** [ ] PASS  [ ] FAIL

### QA SIGN-OFF

**All 8 phases passed:** [ ] YES  [ ] NO

**Critical defects found:** None / [describe]  
**___________________________________________________________________**

**QA Lead Signature:** _________________________ **Date:** __________

---

# 🔒 SECURITY LEAD COMMAND CHECKLIST

## WEEK 1 SECURITY VERIFICATION (May 1-12)

### SSL/TLS Verification

```bash
# Command 1: Check SSL certificate validity
openssl s_client -connect 192.168.168.50:443 -showcerts 2>&1 | grep -E "subject=|issuer=|notAfter="
```
**Expected:** Certificate valid, expiration >30 days away  
**Result:** _____________  
**Status:** [ ] PASS  [ ] FAIL

### Authentication Test

```bash
# Command 2: Test login endpoint
curl -X POST http://192.168.168.50/api/login -d '{"user":"test","pass":"test"}' -v 2>&1 | grep -E "HTTP|201|401"
```
**Expected:** 401 (Unauthorized) or 200 (if test credentials exist)  
**Result:** _____________  
**Status:** [ ] PASS  [ ] FAIL

### Security Logging

```bash
# Command 3: Check for security logs
ssh ubuntu@192.168.168.31 "docker logs gitlab_unicorn 2>&1 | grep -i 'security\|access' | head -10"
```
**Expected:** Access/security events logged  
**Result:** _____________  
**Status:** [ ] PASS  

### Audit Logging

```bash
# Command 4: Verify audit logs created
ssh ubuntu@192.168.168.31 "ls -lh /var/log/audit/ 2>/dev/null || ls -lh /var/log/*audit* 2>/dev/null"
```
**Expected:** Audit log files present and recent  
**Result:** _____________  
**Status:** [ ] PASS  

### Credential Exposure Check

```bash
# Command 5: Search logs for exposed credentials
ssh ubuntu@192.168.168.31 "docker logs gitlab_unicorn 2>&1 | grep -i 'password\|secret\|token' | grep -v encrypted | head -5"
```
**Expected:** No output (no exposed credentials)  
**Result:** _____________  
**Status:** [ ] PASS  [ ] FAIL

### SECURITY SIGN-OFF

**All security checks passed:** [ ] YES  [ ] NO

**Any vulnerabilities found:** None / [describe]  
**___________________________________________________________________**

**Security Lead Signature:** _________________________ **Date:** __________

---

# 📊 MONITORING LEAD COMMAND CHECKLIST

## DAILY MONITORING HEALTH (May 1-12, 09:00 UTC)

### Prometheus Health

```bash
# Command 1: Check Prometheus endpoint health
curl -s http://192.168.168.31:9090/-/healthy && echo " ✓ OK"
```
**Expected:** Response OK  
**Status:** [ ] PASS  [ ] FAIL  **Time:** _____

```bash
# Command 2: Count active targets
curl -s http://192.168.168.31:9090/api/v1/targets \
  | jq '.data.activeTargets | length'
```
**Expected:** 8+  
**Result:** _____________  
**Status:** [ ] PASS  [ ] FAIL

```bash
# Command 3: List any failed targets
curl -s http://192.168.168.31:9090/api/v1/targets \
  | jq '.data.activeTargets[] | select(.health=="down") | .labels.job'
```
**Expected:** No output (no down targets)  
**Result:** _____________  
**Status:** [ ] PASS  [ ] FAIL

### Grafana Health

```bash
# Command 4: Check Grafana endpoint health
curl -s http://192.168.168.31:3000/api/health | jq '.status'
```
**Expected:** ok  
**Status:** [ ] PASS  [ ] FAIL

```bash
# Command 5: List available dashboards
curl -s http://192.168.168.31:3000/api/search | jq '. | length'
```
**Expected:** 3+  
**Result:** _____________  
**Status:** [ ] PASS  

### AlertManager Health

```bash
# Command 6: Check AlertManager endpoint health
curl -s http://192.168.168.31:9093/-/healthy && echo " ✓ OK"
```
**Expected:** Response OK  
**Status:** [ ] PASS  [ ] FAIL

```bash
# Command 7: Check active alerts
curl -s http://192.168.168.31:9093/api/v1/alerts | jq '.data | length'
```
**Expected:** 0 (or document any firing alerts)  
**Result:** _____________  
**Status:** [ ] PASS  

### Performance Baseline Recording (May 1 at 05:00 UTC)

```bash
# Command 8: Record baseline metrics
curl -s 'http://192.168.168.31:9090/api/v1/query?query=rate(container_cpu_usage_seconds_total[5m])*100' \
  | jq '.data.result[0].value[1]' > /tmp/baseline_cpu.txt

echo "Baseline CPU recorded: $(cat /tmp/baseline_cpu.txt)"
```
**Status:** [ ] PASS

**MONITORING LEAD DAILY SIGN-OFF**

**All monitoring systems healthy:** [ ] YES  [ ] NO  
**Date:** __/__/__  **Time:** _____  **Operator:** _______________

---

# 📋 PROJECT MANAGER COMMAND CHECKLIST

## WEEK 1 MILESTONE TRACKING

### End-of-Day Status Report Template (Daily at 18:00 UTC)

```bash
# Command 1: Generate status snapshot
cat <<EOF > /tmp/daily_status_$(date +%Y%m%d).txt
Date: $(date)
Time: $(date +%H:%M UTC)

INFRASTRUCTURE STATUS:
$(ssh ubuntu@192.168.168.31 "docker ps | wc -l") containers on PRIMARY
$(ssh ubuntu@192.168.168.42 "docker ps | wc -l") containers on REPLICA

DATABASE STATUS:
$(ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT pg_size_pretty(pg_database_size(\"gitlab_db\"));'" 2>&1 | head -1)

REPLICATION LAG:
$(ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (now() - pg_last_wal_receive_lsn_time())) as lag_sec;'" 2>&1 | head -1) seconds

MONITORING:
$(curl -s http://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets | length') targets active
EOF

cat /tmp/daily_status_$(date +%Y%m%d).txt
```

**Review and attach to daily standup:** [ ] YES

---

**All command checklists complete and ready for use.**  
**Print this document and distribute to each team lead.**

