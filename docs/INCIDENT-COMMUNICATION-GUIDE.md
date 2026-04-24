# Incident Communication & Management Guide

**Purpose**: Standardized communication and escalation procedures for production incidents  
**Audience**: Operations Team, Incident Commanders, On-Call Engineers  
**Date**: April 24, 2026  
**Status**: Production-Ready

---

## Incident Classification & Response Times

### Severity Levels

| Level | Impact | Response Time | Resolution SLA | Examples |
|-------|--------|---------------|-----------------|----------|
| **P0 - Critical** | Complete service outage, data loss | 5 minutes | 30 minutes | Both replicas down, data corruption, security breach |
| **P1 - High** | Major degradation, feature broken | 15 minutes | 2 hours | One replica down, database lag > 1 hour, cert expired |
| **P2 - Medium** | Partial degradation, workaround available | 30 minutes | 4 hours | Performance issue, slow query, memory leak |
| **P3 - Low** | Minor issue, no user impact | 2 hours | 24 hours | Unused service failing, log errors, documentation gap |

### Initial Assessment (First 2 minutes)

```
1. What is the reported impact? (Complete/Partial/None)
2. How many users affected? (All/Some/Internal-only)
3. Are there workarounds? (Yes/No)
4. Is data at risk? (Yes/No)

Based on answers → Assign severity level
```

---

## Communication Channels

### During Incident

| Channel | Use Case | Frequency |
|---------|----------|-----------|
| **#ops-critical** (Slack) | Real-time incident coordination | Every 5-10 min during P0/P1 |
| **PagerDuty** | Alert escalation, on-call rotation | Automatic for P0/P1 |
| **War Room** (Zoom) | Multi-team coordination (if needed) | P0 incidents only |
| **Email** | Status updates to stakeholders | On-demand (per protocol) |
| **GitHub Issue** | Incident tracking & post-mortem | Document throughout |

### Incident Timeline Template

```
[HH:MM] <severity> <title>: <initial observation>
[HH:MM] Root cause identified: <cause>
[HH:MM] Mitigation in progress: <action>
[HH:MM] Status update: <current state>
[HH:MM] RESOLVED: <resolution> (TTR: XX min)
```

---

## P0 Critical Incident Procedure

### Activation (0-2 minutes)

```bash
# 1. Confirm incident is P0
# Questions:
#   - Is production completely unavailable? YES/NO
#   - Are users unable to use service? YES/NO
#   - Is data at risk or lost? YES/NO
#   → If ALL yes, proceed as P0

# 2. Activate war room
# - Post to #ops-critical: "🚨 P0 INCIDENT: <title>"
# - Create GitHub issue: `gh issue create --title "P0: <title>" --label P0,incident`
# - PagerDuty auto-triggered (if monitoring configured)

# 3. Assign roles
#   - Incident Commander: Coordinates response
#   - Technical Lead: Leads diagnosis & fix
#   - Communicator: Updates status every 5 minutes
#   - Note-Taker: Documents timeline

echo "🚨 P0 INCIDENT DECLARED"
echo "War room: #ops-critical"
echo "GitHub: [issue link]"
echo "Incident Commander: [name]"
```

### Diagnosis Phase (2-10 minutes)

```bash
# Run in parallel (don't wait sequentially):
(bash scripts/ops/verify-deployment-state.sh) &
(for r in 192.168.168.31 192.168.168.42; do ssh akushnir@$r 'docker ps'; done) &
(ssh akushnir@192.168.168.31 'docker-compose logs --tail 100') &
wait

# Determine root cause
# 1. All replicas down? → Network/power issue
# 2. One replica down? → Failover should handle (not P0 usually)
# 3. Database issue? → Check replication status
# 4. Certificate issue? → Check #1694 status
# 5. Memory/resource? → Check `docker stats`
```

### Mitigation (10-30 minutes)

