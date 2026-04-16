# PHASE 21: ON-CALL PROGRAM & PROCEDURES
# 24/7 Operations Rotation
# Date: April 14, 2026

---

## ON-CALL RESPONSIBILITIES

### On-Call Duty
- **Duration**: 7 consecutive days (Monday 00:00 UTC → Sunday 23:59 UTC)
- **Response SLA**: 5 minutes (max) from alert to acknowledgement
- **Availability**: Must be reachable 24/7 (phone, Slack, email)
- **Tools**: PagerDuty (primary), Slack (secondary), Phone (emergency)

### Critical Activities
1. **Alert Response**: Acknowledge within 5 minutes
2. **Incident Triage**: Determine severity (P1: page, P2: Slack, P3: ticket)
3. **Investigation**: Use runbooks to diagnose issue
4. **Resolution**: Follow procedures to fix or escalate
5. **Communication**: Update #incidents channel continuously
6. **Post-mortems**: Participate in incident review (within 24h)

---

## ON-CALL ROTATION SCHEDULE

### Week 1 (April 21-27, 2026)
| Starting | On-Call Engineer | Backup | Notes |
|----------|------------------|--------|-------|
| Apr 21 | TBD (Engineer 1) | TBD (Engineer 2) | Kickoff week |
| Apr 22 | TBD (Engineer 2) | TBD (Engineer 1) | |
| ...continuing weekly | | | |

### Rotation Rules
- Each engineer: 1 week on-call per quarter
- Backup: Must be same team, available 24/7
- Handoff meeting: Every Monday 09:00 UTC (30 min)
- No back-to-back weeks (minimum 2 weeks rest between rotations)

### Handoff Procedure
```
Monday 09:00 UTC: Outgoing on-call → Incoming on-call
1. Review last week's incidents
2. Update runbooks if lessons learned
3. Test alert acknowledgement
4. Discuss any known issues
5. Confirm backup contact info
Duration: 30 minutes
```

---

## ALERT ESCALATION PATH

### P1 Critical (Page Immediately)
**Condition**: Database failover, 5xx errors, complete outage
**Response**: 5 min max
**Action**: Page on-call engineer via PagerDuty
**Escalation**: If no response in 15 min, page backup engineer
**Expected Resolution**: 30 minutes

**Alert Examples**:
- DatabasePrimaryDown
- DatabaseFailoverDetected
- OutageDetected (error rate > 10%)

### P2 High (Slack Notification)
**Condition**: High latency, memory critical, partial outage
**Response**: 15 min max
**Action**: Post in #incidents Slack channel
**Escalation**: If unresolved after 1 hour, page manager
**Expected Resolution**: 2 hours

**Alert Examples**:
- LatencySpike
- ErrorRateHigh
- RedisMemoryCritical

### P3 Medium (Create Ticket)
**Condition**: Certificate expiry, disk space, non-critical warnings
**Response**: Within business hours (9-17 USA East)
**Action**: Create GitHub issue, assign to queue
**Escalation**: None (handle during business hours)
**Expected Resolution**: 1 week

**Alert Examples**:
- CertificateNearExpiry
- DiskSpaceLow

---

## COMMUNICATION PROTOCOL

### During Incident (Real-Time)
**Slack Channel**: #incidents (mandatory)

**Updates Every 5 Minutes**:
1. **Initial**: "🔴 P1 incident detected: [description]"
2. **Investigation**: "Status: Investigating [specific area]"
3. **Found Issue**: "Root cause: [X] - Implementing fix"
4. **Resolution**: "✅ Issue resolved. RTO: X minutes. Details in thread"

**Slack Mention Templates**:
- P1: `@on-call-engineer` (or `@here` if very severe)
- P2: `#software-engineering` (team awareness)
- P3: Just comment in issue

### Post-Incident
**Within 24 hours**:
1. Create draft post-mortem in #incidents thread
2. Schedule retrospective call (30 min)
3. Assign action items for prevention
4. Update runbooks with any learnings

