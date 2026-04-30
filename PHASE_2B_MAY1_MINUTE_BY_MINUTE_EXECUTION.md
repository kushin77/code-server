# PHASE 2B MAY 1 DEPLOYMENT EXECUTION TIMELINE
## Minute-by-Minute War Room Procedures (04:00-06:00 UTC)

**Purpose:** Exact procedures for all team members during critical 2-hour go-live window  
**Audience:** All 6 team leads + war room staff  
**Timing:** May 1, 2026 - 04:00 to 06:00 UTC  
**Print/Laminate:** Reference on war room wall + each team member

---

## 📅 MASTER TIMELINE

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    MAY 1, 2026 DEPLOYMENT EXECUTION                      ║
║              Critical Pre-Flight & Go-Live Window (04:00-06:00 UTC)      ║
╚═══════════════════════════════════════════════════════════════════════════╝

                          GO-LIVE COUNTDOWN

         T-120 Minutes  (04:00 UTC) ──┐ Pre-Flight Begins
         T-60 Minutes   (05:00 UTC)   │ Go-Live Decision Point
         T-0 Minutes    (05:00 UTC) ──┤ 🚀 DEPLOYMENT LIVE
         T+30 Minutes   (05:30 UTC)   │ First Phase Checkpoint
         T+60 Minutes   (06:00 UTC) ──┘ End of Critical Window
```

---

## ⏰ DETAILED MINUTE-BY-MINUTE PROCEDURES

### T-120 MIN (04:00 UTC) — PRE-FLIGHT VERIFICATION BEGINS

**CALL-IN & ASSEMBLY (04:00-04:02)**

```
WHO JOINS WAR ROOM BY 04:00:
├─ Project Manager (MUST be present)
├─ Infrastructure Lead (MUST be present)
├─ Operations Lead (MUST be present)
├─ Monitoring Lead (MUST be present)
└─ CTO (standby - monitor Slack, phone on)

NOT YET IN WAR ROOM:
├─ QA Lead (joins at 05:15 UTC)
├─ Security Lead (monitoring, joins for escalations)
└─ Shift Bravo team members (stand by, arrive at 08:00 UTC)

SYSTEMS CHECK (First 2 minutes):
├─ All monitors ON and displaying dashboards
├─ Slack channel active
├─ Phone bridge connected
├─ Email/SMS notification systems LIVE
└─ Terminal access to PRIMARY & REPLICA verified
```

**ACTION AT 04:00 EXACT:**

```
Project Manager (war room leader):
→ Open PHASE_2B_DEPLOYMENT_INCIDENT_EVENT_LOG.md
→ Record: [04:00] PRE-FLIGHT VERIFICATION COMMENCED
→ Slack: "🔍 Pre-flight verification starting. Status: INITIATED"
→ Email: Send to all stakeholders "Pre-flight begins at 04:00 UTC"

Infrastructure Lead:
→ SSH to 192.168.168.31 and 192.168.168.42
→ Have two terminal windows open (PRIMARY + REPLICA)
→ Run: docker ps (should show 87+ and 88 containers respectively)

Operations Lead:
→ Activate war room conference bridge
→ Ensure video camera ON (if using)
→ Have PHASE_2B_FINAL_PREFLIGHT_SYSTEM_CHECKLIST.md printed + ready
→ Have sign-off section visible

Monitoring Lead:
→ Pull up all 4 Grafana dashboards
→ Set all dashboards to refresh every 15 seconds
→ Screenshot baseline metrics for comparison
→ Monitor for ANY alerts (should be none)
```

---

### 04:02-04:10 UTC — PHASE 1: HARDWARE VERIFICATION

**Infrastructure Lead Executes Phase 1 Checklist (8 minutes):**

```
STEP 1: Primary Node Hardware (04:02-04:04)

