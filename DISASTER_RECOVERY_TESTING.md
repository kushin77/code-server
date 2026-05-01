# Disaster Recovery Testing & Validation - Code-Server Platform
**Date:** May 1, 2026  
**Status:** DR Testing Procedures Ready  
**Audience:** DevOps, SRE, Incident Response Team

---

## Document Purpose

Complete procedures for validating disaster recovery capabilities. Includes:
- ✅ DR testing scenarios
- ✅ Failover procedures
- ✅ Data recovery testing
- ✅ Communication procedures
- ✅ Post-recovery validation
- ✅ Documentation and metrics

---

## Part 1: Disaster Recovery Overview

### Redundancy Architecture

| Component | Primary | Standby | Failover Time |
|-----------|---------|---------|---------------|
| **Database (PostgreSQL)** | 192.168.168.31 | 192.168.168.42 (replica) | Manual (5-10 min) |
| **Cache (Redis)** | Primary | Sentinel (auto) | Automatic (30 sec) |
| **Object Storage (Minio)** | Primary | Replica | Manual (10-15 min) |
| **Services** | Caddy/router on both | Load balanced | Automatic (health check) |
| **Virtual IP** | VIP: 192.168.168.50 | Keepalived/VRRP | Automatic (<2 sec) |

### Recovery Point Objectives (RPO & RTO)

| Scenario | RPO | RTO | Priority |
|----------|-----|-----|----------|
| **Single container down** | None (stateless) | <30 sec | P2 |
| **Database replica lag** | <5 sec | <1 min | P1 |
| **Primary host network partition** | <1 min | <2 min | P1 |
| **Primary host complete failure** | <1 min | 10-15 min | P1 |
| **Data corruption detected** | 24 hours | 2-4 hours | P2 |
| **Ransomware infection** | 24 hours | 4-8 hours | P0 |

---

## Part 2: Pre-Testing Checklist

**Before running any DR test:**

- [ ] Scheduled maintenance window (off-hours)
- [ ] Team communication sent (Slack + email)
- [ ] Monitoring team notified (will see alerts)
- [ ] Backup of current state taken
- [ ] Runbook reviewed and accessible
- [ ] Communication channels ready (Slack, conference bridge)
- [ ] Rollback procedure documented
- [ ] Success criteria defined

### Communication Template

**Slack announcement:**
```
🔄 SCHEDULED MAINTENANCE: Disaster Recovery Test

START: [DATE] [TIME] UTC
EXPECTED DURATION: [XX] minutes
IMPACT: [Unavailability, degraded performance, etc.]
REASON: DR testing to validate failover procedures

Will update status in #status-page channel every 5 minutes.
Questions? Contact @ops-lead
```

---

## Part 3: Test 1 - Single Container Failure

**Objective:** Validate automatic recovery of failed stateless containers  
**Duration:** 10 minutes  
**Risk Level:** Low (automatic restart)

### Procedure

1. **Document current state:**
```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server
docker compose ps > /tmp/before_test.txt
```

2. **Stop a stateless container:**
```bash
docker compose stop api-gateway
# OR forcefully kill it:
docker compose kill api-gateway
```

3. **Verify it's down:**
```bash
docker compose ps | grep api-gateway
# Should show "Exited" or not running
```

4. **Monitor recovery:**
```bash
# Wait 30 seconds, then check
sleep 30
docker compose ps | grep api-gateway
# Should show "Up" - it auto-restarted!
```

5. **Verify service is healthy:**
```bash
curl -s http://localhost:8080/health | jq .
# Should return 200 with healthy status
```

### Success Criteria

- ✅ Container shows "Up" after restart
- ✅ Health endpoint returns 200
- ✅ No manual intervention required
- ✅ Logs show clean restart

### Troubleshooting

| Issue | Fix |
|-------|-----|
| Container doesn't restart | Check docker compose config for `restart: always` |
| Health check fails | Review service logs: `docker compose logs api-gateway` |
| Restart takes >2 min | Check resource constraints: `docker stats` |

---

## Part 4: Test 2 - Database Failover (Replica Promotion)

**Objective:** Validate PostgreSQL replica can be promoted to primary  
**Duration:** 30-45 minutes  
**Risk Level:** High (potential data loss if not done carefully)

### Pre-Test Validation

```bash
# Check replication status on primary
ssh akushnir@192.168.168.31
docker compose exec postgres psql -U postgres -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"
# Should show replication slot active

# Check replica has caught up
docker compose exec postgres psql -U postgres -c "SELECT now() - pg_last_wal_receive_time() AS replication_delay;"
# Should be <1 second
```

### Failover Procedure

**IMPORTANT: Only do this if primary is PERMANENTLY DOWN**