**Post-Mortem Format**:
```markdown
## Incident: [Title]
**Date**: YYYY-MM-DD HH:MM UTC
**Duration**: X minutes
**Impact**: [Users affected, features down]
**Root Cause**: [Why it happened]
**Resolution**: [How we fixed it]
**Prevention**: [What we'll do to prevent]
**Assigned**: [Owner of each prevention action]
```

---

## ON-CALL TOOLS & ACCESS

### PagerDuty
- **URL**: https://your-company.pagerduty.com
- **Mobile App**: PagerDuty (iOS/Android)
- **Action**: Acknowledge within 5 min of alert

### Slack
- **Channel**: #incidents (all alerts)
- **Status**: React with 👀 when investigating, ✅ when resolved
- **Thread**: Keep all discussion in incident thread

### SSH Access
```bash
# Connect to production server
ssh ops@192.168.168.31

# Docker commands
docker ps
docker logs <container>
docker exec <container> <command>
```

### Monitoring Dashboards
- **Prometheus**: http://localhost:9090 (metrics)
- **Grafana**: http://localhost:3000 (dashboards)
- **AlertManager**: http://localhost:9093 (alerts)

### GitHub Issues
- **Create incident issues**: Labels: `incident`, `p1`/`p2`/`p3`
- **Follow**: On-call engineer responsible for creating issue

---

## COMPENSATION & BENEFITS

### On-Call Compensation
- **Per week**: 1 day paid time off (PTO) for on-call week
- **Emergency call-outs** (any P1 incident):
  - Time worked counts as 1.5x hours (time-and-a-half)
  - If incident resolves late (> 22:00 local), next day off
- **Definition of "on-call"**: On the PagerDuty rotation, available 24/7

### Recovery Time
- **After incident resolution**: If incident resolved after 22:00 local time, takes next 2 hours off
- **Sleep disruption**: If incident wakes you at night, can take comp time next day
- **Rest between rotations**: Minimum 2 weeks between on-call assignments

### Example Compensation
```
Week of April 21: On call, 2 incidents
- Week 1 P1 incident: 1 hour work -> 1.5 hours comp time
- Week 1 P2 incident: 30 min work -> 45 min comp time
- Total: 1 day PTO + 2.25 hours comp time
```

---

## COMMON SCENARIOS & RESPONSE FLOWCHART

### Scenario 1: Database Alert at 3 AM
```
1. Wake up → PagerDuty notification (phone alarm)
2. Acknowledge within 5 min in PagerDuty app
3. SSH to server: ssh ops@192.168.168.31
4. Check status: docker logs postgres-ha-primary
5. Slack #incidents: "Investigating database issue - [time]"
6. If clear fix: Apply fix (see runbook)
7. If unclear: Page backup engineer after 10 minutes
8. Update #incidents every 5 minutes
9. Once resolved: Document in post-mortem
10. Resume sleep (if incident < 1 hour duration)
```

### Scenario 2: Latency Spike at 6 AM
```
1. Wake up → Slack notification (less urgent)
2. Read alert in Slack #incidents (no hard deadline)
3. Start investigation at comfortable pace (15-30 min window)
4. Check Grafana dashboard for affected endpoints
5. Run slow query analysis (see runbook)
6. Update #incidents with findings
7. Implement fix or scale
8. Monitor for 30 minutes to confirm resolution
9. Close loop in Slack
10. Continue morning routine (non-critical)
```

### Scenario 3: Disk Space Low (10 AM)
```
1. See GitHub issue notification (no rush)
2. Acknowledge same day (no SLA)
3. Schedule cleanup during business hours
4. Run docker system prune, remove old logs
5. Update issue and close
6. If needs permanent fix, create tech debt issue
```

---

## TRAINING CHECKLIST

