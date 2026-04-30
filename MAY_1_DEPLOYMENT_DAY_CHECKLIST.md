# May 1 Deployment Day - Hour-by-Hour Timeline & Checklist

**Date:** May 1, 2026  
**Timeline:** 06:00 UTC - 10:00 UTC  
**Team:** DevOps, On-Call L1/L2, QA, Operations Manager  

---

## DEPLOYMENT DAY CRITICAL PATH

```
06:00 ─────── Team Assembles (All roles present)
06:00 ─────── Go/No-Go Review
06:15 ─────── Pre-Deployment Verification (7-item checklist)
06:45 ─────── Team Standby (Ready for PostgreSQL replication fix)
08:00 ─────── PostgreSQL Replication Fix Begins (CRITICAL - MUST SUCCEED)
08:30 ─────── Replication Fix Complete + Verified (Escalate if failed)
08:45 ─────── Final Go/No-Go Decision (All systems ready?)
09:00 ─────── Main Deployment Begins
09:30 ─────── Deployment Complete - Health Check
10:00 ─────── 24-Hour Monitoring Window Active
```

---

## 06:00 UTC - TEAM ASSEMBLY (15 minutes)

### Who Should Be Present
- [ ] DevOps Lead (orchestrating)
- [ ] DevOps Engineer (PostgreSQL replication fix)
- [ ] On-Call L1 (monitoring alerts)
- [ ] On-Call L2 (escalation support)
- [ ] QA Lead (validation testing)
- [ ] Operations Manager (communication)

