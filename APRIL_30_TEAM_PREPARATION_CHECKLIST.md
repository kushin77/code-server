# APRIL 30 TEAM PRE-DEPLOYMENT PREPARATION CHECKLIST

**Date:** April 30, 2026  
**Deployment:** May 1, 2026, 09:00 UTC  
**Team Deadline:** 18:00 UTC TODAY  
**Time Available:** ~6 hours for preparation  

---

## ✅ CHECKLIST FOR ALL TEAM MEMBERS

**Estimated Time: 90 minutes total (distributed through day)**

### 1. Email & Role Assignment (5 minutes)
- [ ] Received deployment coordination email from DevOps Lead
- [ ] Read email subject: "🚀 May 1 Deployment - Final Readiness & Team Assignment"
- [ ] Identified your role assignment:
  - [ ] DevOps Lead
  - [ ] On-Call L1
  - [ ] On-Call L2
  - [ ] QA Lead
  - [ ] Operations Manager

### 2. Role-Specific Document Review (30-45 minutes)

**For DevOps Lead:**
- [ ] Read: MAY_1_DEPLOYMENT_DAY_CHECKLIST.md (20 minutes)
- [ ] Read: ROLLBACK_AND_EMERGENCY_PROCEDURES.md (15 minutes)
- [ ] Understand: 5 go/no-go decision points and your decision authority
- [ ] Understand: PostgreSQL replication fix timeline (08:00-08:30 UTC) and critical success criteria

**For On-Call L1:**
- [ ] Read: PRODUCTION_ON_CALL_RUNBOOK.md (20 minutes)
- [ ] Read: MAY_1_OPERATIONS_QUICK_REFERENCE.md (10 minutes)
- [ ] Understand: Alert escalation procedures and acknowledgment logging
- [ ] Understand: Update frequency and reporting requirements

**For On-Call L2:**
- [ ] Read: ROLLBACK_AND_EMERGENCY_PROCEDURES.md (25 minutes)
- [ ] Read: PRODUCTION_ON_CALL_RUNBOOK.md (10 minutes)
- [ ] Understand: Escalation criteria and rollback decision tree
- [ ] Understand: Technical troubleshooting and rollback authorization

**For QA Lead:**
- [ ] Read: MAY_1_DEPLOYMENT_DAY_CHECKLIST.md section "09:30 HEALTH CHECK" (10 minutes)
- [ ] Read: BACKUP_DISASTER_RECOVERY_PROCEDURES.md (15 minutes)
- [ ] Prepare: Health check test scripts
- [ ] Prepare: Database validation queries

**For Operations Manager:**
- [ ] Read: MAY_1_FINAL_PRE_DEPLOYMENT_READINESS.md (15 minutes)
- [ ] Read: ROLLBACK_AND_EMERGENCY_PROCEDURES.md communication section (10 minutes)
- [ ] Prepare: Stakeholder notification templates
- [ ] Understand: Decision approval process and escalation authority

### 3. System Access Verification (20 minutes)

**All Team Members - Verify Access:**
- [ ] Can SSH to primary (192.168.168.31)
  - Command: `ssh akushnir@192.168.168.31 "echo OK"`
  - Expected: "OK" returned
- [ ] Can SSH to replica (192.168.168.42)
  - Command: `ssh akushnir@192.168.168.42 "echo OK"`
  - Expected: "OK" returned
