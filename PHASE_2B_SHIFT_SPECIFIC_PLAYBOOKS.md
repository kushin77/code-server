# PHASE 2B SHIFT-SPECIFIC PLAYBOOKS
## Alpha, Bravo, Charlie - Condensed Daily References

**Purpose:** Each shift has their own condensed playbook to print and keep at desk  
**Audience:** Each shift team (rotating 8 hours)  
**Format:** Print 1 copy per person, laminate, keep at station  
**Duration:** May 1-12, 2026 (24/7 operations)

---

## ⏰ SHIFT ALPHA PLAYBOOK
**Time:** 04:00-12:00 UTC | **Duration:** 8 hours | **Team:** All 6 leads (rotating)

### YOUR MISSION TODAY
Complete Phase [X] tasks. Maintain all systems healthy. Prepare handoff for Shift Bravo.

### ARRIVAL CHECKLIST (04:00 UTC)
```
Upon arrival, each team member:
□ Log into war room systems
□ Check: All 4 Grafana dashboards loading
□ Check: Prometheus targets responding (8+)
□ Check: AlertManager configured
□ Check: Incident log accessible
□ Check: SSH to PRIMARY responds
□ Check: SSH to REPLICA responds
□ Report: Ready to Project Manager

Project Manager action: Start morning standup
```

### MORNING STANDUP (04:00 UTC) - 10 MINUTES
```
All 6 leads present. Each reports:

Infrastructure Lead: "Containers [X]/87, Replication [X]s, Status: [GREEN/YELLOW/RED]"
Operations Lead: "War room: [Status], Comms: [Active/Issues], Status: [GREEN/YELLOW/RED]"
Monitoring Lead: "Dashboards: [Normal/Anomalies], Lag trending: [Status], [GREEN/YELLOW/RED]"
QA Lead: "Tests ready, Environment: [Status], Status: [GREEN/YELLOW/RED]"
Security Lead: "Logs normal, No incidents, Status: [GREEN/YELLOW/RED]"
Project Manager: "Phase [X] go/no-go? ALL LEADS CONFIRM GO → Proceed to Phase work"

If ANY RED flag: HOLD and escalate to CTO immediately
If ALL GREEN: Proceed to Phase [X] execution
```

### HOURLY SYNC (Every hour: 05:00, 06:00, 07:00, etc.)
```
Operations Lead calls 5-minute sync with all leads

Each role reports 1-minute status:
├─ Infrastructure: Phase progress %
├─ Monitoring: Any anomalies
├─ QA: Tests passing?
├─ Security: Any incidents?
└─ Project Manager: On track for today's milestone?

If issues: Briefly discuss, assign owner, escalate if needed
If all green: Continue Phase work
If blocking issue: Call CTO immediately
```

### CRITICAL MONITORING (Operations Lead responsibility)
```
During entire 8-hour shift:

Every 5 minutes:
- Watch Grafana dashboards for RED alerts
- If any RED: Alert Infrastructure Lead immediately
- Screenshot dashboard (evidence)

Every 30 minutes:
- Verify Prometheus targets (8+)
- Check AlertManager is sending alerts
- Verify incident log is being updated

Escalation decision:
- Minor alert (recovers): Wait, monitor
- Persistent alert (>5 min): Investigate, escalate if unsolved
- Critical alert (RED): Escalate immediately to CTO + Infrastructure
```

### END OF SHIFT RESPONSIBILITIES (12:00 UTC)
```
Infrastructure Lead:
- [ ] Document Phase [X] completion status
- [ ] Note any issues encountered
- [ ] Verify all systems green for handoff
- [ ] Prepare to brief Shift Bravo (30 min)

Operations Lead:
- [ ] Prepare shift summary for handoff
- [ ] Update incident log final status
- [ ] Print handoff checklist
- [ ] Notify Shift Bravo: "Ready for 30-min overlap"

Monitoring Lead:
- [ ] Screenshot final dashboards (end-of-shift baseline)
- [ ] Screenshot any anomalies for trend analysis
- [ ] Print metrics report
- [ ] Brief incoming Monitoring Lead

QA Lead:
- [ ] Test results documented
- [ ] Any failures escalated
- [ ] Test environment preserved for Bravo
- [ ] Ready to brief QA on Bravo

Security Lead:
- [ ] Access logs reviewed
- [ ] Any incidents documented
- [ ] Compliance status confirmed
- [ ] Brief Security on Bravo

Project Manager:
- [ ] Daily progress email sent to stakeholders
- [ ] Status update: Phase [X] progress [%]
- [ ] Tomorrow's focus confirmed
- [ ] Incident log summary prepared
```

### SHIFT ALPHA QUICK PHASE REFERENCE

```
DAY 1 (May 1):       Phase 1 - Infrastructure Activation
DAY 2 (May 2-4):     Phase 2 - GitHub PR Process
DAY 5 (May 5):       Phase 3 - Docker Build
DAYS 6-7 (May 6-7):  Phase 4 - Staging Deployment
DAY 8 (May 8):       Phase 5 - Failover Verification
DAYS 9-12 (May 9-12): Phases 6-8 - 72-Hour Observation

Your Phase responsibility: [X] (depends on which day)
Success metric: All Phase [X] tasks complete by shift end
```