### Initial Briefing (5 minutes)
- [ ] Review critical path timeline (everyone knows timing)
- [ ] Confirm all systems accessible (SSH, dashboards, logs)
- [ ] Verify escalation contacts available
- [ ] Confirm communication channels open (Slack #deployment, email)

### Systems Checks (10 minutes)
- [ ] SSH access to 192.168.168.31 (primary) - ✅ Working
- [ ] SSH access to 192.168.168.42 (replica) - ✅ Working
- [ ] Prometheus dashboard accessible - ✅ Working
- [ ] Grafana dashboard accessible - ✅ Working
- [ ] AlertManager accessible - ✅ Working
- [ ] Slack notifications connected - ✅ Working
- [ ] Email notifications configured - ✅ Working

### **Go/No-Go Decision Point #1**
- **Question:** Can all team members access all systems?
- **If YES:** Proceed to 06:15 Pre-Deployment Verification
- **If NO:** Delay deployment, troubleshoot access issues

---

## 06:15 UTC - PRE-DEPLOYMENT VERIFICATION (30 minutes)

### Run Full Infrastructure Validation
```bash
ssh ubuntu@192.168.168.31
cd /home/ubuntu/code-server
bash final-infrastructure-validation.sh
```

**Monitor these 7 critical items:**

| Item | Check Command | Expected | Status |
|------|---------------|----------|--------|
| **Connectivity** | `ping 192.168.168.31` | PONG | ☐ |
| **Containers** | `docker-compose ps \| grep -c Up` | ≥ 87 | ☐ |
| **PostgreSQL Replication** | `pg_is_in_recovery()` | `t` (replica) | ☐ |
| **Replication Lag** | Check replication lag query | < 5s | ☐ |
| **Redis Status** | `redis-cli PING` | PONG | ☐ |
| **API Health** | `curl /health` | 200 OK | ☐ |
| **Monitoring Active** | `curl 9090/api/v1/targets` | Targets up | ☐ |

### Review Validation Report
```bash
cat infrastructure-validation-report-*.txt
```

**Expected outcomes:**
- ✅ All checks passing (green)
- ✅ 0 failures (red items)
- ✅ < 5 warnings is acceptable
- ✅ Final status: "READY FOR DEPLOYMENT"

### **Go/No-Go Decision Point #2**
- **Question:** Do all 7 critical items pass validation?
- **If YES:** All items checked ✅ → Proceed to 06:45 Standby
- **If NO:** Review failed items below

**If Item Fails - Troubleshoot:**

```
Containers < 87?
  → Check: docker-compose ps
  → Action: docker-compose restart <service>
  → Wait: 2 minutes for startup
  → Recount: docker-compose ps | grep -c Up
  → If still < 87 after restart: ESCALATE TO L2

PostgreSQL Replication NOT active (pg_is_in_recovery = f)?
  → This is CRITICAL - must fix before deployment
  → Procedure: Continue to 08:00 PostgreSQL Replication Fix
  → Current plan already accounts for this

Replication Lag > 5s?
  → Check: docker logs code-server-postgres
  → Check: Replica CPU/memory load
  → Action: If high: restart replica
  → If lag > 30s: ESCALATE TO L2, delay deployment

API Not Responding?
  → Check: docker logs api-server | tail -30
  → Check: curl api-server:8000/health
  → Action: docker-compose restart api-server
  → Wait: 30 seconds
  → Retest: curl localhost:8000/health

Monitoring Not Active?
  → Check: docker logs prometheus | tail -20
  → Action: docker-compose restart prometheus alertmanager
  → Verify: curl localhost:9090 (should load)
  → If still failing: ESCALATE, can proceed with monitoring
```

---

## 06:45 UTC - TEAM STANDBY (15 minutes)

### Pre-PostgreSQL Replication Fix Staging

**DevOps Engineer Tasks:**
- [ ] SSH to replica server (192.168.168.42)
- [ ] Verify orchestrate-postgresql-replication-fix.sh exists
```bash
ssh ubuntu@192.168.168.42
cd /home/ubuntu/code-server
ls -la orchestrate-postgresql-replication-fix.sh
```
- [ ] Read through script (2 minutes) - understand what will happen
- [ ] Confirm understanding with DevOps Lead
- [ ] **WAIT FOR 08:00 UTC SIGNAL** (ready to execute)

**DevOps Lead Tasks:**
- [ ] Set timer for 08:00 UTC (exactly)
- [ ] Brief team on what happens at 08:00
- [ ] Confirm PostgreSQL replication fix is the ONLY thing running 08:00-08:30
- [ ] No other deployments, restarts, or changes during this window
- [ ] Have escalation path clear (L2 contact ready)

**On-Call L1 Tasks:**
- [ ] Open AlertManager dashboard
- [ ] Open Prometheus dashboard
- [ ] Have alert acknowledgment process ready
- [ ] Brief: During fix, may see transient alerts (normal)
- [ ] Do NOT auto-restart containers during 08:00-08:30

**QA Tasks:**
- [ ] Have test scripts ready for 09:30 health check
- [ ] Prepare: API endpoint test, data validation, health check
- [ ] **Standby** (don't start testing yet)

**Communication:**
- [ ] All systems ready
- [ ] All roles standing by
- [ ] Message to Slack: "✅ Pre-deployment checks complete, standing by for PostgreSQL replication fix at 08:00 UTC"

### **Go/No-Go Decision Point #3**
- **Question:** Is team assembled, validation passed, and ready?
- **If YES:** Post to Slack "🚀 Standing by for 08:00 UTC fix" → Proceed to 08:00
- **If NO:** Resolve issues, report delay

---

## 08:00 UTC - POSTGRESQL REPLICATION FIX (CRITICAL - 30 minutes)

### ⚠️ THIS IS THE CRITICAL PATH ITEM

**DO NOT SKIP THIS** - PostgreSQL replication must be 100% active before main deployment at 09:00.

### DevOps Engineer Executes Fix
```bash
# On replica (192.168.168.42)
cd /home/ubuntu/code-server
bash orchestrate-postgresql-replication-fix.sh

# Expected output:
# [00:00] Starting PostgreSQL replication fix...
# [02:15] Checking permissions...
# [05:30] Verifying replication...
# [15:45] Docker Compose update...
# [20:00] Complete!
```

**Time breakdown:**
- 08:00 - Fix starts
- 08:05 - Permission corrections applied
- 08:10 - Verification queries running
- 08:15 - Docker compose restart
- 08:20 - Replica coming back online
- 08:25 - Final verification
- 08:30 - Fix complete (or escalate if failed)

### DevOps Lead Monitors Execution
- [ ] Watch for error messages (script logs to STDOUT)
- [ ] Monitor replication lag query on primary
- [ ] **Do not interrupt the script**
- [ ] If script hangs > 5 minutes: Ctrl+C, troubleshoot, re-run

### On-Call L1 Monitors Alerts
- [ ] Watch Prometheus for alerts
- [ ] Expected: Possible temporary alerts during restart
- [ ] Do NOT acknowledge/auto-resolve yet
- [ ] Just monitor, don't interfere

### Verification at 08:25 UTC (on primary)
```bash
# Run this while script finishing
docker exec code-server-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Expected: t (true)

docker exec code-server-postgres psql -U postgres -c \
  "SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp())) \
   FROM pg_stat_replication;"
# Expected: < 5.0
```

### **Critical Decision Point #4**

**At 08:30 UTC - Script Complete?**
- [ ] Script finished without errors? → YES
- [ ] pg_is_in_recovery() = t? → YES
- [ ] Replication lag < 5 seconds? → YES

**If ALL YES:**
- ✅ PostgreSQL replication ACTIVE
- ✅ Ready for main deployment at 09:00
- ✅ Proceed to 08:45 Final Go/No-Go

**If ANY NO (failure detected):**
- ❌ Script failed or replication not active
- ❌ **DO NOT PROCEED** with 09:00 deployment
- ❌ Escalate immediately to L2 engineer
- ❌ Options: 1) Retry fix, 2) Delay deployment, 3) Activate standby procedure