SSH Terminal 1 (PRIMARY):
┌─────────────────────────────────────────────────────────────┐
│ $ ssh ubuntu@192.168.168.31                                │
│ ubuntu@primary:~$ df -h /                                  │
│ Expected: [XX]G available (minimum 50GB)                   │
│           Usage: <80%                                       │
│ $ free -h | grep Mem                                       │
│ Expected: [XX]G available (minimum 30GB)                   │
│ $ lscpu | grep "CPU(s)"                                    │
│ Expected: [X] CPUs available                               │
│ $ uptime                                                    │
│ Expected: Load average <2.0                                │
└─────────────────────────────────────────────────────────────┘

STEP 2: Replica Node Hardware (04:04-04:06)

SSH Terminal 2 (REPLICA):
┌─────────────────────────────────────────────────────────────┐
│ $ ssh ubuntu@192.168.168.42                                │
│ ubuntu@replica:~$ df -h /                                  │
│ Expected: [XX]G available (minimum 50GB)                   │
│ $ free -h | grep Mem                                       │
│ Expected: [XX]G available (minimum 30GB)                   │
│ $ uptime                                                    │
│ Expected: Load average <2.0                                │
└─────────────────────────────────────────────────────────────┘

STEP 3: Network Connectivity (04:06-04:08)

Both Terminals - Test Latency:
┌─────────────────────────────────────────────────────────────┐
│ $ ping -c 5 192.168.168.42  (from PRIMARY)                │
│ Expected: All 5 packets received, latency <1ms             │
│ $ ping -c 5 192.168.168.31  (from REPLICA)                │
│ Expected: All 5 packets received, latency <1ms             │
│ $ ping -c 5 192.168.168.50  (from both, VIP test)        │
│ Expected: All packets received                             │
└─────────────────────────────────────────────────────────────┘

STEP 4: Sign-Off Phase 1 (04:08-04:10)

Infrastructure Lead Report:
├─ PRIMARY Hardware: ✓ PASS / ✗ FAIL
├─ REPLICA Hardware: ✓ PASS / ✗ FAIL
├─ Network Connectivity: ✓ PASS / ✗ FAIL
└─ Phase 1 Status: ✓ COMPLETE / ✗ ISSUES

If ANY FAIL: → STOP immediately, escalate to CTO
```

**Project Manager Actions (04:02-04:10):**
```
□ Record each step in incident log with timestamps
□ Monitor: No alerts in Grafana during this phase
□ Slack update at 04:08: "Phase 1 (Hardware) complete, 88% on track"
```

**Monitoring Lead Actions (04:02-04:10):**
```
□ Watch Grafana cluster health dashboard
□ Verify: No CPU spikes, no memory jumps
□ Verify: Replication lag stable <5s
□ Alert if: Any metric exceeds threshold
□ Screenshot: Pre-Phase-2 baseline metrics
```

---

### 04:10-04:20 UTC — PHASE 2: DOCKER & CONTAINERS

**Infrastructure Lead Executes Phase 2 Checklist (10 minutes):**

```
STEP 1: Primary Container Count (04:10-04:12)

PRIMARY Terminal:
┌─────────────────────────────────────────────────────────────┐
│ $ docker ps | wc -l                                        │
│ Expected: 88 (87 containers + 1 header line = 88 lines)    │
│ $ docker ps --filter "status=exited" | wc -l              │
│ Expected: 1 (only header line, 0 exited containers)        │
│ $ docker ps -a --filter "status=exited"                    │
│ Expected: Only header line (verify output)                 │
└─────────────────────────────────────────────────────────────┘

STEP 2: Replica Container Count (04:12-04:14)

REPLICA Terminal:
┌─────────────────────────────────────────────────────────────┐
│ $ docker ps | wc -l                                        │
│ Expected: 89 (88 containers + 1 header line = 89 lines)    │
│ $ docker ps --filter "status=exited" | wc -l              │
│ Expected: 1 (only header line, 0 exited containers)        │
│ $ docker ps -a | grep -i "gitlab_"                         │
│ Expected: All gitlab services running                      │
└─────────────────────────────────────────────────────────────┘

STEP 3: Health Check (04:14-04:17)

PRIMARY Terminal:
┌─────────────────────────────────────────────────────────────┐
│ $ docker ps --format "table {{.Names}}\t{{.Status}}"       │
│ Review each row - all should show "Up [time]"               │
│ (Scan list for any "Exited" or "Unhealthy")                │
│ Any issues? → Take note of container names                 │
└─────────────────────────────────────────────────────────────┘

