# PHASE 2B SHIFT REMINDER & NOTIFICATION TEMPLATES
## Automated Slack/Email Reminders 2 Hours Before Shift Start

**Purpose:** Each shift gets automated reminder 2 hours before start with their key focus for the day  
**Audience:** All team members (each shift gets specific reminder)  
**Format:** Slack/Email templates, can be automated via cron or Slack bot  
**Frequency:** Daily at 02:00, 10:00, 18:00 UTC (2 hours before each shift)

---

## 📨 SLACK REMINDER - SHIFT ALPHA (2 hours before 04:00 UTC = 02:00 UTC)

```
@channel #shift-alpha | Shift Alpha Daily Brief - Arriving in 2 hours

🌅 GOOD MORNING SHIFT ALPHA (04:00-12:00 UTC)

Today's Focus: May [X], 2026 - Phase [X] Execution

KEY FOCUS FOR TODAY:
├─ Primary objective: [Describe main Phase task]
├─ Success metric: [What success looks like today]
├─ Critical constraint: [Time limit or dependency]
└─ Status heading into today: [Yesterday's final status]

YOUR RESPONSIBILITIES:

🏗️  Infrastructure Lead:
   • [Task 1 for today]
   • [Task 2 for today]
   • [Key monitoring points]
   Contact CTO if: [Issue type]

📊 Operations Lead:
   • War room activation at 03:50 UTC
   • Facilitate morning standup at 04:00 UTC
   • Status updates at 06:00, 09:00, 12:00 UTC
   Emergency escalation contact: [CTO phone]

📈 Monitoring Lead:
   • All dashboards update before 04:00 UTC
   • Screenshot baseline at shift start
   • Alert threshold: Replication lag >30s
   • Report anomalies immediately

🧪 QA Lead:
   • Phase [X] test suite ready
   • Environment verified before 04:00 UTC
   • Test execution starts at 05:15 UTC
   • Escalate failures to Infrastructure

🔒 Security Lead:
   • Access logs reviewed from overnight
   • Any incidents from night shift?
   • Compliance check: [Item]
   • Report to Project Manager

📋 Project Manager:
   • Facilitate morning standup at 04:00 UTC
   • Go/No-Go decision at 05:00 UTC
   • Status report email at 06:00 UTC
   • All team ready? Confirm at 03:55 UTC

PRE-SHIFT CHECKLIST (Before 04:00 UTC):
□ Log into all systems
□ Read incident log from overnight shift
□ Check yesterday's final status
□ Verify your access (SSH keys, dashboards, etc.)
□ Arrive war room by 03:50 UTC
□ Report "ready" in Slack #general at 03:55 UTC

MEETING REMINDERS:
  ├─ 04:00 UTC - Morning Standup (10 min)
  ├─ 05:00 UTC - Go/No-Go Decision Point
  ├─ 06:00 UTC - First hourly sync
  ├─ 12:00 UTC - Shift change preparation
  └─ 12:30 UTC - Shift change handoff complete

QUESTIONS? Reach out to Operations Lead: [Slack handle]
EMERGENCY? Call CTO: [Phone number]

Let's make today great. See you in 2 hours! 🚀
```

---

## 📧 EMAIL REMINDER - SHIFT ALPHA (2 hours before 04:00 UTC = 02:00 UTC)

```
Subject: ⏰ Shift Alpha Brief - May [X] (Arrival in 2 hours)

Team Alpha,

Your shift begins in 2 hours at 04:00 UTC. Here's your daily brief:

PHASE [X] EXECUTION - May [X], 2026
═════════════════════════════════════

Primary Objective:
[What we're accomplishing today]

Success Criteria:
[What success looks like]

Yesterday's Status:
[Summary from night shift]

YOUR ROLES TODAY:

Infrastructure Lead:
- Complete Phase [X] tasks: [specifics]
- Monitor: Replication lag, container health
- Escalation trigger: Containers <85

Operations Lead:
- War room active by 03:50 UTC
- Morning standup at 04:00 UTC
- Status updates: 06:00, 09:00, 12:00 UTC

Monitoring Lead:
- Dashboards ready by 03:55 UTC
- Screenshot baseline at shift start
- Alert if replication lag >30s

QA Lead:
- Test environment verified by 03:55 UTC
- Begin Phase [X] tests at 05:15 UTC
- Report failures immediately

Security Lead:
- Review overnight access logs
- Report any incidents
- Compliance check: [item]

Project Manager:
- Facilitate standup at 04:00 UTC
- Go/No-Go decision at 05:00 UTC
- Email executives at 06:00 UTC

PRE-SHIFT PREPARATION:
1. Review incident log from overnight
2. Verify your system access
3. Arrive war room by 03:50 UTC
4. Report "ready" in Slack
5. Questions? Contact Ops Lead

METRICS FROM YESTERDAY:
- Containers: 87/88 up
- Replication lag: X.Xs avg
- Uptime: 99%+
- Team morale: HIGH

TODAY'S FORECAST:
Weather: 🌤️ (All indicators green)
Confidence: HIGH (>95%)
Risk: LOW

Questions: Reply to this email or message Ops Lead on Slack
Emergency: Call CTO directly

See you at 04:00 UTC! 🚀

---
Operations Team
```

