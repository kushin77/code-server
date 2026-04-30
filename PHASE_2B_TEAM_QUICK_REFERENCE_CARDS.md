# PHASE 2B TEAM ROLE QUICK-REFERENCE CARDS

**Purpose:** One-page reference cards for each team role to bookmark and use during Week 1-3 deployment  
**Format:** Printable (fits on standard letter paper)
**Usage:** Post on wall or bookmark in browser

---

# 📋 INFRASTRUCTURE LEAD - QUICK REFERENCE

## WEEK 1 DAILY CHECKLIST (5 minutes each morning at 09:30 UTC)

```bash
# Health Check Script
echo "=== PRIMARY HEALTH CHECK ==="
ssh ubuntu@192.168.168.31 "docker ps | grep -c healthy"  # Expect: 87+
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT version();'"
ssh ubuntu@192.168.168.31 "docker exec gitlab_redis redis-cli PING"
ping -c 1 192.168.168.50  # VIP test

echo "=== REPLICA HEALTH CHECK ==="
ssh ubuntu@192.168.168.42 "docker ps | grep -c Up"  # Expect: 88+
ssh ubuntu@192.168.168.42 "docker exec gitlab_db psql -U postgres -c 'SELECT pg_is_in_recovery();'"  # Expect: t

echo "=== REPLICATION LAG ==="
ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (now() - pg_last_wal_receive_lsn_time())) as lag_sec;'"
```

## ESCALATION TRIGGERS (Contact Operations Lead if ANY are true)

- [ ] Docker daemon not responding (docker ps fails)
- [ ] Container count <85 on PRIMARY
- [ ] Replication lag >60 seconds
- [ ] VIP (192.168.168.50) not responding to ping
- [ ] SSH to REPLICA fails for >5 minutes
- [ ] Disk space <5GB on either node

## CRITICAL COMMANDS (Bookmark These)

| Task | Command |
|------|---------|
| Check all containers | `docker ps \| wc -l` |
| Check container health | `docker ps --format "table {{.Names}}\t{{.Status}}"` |
| View container logs (last 50 lines) | `docker logs --tail 50 [container_name]` |
| Restart container | `docker restart [container_name]` |
| Check disk space | `df -h /` |
| Check memory | `free -h` |
| Replication status | `docker exec gitlab_db psql -U postgres -c "SELECT * FROM pg_stat_replication;"` |
| Keepalived status | `docker exec gitlab_keepalived systemctl status keepalived` |
| Check network latency | `ping -c 5 192.168.168.42` |
| Force failover test | `docker stop gitlab_keepalived` (on PRIMARY) |

## WEEK 1-3 MILESTONES

| Week | Milestone | Sign-Off | Date |
|-----|-----------|----------|------|
| 1 | All 8 staging phases complete | Infrastructure Lead | __/__/__ |
| 2 | Production readiness verified | Infrastructure Lead | __/__/__ |
| 2-3 | Blue-green deployment complete | Infrastructure Lead | __/__/__ |
| 3+ | 72-hour observation passed | Infrastructure Lead | __/__/__ |

## EMERGENCY: VIP DOWN (Follow This Immediately)

```bash
# Step 1: Verify both nodes reachable
ping 192.168.168.31
ping 192.168.168.42

# Step 2: Check Keepalived status
ssh ubuntu@192.168.168.31 "docker ps | grep keepalived"
ssh ubuntu@192.168.168.42 "docker ps | grep keepalived"

# Step 3: Restart Keepalived (on PRIMARY first)
ssh ubuntu@192.168.168.31 "docker restart gitlab_keepalived"
sleep 5
ping 192.168.168.50

# Step 4: If still down, check REPLICA
ssh ubuntu@192.168.168.42 "docker restart gitlab_keepalived"
sleep 5
ping 192.168.168.50

# Step 5: If still down, escalate to CTO
```

## EMERGENCY CONTACTS