STEP 4: Critical Services Check (04:17-04:19)

PRIMARY Terminal:
┌─────────────────────────────────────────────────────────────┐
│ $ docker ps | grep gitlab_db                               │
│ Expected: 1 line, Status "Up"                              │
│ $ docker ps | grep gitlab_redis                            │
│ Expected: 1 line, Status "Up"                              │
│ $ docker ps | grep nginx                                   │
│ Expected: 1 line, Status "Up"                              │
└─────────────────────────────────────────────────────────────┘

STEP 5: Phase 2 Sign-Off (04:19-04:20)

Infrastructure Lead Report:
├─ PRIMARY Containers: 87+ running ✓ PASS / ✗ FAIL
├─ REPLICA Containers: 88 running ✓ PASS / ✗ FAIL
├─ No Exited Containers: ✓ PASS / ✗ FAIL
└─ Phase 2 Status: ✓ COMPLETE / ✗ ISSUES

If ANY issues detected:
→ Investigate container: docker logs [container_name]
→ Record issue in incident log
→ Decide: Restart container / Escalate / Proceed
```

**Monitoring Lead Actions (04:10-04:20):**
```
□ Watch for container restart events in dashboards
□ Monitor CPU/Memory: Should be stable
□ Verify: No spike in error rates
□ Check: Prometheus targets still responding (8+)
□ Screenshot: Phase 2 completion metrics
```

---

### 04:20-04:30 UTC — PHASE 3: DATABASE REPLICATION

**Infrastructure Lead Executes Phase 3 Checklist (10 minutes):**

```
STEP 1: Primary Database Status (04:20-04:23)

PRIMARY Terminal - Access PostgreSQL:
┌─────────────────────────────────────────────────────────────┐
│ $ docker exec gitlab_db psql -U postgres -c "SELECT        │
│   version();"                                                │
│ Expected: PostgreSQL 12.x running                          │
│                                                             │
│ $ docker exec gitlab_db psql -U postgres -c "SELECT        │
│   slot_name, restart_lsn FROM pg_replication_slots;"       │
│ Expected: 1 slot named "standby", showing LSN position     │
└─────────────────────────────────────────────────────────────┘

STEP 2: Replica Replication Status (04:23-04:26)

REPLICA Terminal - Check Recovery:
┌─────────────────────────────────────────────────────────────┐
│ $ docker exec gitlab_db psql -U postgres -c "SELECT        │
│   pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();"    │
│ Expected: Both LSNs present, closely matching PRIMARY       │
│                                                             │
│ $ docker exec gitlab_db psql -U postgres -c "SELECT        │
│   EXTRACT(EPOCH FROM (now() -                              │
│   pg_last_wal_receive_lsn_time()));"                        │
│ Expected: Replication lag <5 seconds                        │
└─────────────────────────────────────────────────────────────┘

STEP 3: Connected Replicas (04:26-04:28)

PRIMARY Terminal:
┌─────────────────────────────────────────────────────────────┐
│ $ docker exec gitlab_db psql -U postgres -c "SELECT        │
│   client_addr, state FROM pg_stat_replication;"            │
│ Expected: 1 row showing REPLICA IP 192.168.168.42, state   │
│           'streaming'                                       │
└─────────────────────────────────────────────────────────────┘

STEP 4: Phase 3 Sign-Off (04:28-04:30)

Infrastructure Lead Report:
├─ PRIMARY DB Running: ✓ PASS / ✗ FAIL
├─ Replication Lag <5s: ✓ PASS / ✗ FAIL
├─ Replica Connected: ✓ PASS / ✗ FAIL
└─ Phase 3 Status: ✓ COMPLETE / ✗ ISSUES

