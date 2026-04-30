# PHASE 2B ROLE-SPECIFIC ONE-PAGE QUICK REFERENCES
## Print, Laminate, Keep at Desk - For All 6 Team Leads

**Purpose:** Each role has a one-page summary for quick daily reference  
**Format:** Tear along dashes, print 1 per role, laminate, tape to desk  
**Usage:** Consult during shift when you need quick reminder of responsibilities

---

# 📋 INFRASTRUCTURE LEAD - ONE-PAGE QUICK REFERENCE

## YOUR MISSION
Maintain all 87 containers running. Monitor replication. Alert if issues.

## DAILY CHECKLIST (Every 2 hours)
```
□ Docker containers: docker ps | wc -l (should = 87)
□ Replication lag: Check Grafana (should be <5s)
□ Container health: docker ps (check STATUS column)
□ API responsive: curl http://PRIMARY:8080/api/v4/user
□ Database: docker exec gitlab_db psql -U postgres -c "SELECT 1"
```

## IF ISSUES APPEAR
```
Container exited?
  → docker-compose restart [service_name]

Replication lag >30s?
  → Check CPU on REPLICA: docker stats
  → If OK, monitor for 2 min
  → If persists, call CTO

API not responding?
  → Check nginx: docker logs nginx
  → Restart if needed: docker restart gitlab_nginx

Database slow?
  → Check connections: docker exec gitlab_db psql -U postgres -c "SELECT * FROM pg_stat_activity"
  → If >40: Potential issue, escalate

VIP not responding?
  → Ping 192.168.168.50
  → If no response, SSH to PRIMARY, restart keepalived
  → Wait 10s, ping again
```

## ESCALATION CONTACTS
```
CTO: [Phone number]
Operations Lead: [Phone number]
On-Call Engineer: [Phone number]
```

## RED FLAGS → CALL CTO IMMEDIATELY
- Multiple containers crashed
- Replication lag >60s
- Data corruption detected
- Cannot SSH to either node
- Disk usage >90%
- Memory usage >95%

## SUCCESS TODAY
Phase [X] complete by 12:00 UTC / All systems green

---

# 📊 MONITORING LEAD - ONE-PAGE QUICK REFERENCE

## YOUR MISSION
Watch dashboards. Alert on anomalies. Trends are your job.

## DASHBOARD METRICS (Check every 5 minutes)
```
Grafana Dashboard 1 - Cluster Health:
  □ Replication lag: ______ s (normal: <5s)
  □ CPU PRIMARY: ______ % (normal: <40%)
  □ CPU REPLICA: ______ % (normal: <40%)
  □ Memory PRIMARY: ______ % (normal: <80%)
  □ Memory REPLICA: ______ % (normal: <80%)

Grafana Dashboard 2 - Database Replication:
  □ WAL bytes: ______ (trending?)
  □ Replication slot: Active / Inactive
  □ Lag: ______ s

Grafana Dashboard 3 - Application Performance:
  □ Response time: ______ ms (normal: <500ms)
  □ Error rate: ______ % (normal: <0.1%)
  □ Requests/sec: ______ (baseline)

Grafana Dashboard 4 - Services Status:
  □ All services: GREEN / YELLOW / RED
```

## ALERT THRESHOLDS
```
YELLOW ALERT (notify Ops Lead, monitor):
  - Replication lag 10-30s
  - CPU 50-80%
  - Memory 80-90%
  - Error rate 0.5-1%
  - Response time 500-1000ms

RED ALERT (call CTO immediately):
  - Replication lag >60s
  - CPU >90%
  - Memory >95%
  - Error rate >5%
  - Response time >2000ms
```

## SCREENSHOT TRACKING
```
Take screenshots every 5 minutes:
  ✓ Trend analysis (can show issue happened)
  ✓ Evidence for post-incident review
  ✓ Baseline for next shift

Store in: screenshots/ folder with timestamp
```

## ESCALATION TRIGGER
If ANY metric shows RED for >1 minute → Call CTO

---