```bash
# Parallel actions (assign to different people):

# Action 1: Stop writes (if data at risk)
# - Disable API endpoints
# - Redirect to read-only mode
# - Notify users

# Action 2: Begin recovery (lead technical team)
# - Restart services: docker-compose restart
# - Failover if needed: docs/FAILOVER-RUNBOOK-SIMPLIFIED.md
# - Restore from backup if data loss suspected

# Action 3: Continuous monitoring
# - Health checks every 30 seconds
# - Status updates every 5 minutes
# - Log all actions in GitHub issue

# Action 4: Escalation (if not resolved by 30 min)
# - Contact infrastructure lead
# - Prepare for emergency meeting
```

### Resolution (30+ minutes)

```bash
# Step 1: Verify recovery
bash scripts/ops/verify-production-readiness.sh

# Step 2: Run validation suite
docker-compose ps              # All services running?
curl -I http://192.168.168.31:8080/health  # Health OK?
curl -I http://192.168.168.42:8080/health  # Both replicas OK?

# Step 3: Close incident
# - Post resolution summary to #ops-critical
# - Update GitHub issue with resolution details
# - Begin post-mortem (within 24 hours)
```

### P0 Communication Template

```
🚨 [HH:MM UTC] P0 INCIDENT: Complete production outage
Severity: CRITICAL
Impact: All users unable to access IDE
Status: INVESTIGATING

🔍 [HH:MM UTC] Root cause identified: Both replicas network unreachable
🛠️ [HH:MM UTC] MITIGATION IN PROGRESS: Restarting Docker daemons on both replicas
⏳ [HH:MM UTC] Services coming online, validating health checks
✅ [HH:MM UTC] RESOLVED at HH:MM UTC (Duration: XX minutes)

Recovery Summary:
- Network connectivity restored
- Docker daemon restarted on both replicas
- All services recovered
- Database replication verified
- No data loss

Impact: ~XX minutes downtime
Next Steps: Post-mortem scheduled for [time]
```

---

## P1 High Priority Incident

### Activation (0-5 minutes)

```bash
# Similar to P0 but less urgent
echo "🔴 P1 INCIDENT: <title>"
# Post to #ops-critical
# PagerDuty triggered (if configured)
```

### Expected Resolution Time: 2 hours

| Time | Activity |
|------|----------|
| 0-5 min | Assess, classify, assign resources |
| 5-20 min | Diagnose root cause |
| 20-45 min | Implement fix/workaround |
| 45-90 min | Validation and monitoring |
| 90+ min | Escalate if not resolved |

---

## P2 Medium Priority Incident

### Activation (0-30 minutes)

```bash
# Post to #ops (not #ops-critical)
# PagerDuty optional (during business hours)
```

### Expected Resolution Time: 4 hours

- No page escalation required
- Monitor during business hours
- Debug after hours if possible, or defer

---

## P3 Low Priority Incident

### Handling

```bash
# Post to #infrastructure or GitHub issue
# No page escalation
# Address during regular business hours
```

---

## Status Update Cadence

| Incident Level | Frequency | Channel |
|---|---|---|
| **P0** | Every 5 minutes | #ops-critical + email |
| **P1** | Every 15 minutes | #ops-critical |
| **P2** | Every 30 minutes or upon significant change | #ops |
| **P3** | At resolution | #infrastructure |

### Status Update Template

```
⏰ [HH:MM UTC] STATUS UPDATE #X

Current Status: [INVESTIGATING / MITIGATING / MONITORING]
Latest Action: [What was just done]
Next Action: [What will be done next]
Estimated Time to Resolution: [XX minutes / Not available]
Impact: [Current user-facing impact]
```

---

## Post-Incident Review (Within 24 hours)

### Timeline Documentation

```markdown
## Incident Timeline
[HH:MM] User report: Service unavailable
[HH:MM] Confirmed: Both replicas unreachable
[HH:MM] Cause identified: Network switch failure
[HH:MM] Network team engaged
[HH:MM] Network restored
[HH:MM] Services recovered
[HH:MM] All health checks passing

**Total Duration**: XX minutes
**Detection to Resolution**: XX minutes
```

### Root Cause Analysis

```markdown
### Root Cause
[Describe the underlying cause, not just symptoms]

### Contributing Factors
1. [Factor 1]
2. [Factor 2]
3. [Factor 3]

### Why Detection Was Slow?
[If applicable]

### Why Response Was Slow?
[If applicable]
```