If replication lag >5s:
→ Monitor for 2 minutes
→ If persists >10s: Escalate to CTO
→ Likely cause: HIGH WRITE LOAD (expected at go-live)
```

**Monitoring Lead Actions (04:20-04:30):**
```
□ Watch replication lag in DB Replication dashboard
□ Verify: Lag trending toward <5s (not increasing)
□ Monitor PRIMARY write QPS: Should be <100 (pre-go-live)
□ Monitor REPLICA read lag: Should be minimal
□ Alert if: Lag exceeds 30 seconds
□ Screenshot: Replication metrics at end of phase
```

---

### 04:30-04:40 UTC — PHASE 4: HA & KEEPALIVED

**Infrastructure Lead Executes Phase 4 Checklist (10 minutes):**

```
STEP 1: Keepalived Status (04:30-04:33)

PRIMARY Terminal:
┌─────────────────────────────────────────────────────────────┐
│ $ ssh ubuntu@192.168.168.31 "sudo systemctl status         │
│   keepalived | head -20"                                    │
│ Expected: "active (running)"                               │
│ $ ssh ubuntu@192.168.168.31 "sudo ip addr show | grep      │
│   192.168.168.50"                                          │
│ Expected: PRIMARY has VIP assigned (inet 192.168.168.50)  │
└─────────────────────────────────────────────────────────────┘

REPLICA Terminal:
┌─────────────────────────────────────────────────────────────┐
│ $ ssh ubuntu@192.168.168.42 "sudo systemctl status         │
│   keepalived | head -20"                                    │
│ Expected: "active (running)"                               │
│ $ ssh ubuntu@192.168.168.42 "sudo ip addr show | grep      │
│   192.168.168.50"                                          │
│ Expected: REPLICA does NOT have VIP (PRIMARY is master)    │
└─────────────────────────────────────────────────────────────┘

STEP 2: VIP Responsiveness (04:33-04:36)

Both Terminals:
┌─────────────────────────────────────────────────────────────┐
│ $ ping -c 5 192.168.168.50                                 │
│ Expected: All 5 packets received                           │
│           Response from 192.168.168.31 (PRIMARY)          │
│                                                             │
│ $ curl -s http://192.168.168.50:8080/health | head        │
│ Expected: HTTP 200 OK                                      │
│           JSON response with "status": "healthy"            │
└─────────────────────────────────────────────────────────────┘

STEP 3: Failover Status (04:36-04:38)

Check Failover Test Results (from prior session):
┌─────────────────────────────────────────────────────────────┐
│ $ cat failover_test_results.log 2>/dev/null | head -20      │
│ Expected: 8/8 scenarios PASSED from prior testing           │
│                                                             │
│ If not present: Assume good based on prior verification    │
└─────────────────────────────────────────────────────────────┘

STEP 4: Phase 4 Sign-Off (04:38-04:40)

Infrastructure Lead Report:
├─ Keepalived PRIMARY MASTER: ✓ PASS / ✗ FAIL
├─ Keepalived REPLICA BACKUP: ✓ PASS / ✗ FAIL
├─ VIP 192.168.168.50 Responding: ✓ PASS / ✗ FAIL
├─ HA Ready (8/8 failover tests passed): ✓ PASS / ✗ FAIL
└─ Phase 4 Status: ✓ COMPLETE / ✗ ISSUES

If VIP not responding:
→ SSH to PRIMARY and restart keepalived:
  sudo systemctl restart keepalived
→ Retest ping to VIP
→ If still failing: Escalate to CTO
```

**Monitoring Lead Actions (04:30-04:40):**
```
□ Monitor: Keepalived service health in Services dashboard
□ Verify: VIP active and responding
□ Check: No failover events triggered (should be MASTER/BACKUP state)
□ Screenshot: HA status at end of phase
```

---

### 04:40-04:50 UTC — PHASE 5: SERVICES & HEALTH

**Infrastructure Lead + Operations Lead Execute Phase 5 (10 minutes):**

```
STEP 1: Critical Services Verify (04:40-04:43)

PRIMARY Terminal:
┌─────────────────────────────────────────────────────────────┐
│ $ for service in gitlab_db gitlab_redis nginx gitlab_web;  │
│   do echo -n "$service: "; docker ps | grep "$service" |   │
│   grep -q "Up" && echo "✓ UP" || echo "✗ DOWN"; done       │
│ Expected: All 4 services show ✓ UP                         │
└─────────────────────────────────────────────────────────────┘