# ⚙️ OPERATIONS LEAD - ONE-PAGE QUICK REFERENCE

## YOUR MISSION
War room command center. Team coordination. Status reporting.

## HOURLY RESPONSIBILITIES
```
Hour 0 (start of shift):
  □ Verify all communications working (Slack, email, phone)
  □ Start 8-hour monitoring clock
  □ Brief team on today's Phase

Every 60 minutes:
  □ Quick 5-min team sync (all 6 leads)
  □ Each reports 1-minute status
  □ Note: Any issues? Actions needed?
  □ Escalate critical items immediately

Status updates (email to stakeholders):
  □ 06:00 UTC: Morning brief
  □ 12:00 UTC: Pre-handoff status
  □ 18:00 UTC: End-of-day report
  □ [Adjust times based on shift]

End of shift:
  □ Incident log summary
  □ Handoff checklist
  □ All issues escalated or resolved
```

## TEAM COORDINATION
```
Team support (during shift):
  - Check in with each lead (informal)
  - Notice: Who looks tired? Stressed?
  - Encourage: Movement breaks, hydration
  - Facilitate: If conflicts arise, resolve quickly

Shift change handoff:
  - Ensure all pair handoffs complete (30 min)
  - Each team lead signs off
  - Release to next shift
```

## ESCALATION DECISION TREE
```
Minor issue (can fix in <5 min) → Fix and continue
Moderate issue (takes 5-30 min) → Monitor, escalate if >15 min
Critical issue (>30 min or blocking) → Call CTO immediately
Data loss risk → STOP, call CTO + General Counsel
```

## COMMUNICATION TEMPLATES
```
Email subject: "[DATE] Phase [X] Status - [Status]"
Body: Phase progress, metrics, issues, next focus, confidence

Slack message: "@channel Phase [X] update: [% complete], [status]"

Critical alert: "@Infrastructure @CTO CRITICAL ISSUE: [Description]"
```

## SUCCESS TODAY
All team leads coordinated / No escalations left unresolved / Shift handed off cleanly

---

# 🧪 QA LEAD - ONE-PAGE QUICK REFERENCE

## YOUR MISSION
Test Phase [X]. Ensure no regressions. Alert on failures.

## DAILY TEST PLAN
```
Phase [X] tests for today:
  Test 1: [Name] ........................ Target: Pass
  Test 2: [Name] ........................ Target: Pass
  Test 3: [Name] ........................ Target: Pass
  Test 4: [Name] ........................ Target: Pass
  [Add tests per Phase]

Success: [X]% of tests passed
Failures: [List any failures]
```

## TEST EXECUTION
```
Per test:
  1. Setup test environment (if needed)
  2. Run test with exact parameters
  3. Verify expected output
  4. Document result (PASS / FAIL)
  5. If FAIL: Note error message, escalate

Track: Test results log
Report: Daily to Ops Lead
```

## IF TESTS FAIL
```
Step 1: Investigate (5 min)
  - Is it environment issue or code issue?
  - Can you reproduce?
  - Have you seen this before?

Step 2: Attempt fix (5 min)
  - Is it quick fix? Try it
  - Not fixable? Stop here

Step 3: Escalate (if not fixed in 10 min)
  - Tell Infrastructure Lead
  - Describe: What, why, impact
  - Let them decide: Fix now or continue

Step 4: Document
  - Note in incident log
  - Will review after deployment
```

## REGRESSION DETECTION
```
Watch for:
  - API endpoints not responding
  - Web UI not loading
  - Authentication failures
  - Data not persisting
  - Performance degradation

If detected:
  - Alert immediately to Infrastructure
  - Describe: What regression, when detected
```

## SUCCESS TODAY
All Phase [X] tests passed / No regressions detected / QA sign-off obtained

---

# 🔒 SECURITY LEAD - ONE-PAGE QUICK REFERENCE

## YOUR MISSION
Monitor security posture. Alert on incidents. Verify compliance.

