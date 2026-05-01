# Operations SOP Checklist - Daily & Weekly Procedures

**Document**: Standard Operating Procedures Checklist  
**Version**: Phase 10  
**Date**: April 30, 2026  
**Audience**: Daily Operations Team

---

## Daily Morning Checklist (10 minutes)

```
DATE: ________________  SHIFT: ________________  OPERATOR: ________________

☐ 1. SSH Access Verification (2 min)
    ☐ Primary: ssh akushnir@192.168.168.31
        Result: [ PASS / FAIL ]
    ☐ Replica: ssh akushnir@192.168.168.42
        Result: [ PASS / FAIL ]
    ☐ Virtual IP: ssh akushnir@192.168.168.50
        Result: [ PASS / FAIL ]

☐ 2. Infrastructure Validation (3 min)
    Command: cd /home/akushnir/code-server && bash scripts/ci/validate-pre-apply.sh
    Expected Result: "All 14 checks PASS"
    Actual Result: [ PASS / FAIL / PARTIAL ]
    Notes: ________________________________________________

☐ 3. Container Health Check (2 min)
    Command: docker ps | grep -i unhealthy
    Expected: No output (0 unhealthy containers)
    Actual Count: ________
    Result: [ PASS / FAIL ]

☐ 4. Disk Space Check (1 min)
    Command: df -h /home | tail -1
    Expected: Usage <70%
    Actual: ________%
    Result: [ PASS / FAIL ]

☐ 5. Recent Alerts Review (2 min)
    Command: tail -20 /tmp/code-server-remediation.log
    Errors Found: [ YES / NO ]
    If YES, describe: ________________________________________________

MORNING STATUS: [ ✓ READY / ⚠ CAUTION / ✗ ISSUES DETECTED ]
If issues: Follow troubleshooting guide or escalate to Level 2 support
```

---

## Daily Pre-Deployment Checklist (15 minutes)

```
DEPLOYMENT: ________________  DATE: ________________  APPROVER: ________________

☐ PHASE 1: Pre-Deployment Validation (5 min)
    ☐ All morning checks passed
        [ YES / NO ]
    ☐ No uncommitted git changes
        Command: git status --porcelain
        Result: [ EMPTY / HAS CHANGES ]
    ☐ Run validation script
        Command: bash scripts/ci/validate-pre-apply.sh
        Result: [ ALL PASS / SOME FAIL ]
    ☐ Backup created
        Command: git add -A && git commit -m "backup: before deployment"
        Result: [ SUCCESS / FAILED ]

☐ PHASE 2: Review Changes (5 min)
    ☐ Terraform plan reviewed
        Command: cd terraform/environments/private && terraform plan
        Changes: _________________________________________
        Risks: ⚠️ [LOW / MEDIUM / HIGH]
    ☐ Team approval obtained
        Approver: ________________  Time: ________________
    ☐ Rollback plan documented
        Plan: _________________________________________

☐ PHASE 3: Execute Deployment (5 min)
    ☐ Terraform apply executed
        Command: cd terraform/environments/private && terraform apply
        Result: [ SUCCESS / FAILED ]
        Errors (if any): ________________________________________________
    ☐ Post-deployment validation
        Command: bash scripts/ci/validate-pre-apply.sh
        Result: [ ALL PASS / SOME FAIL ]
    ☐ SLO metrics checked
        Command: ./scripts/ops/track-slo-metrics.sh
        Availability: ________%  Deployment: ________%
        Drift-Free: ________%    Health: ________%

DEPLOYMENT STATUS: [ ✓ SUCCESS / ⚠ PARTIAL SUCCESS / ✗ FAILED ]
If failed: Contact escalation Level 2/3
If successful: Monitor for 30 minutes and complete evening review

Time Spent: _________  Completed By: ________________  Time: ________________
```

---

## Daily After-Deployment Monitoring (5 minutes)