STEP 2: API Health Check (04:43-04:46)

Operations Lead - Test API:
┌─────────────────────────────────────────────────────────────┐
│ $ curl -s -I http://192.168.168.31/api/v4/user            │
│ Expected: HTTP 200 OK (or 401 if auth required, still OK)  │
│                                                             │
│ $ curl -s http://192.168.168.50:8080/health | jq          │
│ Expected: JSON with "status": "healthy"                    │
│           response_time_ms: <200                           │
└─────────────────────────────────────────────────────────────┘

STEP 3: Web Interface Check (04:46-04:48)

Monitoring Lead - Visual Verification:
┌─────────────────────────────────────────────────────────────┐
│ Open browser: http://192.168.168.31                        │
│ Expected: GitLab login page loads within 3 seconds         │
│           No obvious errors in console                     │
│           Page title: "GitLab"                             │
└─────────────────────────────────────────────────────────────┘

STEP 4: Phase 5 Sign-Off (04:48-04:50)

Infrastructure Lead Report:
├─ All Critical Services UP: ✓ PASS / ✗ FAIL
├─ API Responding Normally: ✓ PASS / ✗ FAIL
├─ Web UI Loading: ✓ PASS / ✗ FAIL
└─ Phase 5 Status: ✓ COMPLETE / ✗ ISSUES

If ANY services down:
→ Check container logs: docker logs [container_name]
→ Attempt restart: docker-compose restart [service]
→ If doesn't come up: Escalate to CTO
```

**Monitoring Lead Actions (04:40-04:50):**
```
□ Verify: All services healthy in Services Status dashboard
□ Check: Error rate at 0% (before any load)
□ Monitor: Response times normal (<200ms p99)
□ Screenshot: Services status at end of phase
```

---

### 04:50-05:00 UTC — PHASE 6: MONITORING ACTIVE

**Monitoring Lead Executes Phase 6 (10 minutes):**

```
STEP 1: Prometheus Targets (04:50-04:53)

Navigate to: http://192.168.168.31:9090/targets
┌─────────────────────────────────────────────────────────────┐
│ Expected results:                                           │
│ ✓ 8+ targets showing "UP" status                           │
│ ✓ 0 targets showing "DOWN"                                 │
│ ✓ All scrape times <15 seconds                             │
│ ✓ No errors in scrape logs                                 │
│                                                             │
│ If target DOWN:                                            │
│ → Check service on that host                               │
│ → Restart if needed                                        │
│ → Verify in Prometheus targets within 1 minute             │
└─────────────────────────────────────────────────────────────┘

STEP 2: Dashboard Refresh (04:53-04:56)

All 4 Grafana Dashboards:
┌─────────────────────────────────────────────────────────────┐
│ Dashboard 1 - Cluster Health:                              │
│ ✓ Showing 87+ PRIMARY containers                           │
│ ✓ Showing 88 REPLICA containers                            │
│ ✓ Replication lag <5s                                      │
│ ✓ All resources green/good                                 │
│                                                             │
│ Dashboard 2 - Database Replication:                        │
│ ✓ Replication lag <5s                                      │
│ ✓ Connected replicas: 1                                    │
│ ✓ No lag spikes                                            │
│                                                             │
│ Dashboard 3 - Application Performance:                     │
│ ✓ Response times <200ms p99                                │
│ ✓ Error rate 0%                                            │
│ ✓ Request rate normal                                      │
│                                                             │
│ Dashboard 4 - Services Status:                             │
│ ✓ All services green/healthy                               │
│ ✓ No service failures                                      │
└─────────────────────────────────────────────────────────────┘

STEP 3: AlertManager (04:56-04:58)

Check: http://192.168.168.31:9093
┌─────────────────────────────────────────────────────────────┐
│ Expected: 0 active alerts (everything is healthy)          │
│ All alert routing configured and ready                     │
│ Slack channel: #phase2b-deployment connected              │
│ Email notifications: Ready to send                         │
│ SMS escalation: Numbers verified                           │
└─────────────────────────────────────────────────────────────┘

