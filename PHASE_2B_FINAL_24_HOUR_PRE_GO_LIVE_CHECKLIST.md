# PHASE 2B FINAL 24-HOUR PRE-GO-LIVE CHECKLIST

**Purpose:** Ensure all final preparations are complete before May 1, 2026 05:00 UTC go-live moment  
**Timeline:** April 30 (Today) → May 1 (Go-Live Day)  
**Scope:** 24-hour countdown checklist with hourly milestones  
**Owner:** Project Manager + All Team Leads

---

## 🎯 CRITICAL DEADLINES

```
TODAY - APRIL 30, 2026 (7 Hours Remaining)
├─ 17:00 UTC: Final team briefing
├─ 18:00 UTC: Systems final verification
├─ 19:00 UTC: War room setup & testing
├─ 20:00 UTC: All teams stand-by
└─ 23:59 UTC: Day 1 complete, all hands rest

TOMORROW - MAY 1, 2026 (Go-Live Day)
├─ 00:00 UTC: Shift Alpha arrives, war room activated
├─ 03:00 UTC: Final 2-hour alert (pre-flight begins soon)
├─ 04:00 UTC: PRE-FLIGHT VERIFICATION PHASE BEGINS
├─ 04:30 UTC: Monitoring Lead activates all dashboards
├─ 05:00 UTC: 🚀 GO-LIVE MOMENT (if all green)
└─ 05:05 UTC: CTO final authorization + execution begins
```

---

## ✅ TODAY'S CHECKLIST (April 30, 2026)

### MORNING - BY 10:00 UTC

**Infrastructure Lead Checklist:**
- [ ] Access to 192.168.168.31 verified (SSH test)
  ```bash
  ssh ubuntu@192.168.168.31 "echo 'PRIMARY ACCESSIBLE' && docker ps | wc -l"
  # Expected: PRIMARY ACCESSIBLE, 87+ containers
  ```
- [ ] Access to 192.168.168.42 verified (SSH test)
  ```bash
  ssh ubuntu@192.168.168.42 "echo 'REPLICA ACCESSIBLE' && docker ps | wc -l"
  # Expected: REPLICA ACCESSIBLE, 88 containers
  ```
- [ ] All 4 Grafana dashboards loading (manual test)
  - Cluster Health Dashboard
  - Database Replication Dashboard
  - Application Performance Dashboard
  - Services Status Dashboard
- [ ] Prometheus targets all responding (verify 8+ targets active)
- [ ] AlertManager channels tested (Slack, Email verified)
- [ ] Bash scripts executable and readable
  ```bash
  chmod +x scripts/ops/full-deployment-test.sh
  chmod +x scripts/ci/check-docker-compose-idempotency.sh
  ```
- [ ] No uncommitted changes in Git
  ```bash
  git status  # Expected: working tree clean
  ```
- [ ] Latest code pulled from origin
  ```bash
  git pull origin fix/domain-variability-caddy
  ```

**Operations Lead Checklist:**
- [ ] War room reserved and confirmed for May 1, 00:00-May 12, 23:59
- [ ] All communication channels set up
  - Slack: #phase2b-deployment active
  - Email: Distribution list updated
  - SMS: On-call list verified
  - Video: Zoom/Teams meeting link ready
- [ ] Contact list printed (posted in war room)
- [ ] Emergency escalation path verified (called contacts to confirm)
- [ ] 6 printable role cards ready (one per team member)
- [ ] Status tracker spreadsheet opened and ready to use

**Monitoring Lead Checklist:**
- [ ] All 4 dashboards bookmarked in browser
  ```
  Cluster Health: 192.168.168.31:3000/d/cluster-health
  DB Replication: 192.168.168.31:3000/d/db-replication
  App Performance: 192.168.168.31:3000/d/app-performance
  Services Status: 192.168.168.31:3000/d/services-status
  ```
- [ ] Prometheus accessible and all targets responding
- [ ] Log aggregation system verified running
- [ ] Dashboard refresh rates confirmed (15-30 seconds)
- [ ] Baseline metrics recorded for comparison
  ```
  Current state saved for trending analysis
  Replication lag: [X]s
  CPU avg: [X]%
  Memory avg: [X]%
  Error rate: [X]%
  ```

