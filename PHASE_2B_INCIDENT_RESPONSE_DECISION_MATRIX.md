# PHASE 2B INCIDENT RESPONSE DECISION MATRIX
## Quick Decision Tree for Rapid Incident Classification & Response

**Purpose:** Team can rapidly classify incidents and know exactly what to do  
**Audience:** All team members (Infrastructure Lead especially)  
**Format:** Single page, laminate and post on wall  
**Usage:** When issue detected, follow decision tree to determine severity and action

---

## 🚨 INCIDENT SEVERITY & RESPONSE MATRIX

```
INCIDENT DETECTED
   ↓
   
STEP 1: CLASSIFY SEVERITY
═════════════════════════════════════════════════════════════════

Ask these questions:

Is data at risk?
├─ YES → CRITICAL (go to CRITICAL response below)
├─ NO → Continue

Is deployment blocked or severely impaired?
├─ YES → CRITICAL (go to CRITICAL response below)
├─ NO → Continue

Is there degraded service or partial functionality?
├─ YES → HIGH (go to HIGH response below)
├─ NO → Continue

Is there a minor issue or anomaly?
├─ YES → MEDIUM (go to MEDIUM response below)
└─ NO → LOW (informational only)

───────────────────────────────────────────────────────────────────

SEVERITY LEVEL: [CRITICAL / HIGH / MEDIUM / LOW]

Now find your severity level below and follow response procedures.
```

---

## 🔴 CRITICAL SEVERITY INCIDENTS

**What qualifies:**
- Data loss or corruption detected
- Multiple containers crashed (>2)
- Database not responding or replication broken
- Replication lag >60 seconds
- API errors >5%
- VIP not responding
- Security breach suspected
- Multiple system failures cascading

**IMMEDIATE RESPONSE (Next 30 seconds):**
```
[ ] 1. Call CTO NOW (don't email, CALL)
      "CRITICAL issue: [ONE SENTENCE DESCRIPTION]"
      
[ ] 2. Stop all Phase work immediately
      "Team, PAUSE current work. Critical issue detected."
      
[ ] 3. Notify all team leads in war room
      Slack: @Infrastructure @Operations @Monitoring - CRITICAL ISSUE
      
[ ] 4. Document in incident log (even if brief)
      "[TIME] CRITICAL - [Description]"
      
[ ] 5. CTO provides direction
      Wait for CTO guidance - don't proceed without approval
```

**INVESTIGATION PHASE (Next 5 minutes):**
```
[ ] Infrastructure Lead: Investigate root cause
    ├─ Check system logs
    ├─ Verify what failed
    ├─ Identify why it failed
    └─ Report findings to CTO

[ ] Monitoring Lead: Assess scope
    ├─ How many users affected?
    ├─ How long has it been happening?
    ├─ Screenshot dashboards

[ ] Operations Lead: Prepare contingency
    ├─ Brief team on Pause/Rollback procedures
    ├─ Stand by to execute CTO direction
    ├─ Prepare stakeholder communication
```

**CTO DECISION POINT (After 5 min investigation):**
```
CTO decides one of:

1. FIX IT (if fixable in <30 min)
   └─ Infrastructure Lead attempts fix
      Monitoring Lead watches for recovery
      Report when recovered

2. INVESTIGATE MORE (if complex situation)
   └─ Continue investigation up to 60 min total
      If fixed: Return to normal operations
      If not fixed: Move to ROLLBACK

3. ROLLBACK (if can't fix)
   └─ Execute rollback procedures
      Restore to known good state
      Resume from rollback point

4. ABORT (if unrecoverable)
   └─ Execute abort procedures
      Restore to previous release
      Incident post-mortem begins
```

**ESCALATION CONTACTS:**
```
Immediate escalation: CTO [Phone: _______________]
Backup escalation: VP Operations [Phone: _______]
Legal escalation: General Counsel [Phone: ______]
Executive escalation: Executive Sponsor [Phone: _]
```

