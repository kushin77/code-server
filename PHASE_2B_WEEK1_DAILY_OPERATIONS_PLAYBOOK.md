# PHASE 2B WEEK 1 DAILY OPERATIONS PLAYBOOK
## May 1-12, 2026 - Day-by-Day Procedures for All Team Members

**Purpose:** Specific procedures for each team member for every day of Week 1  
**Audience:** All 6 team leads  
**Duration:** 12 days (May 1-12), 24/7 operations with 3 shifts  
**Timing:** This is your daily reference - print and laminate each day

---

## 📋 HOW TO USE THIS DOCUMENT

**Every morning at shift start (04:00, 12:00, 20:00 UTC):**

1. Find your day section below (Day 1, Day 2, etc.)
2. Find your team role section
3. Execute the procedures in order
4. Check off each task as completed
5. Report completion to Operations Lead
6. Log any issues in incident tracking log

**This document is your daily playbook - not a reference, but your TO-DO LIST.**

---

## ⏰ WEEK 1 OVERVIEW (May 1-12, 2026)

```
Week 1 Objective: Complete 8-phase staging deployment
├─ Days 1-4 (May 1-4): GitHub PR process (branch → merge)
├─ Day 5 (May 5): Docker build (new container images)
├─ Days 6-7 (May 6-7): Staging deployment (8 phases → all 8 complete)
├─ Day 8 (May 8): Failover verification
├─ Days 9-12 (May 9-12): 72-hour critical observation (zero critical issues)
└─ May 12 Checkpoint: All 8 phases COMPLETE ✓

Success Criteria:
├─ ✓ All 8 phases deployed without critical issues
├─ ✓ 72 hours observation: zero critical issues
├─ ✓ Team morale: maintained at high level
└─ ✓ Sleep: 5+ hours per person per day (minimum)

If ALL criteria met by May 12, 23:59 UTC:
→ Week 1 COMPLETE, proceed to Week 2 production prep
```

---

## 🚀 DAY 1 - MAY 1, 2026 (GO-LIVE DAY)

### MORNING STANDUP (All 6 Team Leads Together - 05:10 UTC)

```
Location: War room
Duration: 10 minutes
Attendees: All 6 team leads + Project Manager
Agenda:
  1. Project Manager opens standup: "Good morning, team. Welcome to May 1."
  2. Each lead reports readiness (1 min each):
     - Infrastructure: "Systems operational, ready for Phase 1"
     - Operations: "War room active, all communications live"
     - Monitoring: "Dashboards operational, alerts configured"
     - QA: "Test cases ready, environment verified"
     - Security: "Access logs active, compliance verified"
     - Project Manager: "All systems green, proceeding to Phase 1"
  3. Project Manager: "Confirmed: ALL SYSTEMS GO. Execution begins now."
  4. Team disperses to assigned positions

STANDUP OUTCOMES:
  ✓ All team leads confirmed ready
  ✓ Any issues identified? NO (expected: green across the board)
  ✓ Confidence level: HIGH
  ✓ Proceed to Phase 1 execution
```

### INFRASTRUCTURE LEAD - DAY 1 PROCEDURES

**Time Block: 05:15-12:00 UTC (6.75 hours)**

