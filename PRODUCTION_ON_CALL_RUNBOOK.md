# Production On-Call Procedures & Runbooks

**Date:** April 30, 2026  
**Status:** ✅ READY FOR MAY 1 DEPLOYMENT  
**Audience:** On-call engineers, DevOps team, operations team  

---

## On-Call Basics

### Your Responsibilities (When You're On-Call)

**During Business Hours (06:00-18:00 UTC):**
- Monitor Grafana dashboards periodically
- Respond to Slack alerts in #critical-incidents within 5 minutes
- Acknowledge PagerDuty alerts immediately
- Keep team informed of status via Slack

**After Hours (18:00-06:00 UTC):**
- Set PagerDuty phone notifications ON
- Respond to PagerDuty pages within 5 minutes
- Get help from backup on-call if needed
- Document all actions taken

### Alert Severity & Response Times

| Severity | Type | Response | Examples |
|----------|------|----------|----------|
| **CRITICAL** | Immediate page | 5 min acknowledge, 15 min resolve | Service down, replication fail, data loss |
| **HIGH** | Email + Slack | 15 min acknowledge, 1 hour resolve | High error rate, slow API, memory leak |
| **WARNING** | Slack #warnings | 30 min review, 4 hour resolve | High CPU, disk usage, slow query |
| **INFO** | Log only | No SLA | Routine info, metric update |

### Escalation Chain

**Level 1 (YOU):** First responder  
- Assess severity
- Take immediate action if clear
- Escalate if unsure or stuck > 15 minutes

**Level 2 (Backup):** Senior engineer  
- Called if Level 1 can't resolve
- Has deeper access/knowledge
- Can make bigger infrastructure changes

**Level 3 (Manager):** Escalation  
- Called for major incidents
- Coordinates customer communication
- Authorizes emergency procedures

---

## CRITICAL ALERTS - RESPONSE PROCEDURES

### 🔴 Alert: PostgreSQL Replication Not Active

**Severity:** CRITICAL  
**SLA:** 5 min acknowledge, 15 min resolve  
**Impact:** No automatic failover if primary fails  

**Detection:**
- Alert shows: "PostgreSQL replication not active on 192.168.168.42"
- Slack message in #critical-incidents
- PagerDuty page sent

**Step-by-Step Response:**

1. **Acknowledge Alert**
   ```bash
   # Acknowledge in PagerDuty (click button)
   # Post in Slack: "@ops-team Acknowledged: PostgreSQL replication alert"
   ```

2. **Initial Diagnosis (2 min)**
   ```bash
   # SSH to replica
   ssh ubuntu@192.168.168.42
   
   # Check replication status
   cd /home/ubuntu/code-server
   docker exec code-server-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
   
   # If output is 'f' (false): Replica is NOT in recovery mode - FIX NEEDED
   # If output is 't' (true): Replica IS in recovery mode - Alert is FALSE POSITIVE
   ```

3. **If NOT in Recovery Mode (Needs Fix)**
   ```bash
   # Run the replication fix (takes ~20 minutes)
   cd /home/ubuntu/code-server
   bash orchestrate-postgresql-replication-fix.sh
   
   # Monitor output for:
   # ✅ "Part 1: PostgreSQL permissions fixed"
   # ✅ "Part 2: Replication verified (replica)"
   # ✅ "Part 3: Replication verified (primary)"
   
   # Post progress to Slack every 5 minutes
   ```

4. **Verification (5 min)**
   ```bash
   # On replica
   docker exec code-server-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
   # Should now show 't' (true)
   
   # On primary
   ssh ubuntu@192.168.168.31
   docker exec code-server-postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;" 
   # Should show connected replica
   
   # Test data sync
   ssh ubuntu@192.168.168.31
   docker exec code-server-postgres psql -U postgres -c "INSERT INTO test_table (data) VALUES ('test-$(date)');"
   sleep 2
   ssh ubuntu@192.168.168.42
   docker exec code-server-postgres psql -U postgres -c "SELECT * FROM test_table WHERE data LIKE 'test-%' ORDER BY created DESC LIMIT 1;"
   # Should show the inserted row
   ```