- [ ] Can access Prometheus dashboard (http://192.168.168.31:9090)
- [ ] Can access Grafana dashboard (http://192.168.168.31:3000)
- [ ] Can access AlertManager (http://192.168.168.31:9093)
- [ ] Slack notifications working (test by sending yourself a message)
- [ ] Email notifications working (verify you received deployment email)

**Issues Found:**
- [ ] None - all systems accessible
- [ ] SSH issues: Contact L2 engineer for key/access troubleshooting
- [ ] Dashboard access issues: Check firewall/VPN connection
- [ ] Notifications: Test Slack/email settings

**Resolution if Issues:** Contact DevOps Lead immediately - do not wait for 18:00 UTC deadline

### 4. Deployment Timeline Understanding (10 minutes)

- [ ] Know deployment starts: May 1, 06:00 UTC (team assembly)
- [ ] Know deployment execution: May 1, 09:00 UTC (main deployment)
- [ ] Know critical path item: PostgreSQL replication fix 08:00-08:30 UTC on replica
- [ ] Know health checks: 09:30 UTC (confirm deployment successful)
- [ ] Know monitoring window: 10:00 UTC - May 2, 10:00 UTC (24-hour surveillance)

**Your Specific Arrival Time:**
- [ ] DevOps Lead: 05:45 UTC (earliest, stay until 10:30 UTC)
- [ ] On-Call L1: 05:45 UTC (full day, 10:00+ standby)
- [ ] On-Call L2: 06:00 UTC (standby, escalate if needed)
- [ ] QA Lead: 08:30 UTC (health checks at 09:30 UTC)
- [ ] Operations Manager: 06:00 UTC (communications, 10:00+ standby)

### 5. Print & Prepare Desk Materials (10 minutes)

**DevOps Lead - Print:**
- [ ] MAY_1_DEPLOYMENT_DAY_CHECKLIST.md (for desk/monitor reference)
- [ ] ROLLBACK_AND_EMERGENCY_PROCEDURES.md (emergency procedures backup)
- [ ] Escalation contacts list (post-it note on monitor)

**On-Call L1 - Print:**
- [ ] MAY_1_OPERATIONS_QUICK_REFERENCE.md (desk reference card)
- [ ] Alert escalation procedures
- [ ] Escalation contacts list

**On-Call L2 - Print:**
- [ ] ROLLBACK_AND_EMERGENCY_PROCEDURES.md decision tree section
- [ ] Rollback authorization criteria
- [ ] Escalation contacts list

**QA Lead - Print:**
- [ ] Health check procedures from MAY_1_DEPLOYMENT_DAY_CHECKLIST.md
- [ ] Test script template
- [ ] Expected success criteria

**Operations Manager - Print:**
- [ ] Communication template examples
- [ ] Stakeholder update schedule
- [ ] Decision approval process

### 6. Escalation Contacts Verification (5 minutes)

- [ ] Have DevOps Lead contact info (phone + Slack handle)
- [ ] Have On-Call L1 contact info (phone + Slack handle)
- [ ] Have On-Call L2 contact info (phone + Slack handle)
- [ ] Have Operations Manager contact info (phone + Slack handle)
- [ ] Know Slack channels: #deployment, #alerts, #critical-incidents
- [ ] Understand when to use each channel (see MAY_1_TEAM_COORDINATION_PACKAGE.md)

### 7. Pre-Deployment Confirmation in Slack (5 minutes)

- [ ] Join Slack channel #deployment
- [ ] Verify announcement from DevOps Lead about team distribution
- [ ] Post message: "✅ [Your Name] - [Your Role] - Prepared and ready for May 1 deployment"
- [ ] React to DevOps Lead's confirmation message with 🚀 emoji

---

## 📋 ROLE-SPECIFIC PRE-DEPLOYMENT CHECKLIST

### DevOps Lead ONLY

**Understanding & Knowledge (by 18:00 UTC):**
- [ ] Understand all 5 go/no-go decision points
  - 06:00 - Can all team members access all systems?
  - 06:15 - Do all 7 critical items pass validation?
  - 08:30 - PostgreSQL replication ACTIVE with < 5s lag?
  - 08:45 - All systems ready and team consensus GO?
  - 09:25 - Deployment complete without critical errors?
- [ ] Understand PostgreSQL replication fix (08:00-08:30 UTC MUST SUCCEED)
- [ ] Know exact commands for replication verification
- [ ] Know rollback decision criteria and authorization levels
- [ ] Have tested all communication channels (Slack, phone, email)

**Equipment & Setup (May 1, 05:45 UTC):**
- [ ] Primary laptop with SSH keys tested
- [ ] Monitor/display setup for dashboards
- [ ] Phone with Slack notification sound enabled
- [ ] Conference line dial-in number if applicable
- [ ] Master checklist printed and at desk
- [ ] Escalation contacts posted at desk

**Responsibility Acknowledgment:**
- [ ] Understand you own deployment success/failure decisions
- [ ] Understand you control the 5 go/no-go gates
- [ ] Understand you lead the critical PostgreSQL replication fix
- [ ] Understand you coordinate all team communication
- [ ] Confirm: Ready to own this responsibility ✅

---

### On-Call L1 ONLY

**Understanding & Knowledge (by 18:00 UTC):**
- [ ] Understand alert acknowledgment logging requirement
- [ ] Know escalation criteria (when to call L2)
- [ ] Know critical alerts that need immediate L2 notification
- [ ] Know how to access AlertManager and acknowledge alerts
- [ ] Understand reporting frequency to DevOps Lead (every 10 minutes)
- [ ] Know how to read Prometheus dashboard and identify patterns

**Equipment & Setup (May 1, 05:45 UTC):**
- [ ] Primary laptop with dashboard access
- [ ] Multiple monitor setup if available (one for Prometheus, one for Grafana)
- [ ] AlertManager dashboard open and monitoring
- [ ] Alert acknowledgment spreadsheet open and ready
- [ ] Phone with Slack notifications enabled
- [ ] Quick reference card at desk
- [ ] Escalation contacts visible

**Responsibility Acknowledgment:**
- [ ] Understand you are the first line of alert monitoring
- [ ] Understand you don't auto-resolve alerts - you acknowledge and log
- [ ] Understand you must report patterns every 10 minutes
- [ ] Understand you must escalate immediately if critical alert won't quiet
- [ ] Confirm: Ready to monitor dashboards for 24+ hours ✅

---

### On-Call L2 ONLY

**Understanding & Knowledge (by 18:00 UTC):**
- [ ] Understand all rollback options and execution times
- [ ] Know quick rollback procedure (< 10 min)
- [ ] Know full recovery procedure (45-90 min)
- [ ] Know partial/single-component rollback
- [ ] Know failover procedure (promote replica if primary fails)
- [ ] Understand decision criteria for each rollback type
- [ ] Know when to authorize vs escalate to manager/VP

**Equipment & Setup (May 1, 06:00 UTC):**
- [ ] Primary laptop with full SSH/Docker access
- [ ] Database admin access verified working
- [ ] Backup recovery scripts accessible and tested
- [ ] Recovery documentation nearby or in second monitor
- [ ] Phone for escalation calls
- [ ] Slack with #critical-incidents channel open

**Responsibility Acknowledgment:**
- [ ] Understand you are technical decision-maker if L1 escalates
- [ ] Understand you authorize rollback (< 10 min)
- [ ] Understand you make technical recommendations to manager for > 10 min rollback
- [ ] Understand you lead any crisis troubleshooting
- [ ] Confirm: Ready to troubleshoot and potentially rollback ✅

---

### QA Lead ONLY

**Understanding & Knowledge (by 18:00 UTC):**
- [ ] Know exact health check procedures (from MAY_1_DEPLOYMENT_DAY_CHECKLIST.md)
- [ ] Know API endpoints to test and expected responses
- [ ] Know database health check queries to run
- [ ] Know Redis validation commands
- [ ] Know backup system validation procedures
- [ ] Know what constitutes "successful deployment" vs "needs rollback"

**Test Script Preparation:**
- [ ] API health endpoint test: `curl http://localhost:8000/health`
- [ ] Database connectivity: `SELECT 1;` via psql
- [ ] Redis check: `PING` via redis-cli
- [ ] Monitoring dashboard: Prometheus/Grafana visual inspection
- [ ] Backup automation: Recent backup file timestamps

**Equipment & Setup (May 1, 08:30 UTC):**
- [ ] Primary laptop with test scripts ready
- [ ] psql client configured for database connections
- [ ] redis-cli installed and ready
- [ ] curl command ready (or Postman if preferred)
- [ ] Test results template ready
- [ ] Phone for reporting results to DevOps Lead

**Responsibility Acknowledgment:**
- [ ] Understand you validate deployment success at 09:30 UTC
- [ ] Understand you must be thorough - incomplete validation could miss issues
- [ ] Understand your results determine GO or NO-GO for monitoring phase
- [ ] Confirm: Ready to execute comprehensive health checks ✅

---

### Operations Manager ONLY

**Understanding & Knowledge (by 18:00 UTC):**
- [ ] Know who your stakeholders are (execs, customers, etc.)
- [ ] Know escalation approval process
- [ ] Know what issues require executive notification
- [ ] Know status page management (if applicable)
- [ ] Know communication frequency (team every 15 min, stakeholders every 30 min)
- [ ] Know how to handle "bad news" communication with grace

**Communication Template Preparation:**
- [ ] Draft: "Deployment In Progress" status
- [ ] Draft: "Deployment Successful" status
- [ ] Draft: "Deployment Delayed" status
- [ ] Draft: "Deployment Rolling Back" status
- [ ] Draft: "Deployment Complete" final status
- [ ] Understand post-deployment retrospective responsibility

**Equipment & Setup (May 1, 06:00 UTC):**
- [ ] Primary laptop with email/status page access
- [ ] Communication templates open in editor
- [ ] Stakeholder contact list visible
- [ ] Phone for escalation approval calls
- [ ] Slack for team coordination
- [ ] Calendar blocked for entire deployment + 2 hours

**Responsibility Acknowledgment:**
- [ ] Understand you own stakeholder communication (not tech details)
- [ ] Understand you are bridge between technical team and executives
- [ ] Understand you manage escalation approvals and decisions
- [ ] Understand you lead post-deployment retrospective May 2
- [ ] Confirm: Ready to manage communications and escalations ✅

---

## 🎯 CONFIRMATION BY 18:00 UTC

Once you've completed all applicable sections above, **confirm in Slack #deployment:**

```
✅ [Your Name] - [Your Role]
- Document review: COMPLETE
- System access: VERIFIED
- Equipment setup: READY
- Escalation contacts: CONFIRMED
- Ready for May 1 deployment: YES
```

---

## 🚨 IF YOU CANNOT COMPLETE BY 18:00 UTC

**Contact DevOps Lead immediately if:**
- You don't have system access → L2 needs to fix today
- You can't read documents → They need to be resent or shared
- You have scheduling conflict → Need to find backup person
- You don't understand your role → Need role briefing call
- You're not available for your scheduled time → Need immediate escalation

**DO NOT PROCEED to May 1 with incomplete preparation**

---

## 📞 SUPPORT

**Questions about your role?**
- Reply to deployment email or ask in #deployment Slack

**Questions about procedures?**
- See MAY_1_DEPLOYMENT_DAY_CHECKLIST.md or relevant role document

**Technical issues?**
- Contact On-Call L2 engineer for immediate troubleshooting

**Can't complete by 18:00 UTC?**
- Contact DevOps Lead immediately - don't wait

---

**Status: READY FOR TEAM COMPLETION**

Estimated time to complete: 90-120 minutes distributed throughout April 30  
Deadline: 18:00 UTC today  
Next milestone: Team assembly May 1, 05:45 UTC  

✅ This checklist ensures you and your team are ready to execute flawlessly on May 1.

