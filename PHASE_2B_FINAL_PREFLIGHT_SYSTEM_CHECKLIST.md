# PHASE 2B FINAL PRE-FLIGHT SYSTEM CHECKLIST

**Execution Window:** May 1, 2026 04:00-05:00 UTC (1 hour before go-live)
**Responsibility:** Infrastructure Lead + Operations Lead
**Time Allocation:** 60 minutes maximum
**Decision Gate:** GO/NO-GO for 00:00 UTC deployment launch

---

## 🚀 PRE-FLIGHT CHECKLIST STRUCTURE

This checklist must be completed between 04:00-05:00 UTC on May 1, 2026.
All items must be verified and signed off by both Infrastructure Lead and Operations Lead.
Any FAILED item triggers HOLD status and escalates to CTO immediately.

---

## ✈️ PHASE 1: INFRASTRUCTURE HARDWARE VERIFICATION (15 minutes)

### Primary Node (192.168.168.31) - Infrastructure Lead
- [ ] **SSH Access Test**
  ```bash
  ssh -v ubuntu@192.168.168.31 "echo 'PRIMARY SSH OK'"
  # Expected: Connection successful, command executes
  ```
  - Status: _________  Time: _________
  - Evidence: Capture SSH output timestamp

- [ ] **Disk Space Verification**
  ```bash
  ssh ubuntu@192.168.168.31 "df -h / | tail -1"
  # Expected: >50GB available (show output)
  ```
  - Status: _________  Time: _________
  - Available Space: _________ GB

- [ ] **Memory Status**
  ```bash
  ssh ubuntu@192.168.168.31 "free -h | grep Mem"
  # Expected: >32GB total, <25% used
  ```
  - Status: _________  Time: _________
  - Available Memory: _________ GB

- [ ] **Network Connectivity**
  ```bash
  ssh ubuntu@192.168.168.31 "ping -c 1 8.8.8.8 && ping -c 1 192.168.168.42"
  # Expected: Both pings successful (ICMPv4 responses)
  ```
  - Status: _________  Time: _________
  - Latency to 8.8.8.8: _________ ms
  - Latency to REPLICA: _________ ms

- [ ] **Docker Daemon Status**
  ```bash
  ssh ubuntu@192.168.168.31 "systemctl is-active docker"
  # Expected: active
  ```
  - Status: _________  Time: _________

---

### Replica Node (192.168.168.42) - Infrastructure Lead
- [ ] **SSH Access Test**
  ```bash
  ssh -v ubuntu@192.168.168.42 "echo 'REPLICA SSH OK'"
  # Expected: Connection successful
  ```
  - Status: _________  Time: _________

- [ ] **Disk Space Verification**
  ```bash
  ssh ubuntu@192.168.168.42 "df -h / | tail -1"
  # Expected: >50GB available
  ```
  - Status: _________  Time: _________
  - Available Space: _________ GB

- [ ] **Memory Status**
  ```bash
  ssh ubuntu@192.168.168.42 "free -h | grep Mem"
  # Expected: >32GB, <25% used
  ```
  - Status: _________  Time: _________
  - Available Memory: _________ GB

- [ ] **Network Connectivity**
  ```bash
  ssh ubuntu@192.168.168.42 "ping -c 1 192.168.168.31 && ping -c 1 192.168.168.50"
  # Expected: Both successful
  ```
  - Status: _________  Time: _________
  - Latency to PRIMARY: _________ ms
  - Latency to VIP: _________ ms

- [ ] **Docker Daemon Status**
  ```bash
  ssh ubuntu@192.168.168.42 "systemctl is-active docker"
  # Expected: active
  ```
  - Status: _________  Time: _________

---

## 🔌 PHASE 2: DATABASE VERIFICATION (15 minutes)

### PostgreSQL Primary - Infrastructure Lead
- [ ] **Connection Test**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT version();'"
  # Expected: PostgreSQL 12+ version displayed
  ```
  - Status: _________  Time: _________
  - Version: _________

- [ ] **Replication Status Check**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT slot_name, active FROM pg_replication_slots;'"
  # Expected: Replication slots active with gitlab_replica active=t
  ```
  - Status: _________  Time: _________
  - Replication Lag: _________ MB
  - Slots Active: [ ] YES