1. **Verify primary is unreachable:**
```bash
ping -c 3 192.168.168.31
ssh akushnir@192.168.168.31 'echo "test"'
# Both should fail
```

2. **SSH to replica host:**
```bash
ssh akushnir@192.168.168.42
cd /home/akushnir/code-server
```

3. **Stop replica services (PostgreSQL only):**
```bash
docker compose stop postgres
```

4. **Promote replica to primary:**
```bash
# This makes it a standalone database (can't replicate further)
docker compose exec postgres pg_ctl -D /var/lib/postgresql/data promote
# OR (if pg_ctl doesn't work):
docker compose exec postgres psql -U postgres -c "SELECT pg_promote();"
```

5. **Verify promotion successful:**
```bash
docker compose logs postgres | tail -20
# Should see "wal receiver process shut down"
# Should see "database is now in production mode"
```

6. **Restart all services on replica (now primary):**
```bash
docker compose up -d
```

7. **Verify services are healthy:**
```bash
docker compose ps
# All should show "Up"

curl -s http://localhost:8080/health | jq .
# Should return healthy
```

### Post-Failover

**If primary comes back up:**
1. Do NOT automatically make it primary again
2. Join it as new replica:
```bash
# On the host that was original primary
docker compose stop
# Remove old data
rm -rf data/postgres/*
# Restore from replica via WAL streaming
docker compose up -d
```

### Success Criteria

- ✅ Replica promoted to standalone primary
- ✅ Applications connect to new primary (may need DNS/VIP update)
- ✅ Replication slots cleaned up
- ✅ Data integrity verified
- ✅ All services healthy on new primary

### Rollback (If Needed)

If promotion caused issues, revert to old primary:
```bash
# Restore from backup
# OR restart old primary and accept data loss
```

---

## Part 5: Test 3 - Network Partition Simulation

**Objective:** Validate behavior when primary and replica can't communicate  
**Duration:** 15-20 minutes  
**Risk Level:** Medium (partial outage)

### Procedure

1. **Verify connectivity baseline:**
```bash
# On primary
ssh akushnir@192.168.168.31
ping -c 3 192.168.168.42
# Should succeed
```

2. **Simulate network partition:**
```bash
# Block traffic from primary to replica
sudo iptables -A OUTPUT -d 192.168.168.42 -j DROP
sudo iptables -A INPUT -s 192.168.168.42 -j DROP
```

3. **Verify partition:**
```bash
ping -c 3 192.168.168.42
# Should timeout/fail
```

4. **Monitor system behavior:**
```bash
# Check replication status
docker compose logs postgres | grep -i "replication\|error\|connection" | tail -20

# Check if services still responding
curl -s http://localhost:8080/health

# Monitor for automatic failover (check Keepalived/VIP)
ip addr show | grep 192.168.168.50
```

5. **Restore connectivity:**
```bash
# Remove iptables rules
sudo iptables -D OUTPUT -d 192.168.168.42 -j DROP
sudo iptables -D INPUT -s 192.168.168.42 -j DROP

# Verify restored
ping -c 3 192.168.168.42
# Should succeed
```

6. **Verify recovery:**
```bash
docker compose logs postgres | grep -i "replication" | tail -5
# Should show replication reconnected

# Check replication lag
docker compose exec postgres psql -U postgres -c "SELECT now() - pg_last_wal_receive_time();"
# Should be small again
```

### Success Criteria

- ✅ Partition detected by system
- ✅ Alerts fired for replication lag
- ✅ Connection reestablished automatically after 5 min
- ✅ Replication resumes without manual intervention
- ✅ No data loss

---

## Part 6: Test 4 - Storage Failure Simulation

**Objective:** Validate behavior when storage becomes unavailable  
**Duration:** 20-25 minutes  
**Risk Level:** Medium (if Minio is down, object storage unavailable)

### Procedure

1. **Verify Minio is healthy:**
```bash
ssh akushnir@192.168.168.31
curl -s http://localhost:9000/health | jq .
```

2. **Stop Minio service:**
```bash
docker compose stop minio
```

3. **Monitor alerting:**
```bash
# Check that Alertmanager fired alerts
curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | select(.status.state=="firing")'
# Should see Minio down alert

# Check Slack received notification
# Look for alert in #code-server-alerts channel
```

4. **Verify services gracefully degrade:**
```bash
# Try operations that don't need Minio (should work)
curl -s http://localhost:8080/health

# Try operations that need Minio (should fail gracefully)
# Check logs for appropriate errors
docker compose logs api-gateway | grep -i "minio\|storage" | tail -10
```