---

## 📨 SLACK REMINDER - SHIFT BRAVO (2 hours before 12:00 UTC = 10:00 UTC)

```
@channel #shift-bravo | Shift Bravo Daily Brief - Arriving in 2 hours

☀️  GOOD MORNING SHIFT BRAVO (12:00-20:00 UTC)

Today's Focus: May [X], 2026 - Phase [X] Continuation

KEY FOCUS FOR TODAY:
├─ Incoming status: [Alpha shift handoff]
├─ Continuation objective: [What you'll advance]
├─ Current phase: Phase [X] [%% complete]
├─ Known risks from morning: [Any items]
└─ Daytime monitoring focus: [Business hours considerations]

YOUR RESPONSIBILITIES:

🏗️  Infrastructure Lead:
   • Receive handoff from Alpha at 11:45 UTC
   • Verify container health matches handoff report
   • Continue Phase [X]: [Tasks for day]
   Contact CTO if: [Issue type]

📊 Operations Lead:
   • War room handoff at 12:00 UTC (30 min overlap with Alpha)
   • Confirm all systems green before assuming leadership
   • Status updates: 15:00, 18:00 UTC
   Emergency contact: [CTO phone]

📈 Monitoring Lead:
   • Receive dashboards from Alpha
   • Continue hourly monitoring
   • Watch for: [Any daytime-specific issues]
   • Screenshot every 5 min

🧪 QA Lead:
   • Receive test status from Alpha
   • Continue Phase [X] testing if in progress
   • Escalate failures immediately
   • Document test results

🔒 Security Lead:
   • Review access logs from morning
   • Monitoring during business hours (higher traffic)
   • Alert on any suspicious patterns
   • Report to Project Manager

📋 Project Manager:
   • Facilitate handoff acceptance at 12:00 UTC
   • Status email at 15:00 UTC
   • Evening report at 18:00 UTC
   • Confirm all shifts are coordinated

HANDOFF CHECKPOINTS:
□ Alpha team: Describes current status
□ Infrastructure: Verifies systems match description
□ Ops: Confirms all communications received
□ All leads: Understand current Phase progress
□ Confirm: Shift Bravo ready to assume

DAYTIME CONSIDERATIONS:
- Higher user traffic expected during 12:00-18:00 UTC
- Business users may experience API during testing
- Have communication ready if issues detected

QUESTIONS? Contact Ops Lead: [Slack]
EMERGENCY? Call CTO: [Phone]

See you at 12:00 UTC! 🚀
```

---

## 📨 SLACK REMINDER - SHIFT CHARLIE (2 hours before 20:00 UTC = 18:00 UTC)

```
@channel #shift-charlie | Shift Charlie Night Brief - Arriving in 2 hours

🌙 GOOD EVENING SHIFT CHARLIE (20:00-04:00 UTC)

Tonight's Focus: May [X], 2026 - Phase [X] Night Operations

KEY FOCUS FOR TONIGHT:
├─ Incoming status: [Bravo shift handoff]
├─ Night shift objective: [Stable operations vs progress]
├─ Phase progress: Phase [X] [%% complete]
├─ Known night-time risks: [Any items from daytime]
└─ Alert sensitivity: [Heightened due to night skeleton crew]

NIGHT SHIFT MISSION: STABILITY + PROGRESS

Tonight you have fewer people watching, so heightened vigilance is needed.
Your focus: Keep systems stable through the night while continuing Phase work if possible.

YOUR RESPONSIBILITIES:

🏗️  Infrastructure Lead:
   • Receive handoff from Bravo at 19:45 UTC
   • Verify all systems operational and stable
   • Continue Phase [X] if on track: [Tasks]
   • Night shift priority: Stability first, progress second
   Contact CTO if: [Issue type] - don't wait, call immediately

📊 Operations Lead:
   • War room leadership for night shift (8 hours solo)
   • Facilitate handoff at 20:00 UTC (30 min overlap)
   • Team support: Check in with each lead every 2 hours
   • Encourage breaks and hydration
   Emergency: Call CTO anytime, no hesitation

📈 Monitoring Lead:
   • MORE VIGILANT monitoring (fewer eyes overnight)
   • Screenshot every hour (not 5 min, but more frequent than day)
   • Alert immediately on ANY RED indicator
   • Don't ignore "maybe" issues - investigate

🧪 QA Lead:
   • Receive test status from Bravo
   • Run tests in background (don't stress resources)
   • Document results for day team review
   • Alert if regressions appear

🔒 Security Lead:
   • Overnight access logs review (more risk of unauthorized access)
   • Stay alert for suspicious patterns
   • Night shift often target for attacks
   • Report any concerns immediately

📋 Project Manager:
   • Facilitate handoff at 20:00 UTC
   • Night shift check-in at 00:00 UTC
   • Morning handoff prep at 03:30 UTC
   • Prepare for Alpha team morning standup

NIGHT SHIFT SPECIAL NOTES:

You're the guardian tonight. Everything depends on you staying alert.

Movement Breaks: Take one every 60 min (stand, walk, stretch)
Hydration: Water bottle full, drink continuously
Morale: Stay positive, team is counting on you
Sleep after: Get your 5+ hours after shift

If issues arise:
  Small: Fix if possible, document, continue
  Moderate: Investigate, escalate if >15 min
  Critical: Call CTO immediately, don't wait

TEAM SUPPORT:
Operations Lead will check in with each of you periodically
If you're struggling: Tell Ops Lead immediately
Buddy system: Lean on each other

MORNING HANDOFF (Ready at 03:45 UTC):
- Prepare handoff checklist
- Summarize night's work
- Alert Alpha to any ongoing issues
- Be thorough (Alpha team arriving tired)

Questions? Message Ops Lead: [Slack]
Emergency? Call CTO anytime: [Phone]

You've got this. Hold the line through the night. 🌙🚀
```