5. **Closure**
   ```bash
   # Update Slack
   "@ops-team ✅ PostgreSQL replication restored and verified"
   
   # Resolve in PagerDuty (click 'Resolve')
   
   # Document incident
   # Time taken: ___ minutes
   # Root cause: ___ (fix already applied, permissions corrected)
   # Actions: Ran orchestrate-postgresql-replication-fix.sh
   ```

**Common Issues & Solutions:**

| Issue | Solution |
|-------|----------|
| Fix script can't connect to primary | Check SSH access, primary host is up, network reachable |
| Replication still not connecting after fix | Check PostgreSQL logs, restart both containers, escalate to Level 2 |
| Data inconsistency between primary/replica | Stop operations, escalate to Level 2 for manual recovery |

---

### 🔴 Alert: PostgreSQL Down

**Severity:** CRITICAL  
**SLA:** 5 min acknowledge, 15 min resolve  
**Impact:** Complete database unavailability  

**Response:**

1. **Verify Status**
   ```bash
   # SSH to host where PostgreSQL is down
   ssh ubuntu@192.168.168.31  # or 192.168.168.42
   
   # Check container
   docker-compose ps postgres
   # If: "Exit 0" or "Exit 1" → container crashed
   # If: no output → container doesn't exist
   ```

2. **Try Restart (First Attempt)**
   ```bash
   cd /home/ubuntu/code-server
   docker-compose up -d postgres
   
   # Wait 30 seconds
   sleep 30
   
   # Check if healthy
   docker exec code-server-postgres psql -U postgres -c "SELECT 1;"
   # If "1" shown → RECOVERED
   ```

3. **If Still Down - Check Logs**
   ```bash
   docker logs code-server-postgres --tail=50
   # Look for:
   # - "permission denied" → FS issue
   # - "address already in use" → port conflict
   # - "could not initialize database" → data corruption
   ```

4. **Based on Error:**

   **If Permission Error:**
   ```bash
   # Fix permissions and restart
   docker-compose down
   docker volume ls | grep postgres
   # Check volume ownership
   ls -la /var/lib/docker/volumes/*postgres*
   # May need Level 2 help to fix
   ```

   **If Port Conflict:**
   ```bash
   # Find process using port 5432
   netstat -tlnp | grep 5432
   # Kill conflicting process
   kill -9 <PID>
   # Restart PostgreSQL
   docker-compose up -d postgres
   ```

   **If Data Corruption:**
   ```bash
   # This needs backup restore
   # Escalate to Level 2 immediately
   # Message: "Possible data corruption detected, starting restore procedure"
   ```

5. **Success Verification**
   ```bash
   # Connection test
   docker exec code-server-postgres psql -U postgres -c "SELECT version();"
   # Should show PostgreSQL version
   
   # Replication check (if on replica)
   docker exec code-server-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
   ```

**If Still Down After 15 Minutes → ESCALATE TO LEVEL 2**

---

### 🔴 Alert: API Server Down

**Severity:** CRITICAL  
**SLA:** 5 min acknowledge, 10 min resolve  
**Impact:** API completely unavailable  

**Response:**

1. **Verify Status**
   ```bash
   ssh ubuntu@192.168.168.31
   
   # Check container
   docker-compose ps api-server
   # Should be "Up X seconds" or "Exit X"
   ```

2. **Restart Service**
   ```bash
   cd /home/ubuntu/code-server
   docker-compose up -d api-server
   
   # Wait 10 seconds for startup
   sleep 10
   ```

3. **Health Check**
   ```bash
   # Check if API is responding
   curl -s http://localhost:8000/health | jq '.'
   # Should show: {"status": "healthy"}
   
   # If error, check logs
   docker logs api-server --tail=30
   ```

4. **If Still Not Responding:**

   **Check Memory:**
   ```bash
   docker stats api-server --no-stream
   # If memory near limit (e.g., 1.9GB of 2GB):
   # - Kill container
   # - Edit docker-compose.yml: increase memory limit
   # - Restart
   ```

   **Check Dependencies:**
   ```bash
   # Verify PostgreSQL is up
   docker-compose ps postgres
   
   # Verify Redis is up
   docker-compose ps redis
   
   # If either down, start them first
   ```