```
PHASE 1: INFRASTRUCTURE ACTIVATION (Day 1, May 1)

YOUR MISSION:
Begin Week 1 Phase 1: Infrastructure foundation setup
Success criterion: All 87 containers running with no errors

PROCEDURES:

05:15-05:30 UTC (15 min): Verify baseline
├─ SSH to PRIMARY: docker ps | wc -l  (should show 87 containers)
├─ SSH to REPLICA: docker ps | wc -l  (should show 88 containers)
├─ Replication lag: Check in Grafana (should be <5s)
└─ Log: "Baseline verification: All systems green at 05:15 UTC"

05:30-06:00 UTC (30 min): Phase 1 Step 1 - Pre-deployment configuration
├─ Task: Verify docker-compose environment variables on PRIMARY
├─ Command: docker exec gitlab_web env | grep GITLAB_ | head -10
├─ Expected: All env vars correctly set
├─ If issues: docker-compose down, then up
└─ Report to Ops Lead: "Phase 1 Step 1 complete - env vars verified"

06:00-07:00 UTC (60 min): Phase 1 Step 2 - Container health assessment
├─ Task: Verify all 87 containers are healthy
├─ Command: for container in $(docker ps -q); do docker inspect \
│   --format='{{.Name}} {{.State.Health.Status}}' $container; done
├─ Expected: All containers showing "healthy"
├─ If unhealthy: docker-compose restart [service_name]
├─ Repeat until all healthy
└─ Report to Ops Lead: "Phase 1 Step 2 complete - all containers healthy"

07:00-08:00 UTC (60 min): Phase 1 Step 3 - Service connectivity
├─ Task: Verify all services can communicate
├─ Test 1: API responds: curl http://PRIMARY:8080/api/v4/user
├─ Test 2: Database responsive: docker exec gitlab_db psql -U postgres -c "SELECT 1"
├─ Test 3: Redis responsive: docker exec gitlab_redis redis-cli PING
├─ If any fail: Investigate and fix
└─ Report to Ops Lead: "Phase 1 Step 3 complete - all services connected"

08:00-12:00 UTC (240 min): Phase 1 Step 4 - Data validation
├─ Task: Verify no data corruption in database
├─ Command: docker exec gitlab_db psql -U postgres -c \
│   "SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM projects;"
├─ Expected: Row counts match pre-deployment baseline
├─ Compare with: Baseline counts captured in pre-flight
├─ If mismatch: Investigate, potential issue
└─ Report to Ops Lead: "Phase 1 Step 4 complete - data integrity verified"

12:00 UTC: DAILY STANDUP (with Operations Lead)
├─ Infrastructure Lead: "Phase 1 complete, all containers operational"
├─ Status: ON TRACK / AT RISK / BLOCKED
├─ Estimated Phase 2 start: [next day]
└─ Sleep until next shift (minimum 5 hours)

CHECKLIST FOR INFRASTRUCTURE LEAD - DAY 1:
□ Baseline verification: All systems at 05:15 UTC
□ Phase 1 Step 1: Environment variables verified
□ Phase 1 Step 2: Container health verified
□ Phase 1 Step 3: Service connectivity verified
□ Phase 1 Step 4: Data integrity verified
□ Daily standup completed at 12:00 UTC
□ No critical issues encountered (if any: escalated to CTO)
□ Ready for Day 2
```

### OPERATIONS LEAD - DAY 1 PROCEDURES

**Time Block: 05:15-12:00 UTC (6.75 hours) + 20:00-04:00 UTC (8 hours) Shift Bravo**

```
MISSION: Manage war room and coordinate all teams

05:15-05:30 UTC (15 min): War room status check
├─ Verify all 4 dashboards displaying correctly
├─ Check: Alerts not firing (should be all green)
├─ Status: Communications active (Slack, Email, Phone)
└─ Post in Slack: "War room online, all systems operational"

05:30-12:00 UTC (6.5 hours): Continuous war room management
├─ Monitor dashboards for anomalies
├─ Log all events in incident tracking log
├─ Facilitate communication between teams
├─ Run 2-hour checkins with each team lead:
│  ├─ 06:00 UTC: Infrastructure Lead check-in
│  ├─ 08:00 UTC: Monitoring Lead check-in
│  ├─ 10:00 UTC: QA Lead check-in
│  └─ 12:00 UTC: Prepare for shift change
└─ Status updates: Send at 06:00, 09:00, 12:00 UTC to stakeholders

12:00 UTC: Shift change preparation
├─ Conduct 30-min handoff with Shift Bravo Operations Lead
├─ Brief incoming team on Phase 1 progress
├─ Review incident log
├─ Confirm all systems stable
└─ Shift Bravo takes over

20:00 UTC: Shift Bravo (Operations Lead): Resume from handoff
├─ Phase 1 completion assessment
├─ Status: Phase 1 fully complete (all steps done)
├─ Begin Phase 2 preparation (GitHub PR process)
└─ Continue monitoring through night

OPERATIONS LEAD CHECKLIST - DAY 1:
□ War room activated and all systems verified
□ Dashboards showing correct metrics
□ Incident log opened and logging all events
□ Team check-ins every 2 hours
□ Status updates sent to stakeholders
□ Shift change handoff completed successfully
□ Night shift (Shift Bravo) briefed and positioned
□ No critical communications missed
```