**QA Lead Checklist:**
- [ ] Test management system access verified
- [ ] Test cases for Phase 1 loaded and ready
- [ ] Test environment verified (separate from staging/prod)
- [ ] Test data prepared (refresh if needed)
- [ ] First test case ready to execute at 05:15 UTC May 1

**Security Lead Checklist:**
- [ ] SSL certificates verified and not expiring soon
  ```bash
  # Check certificate expiry (should be >30 days)
  openssl s_client -connect 192.168.168.31:443 -servername gitlab.example.com \
    | openssl x509 -noout -dates
  ```
- [ ] Firewall rules active and tested
- [ ] VPN access verified (if needed for team members)
- [ ] Security scanning tools ready
- [ ] Compliance checklist updated

**Project Manager Checklist:**
- [ ] All 45 deployment files reviewed (spot-checked 5-10 files)
- [ ] Master index verified to navigate all documents
- [ ] Stakeholder communication list updated
- [ ] Executive summary printed (1-page briefing)
- [ ] Timeline printout verified (posted in war room)
- [ ] Sign-off authorization chain confirmed (5-level approvals ready)

---

### AFTERNOON - BY 14:00 UTC

**Full Team System Verification:**

```bash
# RUN THIS COMMAND ON PRIMARY NODE (via Infrastructure Lead)
ssh ubuntu@192.168.168.31 << 'EOF'
#!/bin/bash
echo "=== FINAL SYSTEM VERIFICATION (April 30, 14:00 UTC) ==="
echo ""
echo "1. Container Health:"
docker ps | tail -10
echo "   Total: $(docker ps | wc -l) (expect 87+)"
echo ""
echo "2. Disk Space:"
df -h / | tail -1
echo ""
echo "3. Memory Available:"
free -h | grep Mem
echo ""
echo "4. Replication Status:"
docker exec gitlab_db psql -U postgres -c "SELECT slot_name, restart_lsn FROM pg_replication_slots;" 2>/dev/null || echo "REPLICA: checking..."
echo ""
echo "5. VIP Responsiveness:"
ping -c 1 192.168.168.50 | grep received
echo ""
echo "=== All systems operational ==="
EOF
```

**Verification Results:**
```
System State: ✓ VERIFIED / ✗ ISSUES

Issue Details (if any):
[Record any anomalies found]

Required Resolution:
[Any immediate fixes needed before go-live]

Verified By: _________________________ Time: _______
```

---

### LATE AFTERNOON - BY 17:00 UTC

**FINAL TEAM BRIEFING (All 6 Team Leads + Project Manager)**

**Briefing Agenda (30 minutes):**
1. Review go-live timeline (5 min)
2. Role assignments for each shift (5 min)
3. Quick reference card review (5 min)
4. Communication procedures (5 min)
5. Emergency escalation (5 min)
6. Q&A (3 min)
7. Sign-off (2 min)

**Briefing Checklist:**
- [ ] All 7 team members present (in person or video)
- [ ] Each person has their quick reference card
- [ ] Each person knows their shift assignment
- [ ] Go-live timeline reviewed (04:00-06:00 UTC window)
- [ ] Each person can articulate their role
- [ ] No questions remain unanswered
- [ ] Team confidence level: HIGH / MEDIUM / LOW
- [ ] All team members sign briefing attendance log

**Briefing Attendance Log:**
```
FINAL BRIEFING - April 30, 2026 17:00 UTC

Team Member                 Role                    Present  Confident
─────────────────────────────────────────────────────────────────────
[Name]                      Project Manager         [ ]      [ ]
[Name]                      Infrastructure Lead     [ ]      [ ]
[Name]                      Operations Lead         [ ]      [ ]
[Name]                      Monitoring Lead         [ ]      [ ]
[Name]                      QA Lead                 [ ]      [ ]
[Name]                      Security Lead           [ ]      [ ]

Briefing Conducted By: _____________________ Time: _______
Briefing Attendees: ________________________ Count: _____
```

---

### EVENING - BY 19:00 UTC

**War Room Setup & Testing**