- **Operations Lead:** [Phone] [Email]
- **CTO:** [Phone] [Email]
- **Escalation:** Contact Operations Lead first

---

# 📋 OPERATIONS LEAD - QUICK REFERENCE

## WEEK 1 DAILY STANDUP (20 minutes at 10:00 AM UTC)

**Slides to Review (1 minute each):**
1. Infrastructure status (from Prometheus dashboard)
2. Database status (PRIMARY lag <5s? REPLICA in sync?)
3. Services running (docker ps shows 87+?)
4. Monitoring health (Prometheus targets up? Grafana updating?)
5. Any escalations today?

**Status Report Format:**
- [ ] All systems operational
- [ ] X issue(s) encountered: [list]
- [ ] Confidence level (HIGH/MEDIUM/LOW)
- [ ] Expected completion: [time]

## ESCALATION MATRIX

```
Issue Duration < 5 min  → Try quick troubleshooting first
Issue Duration 5-30 min → Document & try fixes in PHASE_2B_WEEK1_RAPID_RESPONSE_GUIDE.md
Issue Duration > 30 min → Escalate to CTO with full context
Critical Failure (multiple systems down) → Page CTO immediately
```

## MONITORING COMMANDS

```bash
# Prometheus dashboard
open http://192.168.168.31:9090/graph

# Grafana dashboards
open http://192.168.168.31:3000

# AlertManager
open http://192.168.168.31:9093

# Check all alerts
curl -s http://192.168.168.31:9093/api/v1/alerts | jq '.data | length'
```

## WEEK 1-3 GO/NO-GO CHECKPOINTS

| Week | Checkpoint | What to Verify | Date | Sign-Off |
|-----|-----------|---|---|---|
| 1 | End of Week 1 | All 8 staging phases complete | __/__/__ | [ ] |
| 2 | Day 4 | Production readiness Level 1 | __/__/__ | [ ] |
| 2 | Day 5 | Production readiness Level 2 | __/__/__ | [ ] |
| 2 | Day 6 | Production readiness Level 3 | __/__/__ | [ ] |
| 2 | Day 7 | Production readiness Level 4 | __/__/__ | [ ] GO |
| 3 | Day 9 | 72-hour observation complete | __/__/__ | [ ] SUCCESS |

## CONTINGENCY TRIGGERS (Reference PHASE_2B_CONTINGENCY_ROLLBACK_PROCEDURES.md if ANY occur)

- [ ] Multiple services fail simultaneously
- [ ] Replication broken for >30 minutes
- [ ] Data corruption detected
- [ ] Security incident detected
- [ ] Network partition between PRIMARY and REPLICA
- [ ] Both PRIMARY and REPLICA down

## BACKUP VERIFICATION (Daily at 16:00 UTC)

```bash
# Check latest backup
ssh ubuntu@192.168.168.31 "ls -lht /backups/*.dump | head -1"

# Expected output example:
# -rw-r--r-- 1 ubuntu ubuntu 2.4G Apr 30 12:30 /backups/gitlab_db_20260430_123000.dump

# Test backup integrity
ssh ubuntu@192.168.168.31 "file /backups/$(ls -t /backups/*.dump | head -1)"
# Expected: PostgreSQL custom format dump
```

## EMERGENCY CONTACTS

- **Infrastructure Lead:** [Phone] [Email]
- **CTO:** [Phone] [Email]
- **Database Specialist:** [Phone] [Email]

---

# 📋 MONITORING LEAD - QUICK REFERENCE

## DAILY MONITORING CHECKLIST (10 minutes at 09:00 UTC)