### MONITORING LEAD - DAY 1 PROCEDURES

```
MISSION: Watch for any anomalies or issues

05:15 UTC: Dashboard setup
├─ All 4 dashboards refreshing every 15-30 seconds
├─ Baseline metrics captured (screenshot all dashboards)
├─ Alerts configured and responding
└─ Ready to monitor

05:15-12:00 UTC: Continuous monitoring
├─ Every 5 minutes: Screenshot dashboard (for trend analysis)
├─ Watch for:
│  ├─ Replication lag >10s (alert if increasing)
│  ├─ CPU >80% on either node (investigate if sustained)
│  ├─ Error rate >0.5% (alert on unusual pattern)
│  ├─ Memory >85% (monitor for swap usage)
│  └─ Any container exit events (alert immediately)
└─ Alert threshold: Escalate if ANY metric exceeds bounds

12:00 UTC: Daily report to Infrastructure Lead
├─ "All metrics normal, no anomalies detected"
├─ Replication lag: X seconds average
├─ CPU average: X%
├─ Memory average: X%
├─ Error rate: X%
└─ Confidence: HIGH

MONITORING LEAD CHECKLIST - DAY 1:
□ Dashboards set to correct refresh rates
□ Baseline metrics captured (screenshot)
□ No anomalies detected
□ All metrics within normal ranges
□ Screenshot every 5 minutes
□ Trending analysis: All metrics stable
□ Ready for 12-hour shift change
```

### QA LEAD - DAY 1 PROCEDURES

```
MISSION: Execute Phase 1 testing

05:15-05:30 UTC: Test environment verification
├─ Verify test database is separate from production
├─ Verify test API credentials working
├─ Load first test scenario
└─ Ready to execute

05:30-07:00 UTC: Phase 1 Test Suite Execution (90 min)
├─ Test 1: API basic functionality
│  └─ Expected: All API endpoints responding with 200 OK
├─ Test 2: Web UI loading
│  └─ Expected: UI loads within 3 seconds
├─ Test 3: Database connectivity
│  └─ Expected: Queries execute normally
├─ Test 4: User authentication
│  └─ Expected: Login flow working
└─ Results: [X] passed, [X] failed

07:00-12:00 UTC: Results analysis
├─ If all passed: Document in test log, prepare next test phase
├─ If failures: Investigate root cause, escalate to Infrastructure
├─ Daily summary: [X] tests executed, [Y] passed, [Z] failed
└─ Report to Ops Lead: Test status and readiness for Day 2 tests

QA LEAD CHECKLIST - DAY 1:
□ Test environment verified
□ Phase 1 test suite executed
□ All tests passed (or failures documented and escalated)
□ Test results logged
□ Ready for Day 2 Phase 2 testing
```

### SECURITY LEAD - DAY 1 PROCEDURES

```
MISSION: Monitor security posture

05:15-12:00 UTC: Security monitoring
├─ Every 30 minutes: Check access logs for anomalies
│  └─ Look for: Unusual login attempts, failed auths, suspicious IPs
├─ Monitor: SSL certificate status (should be valid)
├─ Verify: Firewall rules still active
├─ Check: Encryption active on all data paths
└─ Alert if: Any suspicious activity detected

12:00 UTC: Daily security report
├─ Access logs: Normal activity only
├─ Failed authentication attempts: [X] (normal baseline)
├─ Suspicious activity detected: NO
├─ Compliance violations: NONE
└─ Security posture: NORMAL

SECURITY LEAD CHECKLIST - DAY 1:
□ Access logs monitored (no suspicious activity)
□ SSL certificates verified (valid expiry dates)
□ Firewall rules confirmed active
□ Encryption status confirmed
□ No security incidents
□ Compliance requirements met
```