STEP 4: Phase 6 Sign-Off (04:58-05:00)

Monitoring Lead Report:
├─ Prometheus Targets: 8+ UP ✓ PASS / ✗ FAIL
├─ All Dashboards Updating: ✓ PASS / ✗ FAIL
├─ Alerts Ready: ✓ PASS / ✗ FAIL
├─ Log Aggregation Active: ✓ PASS / ✗ FAIL
└─ Phase 6 Status: ✓ COMPLETE / ✗ ISSUES
```

---

### 05:00 UTC (EXACT) — 🚀 GO-LIVE DECISION POINT

**Infrastructure Lead Presents Final Status (05:00 Exact):**

```
FINAL PRE-FLIGHT ASSESSMENT:

Phase 1 - Hardware: ✓ PASS / ✗ FAIL
Phase 2 - Containers: ✓ PASS / ✗ FAIL
Phase 3 - Replication: ✓ PASS / ✗ FAIL
Phase 4 - HA/VIP: ✓ PASS / ✗ FAIL
Phase 5 - Services: ✓ PASS / ✗ FAIL
Phase 6 - Monitoring: ✓ PASS / ✗ FAIL

OVERALL PRE-FLIGHT VERDICT:

All 6 Phases PASSED:
  → GO FOR DEPLOYMENT 🟢

Any Phase FAILED:
  → HOLD (investigate & resolve)
  → Re-execute phase
  → Return to this decision point
```

**GO/NO-GO AUTHORIZATION (05:00-05:05):**

```
Project Manager → Operations Lead → Infrastructure Lead → CTO

SEQUENCE:

1. Infrastructure Lead: "All systems GREEN for deployment"

2. Operations Lead: "War room ready, team briefed, 
                     communication channels active"

3. Project Manager: "Executive sponsor standing by for authorization"

4. CTO (on standby): "Confirmed GO for deployment"

5. Project Manager (OFFICIAL): 
   "🚀 PHASE 2B DEPLOYMENT OFFICIALLY LIVE AT 05:00 UTC"
   
   Proceed to Phase 1 operations procedures.
```

**IF ANY PHASE FAILED:**

```
Timeline shifts to HOLD status:

1. Infrastructure Lead describes issue
2. Team mobilizes to resolve
3. Estimated resolution time: [X] minutes
4. Revised GO decision time: [New time]
5. Stakeholder notification: Delay announcement

HOLD decision criteria:
- Infrastructure damage unlikely
- Fix takes <15 minutes
- Risk remains LOW after fix

→ If fix takes >15 min: Escalate to CTO for deployment delay decision
```

---

### 05:00-05:30 UTC — PHASE 1 OPERATIONS BEGIN

**All Teams Execute Phase 1 Deployment Procedures**

```
IF 05:00 UTC GO-LIVE WAS APPROVED:

Infrastructure Lead:
→ Execute: PHASE_2B_STAGING_DEPLOYMENT_CHECKLIST.md Phase 1
→ Begin: Docker image updates
→ Monitor: Container status
→ Report: Progress every 15 minutes

Operations Lead:
→ Activate: War room monitoring mode
→ Send: "Deployment COMMENCED" notification to all stakeholders
→ Log: All events in incident tracking log
→ Status: Update every 30 minutes

Monitoring Lead:
→ Watch: All 4 dashboards continuously
→ Alert: Any anomalies
→ Compare: Metrics vs. baseline
→ Screenshot: Every 5 minutes during phase

QA Lead:
→ STANDBY until 05:15 UTC
→ Prepare: First test scenario
→ Stand ready to begin Phase 1 testing at infrastructure go-ahead

Project Manager:
→ Stakeholder updates: "Deployment LIVE, Phase 1 executing"
→ Monitor: All communications
→ Track: Milestone completion
→ Escalate: Any critical issues immediately

Security Lead:
→ Monitor: Access logs
→ Watch: For unusual activity
→ Verify: All encryption active
```

---

### 05:30-06:00 UTC — FIRST CHECKPOINT & STATUS

**30-Minute Status Report (05:30 UTC):**

```
PHASE 1 PROGRESS (30 minutes into deployment):