```bash
# Step 1: Check Prometheus health
curl http://192.168.168.31:9090/-/healthy  # Expect: 200 OK

# Step 2: Check active targets
curl -s http://192.168.168.31:9090/api/v1/targets \
  | jq '.data.activeTargets | length'  # Expect: 8+

# Step 3: List failed targets
curl -s http://192.168.168.31:9090/api/v1/targets \
  | jq '.data.activeTargets[] | select(.health=="down") | .labels.job'

# Step 4: Check Grafana
curl -s http://192.168.168.31:3000/api/health  # Expect: 200 OK

# Step 5: Check AlertManager
curl -s http://192.168.168.31:9093/api/v1/alerts | jq '.data | length'
# Expect: 0 (or document any firing alerts)
```

## CRITICAL METRICS TO WATCH

| Metric | Threshold | Action |
|--------|-----------|--------|
| Prometheus targets down | >1 | Investigate immediately |
| Grafana data stale | >5 min old | Check Prometheus |
| Active alerts | >0 | Review alert content |
| CPU usage | >80% | Check with Infrastructure |
| Memory usage | >85% | Check with Infrastructure |
| Disk usage | >80% | Alert Infrastructure |
| Replication lag | >30 sec | Alert Infrastructure |

## DASHBOARD PERFORMANCE BASELINE (Record at May 1 05:00 UTC)

| Metric | Baseline | Peak | Average |
|--------|----------|------|---------|
| API Response Time (p50) | _________ | _________ | _________ |
| API Response Time (p99) | _________ | _________ | _________ |
| Web Response Time (p50) | _________ | _________ | _________ |
| Database Query Time (p50) | _________ | _________ | _________ |
| Error Rate | _________ | _________ | _________ |

## PROMETHEUS QUERIES (Bookmark These)

```
# Check if targets healthy
up == 1

# Check replication lag (seconds)
pg_replication_lag_seconds

# Check container CPU usage (%)
rate(container_cpu_usage_seconds_total[5m]) * 100

# Check container memory (MB)
container_memory_usage_bytes / 1024 / 1024

# Check disk free (GB)
node_filesystem_avail_bytes / 1024 / 1024 / 1024
```

## ALERT CONFIGURATION (Reference PHASE_2B_MONITORING_CONFIG_TEMPLATES.md)

- [ ] 15+ alert rules configured
- [ ] Slack webhook working
- [ ] PagerDuty integration working
- [ ] Email notifications configured

## ESCALATION MATRIX

| Situation | Action | Contact |
|-----------|--------|---------|
| 1-2 targets down | Investigate | Infrastructure Lead |
| >2 targets down | Escalate | Operations Lead |
| Prometheus down | Restart container | Infrastructure Lead |
| Grafana down | Restart container | Infrastructure Lead |
| AlertManager down | Restart container + escalate | Operations Lead → CTO |

---

# 📋 QA/TEST LEAD - QUICK REFERENCE

## WEEK 1 TEST CHECKPOINTS

| Phase | Test | Pass Criteria | Date | Sign-Off |
|-------|------|---|---|---|
| 1 | Container startup | 87+ containers running | __/__/__ | [ ] |
| 2 | Database integrity | SELECT COUNT query returns >0 | __/__/__ | [ ] |
| 3 | Replication sync | Lag <5 seconds | __/__/__ | [ ] |
| 4 | Services responsive | All endpoints returning 200 | __/__/__ | [ ] |
| 5 | Load test | 6000 requests, 20 concurrent | __/__/__ | [ ] |
| 6 | Health checks | All health endpoints returning OK | __/__/__ | [ ] |
| 7 | Integration | Full workflow end-to-end | __/__/__ | [ ] |
| 8 | Regression | No new errors in logs | __/__/__ | [ ] |

## QUICK TEST COMMANDS

```bash
# Check service availability
curl -s http://192.168.168.50 | head -5

# Test database connectivity
docker exec gitlab_db psql -U postgres -c "SELECT 1;"

# Test Redis
docker exec gitlab_redis redis-cli PING

# Test load with ApacheBench
ab -n 6000 -c 20 http://192.168.168.50/

# Check error logs
docker logs gitlab_unicorn 2>&1 | grep -i error | tail -10
```