### PROJECT MANAGER - DAY 1 PROCEDURES

```
MISSION: Track progress and report status

05:15-05:30 UTC: Standup facilitation
├─ Bring all 6 team leads together
├─ Each reports readiness
└─ Confirm: ALL SYSTEMS GO

05:30-12:00 UTC: Tracking and reporting
├─ Track Phase 1 completion status
├─ Status update at 06:00 UTC: "Phase 1 progressing normally"
├─ Status update at 09:00 UTC: "Phase 1 on track for completion"
├─ Status update at 12:00 UTC: "Phase 1 COMPLETE - All systems green"
└─ Log in incident tracking: All milestones hit

12:00 UTC: Daily progress report
├─ Phase 1: ✓ COMPLETE (100%)
├─ Confidence level: HIGH (>95%)
├─ Risk level: LOW (<5%)
├─ Go/No-Go: ✓ GO for Phase 2 tomorrow
└─ Next milestone: Phase 2 starts May 2

PROJECT MANAGER CHECKLIST - DAY 1:
□ Standup facilitation at 05:15 UTC
□ Phase 1 progress tracked hourly
□ Status updates sent at 06:00, 09:00, 12:00 UTC
□ Incident log updated with all events
□ Daily progress report completed
□ All team leads on track
□ Sleep planned (5+ hours)
```

---

## 🛌 DAY 2 - MAY 2, 2026

### MORNING STANDUP (05:00 UTC)

```
ALPHA SHIFT (May 2, 05:00-13:00 UTC) - Shift change from Day 1 Night team
├─ Review: Day 1 Phase 1 complete, all green
├─ Today: Phase 2 - GitHub PR process begins
├─ Objective: Create branch, pull request, and prepare for merge
└─ Success criterion: PR created and ready for review by end of day
```

### TODAY'S OBJECTIVES BY ROLE

**Infrastructure Lead:**
- Prepare code branch with deployment changes
- Create GitHub PR with Phase 2 updates
- Status: Phase 2 Step 1 - PR Creation

**Operations Lead:**
- Continue war room management
- Monitor Phase 2 progress
- Ensure all communications flowing
- Status updates: 06:00, 09:00, 12:00, 15:00 UTC

**Monitoring Lead:**
- Continuous dashboard surveillance
- Trending analysis of Week 1 Day 1 metrics
- Alert on any increases in replication lag or errors
- Status: All metrics stable, no concerns

**QA Lead:**
- Phase 2 testing: PR validation
- Verify code changes not introducing regressions
- Status: Validation in progress

**Security Lead:**
- Access logs: Continue monitoring
- New code review for security implications
- Status: No security issues detected

**Project Manager:**
- Track Phase 2 progress toward PR creation
- Status report: "Phase 2 executing normally, PR creation on schedule"
- Expected: PR ready for review by 15:00 UTC

---

## 📋 WEEK 1 DAILY PATTERN (Days 3-12)

**After Days 1-2 (May 1-2), all remaining Week 1 days follow this pattern:**

### DAILY MORNING STANDUP (05:00 UTC - NEW SHIFT ALPHA)

```
All 6 team leads + Project Manager (10 minutes)

1. Project Manager: "Day [X] status check, Phase [Y]"

2. Each lead reports (1 min each):
   "My area: [Status], [Key metric], [Confidence: HIGH/MEDIUM/LOW]"

   Infrastructure: "Containers: [X]/87, Replication lag: [X]s, Confidence: HIGH"
   Operations: "War room: Nominal, Communications: Active, Confidence: HIGH"
   Monitoring: "Dashboards: Green, Anomalies: None, Confidence: HIGH"
   QA: "Tests: [X] passed/failed, Readiness: [Status], Confidence: HIGH"
   Security: "Access logs: Normal, Issues: None, Confidence: HIGH"
   Project Manager: "Phase progress: [X]%, On track: YES, Confidence: HIGH"

3. Any blockers? Issues? → Escalate immediately
4. Proceed to daily Phase tasks
```