---

## 📧 GENERIC EMAIL TEMPLATE

```
Subject: 🔔 Shift [ALPHA/BRAVO/CHARLIE] Brief - May [X] (Starts in 2 hours)

Team [SHIFT],

Your shift starts in 2 hours. Here's what you need to know:

PHASE [X] - May [X], 2026
═══════════════════════════

Phase Status: [X]% complete
Primary focus: [What we're doing today]
Success criteria: [What winning looks like]
Yesterday/previous shift status: [Summary]

YOUR TEAM'S FOCUS:

Infrastructure Lead:
  - [Main task 1]
  - [Main task 2]
  - Monitoring: [Key metric]

Operations Lead:
  - [Main responsibility]
  - Status updates: [Times]
  - Escalation: [Trigger point]

Monitoring Lead:
  - Dashboard refresh: [Frequency]
  - Alert threshold: [Level]
  - Report if: [Condition]

QA Lead:
  - Test focus: [What to test]
  - Escalation: [Failure type]

Security Lead:
  - Monitor: [What to watch]
  - Report: [Condition]

Project Manager:
  - Meeting: [Time and purpose]
  - Communication: [What to send]

HANDOFF NOTES FROM LAST SHIFT:
[Key info from previous shift]
- Current metrics: [X]
- Known issues: [X]
- Recommendations: [X]

PRE-SHIFT (Do this before 04:00/12:00/20:00 UTC):
1. Log into systems (verify access)
2. Read incident log from previous shift
3. Check Grafana dashboards
4. Verify environment ready
5. Arrive ready by T-10 min
6. Report "ready" in Slack

SUCCESS TODAY MEANS:
✓ Phase [X] progresses on schedule
✓ All systems remain stable
✓ Zero critical unresolved issues
✓ Team morale maintained
✓ Zero data loss

QUESTIONS BEFORE YOU START?
- Reply to this email
- Ping Ops Lead on Slack
- Emergency? Call CTO

Good luck. See you soon! 🚀
```

---

## 🤖 AUTOMATION IMPLEMENTATION

**To automate these reminders:**

**Option 1: Slack Bot (Recommended)**
```
Use Slack Workflow or bot integration:
- Trigger: Every day at 02:00, 10:00, 18:00 UTC
- Action: Post message to #shift-alpha, #shift-bravo, #shift-charlie
- Template: Choose appropriate template above
- Customize: Fill in [brackets] with today's Phase/focus
```

**Option 2: Cron + Email**
```
Create cron jobs:
0 2 * * * /usr/bin/send-email-reminder.sh alpha  # 02:00 UTC daily
0 10 * * * /usr/bin/send-email-reminder.sh bravo # 10:00 UTC daily
0 18 * * * /usr/bin/send-email-reminder.sh charlie # 18:00 UTC daily

Script fills in templates with current Phase/date
```

**Option 3: Manual (If no automation available)**
```
Project Manager manually copies/sends templates 2 hours before each shift
Approximately 21 messages over deployment period (manageable)
```

---

## 📋 TEMPLATE CUSTOMIZATION GUIDE

**Before each shift, fill in:**

```
[SHIFT] = ALPHA / BRAVO / CHARLIE
[X] = Current date (May [date])
[Phase X] = Current Phase number
[Describe main Phase task] = Specific task for today
[What success looks like today] = Measurable success
[Yesterday's final status] = Summary from previous shift
[Issue type] = Critical issue triggers for CTO call

[Task 1 for today] = Role-specific task
[Task 2 for today] = Role-specific task
[CTO phone] = Contact number
[Slack handle] = Operations Lead Slack name
```

---

**Use these templates for consistent, timely shift notifications.**  
**Team arrives prepared and focused.**  
**No surprises about what they need to do.**