```
DEPLOYMENT ID: ________________  START TIME: ________________

☐ Monitor for 30 Minutes
    ☐ T+5 min: Check remediation log
        Command: tail -10 /tmp/code-server-remediation.log
        Status: [ CLEAN / HAS WARNINGS / HAS ERRORS ]
        
    ☐ T+15 min: Verify container health
        Command: docker ps | wc -l
        Expected: ~100 containers (50 per host)
        Actual: _________
        Unhealthy: [ NONE / SOME ]
        
    ☐ T+30 min: Dashboard verification
        URL: http://localhost:3000/d/code-server-ops
        Panels Status: [ ALL GREEN / SOME YELLOW / HAS RED ]
        Notes: ________________________________________________

☐ Final Verification
    ☐ SLO metrics normal
    ☐ No ERROR alerts in log
    ☐ All dashboards green

MONITORING COMPLETE: [ ✓ PASS / ⚠ MINOR ISSUES / ✗ CRITICAL ISSUES ]
If issues: Document and escalate as needed
```

---

## Daily Evening Checklist (10 minutes)

```
DATE: ________________  TIME: ________________  OPERATOR: ________________

☐ 1. Day Summary (2 min)
    Deployments today: _________
    Issues encountered: [ NONE / MINOR / CRITICAL ]
    If issues, describe: ________________________________________________

☐ 2. Alert Log Review (3 min)
    Command: grep -E "ERROR\|WARNING" /tmp/code-server-remediation.log | tail -20
    ERROR count: _________
    WARNING count: _________
    Action items: ________________________________________________

☐ 3. Resource Usage (2 min)
    Disk usage: ________%  (target <70%)
    CPU average: ________%  (target <50%)
    Memory usage: ________%  (target <80%)
    Result: [ NORMAL / ELEVATED / CRITICAL ]

☐ 4. Handoff Notes (3 min)
    For next shift: ________________________________________________
    ____________________________________________________________
    ____________________________________________________________

EVENING STATUS: [ ✓ NORMAL / ⚠ WATCH OVERNIGHT / ✗ ESCALATE ]
If escalation needed: Contact on-call senior SRE
```

---

## Weekly Review Checklist (Friday, 30 minutes)

```
WEEK OF: ________________  REVIEWER: ________________  DATE: ________________

☐ METRICS REVIEW (10 min)
    ☐ SLO compliance
        Command: ./scripts/ops/track-slo-metrics.sh
        Availability: ________%  Target: 99%  [ PASS / FAIL ]
        Deployment: ________%   Target: 95%   [ PASS / FAIL ]
        Drift-Free: ________%   Target: 100%  [ PASS / FAIL ]
        Health: ________%        Target: 98%   [ PASS / FAIL ]
    
    ☐ Remediation frequency
        Command: grep "SUCCESS" /tmp/code-server-remediation.log | wc -l
        Count this week: _________
        Trend: [ INCREASING / STABLE / DECREASING ]

☐ INCIDENT REVIEW (10 min)
    Incidents this week: _________
    ☐ Incident 1: ________________
        Duration: ________  Root cause: _______________________
        Resolution: [ AUTO / MANUAL / ESCALATED ]
    ☐ Incident 2: ________________
        Duration: ________  Root cause: _______________________
        Resolution: [ AUTO / MANUAL / ESCALATED ]

☐ TREND ANALYSIS (5 min)
    ☐ Disk usage trend
        Start of week: ________%  End of week: ________%
        Trend: [ STABLE / GROWING / SHRINKING ]
    
    ☐ Container restart trend
        Frequency: [ INCREASING / STABLE / DECREASING ]
        Most restarted container: _______________________
    
    ☐ Terraform drift
        Incidents: _________
        Cause: _______________________

☐ ADJUSTMENTS (5 min)
    Changes needed:
    ☐ Alert thresholds:
        Current: ___________  Proposed: ___________
        Reason: _________________________________
    
    ☐ Remediation policies:
        Current: ___________  Proposed: ___________
        Reason: _________________________________
    
    ☐ Monitoring intervals:
        Current: ___________  Proposed: ___________
        Reason: _________________________________

WEEKLY REVIEW STATUS: [ ✓ NORMAL / ⚠ CHANGES NEEDED / ✗ ESCALATE ]
If changes proposed, review with team lead before implementing
```