### DAILY 12:00 UTC MIDDAY CHECK-IN

```
Ops Lead calls quick sync with all leads (5 minutes)

Status check:
├─ Infrastructure: Phase progress %
├─ QA: Test results
├─ Monitoring: Any anomalies
├─ Security: Any incidents
└─ Project Manager: Overall confidence level

If all green: Continue Phase
If issues: Escalate, adjust plan
```

### DAILY 18:00 UTC EVENING REPORT

```
Before Shift Bravo takes over

Project Manager sends status email to stakeholders:
├─ Phase [X] progress: [%]
├─ Key metrics (from Monitoring): [Summary]
├─ Issues encountered: [List or "None"]
├─ Tomorrow's plan: [Phase next steps]
└─ Confidence: [HIGH/MEDIUM/LOW]

Example Day 3 report:
  Phase 2 progressing normally (40% complete)
  Metrics: All green, no anomalies
  Issues: None
  Tomorrow: PR review and merge preparation
  Confidence: HIGH (>95%)
```

### DAILY 04:00 UTC NIGHT SHIFT TURNOVER

```
Shift Charlie to Shift Alpha handoff (30 minutes overlap)

Each team lead briefs incoming team:
├─ Night shift progress summary
├─ Any issues encountered
├─ Current status
├─ Next morning's tasks
└─ Any carry-over work

Incoming team confirms understanding:
├─ [ ] Understand current Phase status
├─ [ ] Know morning tasks
├─ [ ] Aware of any issues
└─ [ ] Ready to proceed
```

---

## 🎯 WEEK 1 PHASE TIMELINE (May 1-12)

```
DAY 1 (May 1): Phase 1 - Infrastructure Activation
├─ Objective: Setup foundation (all 87 containers)
├─ Success: All containers operational
└─ Duration: May 1 05:15-12:00 UTC (completed by end of Day 1)

DAYS 2-4 (May 2-4): Phase 2 - GitHub PR Process
├─ Objective: Create PR, get approvals, merge code
├─ Success: Code merged to main branch
└─ Duration: 3 days (May 2 05:00 UTC - May 4 20:00 UTC)

DAY 5 (May 5): Phase 3 - Docker Build
├─ Objective: Build new container images
├─ Success: Images built and pushed to registry
└─ Duration: 1 day (May 5 05:00 UTC - May 5 18:00 UTC)

DAYS 6-7 (May 6-7): Phase 4 - Staging Deployment
├─ Objective: Deploy to staging environment
├─ Success: All services running in staging
└─ Duration: 2 days (May 6 05:00 UTC - May 7 18:00 UTC)

DAY 8 (May 8): Phase 5 - Failover Verification
├─ Objective: Test failover procedures
├─ Success: HA failover works correctly
└─ Duration: 1 day (May 8 05:00 UTC - May 8 18:00 UTC)

DAYS 9-12 (May 9-12): Phase 6-8 - 72-Hour Observation
├─ Objective: Monitor for 72 hours (zero critical issues)
├─ Success: 72 hours pass with no critical issues
└─ Duration: 4 days (May 9 05:00 UTC - May 12 23:59 UTC)

MAY 12 CHECKPOINT:
  ✓ Phase 1-8 COMPLETE
  ✓ 72-hour observation PASSED
  ✓ Week 1 SIGNED OFF
  └─ GO for Week 2 Production Prep
```

---

## ⚠️ IF ISSUES ARISE DURING WEEK 1

**Minor Issue (can be fixed in <5 minutes):**
- Investigate and fix immediately
- Continue operations
- Log in incident tracking
- Inform Operations Lead

**Moderate Issue (takes 5-30 minutes to fix):**
- Investigate and attempt fix
- If not resolved in 15 min: Escalate to team lead
- Operations Lead: Assess impact on timeline
- Continue Phase if possible, or pause Phase

**Critical Issue (>30 min to fix or blocking Phase completion):**
- Escalate to CTO immediately
- Stop Phase execution
- CTO decides: Fix and delay OR Proceed to contingency
- All team leads notified via phone call