---

## 08:45 UTC - FINAL GO/NO-GO DECISION (15 minutes)

### Re-Run Quick Infrastructure Check
```bash
bash final-infrastructure-validation.sh
```

**Must pass:**
- [ ] PostgreSQL replication: ✅ ACTIVE
- [ ] Replication lag: < 5 seconds ✅
- [ ] Containers: ≥ 87 running ✅
- [ ] API responding: ✅ 200 OK
- [ ] Monitoring operational: ✅

### Team Final Confirmation
- [ ] PostgreSQL Replication: Ready? → YES ☐
- [ ] Backups Current: Ready? → YES ☐
- [ ] Monitoring Active: Ready? → YES ☐
- [ ] Team Assembled: Ready? → YES ☐
- [ ] QA Standing By: Ready? → YES ☐

### **FINAL GO/NO-GO DECISION**

**GO for 09:00 deployment if:**
- ✅ All 5 team members confirm ready
- ✅ All infrastructure checks passing
- ✅ PostgreSQL replication 100% active
- ✅ No critical issues

**NO-GO (DELAY) if:**
- ❌ Any infrastructure check failed
- ❌ PostgreSQL replication not active
- ❌ Any team member not ready
- ❌ Critical alert in monitoring

### Decision Communication
**GO:** Post to Slack: "🟢 GO - Deployment starting at 09:00 UTC"
**NO-GO:** Post to Slack: "🔴 NO-GO - Delay reason: [specific issue]"

---

## 09:00 UTC - MAIN DEPLOYMENT BEGINS (30 minutes)

### Deployment Execution Tasks

**DevOps Lead:**
- [ ] 09:00 - Execute main deployment procedure
- [ ] Monitor for any new errors
- [ ] Keep team updated (Slack every 5 minutes)

**On-Call L1:**
- [ ] Monitor Prometheus alerts
- [ ] Acknowledge non-critical alerts (log for review)
- [ ] Escalate to L2 if critical alert fires

**On-Call L2:**
- [ ] Standby for emergencies
- [ ] Have remediation procedures ready
- [ ] Review logs as needed

**QA Lead:**
- [ ] Standby
- [ ] Prepare health check procedures

### Deployment Procedure
```bash
# This will be specific to your deployment
# Reference: MAY_1_COMPLETE_DEPLOYMENT_PACKAGE.md
# Execute: [specific steps from deployment procedure]

# Expected duration: 20-25 minutes
# Expected completion: ~09:25 UTC
```

### **Go/No-Go Decision Point #5**
**At 09:25 UTC - Deployment Complete?**
- [ ] All deployment steps completed? → YES
- [ ] No critical errors in logs? → YES
- [ ] Monitoring showing healthy? → YES

**If YES:** Proceed to 09:30 Health Check
**If NO:** Assess situation, may need to rollback

---

## 09:30 UTC - HEALTH CHECK & VALIDATION (15 minutes)

### Immediate Health Checks
```bash
# API health
curl http://localhost:8000/health
# Expected: 200 OK with healthy status

# PostgreSQL health
docker exec code-server-postgres psql -U postgres -c "SELECT VERSION();"
# Expected: PostgreSQL version info

# Redis health
docker-compose exec redis redis-cli INFO server
# Expected: Redis server info

# Container status
docker-compose ps | grep -c Up
# Expected: ≥ 87 Up
```

### Monitoring Dashboard Check
- [ ] Prometheus: All targets up ✅
- [ ] Grafana: Dashboards showing data ✅
- [ ] AlertManager: No critical alerts ✅

### QA Validation Tests
```bash
# Execute health check script
bash verify-backups.sh

# Test API endpoints
curl http://localhost:8000/api/v1/status | jq '.'

# Test database queries
docker exec code-server-postgres psql -U postgres \
  -c "SELECT COUNT(*) as row_count FROM information_schema.tables;"
```

### **Success Determination**

**Deployment SUCCESS if:**
- ✅ All health checks pass
- ✅ No critical alerts
- ✅ API responding
- ✅ Databases healthy
- ✅ Monitoring operational

**Deployment PARTIAL if:**
- ⚠️ Some warnings present
- ⚠️ No critical failures
- ⚠️ System operational but degraded

**Deployment FAILED if:**
- ❌ Critical alerts firing
- ❌ API not responding
- ❌ Database connectivity issues
- ❌ > 5 containers down

---