5. **Restart Minio:**
```bash
docker compose up -d minio

# Wait for startup
sleep 10

# Verify it came back
curl -s http://localhost:9000/health
```

6. **Monitor recovery:**
```bash
# Verify alerts cleared
curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | select(.labels.alertname=="MinioDown")'
# Should be empty
```

### Success Criteria

- ✅ Alert fired within 1 minute
- ✅ Alert notification sent to Slack
- ✅ Services gracefully handle missing storage
- ✅ Automatic restart succeeds
- ✅ Alert clears within 2 minutes of restart

---

## Part 7: Test 5 - Full Primary Host Failure

**Objective:** Validate complete primary host failure and recovery  
**Duration:** 60 minutes  
**Risk Level:** Very High (full service outage)

### Prerequisites

- **Test in staging only, not production**
- **Coordinate with full team**
- **Have backup access/recovery key ready**
- **Post-incident review scheduled**

### Procedure

1. **Document current state on both hosts:**
```bash
# Primary
ssh akushnir@192.168.168.31
df -h /home
du -sh *
docker compose ps > /tmp/primary_baseline.txt

# Replica
ssh akushnir@192.168.168.42
df -h /home
docker compose ps > /tmp/replica_baseline.txt
```

2. **Simulate total outage:**
```bash
# Option 1: Stop all services on primary
ssh akushnir@192.168.168.31
docker compose down
# OR
# Option 2: Drop all network traffic (full partition)
# sudo iptables -I INPUT -j DROP
```

3. **Monitor failover process:**
```bash
# On replica, watch for automatic takeover
ssh akushnir@192.168.168.42
watch docker compose ps

# Monitor VIP migration (if using Keepalived)
watch 'ip addr show | grep 192.168.168.50'

# Monitor traffic routing
watch 'iptables -L -v -n | grep 192.168.168'
```

4. **Verify services failover:**
```bash
# Replica should now be serving traffic
ssh akushnir@192.168.168.42
curl -s http://localhost/health
docker compose logs | grep "elected\|primary\|active" | tail -10
```

5. **Document failover time:**
```
Time from primary down: _____ seconds
Time to full recovery: _____ minutes
Services still degraded: _____
Data loss: _____ records
```

6. **Recover primary:**
```bash
# Bring primary back online
ssh akushnir@192.168.168.31
docker compose up -d

# OR restore from backup if corrupted
```

7. **Rejoin primary as replica:**
```bash
# On primary (now rejoining cluster)
docker compose stop
rm -rf data/postgres/*  # Clear old state
docker compose up -d

# Monitor replication resume
docker compose logs postgres | grep -i "replication" | tail -5
```

### Success Criteria

- ✅ Failover completed within 5 minutes
- ✅ All critical services available on replica
- ✅ Zero data loss (or <1 minute)
- ✅ Automatic DNS/VIP update worked
- ✅ Primary rejoin smooth and automatic

### Post-Test

```bash
# Verify both hosts healthy
for host in 192.168.168.31 192.168.168.42; do
  echo "=== $host ==="
  ssh akushnir@$host 'docker compose ps | head -20'
done

# Check replication lag
ssh akushnir@192.168.168.31
docker compose exec postgres psql -U postgres -c "SELECT now() - pg_last_wal_receive_time();"
```

---

## Part 8: DR Test Metrics & Documentation

### After Each Test - Complete This Log

```
DR TEST LOG
===========
Date: _______________
Test Type: _______________
Duration: _______________ minutes
Team Members: _______________

PREPARATION
☐ Communication sent
☐ Runbook reviewed
☐ Backup taken
☐ Success criteria defined

EXECUTION
Start Time: _______________
End Time: _______________
Issues Encountered: _____________________________
Mitigations Applied: _____________________________

METRICS
Failover Time: _______________ seconds
Recovery Time: _______________ minutes
Data Loss: _______________ records
Alerts Fired: Yes / No
Alerts Cleared: Yes / No
SLA Compliance: Yes / No

SUCCESS CRITERIA
☐ [Criterion 1]
☐ [Criterion 2]
☐ [Criterion 3]

LESSONS LEARNED
What Went Well:
- _____________________________
- _____________________________

What Could Improve:
- _____________________________
- _____________________________

Action Items:
- [ ] _____________________________
- [ ] _____________________________

SIGN-OFF
Executed By: _______________
Reviewed By: _______________
Date: _______________
```

---

## Part 9: DR Testing Schedule

### Recommended Testing Cadence

| Test | Frequency | Duration | Risk | When |
|------|-----------|----------|------|------|
| Single container failure | Monthly | 10 min | Low | Anytime |
| Database replication lag | Quarterly | 15 min | Low | Off-hours |
| Network partition | Quarterly | 20 min | Medium | Scheduled |
| Storage failure | Semi-annually | 25 min | Medium | Scheduled |
| Full primary failure | Annually | 60 min | Very High | Scheduled |