---

## ⏰ SHIFT BRAVO PLAYBOOK
**Time:** 12:00-20:00 UTC | **Duration:** 8 hours | **Team:** All 6 leads (rotating)

### ARRIVAL CHECKLIST (12:00 UTC)
```
Shift Alpha still present for 30-min overlap (12:00-12:30)

Your team actions:
□ Log into all systems
□ Read incident log from overnight + morning
□ Check Grafana dashboards
□ Listen to Alpha briefing
□ Understand any issues or changes
□ Ask clarifying questions
□ Take notes on priorities
□ Confirm all systems green
□ Sign off: "Shift Bravo assumes responsibility"
```

### SHIFT HANDOFF (12:00-12:30 UTC) - 30 MINUTES
```
STRUCTURE: Each lead pair meets 1:1 (Shift Alpha → Shift Bravo)

Infrastructure Lead handoff:
- Alpha summarizes: "Phase [X] progress [%], status [GREEN/ISSUES]"
- Alpha describes: "Container health, replication lag, any issues"
- Alpha shows: "Key logs or dashboards"
- Bravo confirms: "Understand the status, know next actions"
- Sign-off: Both sign handoff checklist

Operations Lead handoff:
- Alpha summarizes: "War room status, any escalations"
- Alpha describes: "Communications sent, stakeholder updates"
- Alpha shows: "Incident log entries"
- Bravo confirms: "Understand war room status and priorities"
- Sign-off: Both sign handoff checklist

[Same for Monitoring, QA, Security, Project Manager]

After all pairs complete:
- Project Manager: "All handoffs complete? Ready to proceed?"
- All leads: "Ready"
- Project Manager: "Shift Bravo, you have the war room. Good luck."
```

### MIDDAY SHIFT LAUNCH (12:30 UTC)
```
Shift Alpha leaves. Shift Bravo now fully responsible.

First action - Quick verification (5 min):
- Infrastructure Lead: Verify systems match handoff description
- Operations Lead: Verify war room status
- Monitoring Lead: Verify dashboards showing expected metrics
- QA Lead: Verify test environment
- Security Lead: Verify access logs normal

Then: Begin Phase [X] execution for Bravo team
```

### BRAVO TEAM RESPONSIBILITIES (12:30-20:00 UTC)
```
Continue Phase [X] work from where Alpha left off

Hourly syncs: Same as Alpha (every hour, 5 min)

Monitoring: Same critical monitoring as Alpha

Documentation:
- Update incident log every 2 hours
- Document Phase [X] progress
- Note any issues or changes needed

Evening responsibilities (19:30-20:00):
- Phase completion status assessment
- Metrics snapshot for trend analysis
- Incident log summary
- Handoff checklist preparation
```

### END OF SHIFT (20:00 UTC)
```
Shift Charlie arrives (20:00 UTC)
Overlap: 20:00-20:30 UTC (30 min)

Same handoff process as Alpha→Bravo
Each leader pair meets, transfers knowledge
Charlie signs off on status
Bravo releases war room to Charlie
```

---

## ⏰ SHIFT CHARLIE PLAYBOOK
**Time:** 20:00-04:00 UTC | **Duration:** 8 hours | **Team:** All 6 leads (rotating)

### ARRIVAL CHECKLIST (20:00 UTC)
```
Shift Bravo still present for 30-min overlap

Your team actions:
□ Log into all systems
□ Read incident log from day + Bravo
□ Check Grafana dashboards
□ Listen to Bravo briefing
□ Understand Phase [X] current status
□ Identify any night-specific concerns
□ Ask clarifying questions
□ Confirm all systems green
□ Sign off: "Shift Charlie assumes responsibility"
```

### SHIFT HANDOFF (20:00-20:30 UTC) - 30 MINUTES
```
Same handoff structure as Alpha→Bravo

Each lead pair meets 1:1
Transfer: Status, issues, next actions
Confirm: Charlie understands current state
Sign off: Handoff checklist completed

After all pairs:
- Project Manager: "All handoffs complete? Ready to proceed?"
- All leads: "Ready"
- Project Manager: "Shift Charlie, you have the war room."
```

### NIGHT SHIFT RESPONSIBILITIES (20:30-04:00 UTC)
```
SPECIAL NIGHT SHIFT NOTES:

Team Challenge: Night shift fatigue is real
Your advantage: Fewer interruptions, quieter environment

Infrastructure Lead:
- Monitor for slow issues that build overnight
- If system gets slow: Investigate early
- Don't let issues compound during night

Monitoring Lead:
- More vigilant monitoring (less coverage overnight)
- Alert immediately if ANY anomaly
- Screenshot every hour (more frequent)

Operations Lead:
- Facilitate peer support during night
- Check in with each lead: "How are you doing?"
- Encourage movement breaks and hydration
- Escalate stress/fatigue if noticed

QA Lead:
- Run tests in background (don't require extensive resources)
- Document results for review by day team
- Alert if any regressions appear

Security Lead:
- Monitor access logs closely (suspicious activity more likely at night)
- Alert if anything unusual
- Verify SSL certificates still valid

Project Manager:
- Night shift check-in with each team
- Encourage sleep/rest if off-duty
- Prepare morning status report
```