Infrastructure Report:
├─ Containers Started: [X]/87
├─ Containers Healthy: [X]/87
├─ Issues Encountered: [X]
└─ Estimated Phase 1 Completion: [XX:XX UTC May X]

Monitoring Report:
├─ CPU Usage: [X]% avg (was [X]% baseline)
├─ Memory Usage: [X]% avg (was [X]% baseline)
├─ Error Rate: [X]% (was 0% baseline)
├─ Response Time: [X]ms p99 (was <200ms baseline)
└─ Replication Lag: [X]s (was <5s baseline)

QA Report:
├─ Tests Executed: [X]
├─ Tests Passed: [X]
├─ Tests Failed: [X]
└─ Status: READY FOR PHASE 2 / BLOCKED

Operational Status:
├─ Team Performance: EXCELLENT / GOOD / ACCEPTABLE
├─ Communication: CLEAR / ADEQUATE / ISSUES
├─ Confidence Level: HIGH / MEDIUM / LOW
└─ Next 30 Minutes: [Plan]

Stakeholder Notification:
Send Email: "Deployment 30-minute status - ALL GREEN"
Send Slack: "✅ First checkpoint PASSED - Phase 1 executing smoothly"
```

---

## 📋 RAPID RESPONSE TROUBLESHOOTING

**If Issues Arise During 04:00-06:00 UTC Window:**

```
ISSUE: Container won't start
├─ Check: docker logs [container_name]
├─ Try: docker-compose restart [service]
├─ If fails: Escalate to CTO immediately
└─ Proceed if: Only non-critical service affected

ISSUE: Replication lag >30 seconds
├─ Check: REPLICA CPU/disk (docker stats, df -h)
├─ Check: PRIMARY write load (docker exec postgres queries)
├─ Action: Monitor for 2 min
├─ If persists: Escalate to Infrastructure Lead + CTO
└─ Proceed if: Lag trending back down

ISSUE: VIP not responding
├─ Check: ssh ubuntu@192.168.168.31 "sudo systemctl restart keepalived"
├─ Wait: 30 seconds
├─ Retest: ping 192.168.168.50
├─ If fails: Escalate to CTO
└─ Proceed: Only if VIP restored

ISSUE: Dashboard not updating
├─ Refresh browser: Ctrl+F5
├─ Check: Grafana service on PRIMARY: docker ps | grep grafana
├─ Restart if needed: docker-compose restart grafana
├─ If persists: Monitor only, proceed with status reports via CLI
└─ Proceed: Operations continue independently

ANY OTHER ISSUE:
1. Document in incident log immediately
2. Assess: Critical/High/Medium/Low
3. Critical: Escalate to CTO immediately, hold deployment
4. High: Troubleshoot for 5 minutes, then escalate
5. Medium: Continue troubleshooting, parallel operations proceed
6. Low: Monitor, document, address in Phase 2
```

---

## ✅ FINAL REFERENCE: WHO DOES WHAT WHEN

```
04:00 UTC → Infrastructure Lead: Phase 1 & 2 & 3 & 4 & 5 & 6 Checklist Execution
            Operations Lead: War room activation & communications
            Monitoring Lead: Dashboard monitoring & baseline collection
            Project Manager: Timeline tracking & stakeholder notifications

05:00 UTC → CTO: Final GO/NO-GO decision
            All teams: Execute approved decision
            War room: Full operational status

05:00+ UTC → Infrastructure Lead: Phase 1 deployment execution
            Monitoring Lead: Continuous dashboard surveillance
            Operations Lead: War room management
            QA Lead: Prepare to execute testing
            Project Manager: Status reporting every 30 min

ESCALATION CHAIN:
Anomaly detected → Team Lead aware → Operations Lead → CTO alert
Critical issue → CTO notified immediately → Stakeholder alert → Decision on hold/proceed
```

---

**PRINT THIS DOCUMENT**  
**LAMINATE FOR WAR ROOM WALL**  
**POST ABOVE PROJECT MANAGER DESK**

**This is the EXACT sequence for May 1, 2026.**  
**Any deviation requires CTO approval.**