5. **Verification**
   ```bash
   # Final health check
   curl -s http://localhost:8000/health
   
   # Test actual API call
   curl -s http://localhost:8000/api/status | jq '.'
   ```

**If Still Down → ESCALATE TO LEVEL 2**

---

### 🟠 Alert: API Error Rate High (> 1%)

**Severity:** HIGH  
**SLA:** 15 min acknowledge, 1 hour resolve  
**Impact:** Some requests failing, partial degradation  

**Response:**

1. **Assess Scope**
   ```bash
   ssh ubuntu@192.168.168.31
   
   # Check which endpoints are failing
   docker logs api-server --since 5m | grep -i error | head -20
   
   # Check error distribution
   curl -s http://localhost:9090/api/v1/query?query='rate(http_requests_total{status=~"5.."}[5m])' | jq '.'
   ```

2. **Identify Root Cause**
   
   **Database Slow?**
   ```bash
   # Check PostgreSQL
   docker exec code-server-postgres psql -U postgres -c "SHOW max_connections; SELECT count(*) FROM pg_stat_activity;"
   # If connections > 80: might have connection pool issue
   ```

   **Memory Issue?**
   ```bash
   docker stats api-server --no-stream
   # If memory usage > 90%: might be memory leak
   # Solution: Restart container
   ```

   **Specific Error?**
   ```bash
   # Get recent error messages
   docker logs api-server --since 10m --grep=ERROR | tail -20
   # Analyze error messages for patterns
   ```

3. **Quick Mitigations**

   **If High CPU:**
   ```bash
   docker-compose restart api-server
   ```

   **If High Memory:**
   ```bash
   docker-compose restart api-server
   # Monitor: docker stats api-server
   ```

   **If Database Connections High:**
   ```bash
   # Check for stuck connections
   ssh ubuntu@192.168.168.31
   docker exec code-server-postgres psql -U postgres -c "SELECT pid, usename, state FROM pg_stat_activity WHERE state='idle';"
   # Kill idle connections (if many)
   docker exec code-server-postgres psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state='idle';"
   ```

4. **Monitor Recovery**
   ```bash
   # Watch error rate for 5 minutes
   watch -n 5 'curl -s http://localhost:9090/api/v1/query?query="rate(http_requests_total{status=~\"5..\"}[5m])" | jq ".data.result"'
   
   # Error rate should return to < 0.1%
   ```

**If Error Rate Doesn't Improve → ESCALATE TO LEVEL 2**

---

## HIGH ALERTS - RESPONSE PROCEDURES

### 🟠 Alert: Host CPU Usage High (> 80%)

**Severity:** HIGH  
**SLA:** 15 min investigate  
**Response:**

```bash
# Identify which process is using CPU
top -b -n 1 -o +%CPU | head -20

# Check Docker containers
docker stats --no-stream | sort -k8 -rn

# If one container is hogging: docker-compose restart <service>
# If multiple: may need to scale load or investigate code
```

### 🟠 Alert: API Response Time High (P95 > 1s)

**Severity:** HIGH  
**SLA:** 15 min investigate  
**Response:**

```bash
# Check database query performance
ssh ubuntu@192.168.168.31
docker exec code-server-postgres psql -U postgres -c "SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# Check slow query log
docker logs api-server | grep "slow query"

# Solutions:
# - Add database index (if query advisor suggests)
# - Scale API servers (if throughput issue)
# - Restart if memory issue
```

---

## WARNING ALERTS - RESPONSE PROCEDURES

### ⚡ Alert: Host Memory Usage High (> 85%)

**Severity:** WARNING  
**SLA:** 30 min investigate  
**Action:** Monitor, don't necessarily restart

```bash
# Check memory by container
docker stats --no-stream | head -20

# Check host memory
free -h

# If specific container leaking: schedule restart during maintenance
# If overall: may need to optimize or add resources
```

