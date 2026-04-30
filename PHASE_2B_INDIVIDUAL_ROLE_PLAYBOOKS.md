# PHASE 2B INDIVIDUAL ROLE PLAYBOOKS
## Personalized Daily Checklists for Each Team Lead (May 1-21, 2026)

**Purpose:** Each team member has exact daily procedures tailored to their specific role  
**Audience:** 6 team leads (print one per person, tape to desk)  
**Duration:** May 1-21, 2026 (21 days of detailed guidance)  
**Format:** Print 8.5x11, laminate, keep at workstation

---

## 📋 ROLE PLAYBOOK ARCHITECTURE

Each role playbook contains:
- **Daily Checklist** (morning, midday, evening)
- **Hourly Watch Points** (what to monitor)
- **Escalation Triggers** (when to alert leadership)
- **Decision Authority** (what you decide vs. escalate)
- **Success Criteria** (how to know you're winning)
- **Common Issues** (5-minute fixes)
- **Handoff Checklist** (shift end responsibilities)

---

## 🏗️ INFRASTRUCTURE LEAD PLAYBOOK
**Role:** System health, container management, database operations  
**Decision Authority:** All infrastructure decisions <30 min, escalate >30 min  
**Escalates To:** CTO, Project Manager

### DAILY CHECKLIST

**MORNING (First hour of shift):**
```
□ Login to PRIMARY and REPLICA
  Command: ssh ubuntu@192.168.168.31
  Command: ssh ubuntu@192.168.168.42
  Verify: Shell prompt for both machines

□ Run health check script
  Command: bash check-system-health.sh
  Expected: GREEN output for all categories
  If any YELLOW: Investigate root cause (< 5 min)
  If any RED: Escalate to CTO immediately

□ Check container counts
  Command: docker-compose -f docker-compose.enterprise.yml ps | grep -c "Up"
  Expected: 87 on PRIMARY, 88 on REPLICA
  If <85: Investigate which containers exited
  If <84: Escalate to CTO (potential cascading failure)

□ Verify database replication
  Command: psql -h 192.168.168.31 -U gitlab -d gitlabhq_production -c "SELECT slot_name, slot_type, confirmed_flush_lsn FROM pg_replication_slots;"
  Expected: Active slot, confirmed_flush_lsn not NULL
  If delayed: Check network or REPLICA CPU

□ Check VIP status
  Command: ping -c 3 192.168.168.50
  Expected: All pings successful
  If fails: Restart keepalived on REPLICA
  Command: sudo systemctl restart keepalived

□ Review incident log from previous shift
  Location: PHASE_2B_DEPLOYMENT_INCIDENT_EVENT_LOG.md
  Note: Any unresolved issues from overnight
  Plan: How to address if still relevant

□ Sign off on morning readiness
  Message: "#phase2b-deployment: Infrastructure systems GREEN, ready for operations"
  CC: Project Manager, Operations Lead
```

**MIDDAY (Noon check-in, every shift):**
```
□ Re-run health check
  Command: bash check-system-health.sh
  Status: GREEN / YELLOW / RED
  If changed from morning: Investigate immediately

□ Check for container restarts
  Command: docker-compose -f docker-compose.enterprise.yml ps --no-trunc | grep Restarting
  Expected: None
  If any: Identify why and document in incident log

□ Monitor replication lag
  Query: SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT AS replication_lag_seconds;
  Expected: <5 seconds
  If 5-30 sec: Investigate database load
  If >30 sec: Escalate to CTO

□ Check resource usage on both nodes
  Command: free -h && df -h && top -bn1 | head -20
  Expected: Memory <80%, Disk <85%, CPU <70%
  If above thresholds: Identify hot processes
  
□ Verify all services responding
  Command: curl -s http://192.168.168.31:8080/api/v4/health -o /dev/null -w "%{http_code}\n"
  Expected: 200 or 401 (not 5xx)
  If 5xx: Check application logs

□ Document current status
  File: PHASE_2B_DEPLOYMENT_INCIDENT_EVENT_LOG.md
  Entry: "[TIME] [INFO] [INFRASTRUCTURE] Midday status check - all systems nominal"
```

**END OF SHIFT (Before handoff):**
```
□ Run final health check
  Command: bash check-system-health.sh
  Status: GREEN / YELLOW / RED
  If RED: Don't leave without escalating

□ Summarize shift incidents
  Document: Any issues detected and resolved
  Include: Root cause, fix applied, prevention

□ List unresolved issues for next shift
  Format: "Issue X pending [action/decision] from [who]"
  Timeframe: Expected resolution when?

□ Verify incoming shift Infrastructure Lead
  Method: Call or video chat (not Slack)
  Content: "Here's the current status and what to watch"
  Duration: 15-30 minutes minimum

□ Handoff tasks
  Pass logs, dashboards, incident notes to incoming lead
  Answer all questions before leaving

□ Sign off on shift completion
  Log entry: "[TIME] [SHIFT_END] Infrastructure systems stable, [issue count] issues, handoff complete"
```

### HOURLY WATCH POINTS

```
Every hour, Infrastructure Lead should:

□ Glance at Prometheus: Any alerts firing?
□ Count containers: Still 87 on PRIMARY?
□ Listen to Monitoring Lead: Any issues reported?
□ Check replication lag: Still <5 seconds?
□ Review Slack: Any deployment team questions?
□ Mental check: Am I still capable? Need break?

If anything RED:
  └─ Stop current work
  └─ Investigate (5-10 min max)
  └─ If fixable: Fix it
  └─ If not: Call CTO immediately
```

### ESCALATION TRIGGERS

```
ESCALATE IMMEDIATELY (Call CTO, don't email):
- 2+ containers unexpectedly exited
- Replication lag >60 seconds
- Any RED health check category
- VIP not responding
- Database not accepting connections
- Any 5xx errors from API
- Network unreachable between nodes
- Disk space below 20%

ESCALATE AFTER 10 MIN IF UNRESOLVED:
- Replication lag 30-60 seconds
- CPU sustained >80%
- Memory >90%
- Single container crash
- Transient connectivity issue

ALERT OPERATIONS LEAD IF:
- Unusual resource usage pattern
- High number of restarted containers
- Deployment ahead/behind schedule
- Any decision made that affects timeline
```

### COMMON ISSUES & 5-MIN FIXES

```
ISSUE: Single container exited
FIX:
  □ Identify which container: docker-compose ps
  □ Check logs: docker logs [container_name]
  □ Restart: docker-compose restart [container_name]
  □ Verify restarted: docker-compose ps
  □ Log incident: Brief description of why

ISSUE: Replication lag spiked to 20+ seconds
FIX:
  □ Check PRIMARY CPU: top (is it high?)
  □ Check REPLICA CPU: ssh to REPLICA, top
  □ Check network latency: ping 192.168.168.42
  □ If PRIMARY high: Identify hot query or process
  □ If REPLICA high: May need to lighten other workloads
  □ If network: Contact networking team

ISSUE: Memory climbing above 80%
FIX:
  □ Identify largest process: top -o %MEM
  □ Check if container: Is it running process or container?
  □ For container: Check if leak or expected
  □ Restart if needed: docker restart [container]
  □ Monitor for recurrence
  □ If persistent: Escalate to CTO for application analysis

ISSUE: Health check returning YELLOW
FIX:
  □ Re-run to confirm not transient: bash check-system-health.sh
  □ Read YELLOW message carefully
  □ Take suggested action from health check output
  □ Re-run to verify resolution
  □ If still YELLOW: Escalate to CTO

ISSUE: VIP not responding to ping
FIX:
  □ Check which node is active: keepalived status
  □ Restart on active node: sudo systemctl restart keepalived
  □ Wait 10 seconds, re-ping
  □ If still down: Try failover (manual if needed)
  □ If fails: Escalate to CTO immediately
```

### SUCCESS CRITERIA FOR INFRASTRUCTURE LEAD

```
At end of shift, you succeeded if:

✓ No unplanned container restarts
✓ Replication lag stayed <5 seconds all shift
✓ Health check GREEN all shift (or quickly resolved to GREEN)
✓ All phases executed on schedule
✓ Any incidents logged and root cause identified
✓ No critical alerts escalated beyond CTO
✓ Incoming shift prepared and confident
✓ You know what to monitor during next shift
```

---

## 📊 OPERATIONS LEAD PLAYBOOK
**Role:** Team coordination, decision escalation, incident tracking, shift management  
**Decision Authority:** Day-to-day operations, shift coordination, escalate strategic decisions  
**Escalates To:** CTO, Project Manager

### DAILY CHECKLIST

**MORNING (First hour of shift):**
```
□ Review previous shift incident log
  File: PHASE_2B_DEPLOYMENT_INCIDENT_EVENT_LOG.md
  Read: Yesterday's entries, unresolved issues
  Assess: Do any carry into today?

□ Brief all team leads
  Method: 10-minute standup at shift start
  Content: Yesterday summary + today's focus + watch points
  Format: "Here's where we are, here's what's next, here's what to watch"

□ Verify team capacity
  Check: Sleep hours, hydration, readiness
  Action: Note any concerns for wellness monitoring

□ Review today's Phase schedule
  Resource: PHASE_2B_WEEK1_DAILY_OPERATIONS_PLAYBOOK.md
  Timeline: Today's phases, estimated duration, lead for each
  Verify: Infrastructure Lead prepared for first phase

□ Set up incident tracking for the day
  Initialize: New entry in incident log for today
  Format: Date, shift, leads present, start time

□ Establish communication channels
  Slack: #phase2b-deployment active and monitored
  Email: Ready to send escalations
  Phone: On desk, ready for CTO calls
```

**EVERY HOUR DURING SHIFT:**
```
□ Hourly standup (15 minutes)
  Participants: All 6 leads
  Content: Each lead reports status: GREEN / YELLOW / RED
  Format: "Infrastructure: GREEN, Operations: GREEN, Monitoring: YELLOW - high error rate but investigating"
  Outcome: Any escalations needed?

□ Incident log update
  Add: Any incidents from past hour
  Format: [TIME] [SEVERITY] [AREA] - Brief description
  Status: What's the current state? Who's handling?

□ Team health pulse check
  Visual scan: Is anyone struggling?
  Informal: "How's everyone doing?"
  Action: If concerns, note for wellness lead

□ Slack monitoring
  Check: Any questions from team?
  Respond: Answer promptly or route to lead
  Escalate: Any issues needing higher attention?
```

**END OF SHIFT (Before handoff):**
```
□ Prepare daily summary
  Content: Phases completed, incidents, team health, tomorrow's focus
  Format: Written summary for handoff document
  Length: 1 paragraph, 5-10 sentences

□ Compile incident summary
  From: All incidents logged today
  To: Daily statistics (incident count, resolution time, team impact)
  File: PHASE_2B_DEPLOYMENT_INCIDENT_EVENT_LOG.md (daily summary section)

□ Brief incoming Operations Lead
  Duration: 20-30 minutes
  Content: Full shift recap, unresolved issues, advice for tomorrow
  Format: 1:1 call or in-person

□ Hand off documentation
  Pass: Incident log, phase status, any notes
  Verify: Incoming lead comfortable and confident

□ Final status message
  Slack: "#phase2b-deployment Shift complete. [Summary]. Ready for handoff."
  CC: Project Manager
```

### DECISION AUTHORITY MATRIX

```
YOU DECIDE (Don't escalate):
- Team break timing (take it when suitable)
- Phase pacing (move forward/pause based on team)
- Shift schedule adjustments (swaps, timing)
- Communication distribution (who gets what update)
- Incident severity assessment
- Which team member works on which phase

ESCALATE TO PROJECT MANAGER:
- Phase slipping behind schedule
- Multiple critical incidents in one shift
- Team health concerning (score <10)
- Need to modify deployment plan
- Executive communication needed
- Bring in additional team members

ESCALATE TO CTO:
- Technical decision needed (fix vs. rollback)
- Any CRITICAL incident
- Deployment pause or contingency activation
- Authorization for unusual actions
- System architecture decision
```

### WELLNESS MONITORING CHECKLIST

```
Each shift, use this to assess team:

Infrastructure Lead:
  Sleep last night: _____ hours
  Stress level: LOW / MODERATE / HIGH / CRITICAL
  Energy: HIGH / OK / LOW / FLAGGING
  Concern? YES / NO - If yes: _________________

Monitoring Lead:
  Alert fatigue? YES / NO
  Stress level: LOW / MODERATE / HIGH / CRITICAL
  Energy: HIGH / OK / LOW / FLAGGING
  Concern? YES / NO - If yes: _________________

[Repeat for all 6 leads]

Team Health Score: ___/25 (from resilience guide)

Action if concerning:
  □ Talk to person in private
  □ Offer support (break, reassignment, rest)
  □ Document in wellness log
  □ Escalate if severe
```

### SUCCESS CRITERIA FOR OPERATIONS LEAD

```
At end of shift, you succeeded if:

✓ All team leads knew what to do all day
✓ All incidents tracked in log
✓ Team health supported and monitored
✓ Communication flowing smoothly
✓ Escalations sent promptly and clearly
✓ No surprises for incoming lead
✓ Team ready and confident for tomorrow
✓ All phases on track or ahead
```

---

## 📡 MONITORING LEAD PLAYBOOK
**Role:** Dashboard surveillance, alert response, status visibility  
**Decision Authority:** Alert investigation & response, thresholds  
**Escalates To:** Infrastructure Lead, CTO

### DAILY CHECKLIST

**MORNING:**
```
□ Login to Grafana
  URL: http://192.168.168.50:3000
  Dashboards: Cluster Health, Database Replication, Services Status
  Status: All GREEN? YELLOW? Any RED from overnight?

□ Check alert history
  AlertManager: Any alerts fired overnight?
  If yes: Read resolution status from incident log
  If ongoing: Note for Infrastructure Lead

□ Verify Prometheus scraping
  URL: http://192.168.168.50:9090
  Targets: All targets UP?
  Expected: 8+ targets, all GREEN
  If any DOWN: Alert Infrastructure Lead

□ Set up dashboard display
  Monitor: Primary display showing Cluster Health
  Refresh: Set to 15-second intervals
  Keep: Eye on throughout shift

□ Review alerting rules
  Check: All 6+ alert rules are active
  Expected: HIGH and CRITICAL rules active
  Test: No false positives from previous shift

□ Establish baseline for shift
  Screenshot: Current dashboard state
  Numbers: Container count, replication lag, error rate
  Reference: Use to detect changes during shift
```

**EVERY 15 MINUTES:**
```
□ Quick visual scan
  Dashboards: Any color changes (GREEN→YELLOW→RED)?
  Trends: Metrics going up/down?
  Alerts: Any new alerts firing?

□ If any YELLOW or RED:
  □ Note exact metric and value
  □ Check time it started
  □ Alert Infrastructure Lead in Slack
  □ Keep watching (auto-recovery or escalate?)

□ Record observations
  Log: Casual notes in incident log
  Format: "[HH:MM] Replication lag 8 sec - within bounds"
```

**HOURLY:**
```
□ Comprehensive dashboard review
  All 4 dashboards: Cluster Health, Database, Services, Performance
  Status of each: GREEN / YELLOW / RED
  Trend: Getting better / stable / worse?

□ Alert status
  Any active alerts? List them.
  Response: Who's handling each?
  Escalation needed? Check with Infrastructure Lead.

□ Document in hourly summary
  Entry: All metrics observed, alert status, any actions taken

□ Report to Operations Lead
  Status: "All metrics GREEN, no alerts"
  Or: "Replication lag elevated at 8 seconds, Infrastructure investigating"
```

**END OF SHIFT:**
```
□ Final dashboard screenshot
  Capture: Complete state for handoff
  Save: Include time and all metrics visible

□ Alert summary
  Compile: How many alerts fired this shift?
  Duration: How long did each last?
  Resolution: Root cause for each (if known)

□ Briefing for incoming Monitoring Lead
  Duration: 15-20 minutes
  Content: Dashboard state, alerts fired, watch points
  Display: Show dashboards live, walk through

□ Handoff checklist
  Verify: Incoming lead knows how to navigate Grafana
  Verify: Incoming lead knows alert thresholds
  Verify: Incoming lead knows escalation procedures
```

### WATCH POINTS

```
Monitor these throughout shift - watch for:

Primary Container Count:
  Expected: 87
  YELLOW: 86 or 85
  RED: 84 or below

Replication Lag:
  Expected: <5 seconds
  YELLOW: 5-30 seconds
  RED: >30 seconds

Primary CPU:
  Expected: <70%
  YELLOW: 70-80%
  RED: >80%

Memory Usage:
  Expected: <80%
  YELLOW: 80-90%
  RED: >90%

API Error Rate:
  Expected: <0.5%
  YELLOW: 0.5-2%
  RED: >2%

Service Response Time:
  Expected: <100ms
  YELLOW: 100-500ms
  RED: >500ms
```

### ALERT RESPONSE PROCEDURE

```
When alert fires in AlertManager:

STEP 1: Read alert message carefully (5 sec)
  Example: "HIGH: PostgreSQL Replication Lag > 30s"
  Understand: What system is affected?

STEP 2: Assess severity
  CRITICAL alert: Call CTO immediately
  HIGH alert: Alert Infrastructure Lead in Slack with urgency
  MEDIUM alert: Alert Infrastructure Lead, monitor

STEP 3: Investigate (2-5 min)
  Check: What's the current value?
  Check: How long has it been elevated?
  Check: Any corresponding alerts?
  Check: Any phase activity that might explain it?

STEP 4: Communicate
  Alert Infrastructure Lead: "[System] showing [issue], current value [X], [action taken or needed]"
  If escalation: "@Infrastructure Lead urgent: [description]"

STEP 5: Monitor resolution
  Watch dashboard: Is alert resolving?
  If yes: Document when resolved
  If no: After 5 min, escalate to CTO

STEP 6: Document
  Log entry: Alert fired, duration, resolution, any actions
```

### SUCCESS CRITERIA FOR MONITORING LEAD

```
At end of shift, you succeeded if:

✓ All dashboards remained visible and refreshing
✓ All alerts were noticed within 2 minutes of firing
✓ All alerts were escalated appropriately
✓ Team aware of any issues immediately
✓ No alert was missed
✓ Root cause identified for all alerts (if Infrastructure found)
✓ You alert-watched without fatigue
✓ Dashboard data clean and historic (for retrospective)
```

---

## 🧪 QA LEAD PLAYBOOK
**Role:** Testing execution, regression verification, deployment validation  
**Decision Authority:** Test execution pace, coverage decisions  
**Escalates To:** Operations Lead, Project Manager

### DAILY CHECKLIST

**MORNING:**
```
□ Review today's Phase testing plan
  Resource: PHASE_2B_WEEK1_DAILY_OPERATIONS_PLAYBOOK.md
  Today's phase: What's being deployed?
  Test coverage: What tests need to run today?

□ Prepare test environment
  Access: Test accounts ready?
  Data: Test data seeded?
  Scripts: All automated tests available?
  Expected: No blockers to testing

□ Brief QA team (if any)
  Explain: Today's phases and testing approach
  Assign: Who tests what?
  Timeline: When do tests need to complete?
  Success: What does "all tests pass" look like?

□ Verify phase readiness with Infrastructure Lead
  Confirm: Infrastructure ready for deployment?
  Ask: Any known issues I should test for?
  Coordinate: When phase starts testing?

□ Set up test tracking
  System: Track which tests passed/failed
  Document: Results go in incident log
  Screenshot: Save test results for retrospective

□ Establish communication
  Slack: Ready to report test status
  Email: Ready to escalate failures
  Call: Ready to debug with Infrastructure Lead
```

**DURING PHASE EXECUTION:**
```
□ Execute regression test suite
  Scope: All tests covering deployed component
  Automated: Run automated test suite
  Manual: Run critical manual tests
  Expected: 95%+ pass rate

□ Log test results
  Entry: [TIME] [PHASE_X] [COMPONENT] - Testing [feature]
  Result: PASS / FAIL
  Details: Any failures logged with root cause

□ Report blockers immediately
  Critical failure: Alert Operations Lead
  Format: "Test [name] failed, [description], [impact], [need from infrastructure]"
  Blocking: If blocks deployment, escalate to CTO

□ Retest any failures
  Failed test: Re-run to confirm not transient
  If transient: Document and move on
  If persistent: Escalate, may indicate deployment issue

□ Keep Operations Lead updated
  Hourly: Send brief status
  Format: "Tests progressing well" or "Test [X] blocked, investigating"
```

**END OF PHASE:**
```
□ Final test summary
  Passes: Total tests passed
  Failures: Total tests failed
  Blockers: Any tests blocking further deployment?

□ Approval decision
  Ask: Can this phase be marked complete?
  Criteria: 95%+ pass rate, no critical failures
  If yes: "Phase [X] QA approval: PASS"
  If no: "Phase [X] QA approval: HOLD - [reason]"

□ Log final result
  Entry: "[TIME] [PHASE_X] QA Sign-Off - [PASS/HOLD] - [Summary]"
```

**END OF SHIFT:**
```
□ Compile daily test report
  Phases tested: How many?
  Success rate: How many passed?
  Failures: List any failures and root causes
  Impact: Did any failures impact deployment timeline?

□ Briefing for incoming QA Lead
  Duration: 15 minutes
  Content: Phases completed, any retesting needed, today's results
  Action: What does incoming QA lead need to do first?

□ Handoff documentation
  Pass: All test logs, results, any notes
  Verify: Incoming lead knows test procedures
  Ask: Any questions about test approach?
```

### QA DECISION AUTHORITY

```
YOU DECIDE (Don't escalate):
- Exact test procedures and sequence
- Transient vs. persistent failure assessment
- Minor test adjustments
- Test pacing (fast track vs. thorough)
- Retry strategy for failed tests

ESCALATE TO OPERATIONS LEAD:
- Any test blocking deployment progress
- Multiple critical failures in one phase
- Need Infrastructure Lead assistance
- Need to pause deployment for investigation
- Need to deviate from test plan

ESCALATE TO CTO:
- Critical failure suggesting architectural issue
- Need to rollback due to pervasive failures
- Test failure indicates data corruption
- Need to adjust deployment strategy due to testing
```

### SUCCESS CRITERIA FOR QA LEAD

```
At end of shift, you succeeded if:

✓ All planned tests were executed
✓ 95%+ of tests passed
✓ All failures investigated and documented
✓ No defect slipped through to production
✓ Each phase approved for completion
✓ Test coverage complete for deployed code
✓ Incoming QA lead knows what to do tomorrow
✓ No unresolved test issues blocking deployment
```

---

## 🔒 SECURITY LEAD PLAYBOOK
**Role:** Security monitoring, compliance verification, access control  
**Decision Authority:** Security alerts, access decisions  
**Escalates To:** CTO, Legal/Executive

### DAILY CHECKLIST

**MORNING:**
```
□ Security baseline review
  Previous shift: Any security incidents logged?
  Today: Expected baseline security posture?
  Watch: What threats to monitor today?

□ Access log review
  System: Check who logged in overnight
  Expected: Only on-call operations staff
  Unexpected: Anyone logging in outside normal hours?
  Action: If unexpected, investigate

□ Verify security controls active
  Firewall: Rules in place?
  SSL/TLS: Certificates valid?
  Authentication: MFA enabled?
  Authorization: RBAC rules active?
  Encryption: Data at rest/in transit encrypted?

□ Review incident log for security entries
  Previous incidents: Any security-related?
  Status: Resolved or ongoing?
  Impact: Any continuing risk?

□ Establish security watch for today
  Focus: What are the highest-risk activities today?
  Priority: Stages where data most vulnerable?
  Alerts: Know what to monitor?

□ Communications
  Slack: Ready to alert on security issues
  Phone: Ready to escalate to CTO immediately
  Legal: Ready to contact if breach suspected
```

**DURING DEPLOYMENT:**
```
□ Hourly security posture check
  Logs: Any failed login attempts?
  Alerts: Any security scanner alerts?
  Access: Only authorized users accessing systems?
  Data: Only authorized data being accessed?

□ During data migrations (if applicable)
  Encryption: Data encrypted during migration?
  Audit log: Migration activities logged?
  Access: Only authorized staff present?
  Verification: Data integrity checksums match?

□ Monitor for unusual access patterns
  Unusual IPs: Who's connecting from where?
  Bulk transfers: Any large data movements?
  API calls: Abnormal API access patterns?
  Database: Unusual query patterns?

□ Respond to security alerts
  Alert received: Immediately assess
  True positive: Investigate + escalate
  False positive: Document + continue
  Unclear: Err on side of caution (escalate)

□ If security incident suspected
  Immediate: Isolate affected system (take offline if needed)
  Immediate: Contact CTO and Legal
  Immediate: Document everything (for forensics)
  Do not: Delete logs or access histories
```

**END OF SHIFT:**
```
□ Security incident summary
  Any incidents? List them.
  Resolved? How was each resolved?
  Impact: Did any affect deployment timeline?

□ Access and audit logs
  Compile: All access events from shift
  Review: Anything concerning?
  Archive: Save for compliance review

□ Briefing for incoming Security Lead
  Duration: 15 minutes
  Content: Any ongoing security concerns? Watch points?
  Action: What to monitor during next shift?

□ Final security status
  Log entry: "[TIME] [SHIFT_END] Security posture [GREEN/YELLOW/RED]"
```

### SECURITY WATCH POINTS

```
Monitor throughout shift:

Access attempts:
  □ Failed logins: Should be 0 per hour (except typos)
  □ Off-hours access: Only on-call authorized?
  □ Unusual IPs: Connecting from expected locations?

Data flows:
  □ Database queries: Only expected queries?
  □ File transfers: Only expected files moving?
  □ API calls: Expected request patterns?

System integrity:
  □ File permissions: Unchanged since yesterday?
  □ Process list: Only expected processes?
  □ Network connections: Only expected connections?

Compliance:
  □ Audit logs: Recording all activities?
  □ Encryption: Still active and valid?
  □ Certifications: SSL/TLS certs valid?
```

### ESCALATION TRIGGERS

```
ESCALATE IMMEDIATELY:
- Any unauthorized access detected
- Any data breach suspected
- Any encryption failure
- Any malicious code detected
- Any compliance violation
- Any denial-of-service activity
- Any privilege escalation attempt

ESCALATE AFTER INVESTIGATION:
- Unusual access patterns
- Anomalous data movements
- Failed login attempts (>10 per hour)
- Expired certificates or credentials
- Policy violation (even if no impact)

ALERT CTO & LEGAL IF:
- Any breach confirmed
- Any unauthorized data exposure
- Compliance violation with legal impact
- Customer data affected
```

### SUCCESS CRITERIA FOR SECURITY LEAD

```
At end of shift, you succeeded if:

✓ No unauthorized access occurred
✓ No data breach or exposure
✓ All security controls remained active
✓ All suspicious activity investigated
✓ All compliance requirements met
✓ All access properly audited
✓ Team aware of any security concerns
✓ Incoming Security Lead knows watch points
```

---

## 📋 PROJECT MANAGER PLAYBOOK
**Role:** War room leadership, decision coordination, team alignment  
**Decision Authority:** Day-to-day prioritization, team assignments  
**Escalates To:** CTO, Executive Sponsor

### DAILY CHECKLIST

**BEFORE SHIFT STARTS:**
```
□ Review today's planned phases
  Resource: PHASE_2B_WEEK1_DAILY_OPERATIONS_PLAYBOOK.md
  Today: Which phases scheduled?
  Timeline: Estimated completion time?
  Dependencies: Any phases dependent on previous?

□ Prepare for shift standup
  Agenda: Confirm all 6 leads ready
  Timeline: Share today's phases and timing
  Success: Define "day complete" for team
  Support: Ask how you can help

□ Review previous day incidents
  File: PHASE_2B_DEPLOYMENT_INCIDENT_EVENT_LOG.md
  Issues: Any carryover from yesterday?
  Action: What needs addressing today?
  Impact: Any timeline adjustments needed?
```

**MORNING STANDUP (30 min):**
```
□ Call all 6 team leads
  Method: Video conference in war room
  Participants: All must attend
  Duration: 30 minutes max

□ Review overnight/previous shift
  Status: What happened since yesterday?
  Issues: Any incidents or concerns?
  Timeline: Still on track?

□ Lay out today's plan
  Phases: Which phases today?
  Owners: Who leads each phase?
  Timeline: When does each phase start/end?
  Success: What does done look like?

□ Remove blockers
  Ask each lead: "Do you have what you need?"
  Action: Resolve any blockers before they work

□ Set communication expectations
  Frequency: Hourly status updates (15 min)
  Escalation: When to call vs. Slack
  Decisions: How quickly can I decide?

□ Motivate and align team
  Message: "Here's the big picture - you're here because you're the best"
  Focus: "Today's phases are critical, you've got this"
  Support: "I'm here for any decision or escalation needed"

□ Confirm go-ahead
  Ask: All leads ready to proceed?
  Result: READY / NEEDS MORE SETUP
```

**DURING SHIFT - HOURLY STANDUP (15 min):**
```
□ Each lead reports status (2-3 min each)
  Infrastructure: "Systems GREEN" or "[issue status]"
  Operations: "Team functioning well" or "[concern]"
  Monitoring: "No alerts" or "[alerts fired and status]"
  QA: "Tests proceeding" or "[test failures and action]"
  Security: "No incidents" or "[security events and status]"
  You: "Timeline on track" or "[adjustments needed]"

□ Assess overall progress
  Phases: On schedule? Ahead? Behind?
  Incidents: Any escalations needed?
  Team: Morale? Fatigue? Any support needed?
  Blockers: Any decisions needed from you?

□ Make any decisions needed
  Fast decisions (yes/no): Make them immediately
  Complex decisions: Take 5 min discussion, decide
  Escalations: Know when to call CTO

□ Adjust plan if needed
  Schedule: Any phases shifted?
  Resources: Any reallocation needed?
  Timeline: Still on track for day completion?
  Communication: Update team if anything changes

□ Log status update
  Entry: "[TIME] Hourly standup - status [summary]"
```

**END OF SHIFT:**
```
□ Final daily standup (30 min)
  All 6 leads: Final status report
  Accomplishments: Celebrate what was done
  Issues: Any unresolved items?
  Tomorrow: What's the focus?

□ Compile daily summary
  Content: What was accomplished today?
  Incidents: How many? Severity? Resolution?
  Timeline: Ahead / on-track / behind schedule?
  Team health: Morale / fatigue / support given?

□ Prepare executive brief
  For: CTO and Executive Sponsor
  Content: Day summary in 1 paragraph
  Status: Deployment progress toward May 21 completion
  Risks: Any risks to deployment timeline?

□ Briefing for incoming Project Manager
  Duration: 30 minutes
  Content: Full day recap, tomorrow's focus, watch points
  Handoff: Incoming PM confident to lead tomorrow?

□ Sign off on day
  Log entry: "[DATE] [DAY_NAME] - [Summary]. Team performed [well/adequately/needs support]. Tomorrow focus: [X]."
```

### DECISION AUTHORITY

```
YOU DECIDE WITHOUT ESCALATION:
- Daily phase sequencing (if no schedule impact)
- Team break timing
- Which lead handles which issue
- Hourly meeting timing
- War room setup and procedures
- Non-critical resource allocation

YOU DECIDE WITH QUICK CTO INPUT:
- Timeline slippages (<2 hours)
- Non-critical phase delays
- Team reassignments (>1 person)

ESCALATE TO CTO FOR DECISION:
- Timeline slippages (>2 hours)
- Need to pause deployment
- Contingency level decision (Pause/Rollback/Abort)
- Any CRITICAL incident
- Executive communication needed
- Deployment strategy changes

ESCALATE TO EXECUTIVE SPONSOR:
- Deployment delayed >1 day
- Any breach of compliance
- Deployment abort decision
- Team safety concern
- Post-deployment timeline affected
```

### SUCCESS CRITERIA FOR PROJECT MANAGER

```
At end of shift, you succeeded if:

✓ All team leads knew their mission
✓ All phases executed on schedule
✓ Blockers identified and removed quickly
✓ Team aligned and motivated
✓ Escalations made promptly
✓ Executive brief provided
✓ Team ready for tomorrow
✓ No surprises for incoming PM
✓ Deployment tracking to May 21 completion
```

---

## 📈 MONITORING LEAD PLAYBOOK (Detailed)
**Role:** Dashboard surveillance, alert response, status visibility  
**Decision Authority:** Alert investigation & response, thresholds  
**Escalates To:** Infrastructure Lead, CTO

### HOURLY STATUS REPORT TEMPLATE

```
[HOUR] STATUS REPORT - [DATE] [TIME] UTC

Container Status:
  PRIMARY: [87] / REPLICA: [88] 
  Status: GREEN / YELLOW / RED
  
Database Replication:
  Lag: [X] seconds
  Status: GREEN / YELLOW / RED
  Last verified: [TIME]

Alerts Status:
  Active alerts: [0/1/2+]
  Firing: [List if any]
  Status: GREEN / YELLOW / RED

Resource Usage:
  CPU (PRIMARY): [X]%
  Memory (PRIMARY): [X]%
  Status: GREEN / YELLOW / RED

API Error Rate:
  Last hour: [X]%
  Status: GREEN / YELLOW / RED

Overall Status: [GREEN / YELLOW / RED]

Incidents this hour: [0/1+]
  - [Brief description if any]

Actions taken: [None / Brief description]

Next watch: [What to focus on]
```

---

## 🎯 DAILY ROLE TRANSITION CHECKLIST

**Outgoing Lead → Incoming Lead (Every 8 hours):**

```
30-MINUTE HANDOFF:

□ Outgoing: Prepare comprehensive brief
  □ Full shift recap (accomplishments, issues)
  □ Unresolved items (what needs attention?)
  □ Watch points (what might happen next?)
  □ Critical context (anything unusual?)

□ Incoming: Listen actively and take notes
  □ Ask clarifying questions
  □ Confirm understanding of watch points
  □ Ask about team morale and readiness
  □ Understand escalation procedures

□ Technology handoff
  □ Show dashboards/logs
  □ Share important URLs/logins
  □ Verify access to all systems
  □ Explain any unusual setup

□ Team context
  □ Introduce incoming lead to available team
  □ Point out anyone needing extra support
  □ Highlight any team concerns
  □ Share recognition for good work this shift

□ Sign-off
  □ Outgoing: "I'm comfortable handing off to you"
  □ Incoming: "I'm ready to take over"
  □ Both: Mark handoff complete in log
```

---

**Print these playbooks. Laminate them. Keep at workstation. Reference daily.**

**Each role's success depends on knowing exactly what to do, when to do it, and when to escalate.**

**May 1-21 deployment executed by 6 well-prepared leads following exact procedures = SUCCESS**