**Data Loss Risk Detected:**
- STOP all operations immediately
- Call CTO + General Counsel
- Do NOT attempt any fixes
- Wait for legal/technical guidance

---

## ✅ DAILY CHECKLIST TEMPLATE (Print & Use Each Day)

```
WEEK 1 DAILY CHECKLIST - DAY [X], [DATE]

MORNING STANDUP (05:00 UTC):
□ All 6 team leads present
□ Each lead reported status
□ No critical blockers
□ Proceed to Phase [X]

INFRASTRUCTURE TASKS:
□ [Task 1 name]: COMPLETE / IN PROGRESS / BLOCKED
□ [Task 2 name]: COMPLETE / IN PROGRESS / BLOCKED
□ [Task 3 name]: COMPLETE / IN PROGRESS / BLOCKED
Status: [X]% of Phase [X] complete

OPERATIONS MANAGEMENT:
□ War room operational
□ All communications active
□ Incident log updated
□ Status updates sent (06:00, 09:00, 12:00 UTC)
Status: Nominal

MONITORING VIGILANCE:
□ Dashboards updated every 15 seconds
□ Replication lag: [X]s average (normal: <5s)
□ CPU average: [X]% (normal: <40%)
□ Error rate: [X]% (normal: <0.1%)
□ Screenshots taken every 5 minutes
Status: All metrics normal

QA TESTING:
□ Phase [X] tests executed: [Y] count
□ Tests passed: [Z]
□ Tests failed: [A]
□ Issues escalated: [B]
Status: [Testing status]

SECURITY MONITORING:
□ Access logs reviewed
□ No suspicious activity
□ SSL certificates valid
□ Compliance requirements met
Status: All clear

MIDDAY CHECK-IN (12:00 UTC):
□ All leads reported status
□ Progress: [X]% of Phase complete
□ Confidence: HIGH / MEDIUM / LOW
□ Issues: NONE / [List]

EVENING REPORT (18:00 UTC):
□ Status email sent to stakeholders
□ Phase progress reported: [X]%
□ Tomorrow's plan confirmed: Phase [X]
□ Confidence for next day: HIGH / MEDIUM / LOW

NIGHT SHIFT HANDOFF (04:00 UTC):
□ Shift Bravo briefed on progress
□ Any carry-over work explained
□ Morning tasks confirmed
□ All systems handed over cleanly

DAILY SUMMARY:
Phase [X] progress: [X]% complete
Issues encountered: NONE / [Describe]
Critical issues: NONE / [Escalated to CTO]
Team morale: HIGH / GOOD / AT RISK
Sleep planned: 5+ hours per person: YES / NO

READY FOR DAY [X+1]? YES / NO
If NO, describe what needs resolution: [...]
```

---

## 🏆 SUCCESS CRITERIA FOR WEEK 1

**By May 12, 23:59 UTC, ALL of these must be TRUE:**

- [ ] **Phase 1-8 All Complete:** All 8 phases of staging deployment finished
- [ ] **72-Hour Observation Passed:** Zero critical issues for 72 hours
- [ ] **All Metrics Green:** Replication lag <5s, CPU <80%, Error rate <1%, Uptime 99%+
- [ ] **Team Ready:** No team members working >3 consecutive 8-hour shifts, morale HIGH
- [ ] **Infrastructure Stable:** No unexpected container restarts, no data issues
- [ ] **Documentation Current:** All procedures updated, lessons learned captured
- [ ] **Sign-Offs Obtained:** Infrastructure, Operations, QA, Security all sign Week 1 complete

**If ALL criteria met:**
→ **Week 1 CHECKPOINT PASSED** - Proceed to Week 2 production prep

**If ANY criteria not met:**
→ **HOLD** - Resolve issues before proceeding to Week 2

---

**Print this document.**  
**Laminate each day's section.**  
**Keep one copy per team member.**  
**Reference every day May 1-12.**

This is your daily playbook for success. Follow it precisely.