---

## Monthly Operations Review (First Friday, 1 hour)

```
MONTH: ________________  YEAR: ________  REVIEWER: ________________

☐ SECTION 1: Operational Metrics (15 min)
    ☐ Uptime this month: ________%  Target: 99.9%
    ☐ Incidents: _________  Severity: [ CRITICAL / HIGH / MEDIUM / LOW ]
    ☐ MTTR (Mean Time To Repair): _________ minutes
    ☐ Auto-remediation success rate: _________%

☐ SECTION 2: Deployment Activity (15 min)
    ☐ Deployments: _________
    ☐ Successful: _________%
    ☐ Rollbacks: _________
    ☐ Failed deployments: _________
    Causes: ________________________________________________

☐ SECTION 3: Resource Usage (15 min)
    ☐ Peak disk usage: ________%
    ☐ Average CPU: ________%
    ☐ Average memory: ________%
    ☐ Network bandwidth: _________ GB
    Capacity status: [ HEALTHY / WARNING / CRITICAL ]

☐ SECTION 4: Team Feedback (10 min)
    ☐ Documentation adequate? [ YES / NO / NEEDS UPDATE ]
    ☐ Runbooks helpful? [ YES / NO / NEEDS EXPANSION ]
    ☐ Alerts effective? [ YES / NO / TOO MANY / TOO FEW ]
    ☐ Training needs? [ NONE / SOME / SIGNIFICANT ]

☐ SECTION 5: Action Items (5 min)
    Action 1: _________________________________  Owner: _________  Due: _______
    Action 2: _________________________________  Owner: _________  Due: _______
    Action 3: _________________________________  Owner: _________  Due: _______

MONTHLY REVIEW STATUS: [ ✓ HEALTHY / ⚠ NEEDS ATTENTION / ✗ ESCALATE ]
Sign-off: ________________  Date: ________  Time: ________
```

---

## Quarterly Disaster Recovery Drill (15th of every quarter, 2 hours)

```
QUARTER: Q__ / 20__  DATE: ________________  ORGANIZER: ________________

☐ SCENARIO 1: Primary Host Failure (30 min)
    ☐ Setup
        Time started: ________
        Primary host: 192.168.168.31
        Expected failover: <30 seconds
    
    ☐ Simulate failure
        ☐ Mark host as unreachable
        ☐ Monitor Keepalived VRRP failover
        ☐ Verify virtual IP (192.168.168.50) moves to replica
    
    ☐ Results
        Failover time: _________ seconds
        Service continuity: [ YES / NO ]
        Containers affected: _________
        Result: [ PASS / FAIL ]

☐ SCENARIO 2: Database Recovery (30 min)
    ☐ Setup
        Time started: ________
        Simulate: Database crash or corruption
    
    ☐ Test recovery
        ☐ Verify backup exists
        ☐ Restore database from backup
        ☐ Verify data integrity
        ☐ Restart dependent services
    
    ☐ Results
        Recovery time: _________ minutes
        Data loss: [ NONE / MINIMAL / SIGNIFICANT ]
        Result: [ PASS / FAIL ]

☐ SCENARIO 3: Terraform State Corruption (30 min)
    ☐ Setup
        Time started: ________
        Simulate: State file corruption
    
    ☐ Test recovery
        ☐ Detect state corruption
        ☐ Restore from backup
        ☐ Verify infrastructure matches state
        ☐ Resume operations
    
    ☐ Results
        Detection time: _________ minutes
        Recovery time: _________ minutes
        Result: [ PASS / FAIL ]

☐ SCENARIO 4: Network Partition (30 min)
    ☐ Setup
        Time started: ________
        Simulate: Network split between primary/replica
    
    ☐ Test recovery
        ☐ Monitor VRRP behavior
        ☐ Detect split-brain (if it occurs)
        ☐ Recover network partition
        ☐ Verify data consistency
    
    ☐ Results
        Detection time: _________ seconds
        Recovery time: _________ minutes
        Split-brain occurred: [ YES / NO ]
        Result: [ PASS / FAIL ]

DR DRILL SUMMARY:
    Total scenarios: 4
    Passed: _________  Failed: _________
    Issues found: _________________________________
    Improvements needed: _________________________________
    
DRILL SIGN-OFF: ________________  Date: ________  Approved by: ________________
```