## SIGN-OFF REQUIREMENTS

- [ ] All 8 phases passed
- [ ] No critical defects found
- [ ] Performance baseline met
- [ ] No data loss detected
- [ ] All security checks passed

---

# 📋 SECURITY LEAD - QUICK REFERENCE

## WEEK 1 SECURITY CHECKLIST

- [ ] SSL/TLS certificates valid (not expired)
- [ ] Authentication working (can log in)
- [ ] RBAC enforced (permissions working)
- [ ] No SQL injection vulnerabilities detected
- [ ] No exposed credentials in logs
- [ ] Audit logging enabled
- [ ] Data encryption at rest
- [ ] Data encryption in transit

## CRITICAL COMMANDS

```bash
# Check SSL certificate
openssl s_client -connect 192.168.168.50:443 -showcerts

# Check authentication
curl -u test:test http://192.168.168.50/api/test

# Check logs for security issues
docker logs gitlab_unicorn 2>&1 | grep -i "access\|unauthorized\|forbidden" | tail -20

# Check for exposed credentials
docker logs gitlab_unicorn 2>&1 | grep -i "password\|secret\|key" | grep -v "encrypted"
```

## WEEK 2-3 COMPLIANCE CHECKS

- [ ] GDPR compliance verified
- [ ] Data retention policy enforced
- [ ] Backup encryption enabled
- [ ] Access logs retained (30 days)
- [ ] Incident response plan ready

---

# 📋 PROJECT MANAGER - QUICK REFERENCE

## WEEK 1-3 MILESTONE TRACKING

```
Week 1: Staging Deployment (May 1-12)
├─ Days 1-4: GitHub PR process
├─ Days 5-12: 8-phase staging deployment
└─ Checkpoint: All phases PASSED

Week 2: Production Preparation (May 8-14)
├─ Days 1-3: Backup & pre-checks
├─ Days 4-7: 4-level production sign-offs
└─ Checkpoint: All 4 sign-offs obtained

Week 2-3: Production Deployment (May 15-21+)
├─ Day 1: Pre-deployment checks
├─ Days 2-6: Blue-green deployment
├─ Days 7-9: 72-hour observation
└─ Checkpoint: Deployment SUCCESSFUL
```

## GO/NO-GO DECISION POINTS

| Date | Checkpoint | Decision Required |
|------|-----------|---|
| May 12 (EOD) | Week 1 complete? | GO/NO-GO for Week 2 |
| May 14 (EOD) | All sign-offs obtained? | GO/NO-GO for Week 2-3 |
| May 21 (72h) | 72-hour observation passed? | DEPLOYMENT SUCCESSFUL |

## DAILY STATUS TEMPLATE (Send to stakeholders at 18:00 UTC)

**Status:** ON TRACK / AT RISK / BEHIND

**Today's Accomplishments:**
- [ ] Task 1: _______________
- [ ] Task 2: _______________

**Tomorrow's Plan:**
- [ ] Task 1: _______________
- [ ] Task 2: _______________

**Blockers:** None / [describe]

**Confidence:** HIGH / MEDIUM / LOW

---

## EMERGENCY RESPONSE (If deployment blocked)

1. **Immediately:** Convene emergency standup (all 6 leads)
2. **Within 5 min:** Identify blocker and escalate to CTO
3. **Within 15 min:** Develop mitigation plan
4. **Within 30 min:** Execute mitigation or declare HOLD
5. **Decision:** Proceed or Rollback?

---

# 📞 ALL TEAMS - EMERGENCY CONTACTS

**Primary Escalation:**
- Operations Lead: [Phone] [Email]

**Secondary Escalation:**
- CTO/Technical Lead: [Phone] [Email]

**Backup On-Call:**
- [Name]: [Phone]

**After Hours Emergency:**
- [Escalation Number]

---

**Print & Bookmark These Cards - Keep at Your Desk During Deployment**