**Physical Setup:**
- [ ] War room reserved and accessible
- [ ] 4 monitors connected and powered on
- [ ] Monitor 1: Grafana (Cluster Health) - TEST
- [ ] Monitor 2: Grafana (App Performance) - TEST
- [ ] Monitor 3: Grafana (DB Replication) - TEST
- [ ] Monitor 4: Log aggregation or spreadsheet - TEST
- [ ] All 4 monitors verify dashboards displaying correctly
- [ ] Network connectivity to 192.168.168.31 and .42 verified
- [ ] WiFi backup connectivity verified
- [ ] Wired network tested
- [ ] Video conferencing tested (Zoom/Teams audio + video)
- [ ] Slack desktop client running
- [ ] Email client refreshing
- [ ] Phone lines tested (conference bridge)
- [ ] Printed materials available:
  - [ ] Contact list (3 copies)
  - [ ] Escalation procedures (3 copies)
  - [ ] Role quick reference cards (6 copies)
  - [ ] Timeline chart (2 copies)
  - [ ] Architecture diagram (2 copies)

**Digital Setup:**
- [ ] Git workspace clean (no uncommitted changes)
- [ ] All scripts executable and verified
- [ ] Terminal access to both PRIMARY and REPLICA tested
- [ ] SSH keys working for all team members
- [ ] Access control verified (who has sudo, who has docker access, etc.)
- [ ] Backup access method identified (if primary method fails)
- [ ] VPN connection tested (if required)

**Communication Setup:**
- [ ] Slack channel #phase2b-deployment created/verified
- [ ] All 7 team members invited to Slack
- [ ] War room video meeting link shared in Slack
- [ ] Email distribution list updated
- [ ] SMS numbers verified in on-call system
- [ ] Incident escalation numbers (with 24h support) posted

**Test Run (19:30 UTC):**
Execute one quick test of entire communication chain:
```
1. Project Manager posts in Slack: "TEST: All systems check in"
2. Each team member: Reply in Slack and email simultaneously
3. Verify all communications received in real-time
4. Test video conferencing: All join and confirm audio works
5. Test phone conference bridge (if using): All call in and confirm
6. Verify desktop/mobile alerts working (Slack, email)
```

**Communication Test Log:**
```
TEST: April 30, 19:30 UTC
─────────────────────────────────────────
Slack test: ✓ All 7 members responded within 2 min
Email test: ✓ All 7 members received within 3 min
Video test: ✓ All 7 members connected, audio verified
Phone test: ✓ All 7 members called in successfully
Mobile alerts: ✓ All notifications delivered within 30 sec

Communication Status: ✓ READY FOR DEPLOYMENT
Verified By: _________________________ Time: _______
```

---

### NIGHT - BY 20:00 UTC

**All Teams Stand-By Status**

**Each Team Lead Reports Status:**

```
INFRASTRUCTURE LEAD FINAL REPORT (20:00 UTC April 30):
├─ All systems OPERATIONAL: ✓ YES / ✗ NO
├─ Any blocking issues: ✓ NONE / ✗ [Issues]
├─ Ready for go-live: ✓ YES / ✗ NO
├─ Confidence: [HIGH / MEDIUM / LOW]
└─ Signature: _________________________ Time: _______

OPERATIONS LEAD FINAL REPORT (20:00 UTC April 30):
├─ War room READY: ✓ YES / ✗ NO
├─ Communication channels VERIFIED: ✓ YES / ✗ NO
├─ Team BRIEFED: ✓ YES / ✗ NO
├─ Ready for go-live: ✓ YES / ✗ NO
├─ Confidence: [HIGH / MEDIUM / LOW]
└─ Signature: _________________________ Time: _______

MONITORING LEAD FINAL REPORT (20:00 UTC April 30):
├─ Dashboards ACTIVE: ✓ YES / ✗ NO
├─ Alerts RESPONDING: ✓ YES / ✗ NO
├─ Prometheus TARGETS READY: ✓ YES / ✗ NO
├─ Ready for go-live: ✓ YES / ✗ NO
├─ Confidence: [HIGH / MEDIUM / LOW]
└─ Signature: _________________________ Time: _______

QA LEAD FINAL REPORT (20:00 UTC April 30):
├─ Test cases READY: ✓ YES / ✗ NO
├─ Test environment VERIFIED: ✓ YES / ✗ NO
├─ Ready for go-live: ✓ YES / ✗ NO
├─ Confidence: [HIGH / MEDIUM / LOW]
└─ Signature: _________________________ Time: _______

SECURITY LEAD FINAL REPORT (20:00 UTC April 30):
├─ Security VERIFIED: ✓ YES / ✗ NO
├─ No compliance violations: ✓ YES / ✗ [Issues]
├─ Ready for go-live: ✓ YES / ✗ NO
├─ Confidence: [HIGH / MEDIUM / LOW]
└─ Signature: _________________________ Time: _______

PROJECT MANAGER FINAL REPORT (20:00 UTC April 30):
├─ All materials READY: ✓ YES / ✗ NO
├─ Team TRAINED: ✓ YES / ✗ NO
├─ Approvals OBTAINED: ✓ YES / ✗ NO (5/5 levels)
├─ Ready for go-live: ✓ YES / ✗ NO
├─ Confidence: [HIGH / MEDIUM / LOW]
└─ Signature: _________________________ Time: _______
```