**Before going on-call, ensure**:
- [ ] Read INCIDENT-RUNBOOKS.md (all sections)
- [ ] Read this document (ON-CALL-PROGRAM.md)
- [ ] SSH access confirmed (test connection)
- [ ] PagerDuty app installed + notifications enabled
- [ ] Slack notifications enabled (#incidents)
- [ ] Grafana dashboard familiarized
- [ ] Alert list reviewed (know what triggers what)
- [ ] Backup engineer contact info saved
- [ ] Mock incident walkthrough (practice runbook)
- [ ] Questions answered by previous on-call (meet 1:1)

---

## FREQUENTLY ASKED QUESTIONS

### Q: What if I go on vacation during my on-call week?
**A**: Swap with another engineer 2+ weeks in advance. Confirm with manager and PagerDuty.

### Q: What if I get paged at 2 AM and can't sleep after?
**A**: You can take the next morning off (e.g., sleep 5 AM-12 PM) without losing comp time.

### Q: What if the fix requires deploying code?
**A**: Check if you can hotfix it yourself (small config change). If code change needed:
1. Run tests locally
2. Get quick approval from on-call buddy
3. Deploy and monitor
4. Document in post-mortem

### Q: What if I don't know how to fix it?
**A**: That's okay! You're not expected to know everything. Options:
1. Follow the runbook exactly (it's written for this)
2. Page your backup engineer for guidance
3. Escalate to manager (no judgment)
4. Ask in #incidents (other engineers may help)

### Q: Do I have to answer calls outside my on-call week?
**A**: No. Only person on PagerDuty gets paged. If you're called outside rotation, refer to current on-call engineer.

### Q: What if multiple incidents happen at once?
**A**: Page backup engineer immediately. You can work together. Communicate clearly about who handles what.

---

## ANNUAL METRICS & REVIEW

### Tracked Metrics
- **MTBF** (Mean Time Between Failures): Target >720 hours
- **MTTR** (Mean Time To Recovery): Target <30 min for P1
- **Alert accuracy**: Target >90% (not false alarms)
- **On-call engineer satisfaction**: Quarterly survey

### Quarterly Review
- Incident trends: Are incidents decreasing?
- Runbook accuracy: Were runbooks helpful?
- On-call feedback: What worked? What didn't?
- Process improvements: How can we improve?

---

## NIGHT MODE & SLEEP CONSIDERATIONS

### Night On-Call (00:00-06:00 Local Time)
- Keep phone within arm's reach
- Set PagerDuty to loudest notification
- Have laptop quick-accessible
- Expect 20-30 min response + investigation
- Expect to return to sleep after brief incidents

### Tips for On-Call Sleep
1. Keep phone brightness low (avoid waking)
2. Wear earplugs + vibration (don't wake roommates)
3. Have water/coffee nearby (for 3 AM incidents)
4. Document fix quickly, sleep again (post-mortem can wait)
5. Check-in with team after morning sleep

---

## SLO & SUCCESS CRITERIA

**On-Call Program Success Metrics**:
- [ ] P1 incidents: 95% acknowledged within 5 minutes
- [ ] P1 incidents: 90% resolved within 30 minutes
- [ ] P2 incidents: 100% acknowledged within 30 minutes
- [ ] Post-mortems: 100% completed within 24 hours
- [ ] Engineer satisfaction: >4/5 stars in quarterly survey
- [ ] Runbook accuracy: >90% follow-through without clarification

---

## NEXT STEPS

1. **Assign first rotation**: Confirm 2 engineers for April 21-27
2. **Schedule kickoff meeting**: Monday April 21, 09:00 UTC
3. **Send alerts to PagerDuty**: Integrate Prometheus → PagerDuty
4. **Slack integration**: Connect #incidents to alerting
5. **First on-call week**: Execute and gather feedback
6. **Weekly reviews**: Every Monday 09:00 UTC (handoff meetings)

---

**On-Call is critical to production reliability. Thank you for your service! 🎖️**