## 10:00 UTC - DEPLOYMENT COMPLETE (Monitoring Window Begins)

### Post-Deployment Status
- [ ] Deployment completed at: _________ UTC
- [ ] Success level: ☐ Full Success ☐ Partial Success ☐ Failed
- [ ] Outstanding issues: _______________________

### 24-Hour Monitoring Window Active
**On-Call team continues monitoring for 24 hours:**
- Check infrastructure every 15 minutes
- Monitor replication lag (should stay < 100ms)
- Monitor error rates (should stay < 0.1%)
- Check alert dashboard for any anomalies

### Communication & Notification
- [ ] Update status page (if applicable)
- [ ] Post final summary to Slack
- [ ] Notify stakeholders of completion
- [ ] Escalate any issues to L2

### Documentation & Lessons Learned
- [ ] Document any issues encountered
- [ ] Record resolution steps taken
- [ ] Note timing vs. plan
- [ ] Add to lessons learned database

---

## Escalation Contacts & Procedures

### Level 1 (On-Call L1)
- **Role:** Alert monitoring, initial troubleshooting
- **Contact:** [Name/Slack]
- **Escalate to L2 if:** Critical alert, cannot resolve in 10 minutes, needs access to production

### Level 2 (On-Call L2)
- **Role:** Complex troubleshooting, advanced remediation
- **Contact:** [Name/Slack/Phone]
- **Authority:** Can make decisions on rollback, additional restarts

### Level 3 (DevOps Lead)
- **Role:** Orchestration, critical decisions
- **Contact:** [Name/Slack/Phone]
- **Authority:** Deployment approval, halt decision, incident command

### Manager (Operations)
- **Role:** Communication, stakeholder updates
- **Contact:** [Name/Slack/Email]
- **Responsibility:** Status page updates, executive notification

---

## Rollback Procedures (If Needed)

### When to Rollback
- [ ] Critical API errors not resolving within 10 minutes
- [ ] Database connectivity completely broken
- [ ] > 20% of containers failing
- [ ] Replication lag > 300 seconds
- [ ] Data corruption detected

### Rollback Execution
```bash
# Contact L2 engineer for rollback approval
# Then execute rollback procedure:
bash rollback-deployment.sh

# Expected duration: 15-20 minutes
# Verify old version restored with health checks
```

### Post-Rollback
- [ ] All health checks passing with old version?
- [ ] Alert monitoring restored?
- [ ] Incident post-mortem scheduled?
- [ ] Communication to stakeholders?

---

## Success Metrics (First 24 Hours)

### Critical (must achieve)
- ✅ Uptime: > 99.5%
- ✅ API response time P95: < 2 seconds
- ✅ Error rate: < 1%

### Important (should achieve)
- ✅ Uptime: > 99.9%
- ✅ API response time P95: < 1 second
- ✅ Error rate: < 0.1%

### Monitoring
- ✅ All alerts configured and firing correctly
- ✅ Replication lag consistently < 100ms
- ✅ No unexpected container restarts

---

## Printable Checklist Summary

```
MAY 1 DEPLOYMENT DAY - QUICK CHECKLIST

06:00 - TEAM ASSEMBLY
  [ ] All roles present
  [ ] Systems accessible
  [ ] Communications confirmed

06:15 - PRE-DEPLOYMENT VERIFICATION
  [ ] 7-item checklist passed
  [ ] Validation script: 0 failures
  [ ] Infrastructure status: READY

08:00 - POSTGRESQL REPLICATION FIX
  [ ] Script started on replica
  [ ] Monitoring alerts
  [ ] Script completed successfully

08:30 - REPLICATION VERIFICATION
  [ ] pg_is_in_recovery() = t
  [ ] Replication lag < 5s
  [ ] Ready for main deployment

08:45 - FINAL GO/NO-GO
  [ ] All checks re-run
  [ ] Team consensus: GO or NO-GO
  [ ] Decision communicated

09:00 - MAIN DEPLOYMENT
  [ ] Deployment started
  [ ] Progress monitored
  [ ] No critical errors

09:30 - HEALTH CHECK
  [ ] API responding
  [ ] Databases healthy
  [ ] All systems operational

10:00 - DEPLOYMENT COMPLETE
  [ ] Success status confirmed
  [ ] 24-hour monitoring activated
  [ ] Stakeholders notified
```

---

**REMEMBER:**
- 🚨 08:00-08:30: PostgreSQL replication fix is CRITICAL - must succeed
- ⏰ Stick to timeline - no deployment tasks outside their window
- 📡 Keep monitoring active at all times
- 🔄 24-hour window: Stay alert for issues

**Questions? See MAY_1_MASTER_INDEX.md for full documentation**