### HOURLY SYNCS (Every hour: 21:00, 22:00, 23:00, etc.)
```
Same 5-minute syncs as day shifts

BUT NIGHT-SPECIFIC:

If status is GREEN:
- Let teams work
- Don't interrupt unnecessarily

If status is YELLOW:
- Quick investigation
- Escalate to CTO if not resolved in 5 min

If status is RED:
- Immediate escalation
- Get CTO on phone
- Don't hesitate
```

### END OF NIGHT SHIFT (04:00 UTC)
```
Shift Alpha arrives (04:00 UTC)
Overlap: 04:00-04:30 UTC (30 min)

SPECIAL: Night shift often has MORE issues
├─ Bravo must be comprehensive in handoff
├─ Document everything that happened overnight
├─ Alert Alpha to any ongoing monitoring

Same handoff process:
Each leader pair meets, transfers knowledge
Alpha signs off on status
Charlie releases war room to Alpha

THEN: Charlie goes to sleep (hopefully 5+ hours)
```

---

## 🚨 EMERGENCY ESCALATION (All Shifts)

```
If ANY of these occur, ESCALATE IMMEDIATELY:

CRITICAL (Call CTO NOW):
- Container crashes (>1 restarting)
- Replication lag >60 seconds
- Database connection errors
- API errors >5%
- VIP not responding
- Data anomalies detected
- Multiple containers exiting

HIGH (Call CTO in 2 minutes):
- Any RED alert on dashboard
- Persistent slow performance
- Memory >90%
- CPU >95%
- Disk >80%
- Any security incident

MEDIUM (Tell Ops Lead, monitor):
- YELLOW alerts
- Replication lag 15-60 seconds
- Single container restart
- Minor performance degradation

PROCEDURE:
1. Identify issue (2 min)
2. Call escalation contact
3. Explain: What, Why, Impact
4. Listen: Guidance
5. Execute: Direction given
6. Document: In incident log
```

---

## 📋 SHIFT HANDOFF CHECKLIST

**Use this EVERY shift change (Alpha→Bravo, Bravo→Charlie, Charlie→Alpha)**

```
SHIFT HANDOFF CHECKLIST

Date: May [X], 2026
Time: [04:00 / 12:00 / 20:00] UTC
Outgoing Shift: [Alpha / Bravo / Charlie]
Incoming Shift: [Bravo / Charlie / Alpha]

INFRASTRUCTURE LEAD HANDOFF:
Outgoing status:
  □ Phase [X] completion: [%]
  □ Container count: [X]/87 running
  □ Replication lag: [X] seconds
  □ Current issues: NONE / [List]
  □ Known risks: NONE / [List]

Incoming confirmation:
  □ Understand current status
  □ Know next Phase actions
  □ Aware of any issues
  □ Know escalation contacts
  □ Ready to proceed

Sign-off:
Outgoing Infrastructure Lead: _____________ Time: _______
Incoming Infrastructure Lead: _____________ Time: _______

[Repeat same format for Operations, Monitoring, QA, Security, Project Manager]

OVERALL SHIFT STATUS:
□ All systems operational
□ No critical issues
□ No escalations pending
□ Team morale: HIGH / GOOD / OK / AT RISK
□ Ready to proceed

Shift handoff duration: [30 min target] ______ Actual time
Overall readiness: READY TO PROCEED / NEEDS ATTENTION

Project Manager final check:
"All team leads confirmed ready?" 
All leads: Yes / No

If NO: Resolve before shift change completes
If YES: Release shift to incoming team
```

---

## ✅ SHIFT-BY-SHIFT SUCCESS CRITERIA

```
SHIFT ALPHA SUCCESS (04:00-12:00 UTC):
□ Morning standup completed on time
□ Phase [X] tasks 50% complete
□ No critical incidents
□ Team morale HIGH
□ Handoff completed by 12:00 UTC

SHIFT BRAVO SUCCESS (12:00-20:00 UTC):
□ Handoff received, Alpha work understood
□ Phase [X] tasks 80%+ complete
□ No critical incidents during day
□ Team morale HIGH
□ Status update sent to stakeholders
□ Handoff completed by 20:00 UTC

SHIFT CHARLIE SUCCESS (20:00-04:00 UTC):
□ Handoff received, Bravo work understood
□ Phase [X] tasks 100% complete or progressing
□ No critical incidents during night
□ Team morale maintained (night shift support active)
□ No escalations left unresolved
□ Handoff completed by 04:00 UTC

If ALL shifts successful on given day:
→ Day checkpoint: ✓ PASSED
→ Phase progress on track
→ Proceed to next day
```

---

**Print this document.**  
**Tear along dashes to separate shift playbooks.**  
**Laminate one copy per shift.**  
**Keep at desk during May 1-12.**

Each shift now has their exact playbook for 24/7 success.