## HOURLY SECURITY CHECK
```
Access logs review (every 60 min):
  □ Failed authentication attempts: [#] (normal: <5)
  □ Suspicious IPs attempting access: YES / NO
  □ Unusual login patterns: YES / NO
  □ Successful logins from new locations: YES / NO

SSL certificate status:
  □ Certificate valid: YES (expiry: [DATE])
  □ Certificate chain complete: YES
  □ No certificate warnings: YES

Firewall status:
  □ Rules active: YES
  □ No unexpected rule changes: YES

Encryption status:
  □ TLS active on all connections: YES
  □ No unencrypted data channels: YES
```

## RED FLAGS → ALERT IMMEDIATELY
```
- Multiple failed auth attempts from same IP
- Successful login from impossible location
- Unauthorized admin access detected
- Certificate expired or expiring today
- Firewall rules modified
- Unencrypted data detected
- Any security incident in logs
```

## COMPLIANCE VERIFICATION
```
Daily compliance checklist:
  □ Access controls working
  □ Audit logging active
  □ Data encryption active
  □ Backup encryption active
  □ No data exfiltration patterns
```

## ESCALATION CONTACTS
```
CTO: [Phone]
General Counsel: [Phone] (if legal implications)
Security Officer: [Phone]
```

## SUCCESS TODAY
Zero security incidents / All compliance requirements met / Access logs normal

---

# 📈 PROJECT MANAGER - ONE-PAGE QUICK REFERENCE

## YOUR MISSION
Track progress. Coordinate teams. Report status. Make go/no-go decisions.

## MORNING RESPONSIBILITIES (04:00-05:00 UTC)
```
□ Morning standup facilitation (10 min)
  - All 6 leads present
  - Each reports readiness
  - Go/No-Go decision
  - Record decision

□ Status report prep
  - Phase progress assessment
  - Confidence level
  - Expected completion
```

## THROUGHOUT SHIFT (Every 2 hours)
```
□ Track Phase completion %
□ Monitor any escalations
□ Facilitate quick decisions if needed
□ Update incident log with major events
□ Check team morale (informal)
```

## STATUS UPDATES (Send to stakeholders)
```
Timing:
  - 06:00 UTC: Morning brief
  - 12:00 UTC: Pre-handoff status
  - 18:00 UTC: End-of-day summary

Content:
  - Phase [X]: [%] complete
  - Status: ON TRACK / AT RISK / BLOCKED
  - Key metrics: Uptime [%], Errors [%], Replication [Xs]
  - Issues: NONE / [Description]
  - Tomorrow: Plan for Phase [X+1]
  - Confidence: HIGH / MEDIUM / LOW
```

## GO/NO-GO DECISION
```
Criteria for GO:
  ✓ All Phase [X] tasks complete (or on track)
  ✓ No critical issues unresolved
  ✓ All systems green (or recovering from known issue)
  ✓ Team ready to proceed
  ✓ No blocking items

If ALL criteria met → GO
If ANY not met → HOLD and escalate

Decision maker: CTO (final call)
Your role: Facilitate, recommend, implement
```

## COMMUNICATION
```
Stakeholders to update:
  - Executive Sponsor (daily at 18:00 UTC)
  - CTO (immediate if critical)
  - Operations Lead (hourly)
  - All team leads (hourly sync)

Templates:
  - Email template in communications doc
  - Slack template in communications doc
  - Phone escalation script in emergency ref
```

## SUCCESS TODAY
Phase [X] progress [%] / Team morale HIGH / All communications sent / Status accurate

---

## 🎯 QUICK REFERENCE USAGE

**Print:** One copy of each 1-page reference (6 total)  
**Laminate:** Protects from spills, wear  
**Placement:** Tape to each person's desk in war room  
**Usage:** Consult when you need quick reminder  
**Update:** If procedures change mid-deployment, mark on laminate with dry-erase pen

Each team member now has their role distilled to ONE PAGE.
No need to flip through documents.
Just glance at desk reference for your responsibilities.

---

**Created:** April 30, 2026  
**Distribution:** One per team lead (6 copies)  
**Format:** Print, laminate, tape to desk, reference during shift