### ⚡ Alert: PostgreSQL Connection Count High (> 80)

**Severity:** WARNING  
**SLA:** 30 min investigate  
**Action:** Clean up if stuck, monitor if not

```bash
# List connections
docker exec code-server-postgres psql -U postgres -c "SELECT pid, usename, state, query_start FROM pg_stat_activity WHERE state != 'idle' ORDER BY query_start;"

# Kill stuck transactions
docker exec code-server-postgres psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state='idle' AND query_start < NOW() - interval '10 minutes';"
```

---

## Useful Commands Reference

### Status Checks
```bash
# Full system status
docker-compose ps

# Individual service health
docker-compose ps <service>
docker exec <container> <health-check-cmd>

# Logs
docker logs <container> --tail=50 --follow

# Restart service
docker-compose restart <service>
docker-compose up -d <service>
```

### PostgreSQL
```bash
# Connect
docker exec code-server-postgres psql -U postgres

# Basic checks
SELECT 1;                        # Connection works
SELECT version();                # PostgreSQL version
SELECT pg_is_in_recovery();      # In replication mode?
SELECT * FROM pg_replication_slots;  # Replication slot status
```

### Network Diagnostics
```bash
# Test connectivity
nc -zv 192.168.168.31 5432      # PostgreSQL
nc -zv 192.168.168.31 6379      # Redis
nc -zv 192.168.168.31 8000      # API

# DNS resolution
nslookup 192.168.168.31
```

### Escalation
```bash
# Get Level 2 help
@level2-oncall I need assistance with: [BRIEF DESCRIPTION]

# Critical incident escalation
@devops-manager CRITICAL incident in progress: [DESCRIPTION]
```

---

## After-Action Review Template

**Use this for every significant incident:**

```
Date: ___________
Alert: ________________
Severity: ☐ Critical ☐ High ☐ Warning

Timeline:
- Alert fired: HH:MM UTC
- Acknowledged: HH:MM UTC (latency: ___ min)
- Started fixing: HH:MM UTC
- Resolved: HH:MM UTC (total: ___ min)

Root Cause:
_______________________________________________________________

Actions Taken:
1. _______________________________________________________________
2. _______________________________________________________________
3. _______________________________________________________________

Outcome:
☐ Self-resolved
☐ Quick restart fixed
☐ Manual intervention required
☐ Escalated to Level 2

Lessons Learned:
_______________________________________________________________

Preventative Actions:
☐ Need alert threshold adjustment
☐ Need runbook improvement
☐ Need code fix
☐ Need infrastructure change: _________________________
```

---

## Emergency Contacts

**Update these before May 1:**

| Role | Name | Phone | Slack |
|------|------|-------|-------|
| On-Call L1 | [YOU] | [###] | @on-call-l1 |
| On-Call L2 | [SENIOR] | [###] | @on-call-l2 |
| DevOps Manager | [MANAGER] | [###] | @devops-manager |
| CTO | [CTO] | [###] | @cto |
| Operations Manager | [OPS] | [###] | @ops-manager |

---

## Handoff Checklist

**When switching on-call shifts (every 24 hours):**

- [ ] Read this entire document
- [ ] Review incidents from your shift
- [ ] Check dashboards for any ongoing issues
- [ ] Brief incoming on-call on status
- [ ] Verify PagerDuty escalation policy correct
- [ ] Test Slack alert channel accessibility
- [ ] Confirm you have SSH access to both hosts
- [ ] Update calendar: "ON-CALL until HH:MM UTC"

---

## Quick Reference - What to Do For Each Alert

| Alert | First Response |
|-------|-----------------|
| PostgreSQL Replication Not Active | Run replication fix script |
| PostgreSQL Down | Restart container, check logs |
| API Server Down | Restart container, check dependencies |
| API Error Rate High | Check logs for errors, restart if needed |
| API Response Time High | Check database queries, profile code |
| High CPU | Identify process, restart container if needed |
| High Memory | Check for leaks, restart container if needed |
| Replication Lag High | Monitor, investigate if > 5s for > 10m |
| Connection Pool High | Clean up stuck connections |