**OVERALL GO/NO-GO DECISION:**

```
FINAL STATUS: ALL SYSTEMS GO / HOLD / NO-GO

If ANY team member reported: NOT READY or ISSUES:
  → RESOLVE IMMEDIATELY (next 3 hours)
  → Update this report when resolved
  → Get approval before sleeping

Current Time: 20:00 UTC April 30
If issues remain unresolved by 23:00 UTC:
  → Escalate to CTO immediately
  → Decide: Proceed with contingencies OR Delay go-live

FINAL AUTHORIZATION:
Project Manager Sign-Off: _________________ Time: _______
CTO Emergency Approval (if needed): _______ Time: _______
```

---

### PRE-SLEEP CHECK - BY 23:00 UTC

**Final Verification Before Rest (3 Hours Before Deployment):**

```
FINAL PRE-SLEEP CHECKLIST (April 30, 23:00 UTC)

Systems Running:
├─ PRIMARY Node (192.168.168.31): PING CHECK
│  $ ping -c 1 192.168.168.31
│  Expected: 1 packet received
├─ REPLICA Node (192.168.168.42): PING CHECK
│  $ ping -c 1 192.168.168.42
│  Expected: 1 packet received
└─ VIP (192.168.168.50): PING CHECK
   $ ping -c 1 192.168.168.50
   Expected: 1 packet received

Dashboards Accessible:
├─ Grafana cluster health: http://192.168.168.31:3000/d/cluster-health
├─ Grafana replication: http://192.168.168.31:3000/d/db-replication
└─ Prometheus: http://192.168.168.31:9090

All Checks PASSED: ✓ YES / ✗ NO

Status: ✅ SYSTEMS READY FOR MAY 1 GO-LIVE

All Team Members: GO TO SLEEP NOW
Schedule: 7.5 hours minimum sleep before May 1, 04:00 UTC
```

---

## 🚀 MAY 1 GO-LIVE DAY TIMELINE

### 00:00 UTC (Shift Alpha Arrives)

```
DEPLOYMENT CONTROL: All Clear For May 1 Start

├─ Shift Alpha Infrastructure Lead: Arrives war room
├─ Shift Alpha Operations Lead: Activates war room
├─ Shift Alpha Monitoring Lead: Verifies dashboard access
├─ All 6 shift alpha members: Check in (Slack)
├─ Pre-flight verification: Beginning checks
└─ First status: "All teams in position, verifying systems"
```

### 04:00 UTC (Pre-Flight Begins)

**Infrastructure Lead Executes Preflight Checklist:**