---

## Incident Response Checklist (When Issue Occurs)

```
INCIDENT ID: ________________  START TIME: ________________  DATE: ________________

☐ PHASE 1: Recognition & Alert (Immediate)
    ☐ Issue detected/reported by: ___________________________
    ☐ Alert triggered? [ YES / NO / MANUAL REPORT ]
    ☐ Severity assessed: [ CRITICAL / HIGH / MEDIUM / LOW ]
    ☐ Incident logged in tracking system

☐ PHASE 2: Incident Commander Assignment (Immediate)
    ☐ Assigned to: ________________  Time: ________
    ☐ Escalation chain activated: [ YES / NO ]
    ☐ Team notified: Slack #ops-incidents
        Members: __________________________________________

☐ PHASE 3: Investigation (5-15 minutes)
    ☐ Use OPERATIONAL_RUNBOOK.md to identify playbook
    ☐ Playbook used: ________________
    ☐ Root cause identified: ________________________________
    ☐ Severity re-assessed: [ CRITICAL / HIGH / MEDIUM / LOW ]
    ☐ Decision: [ AUTO-REMEDIATE / MANUAL FIX / ESCALATE ]

☐ PHASE 4: Resolution (Varies)
    ☐ Action executed: _________________________________
    ☐ Time to resolution: _________
    ☐ Verification: [ SUCCESS / PARTIAL / FAILED ]
    ☐ If failed, escalate to Level 2/3
    
☐ PHASE 5: Recovery & Monitoring (30 minutes post-fix)
    ☐ Monitoring checks: [ ALL PASS / SOME WARN / HAS ERROR ]
    ☐ SLO impact assessed: _________________________________
    ☐ Affected customers notified: [ YES / NO / N/A ]
    ☐ Systems returned to normal: [ YES / NO ]

☐ PHASE 6: Documentation & Postmortem (Within 24 hours)
    ☐ Timeline documented: _________________________________
    ☐ Root cause analysis complete: [ YES / NO ]
    ☐ Preventive measures identified: ________________________
    ☐ Postmortem scheduled: [ YES / NO ]  Date: ________

INCIDENT RESOLUTION:
    Total duration: _________ minutes
    Time to detect: _________ minutes
    Time to resolve: _________ minutes
    Customers impacted: _________
    
SIGN-OFF: ________________  Date: ________  Time: ________
```

---

## On-Call Schedule Template

```
MONTH: ________________  YEAR: ________

Primary On-Call (First Response):
☐ Week 1 (4/1-4/7):    ________________  Phone: ____________
☐ Week 2 (4/8-4/14):   ________________  Phone: ____________
☐ Week 3 (4/15-4/21):  ________________  Phone: ____________
☐ Week 4 (4/22-4/30):  ________________  Phone: ____________

Secondary On-Call (Escalation):
☐ Week 1-4:            ________________  Phone: ____________

Coverage Verification:
☐ All weeks assigned: [ YES / NO ]
☐ Contact info updated: [ YES / NO ]
☐ On-call runbook reviewed: [ YES / NO ]
☐ Escalation procedures understood: [ YES / NO ]

Handoff Meeting:
☐ Scheduled: ________  Time: ________
☐ Topics: Current issues, ongoing incidents, known risks
☐ Documentation reviewed: [ YES / NO ]
```

---

**Status**: ✅ **SOP READY**

Complete daily, weekly, monthly, and quarterly checklists for operations team.

All procedures documented and ready for implementation.