### Sample Schedule

```
May 2026: Single container test (all team members)
June 2026: Database replication test (DBA focus)
July 2026: Network partition test
August 2026: Storage failure test
September 2026: Full primary failure test (production readiness)
```

---

## Part 10: Automated DR Validation

### Continuous Validation Script

```bash
#!/bin/bash
# Daily automated DR health check

echo "=== DR Health Check ==="
date

# 1. Verify replication active
REPL_STATUS=$(docker exec postgres psql -U postgres -c "SELECT slot_active FROM pg_replication_slots LIMIT 1;" | grep -i true)
if [ -z "$REPL_STATUS" ]; then
  echo "❌ Replication NOT active"
  exit 1
else
  echo "✅ Replication active"
fi

# 2. Check replication lag
LAG=$(docker exec postgres psql -U postgres -c "SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_wal_receive_time())) AS seconds;" | grep -o '[0-9]*\.' | head -1)
if (( $(echo "$LAG > 5" | bc -l) )); then
  echo "⚠️  Replication lag: ${LAG}s (threshold: 5s)"
else
  echo "✅ Replication lag acceptable: ${LAG}s"
fi

# 3. Test failover readiness
if docker compose exec postgres pg_isready -U postgres > /dev/null 2>&1; then
  echo "✅ PostgreSQL responsive"
else
  echo "❌ PostgreSQL not responsive"
  exit 1
fi

# 4. Verify VIP healthy
if ping -c 1 192.168.168.50 > /dev/null 2>&1; then
  echo "✅ VIP (192.168.168.50) reachable"
else
  echo "❌ VIP unreachable"
  exit 1
fi

echo "=== DR Ready ==="
```

**Schedule as daily cron job:**
```bash
0 2 * * * /home/akushnir/code-server/scripts/dr/validate-readiness.sh | mail -s "DR Health Check" ops@company.com
```

---

## Part 11: DR Testing Troubleshooting

### "Database won't promote"

```bash
# Check if promotion command exists
docker compose exec postgres which pg_promote

# Check PostgreSQL logs for errors
docker compose logs postgres | grep -i "error\|failed\|promote"

# Try manual promotion
docker compose exec postgres sudo -u postgres pg_ctl -D /var/lib/postgresql/data promote
```

### "VIP doesn't migrate"

```bash
# Check Keepalived status
docker compose logs keepalived | tail -20

# Check VRRP configuration
docker compose exec keepalived cat /etc/keepalived/keepalived.conf

# Manually trigger failover
docker compose restart keepalived
```

### "Services stay down after failover"

```bash
# Check dependencies
docker compose logs | grep -i "connection refused\|timeout"

# Start services in correct order
docker compose up -d postgres redis vault
# Wait 30 seconds
docker compose up -d
# Verify
docker compose ps
```

---

## Part 12: DR Communication Plan

### During DR Test

**Timeline of updates:**
- **T+0 min:** "Test started - partial outage expected"
- **T+5 min:** "Failover in progress - monitoring"
- **T+10 min:** "Recovery phase - services restoring"
- **T+20 min:** "All services restored - validation in progress"
- **T+25 min:** "Test complete - normal operations resumed"

### Slack Updates

```
🧪 [DR TEST] Disaster Recovery Test in Progress

Phase 1: System partition simulated
Expected Duration: 30 minutes
Impact: Services may be unavailable or degraded

Next Update in 5 minutes...
```

### Post-Test Report Template

```markdown
# Disaster Recovery Test Report
**Date:** May XX, 2026  
**Test Type:** [Type]  
**Duration:** [XX] minutes  

## Results
✅ [Criterion 1 - PASS]
✅ [Criterion 2 - PASS]
⚠️ [Criterion 3 - ISSUE - Resolution: ...]

## Metrics
- Failover Time: X seconds ✅ < 5 min target
- Data Loss: 0 records ✅ No data loss
- Recovery Time: X minutes ✅ < Y min target

## Lessons Learned
...

## Action Items
...
```

---

## DR Testing Success Criteria

✅ All planned tests completed quarterly  
✅ All tests documented with results  
✅ Zero unexpected failures during tests  
✅ Team trained and confident in procedures  
✅ Runbooks updated based on learnings  
✅ Automated health checks passing  
✅ Recovery time consistently <RTO  

---

**Questions?** Review the specific test section or contact your DR lead.

**Next Steps:**
1. Schedule first DR test (60 days from now)
2. Select test team members
3. Update team calendar
4. Review this document in team meeting