- [ ] **Database Size Verification**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT pg_size_pretty(pg_database_size(\"gitlab_db\"));'"
  # Expected: Database size displayed (typically 2-5GB)
  ```
  - Status: _________  Time: _________
  - Database Size: _________

- [ ] **Standby Catchup Status**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT client_addr, state FROM pg_stat_replication;'"
  # Expected: Replica connected, state=streaming
  ```
  - Status: _________  Time: _________
  - Replica Status: streaming [ ] | catchup [ ] | other _________

---

### PostgreSQL Replica - Operations Lead
- [ ] **Replica Connection Verification**
  ```bash
  ssh ubuntu@192.168.168.42 "docker exec gitlab_db psql -U postgres -c 'SELECT pg_is_in_recovery();'"
  # Expected: t (true - replica is in recovery mode)
  ```
  - Status: _________  Time: _________

- [ ] **Replica Lag Check**
  ```bash
  ssh ubuntu@192.168.168.42 "docker exec gitlab_db psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (now() - pg_last_wal_receive_lsn_time())) as replication_lag_sec;'"
  # Expected: <5 seconds (lag should be minimal)
  ```
  - Status: _________  Time: _________
  - Replication Lag: _________ seconds

- [ ] **Data Consistency Test**
  ```bash
  ssh ubuntu@192.168.168.42 "docker exec gitlab_db psql -U postgres -c 'SELECT COUNT(*) FROM gitlab_db.information_schema.tables;'"
  # Expected: Table count matches primary (verify with Infrastructure Lead)
  ```
  - Status: _________  Time: _________
  - Table Count: _________

---

## 🎯 PHASE 3: REDIS VERIFICATION (10 minutes)

### Redis Primary (on PRIMARY node)
- [ ] **PING Test**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli PING"
  # Expected: PONG
  ```
  - Status: _________  Time: _________

- [ ] **Replication Status**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli INFO replication | head -20"
  # Expected: role:master, connected_slaves:1
  ```
  - Status: _________  Time: _________
  - Role: [ ] master  [ ] slave
  - Connected Slaves: _________

- [ ] **Memory Usage**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli INFO memory | grep used_memory_human"
  # Expected: <5GB typically
  ```
  - Status: _________  Time: _________
  - Memory Used: _________

---

### Redis Replica (on REPLICA node)
- [ ] **PING Test**
  ```bash
  ssh ubuntu@192.168.168.42 "docker exec gitlab_redis redis-cli PING"
  # Expected: PONG
  ```
  - Status: _________  Time: _________

- [ ] **Replication Status**
  ```bash
  ssh ubuntu@192.168.168.42 "docker exec gitlab_redis redis-cli INFO replication | head -10"
  # Expected: role:slave, master_link_status:up
  ```
  - Status: _________  Time: _________
  - Role: [ ] master  [ ] slave
  - Master Link: [ ] up  [ ] down

---

## 🔄 PHASE 4: HA & KEEPALIVED VERIFICATION (10 minutes)

### Virtual IP (VIP) - Infrastructure Lead
- [ ] **VIP Ping Test**
  ```bash
  ping -c 1 192.168.168.50
  # Expected: Reply from 192.168.168.50 with <1ms latency
  ```
  - Status: _________  Time: _________
  - Response: [ ] SUCCESS  [ ] FAILED
  - Latency: _________ ms

- [ ] **Keepalived Status on PRIMARY**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_keepalived systemctl is-active keepalived"
  # Expected: active
  ```
  - Status: _________  Time: _________

- [ ] **Keepalived Status on REPLICA**
  ```bash
  ssh ubuntu@192.168.168.42 "docker exec gitlab_keepalived systemctl is-active keepalived"
  # Expected: active
  ```
  - Status: _________  Time: _________

- [ ] **VIP Owner Verification (PRIMARY is MASTER)**
  ```bash
  ssh ubuntu@192.168.168.31 "docker exec gitlab_keepalived systemctl status keepalived | grep -i 'MASTER\|BACKUP'"
  # Expected: MASTER state on PRIMARY
  ```
  - Status: _________  Time: _________
  - PRIMARY Role: [ ] MASTER  [ ] BACKUP
  - REPLICA Role: [ ] MASTER  [ ] BACKUP (should be BACKUP)

---

## 🖥️ PHASE 5: CONTAINER & SERVICES VERIFICATION (10 minutes)

### Container Health - Infrastructure Lead
- [ ] **Docker Compose Status (PRIMARY)**
  ```bash
  ssh ubuntu@192.168.168.31 "cd /opt/gitlab && docker-compose ps | grep -E 'Up|Exited' | wc -l"
  # Expected: 87+ containers running
  ```
  - Status: _________  Time: _________
  - Containers Running: _________
  - Target: 87+ containers

- [ ] **Docker Compose Status (REPLICA)**
  ```bash
  ssh ubuntu@192.168.168.42 "cd /opt/gitlab && docker-compose ps | grep -E 'Up|Exited' | wc -l"
  # Expected: 88 containers running
  ```
  - Status: _________  Time: _________
  - Containers Running: _________
  - Target: 88 containers

- [ ] **Critical Services Check (PRIMARY)**
  ```bash
  ssh ubuntu@192.168.168.31 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'gitlab_unicorn|gitlab_db|gitlab_redis|gitlab_nginx'"
  # Expected: All 4 services running (Up)
  ```
  - Status: _________  Time: _________
  - unicorn: [ ] UP  [ ] DOWN
  - db: [ ] UP  [ ] DOWN
  - redis: [ ] UP  [ ] DOWN
  - nginx: [ ] UP  [ ] DOWN

---

## 🌐 PHASE 6: MONITORING STACK VERIFICATION (5 minutes)

### Prometheus - Operations Lead
- [ ] **Prometheus Endpoint**
  ```bash
  curl -s http://192.168.168.31:9090/-/healthy
  # Expected: 200 OK response
  ```
  - Status: _________  Time: _________
  - Response: [ ] 200 OK  [ ] ERROR

- [ ] **Prometheus Targets**
  ```bash
  curl -s http://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets | length'
  # Expected: 8+ active targets
  ```
  - Status: _________  Time: _________
  - Active Targets: _________

---

### Grafana - Operations Lead
- [ ] **Grafana Endpoint**
  ```bash
  curl -s http://192.168.168.31:3000/api/health
  # Expected: 200 OK (Grafana is ready)
  ```
  - Status: _________  Time: _________
  - Response: [ ] 200 OK  [ ] ERROR

- [ ] **Dashboards Available**
  ```bash
  curl -s http://192.168.168.31:3000/api/search | jq '. | length'
  # Expected: 3+ dashboards
  ```
  - Status: _________  Time: _________
  - Dashboard Count: _________

---

### AlertManager - Operations Lead
- [ ] **AlertManager Status**
  ```bash
  curl -s http://192.168.168.31:9093/-/healthy
  # Expected: 200 OK
  ```
  - Status: _________  Time: _________
  - Response: [ ] 200 OK  [ ] ERROR

- [ ] **Alerts Configuration**
  ```bash
  curl -s http://192.168.168.31:9093/api/v1/alerts | jq '.data | length'
  # Expected: 0 active alerts (or document any firing)
  ```
  - Status: _________  Time: _________
  - Active Alerts: _________

---

## 📋 PHASE 7: BACKUP VERIFICATION (5 minutes)

### Database Backups - Operations Lead
- [ ] **Latest Backup Exists (PRIMARY)**
  ```bash
  ssh ubuntu@192.168.168.31 "ls -lht /backups/*.dump 2>/dev/null | head -3"
  # Expected: Recent backup file dated today or yesterday
  ```
  - Status: _________  Time: _________
  - Latest Backup: _________
  - Date: _________
  - Size: _________

- [ ] **Backup Integrity Test**
  ```bash
  ssh ubuntu@192.168.168.31 "file /backups/$(ls -t /backups/*.dump 2>/dev/null | head -1)"
  # Expected: PostgreSQL custom format dump
  ```
  - Status: _________  Time: _________
  - Format: [ ] VALID  [ ] CORRUPTED

---

## 🎖️ FINAL SIGN-OFF

### Infrastructure Lead Sign-Off
**All items above verified and passed:** [ ] YES  [ ] NO (describe issues below)

**Signature:** _________________________ **Date/Time:** _________

**Notes/Issues (if any):**
```
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
```

---

### Operations Lead Sign-Off
**All items above verified and passed:** [ ] YES  [ ] NO (describe issues below)

**Signature:** _________________________ **Date/Time:** _________

**Notes/Issues (if any):**
```
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
```

---

### CTO/Executive Sponsor Final Approval

**CTO Decision:** [ ] GO FOR DEPLOYMENT  [ ] HOLD (describe below)

**Signature:** _________________________ **Date/Time:** _________

**If HOLD, Reason:**
```
_________________________________________________________________
_________________________________________________________________
```

---

## 🚨 ESCALATION PROCEDURES

If ANY item in this checklist is FAILED:

1. **Immediate:** Document exact failure point and timestamp
2. **Within 5 minutes:** Notify Operations Lead + Infrastructure Lead + CTO
3. **Within 15 minutes:** CTO decision on remediation vs. HOLD
4. **If HOLD:** Trigger PHASE_2B_CONTINGENCY_ROLLBACK_PROCEDURES.md Emergency Response section

### Emergency Escalation Contacts:
- **Infrastructure Lead:** [Name/Phone]
- **Operations Lead:** [Name/Phone]
- **CTO/Technical Lead:** [Name/Phone]
- **Executive Sponsor:** [Name/Phone]

---

## ⏱️ TIMELINE

| Phase | Duration | Start Time | End Time | Owner |
|-------|----------|-----------|----------|-------|
| Hardware Verification | 15 min | 04:00 UTC | 04:15 UTC | Infrastructure |
| Database Verification | 15 min | 04:15 UTC | 04:30 UTC | Infra + Ops |
| Redis Verification | 10 min | 04:30 UTC | 04:40 UTC | Infra + Ops |
| HA & Keepalived | 10 min | 04:40 UTC | 04:50 UTC | Infrastructure |
| Container & Services | 10 min | 04:50 UTC | 05:00 UTC | Infrastructure |
| **Monitoring & Backup** | **5 min** | **05:00 UTC** | **05:05 UTC** | **Operations** |
| **TOTAL** | **60+ min** | **04:00 UTC** | **05:05 UTC** | **Both** |

---

## ✅ SUCCESS CRITERIA FOR GO-LIVE

All of the following must be TRUE to declare GO FOR DEPLOYMENT:

- [ ] PRIMARY SSH access working
- [ ] REPLICA SSH access working
- [ ] Both nodes: >50GB disk, >30GB memory available
- [ ] Network connectivity verified (both directions)
- [ ] PostgreSQL primary + replica streaming replication active
- [ ] Redis primary + replica replication active
- [ ] Replication lag <5 seconds
- [ ] VIP (192.168.168.50) responding to ping
- [ ] Keepalived MASTER on PRIMARY, BACKUP on REPLICA
- [ ] 87+ containers on PRIMARY, 88 on REPLICA
- [ ] Critical services (unicorn, db, redis, nginx) all UP
- [ ] Prometheus 8+ targets active
- [ ] Grafana 3+ dashboards available
- [ ] AlertManager 0 active alerts (or documented)
- [ ] Latest database backup exists and valid
- [ ] Both Infrastructure Lead + Operations Lead signed off
- [ ] CTO approved GO FOR DEPLOYMENT

**If all 17 criteria above are TRUE → 🚀 DEPLOYMENT AUTHORIZED FOR 05:00 UTC MAY 1, 2026**

---

## 📞 SUPPORT

Questions during pre-flight? Contact:
- **Infrastructure Questions:** Infrastructure Lead
- **Database Questions:** Operations Lead (Database specialist)
- **Monitoring Questions:** Operations Lead (Monitoring specialist)
- **Major Issues:** Escalate immediately to CTO

---

**FINAL STATUS (to be filled on May 1 at 05:00 UTC):**

**Pre-Flight Checklist Complete:** [ ] YES  [ ] NO

**Deployment Ready:** [ ] GO 🚀  [ ] HOLD 🛑

**Authorized By:** CTO Signature: _________________ Time: _________