### Action Items

```markdown
## Preventive Actions (To prevent recurrence)
- [ ] Implement [specific improvement]
- [ ] Add monitoring for [specific metric]
- [ ] Update [specific procedure]

## Detective Actions (To catch faster)
- [ ] Add alert for [specific threshold]
- [ ] Improve [specific dashboard]
- [ ] Add [specific health check]

## Responsive Actions (To resolve faster)
- [ ] Document [specific procedure]
- [ ] Create automation for [specific task]
- [ ] Train [person] on [topic]

## Owner & Due Date
| Action | Owner | Due Date |
|---|---|---|
| Implement network redundancy | @infra-lead | 2026-05-24 |
| Add network segment monitoring | @ops-team | 2026-04-30 |
```

---

## Escalation Decision Tree

```
                    Incident Reported
                           |
                           ↓
                   [Assess Severity]
                           |
                ┌──────────┼──────────┐
                |          |          |
              P0           P1         P2/P3
                |          |          |
                ↓          ↓          ↓
         [Page On-Call] [Notify Team] [Log Issue]
                |          |          |
                ↓          ↓          ↓
           [War Room]  [Investigate] [Address in cycle]
                |          |          |
                ↓          ↓          ↓
          [Declare IC] [Assign IC]   [No IC needed]
                |          |
                ↓          ↓
         [30 min timer] [2 hr timer]
                |          |
          Resolved?    Resolved?
         /        \    /        \
       YES   [Escalate]  YES  [Escalate]
```

---

## Escalation Contacts

### On-Call Rotation

**Current On-Call**: [Check PagerDuty]

**Levels**:
1. **Level 1 (On-Call)**: akushnir (primary)
2. **Level 2 (Senior)**: [Team Lead]
3. **Level 3 (Exec)**: [Director]

### External Escalations

| Issue Type | Contact | Response Time |
|---|---|---|
| **Network** | Network Ops: [contact] | 30 minutes |
| **Hardware** | Infrastructure: [contact] | 1 hour |
| **Security Breach** | Security Team: [contact] | 15 minutes |
| **Vendor Issue** | Vendor Support: [ticket] | Per SLA |

---

## Communication Templates

### Initial Alert

```
🚨 INCIDENT ALERT

Service: Kushnir.cloud Production Cluster
Severity: P0 / P1 / P2
Issue: [Brief description]
Started: [HH:MM UTC]
Status: INVESTIGATING

Current Action: [What we're doing]
Updates: Every 5/15/30 minutes to #ops-critical

GitHub Issue: [link]
```

### Status Update

```
📊 STATUS UPDATE [XX minutes since incident]

Status: INVESTIGATING / MITIGATING / MONITORING
Latest: [What changed]
Impact: [Current impact]
ETA: [Estimated resolution time]
Next Update: [HH:MM UTC]
```

### Resolution

```
✅ INCIDENT RESOLVED

Resolved at: [HH:MM UTC]
Duration: [XX minutes]
Root Cause: [One sentence]
Resolution: [What was done]

Post-mortem scheduled: [date/time]
GitHub issue: [remains open for documentation]
```

---

## Tools & Commands Reference

### Quick Status Check

```bash
# One-liner health check
for r in 192.168.168.31 192.168.168.42; do echo "=== $r ==="; ssh akushnir@$r 'docker ps -q | wc -l' 2>&1; done
```

### Alert All Teams

```bash
# Post urgent Slack message
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"🚨 P0 INCIDENT: [description]\nSlack: #ops-critical\nGitHub: [issue]"}' \
  $SLACK_WEBHOOK_URL
```

### Create Incident Issue

```bash
gh issue create \
  --title "INCIDENT: [title]" \
  --body "Reported at: [time]\nSeverity: P0/P1\nImpact: [description]" \
  --label "incident,P0" \
  --repo kushin77/code-server
```

---

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Status**: ✅ Production-Ready  
**Related**: [Advanced Troubleshooting](ADVANCED-TROUBLESHOOTING-GUIDE.md), [Failover Runbook](FAILOVER-RUNBOOK-SIMPLIFIED.md)