**DOCUMENTATION (During and after):**
```
Incident log entry MUST include:
├─ TIME - When detected
├─ DESCRIPTION - What happened
├─ ROOT CAUSE - Why it happened
├─ IMPACT - Who affected, how many, how long
├─ RESOLUTION - What was done
├─ TIME TO RESOLVE - How long it took
└─ PREVENTION - What we'll do to prevent
```

---

## 🟠 HIGH SEVERITY INCIDENTS

**What qualifies:**
- Single container crashed or exited
- Replication lag 30-60 seconds
- API errors 1-5%
- High CPU sustained >80% for >5 min
- High memory >90%
- One service responding slowly
- Performance degradation
- Any security concern (not breach)

**IMMEDIATE RESPONSE (Next 5 minutes):**
```
[ ] 1. Alert Infrastructure Lead
      "HIGH severity issue: [description]"
      
[ ] 2. Describe to Monitoring Lead
      "Watch this metric: [X], alert if worsens"
      
[ ] 3. Document in incident log
      "[TIME] HIGH - [Description]"
      
[ ] 4. Infrastructure Lead investigates
      "Can we fix this? How long?"
      
[ ] 5. Decide: Fix or Escalate
```

**INVESTIGATION & RESOLUTION (5-30 minutes):**
```
[ ] What caused it?
[ ] Can we fix it?
[ ] How long to fix?
[ ] What's the impact if we don't fix?

IF FIXABLE IN <15 MIN:
  └─ Attempt fix
     Monitor for recovery
     Document solution

IF TAKES >15 MIN:
  └─ Escalate to CTO for guidance
     "We think we can fix it but it takes X minutes"
     CTO decides: FIX / INVESTIGATE MORE / ESCALATE

IF NOT FIXABLE:
  └─ Escalate to CTO
     "This needs higher-level intervention"
```

**ESCALATION DECISION:**
```
If unresolved after 15 minutes → Call CTO
"HIGH severity issue, [description]. 
 We've investigated and [what we found].
 Recommendation: [your assessment]"

CTO decision: Continue fix / Escalate further / Pause / Rollback
```

---

## 🟡 MEDIUM SEVERITY INCIDENTS

**What qualifies:**
- One container restarting repeatedly
- Replication lag 10-30 seconds
- API errors 0.5-1%
- CPU 50-80% for several minutes
- Memory 80-90%
- Minor service slowness
- Database query slow (but not timing out)
- One failed health check

**RESPONSE (Investigate, no emergency):**
```
[ ] 1. Infrastructure Lead investigates (no call needed)
      What caused it?
      Is it transient or persistent?
      
[ ] 2. Monitor for 5 minutes
      Is it recovering?
      Is it getting worse?
      
[ ] 3. Take action based on findings:

      IF IT RECOVERS:
      └─ Document in incident log
         "Issue self-resolved"
         Continue normal operations

      IF IT'S PERSISTENT:
      └─ Attempt to fix
         If fixed within 10 min: Log and continue
         If not fixed: Escalate to CTO
         
      IF IT'S GETTING WORSE:
      └─ Escalate to CTO immediately
         "Situation deteriorating"

[ ] 4. Operations Lead updates incident log
      Keep narrative of what's happening
```

**ESCALATION TRIGGER:**
```
If issue persists >10 minutes → Call CTO
"MEDIUM severity issue: [description].
 Status: [current investigation findings].
 Recommend: [your advice]"

CTO may suggest more investigation or move to HIGH/CRITICAL procedures
```

---

## 🟢 LOW SEVERITY / INFORMATIONAL INCIDENTS

**What qualifies:**
- Transient network glitch (1-2 sec)
- Minor log warnings (not errors)
- One slow query (but recovered)
- Metrics slightly outside range (but stable)
- Non-critical service restart

**RESPONSE:**
```
[ ] Log in incident log
[ ] Monitor to ensure not recurring
[ ] If recurring: Escalate to MEDIUM
[ ] If single event: Document and move on

No immediate action needed
No escalation needed
```