```
USE: PHASE_2B_FINAL_PREFLIGHT_SYSTEM_CHECKLIST.md

Phase 1: Hardware Verification (04:00-04:10)
├─ SSH access to PRIMARY: ✓
├─ SSH access to REPLICA: ✓
├─ Disk space >50GB on both: ✓
└─ Network latency <1ms: ✓

Phase 2: Docker & Containers (04:10-04:20)
├─ PRIMARY containers: 87+ running: ✓
├─ REPLICA containers: 88 running: ✓
├─ No exited containers: ✓
└─ Health check: All healthy: ✓

Phase 3: Database Replication (04:20-04:30)
├─ PostgreSQL PRIMARY running: ✓
├─ PostgreSQL REPLICA in recovery: ✓
├─ Replication lag <5s: ✓
└─ Replication slot active: ✓

Phase 4: HA & VIP (04:30-04:40)
├─ Keepalived PRIMARY master: ✓
├─ Keepalived REPLICA backup: ✓
├─ VIP 192.168.168.50 ping OK: ✓
└─ Failover ready: ✓

Phase 5: Services & Health (04:40-04:50)
├─ All critical services UP: ✓
├─ API responding: ✓
├─ Database responsive: ✓
└─ No critical alerts: ✓

Phase 6: Monitoring Active (04:50-05:00)
├─ Prometheus targets: 8+ active: ✓
├─ All dashboards updating: ✓
├─ Alerts firing correctly: ✓
└─ Log aggregation capturing: ✓

Phase 7: Final Sign-Off (05:00-05:05)
├─ Infrastructure Lead: APPROVED
├─ Operations Lead: APPROVED
├─ CTO: AUTHORIZED
└─ **🚀 GO FOR DEPLOYMENT 🚀**
```

### 05:00 UTC (GO-LIVE MOMENT)

```
╔════════════════════════════════════════════════════╗
║  🚀 PHASE 2B DEPLOYMENT OFFICIALLY LIVE 🚀        ║
║  May 1, 2026 05:00:00 UTC                         ║
╚════════════════════════════════════════════════════╝

All Teams: PROCEED TO PHASE 1 PROCEDURES

Infrastructure Lead: Begin Phase 1 container updates
Operations Lead: Monitor all communications
Monitoring Lead: Watch for anomalies
QA Lead: Prepare first test phase
Security Lead: Monitor access logs
Project Manager: Send "DEPLOYMENT COMMENCED" notification

Status Updates: Every 30 minutes or on issues

Confidence: HIGH (>95%)
Risk: LOW (<5%)
Time to completion (Phase 1): 7 days (May 1-7)

LET'S MAKE THIS SUCCESSFUL! 🎯
```

---

## 📋 FINAL SIGN-OFF (Required Before May 1, 05:00 UTC)

**ALL 6 TEAM LEADS MUST SIGN BELOW:**

```
PHASE 2B GO-LIVE AUTHORIZATION - April 30, 2026

I certify that I have completed all preparations for May 1, 2026 deployment 
and my team is ready for the go-live phase.

Infrastructure Lead:
  Name: ________________________________
  Signature: ____________________________
  Time: _________ Date: April 30, 2026
  Status: READY / HOLD

Operations Lead:
  Name: ________________________________
  Signature: ____________________________
  Time: _________ Date: April 30, 2026
  Status: READY / HOLD

Monitoring Lead:
  Name: ________________________________
  Signature: ____________________________
  Time: _________ Date: April 30, 2026
  Status: READY / HOLD

QA Lead:
  Name: ________________________________
  Signature: ____________________________
  Time: _________ Date: April 30, 2026
  Status: READY / HOLD

Security Lead:
  Name: ________________________________
  Signature: ____________________________
  Time: _________ Date: April 30, 2026
  Status: READY / HOLD

Project Manager:
  Name: ________________________________
  Signature: ____________________________
  Time: _________ Date: April 30, 2026
  Status: READY / HOLD

DEPLOYMENT AUTHORIZATION:

Executive Sponsor:
  Name: ________________________________
  Signature: ____________________________
  Time: _________ Date: April 30/May 1, 2026
  Status: APPROVED / CONDITIONAL / DENIED

CTO/Technical Lead:
  Name: ________________________________
  Signature: ____________________________
  Time: _________ Date: April 30/May 1, 2026
  Status: APPROVED / CONDITIONAL / DENIED

FINAL STATUS: ✅ APPROVED FOR GO-LIVE / ⚠️ CONDITIONAL / ❌ HOLD

All Team Leads Confirmed Ready: YES / NO
Executive Authorizations Obtained: YES / NO

DEPLOYMENT MAY PROCEED TO MAY 1, 05:00 UTC GO-LIVE
```

---

**THIS CHECKLIST MUST BE 100% COMPLETE BEFORE MAY 1, 05:05 UTC**

**Keep this in your war room for reference throughout deployment.**