---

## 📋 INCIDENT RESPONSE PROCEDURE SUMMARY

```
┌─────────────────────────────────────────────────────────┐
│ INCIDENT RESPONSE DECISION TREE - QUICK REFERENCE      │
└─────────────────────────────────────────────────────────┘

INCIDENT DETECTED
        ↓
┌─ CRITICAL? (data/deployment at risk)
│      ├─ YES → CALL CTO NOW → Wait for direction
│      └─ NO → Continue below
│
├─ HIGH? (significant degradation/service impact)
│      ├─ YES → Alert Infrastructure Lead → Investigate 15 min
│      │         → If not fixed: Call CTO
│      └─ NO → Continue below
│
├─ MEDIUM? (minor degradation/recoverable)
│      ├─ YES → Infrastructure Lead investigates → Monitor 10 min
│      │         → If not fixed: Call CTO
│      └─ NO → Continue below
│
└─ LOW/INFO? (transient, not concerning)
       └─ Log and monitor → No escalation needed


GOLDEN RULE:
If issue is unresolved after time threshold:
  └─ Move up one severity level
     └─ Escalate to CTO

NEVER IGNORE:
✗ Never wait >30 min without escalating to CTO
✗ Never assume it will fix itself (always verify recovery)
✗ Never fail to document (incident log is future's teacher)
```

---

## 🎯 TEAM MEMBER QUICK ACTION GUIDE

**If you spot an issue:**

1. **Don't panic.** Breathe. Think clearly.

2. **Describe it in ONE SENTENCE:**
   "Containers on PRIMARY down from 87 to 84"

3. **Is anyone at risk of harm?**
   - Data loss risk? → CRITICAL (call immediately)
   - Service broken? → HIGH (call if not fixed in 15 min)
   - Degraded performance? → MEDIUM (investigate, escalate if persists)
   - Minor blip? → LOW (log and monitor)

4. **Take action per severity level above**

5. **Document everything in incident log** (even if minor)

6. **Tell your lead, who tells their lead, escalate as needed**

---

## 📞 ESCALATION CONTACTS (Keep Handy)

```
LEVEL 1 (Local):
  Infrastructure Lead: _________________________
  Operations Lead: ____________________________
  Your direct supervisor: _____________________

LEVEL 2 (Department):
  CTO: ____________________  Phone: ___________
  VP Operations: _______________  Phone: _____

LEVEL 3 (Executive):
  Executive Sponsor: ____________  Phone: _____
  General Counsel: ______________  Phone: _____

EXTERNAL (If vendor issue):
  AWS Support: _______________ Ticket: _______
  GitLab Support: _____________ Ticket: ______
  Database Support: ____________ Ticket: ______

REMEMBER:
Never hesitate to escalate
Never assume someone else will handle it
Always escalate if unsure about severity
In doubt, escalate up
```

---

## ✅ INCIDENT LOG ENTRY TEMPLATE

**Every incident gets logged (even minor ones):**

```
[TIME] [SEVERITY] [COMPONENT] - [ONE LINE DESCRIPTION]
Status: DETECTED / INVESTIGATING / RESOLVED
Owner: [Who's handling it]
Impact: [Who/what affected]
Root Cause: [Once determined]
Actions: [What was done]
Resolution: [How it ended]
Follow-up: [Preventive measure or retry needed?]

Example entry:
[14:23] [HIGH] [Database] - Replication lag spiked to 45 seconds
Status: INVESTIGATING
Owner: Infrastructure Lead
Impact: Data consistency lag, users may see stale data
Root Cause: High write load from tests
Actions: Identified test surge, monitored recovery
Resolution: Lag recovered to <5s within 5 minutes
Follow-up: Adjust test concurrency to prevent recurrence
```

---

**Print this guide. Laminate it. Post on war room wall. Reference it when incidents occur.**

**Fast, clear decisions prevent panic. Good processes prevent disasters.**

