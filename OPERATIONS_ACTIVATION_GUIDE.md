# Operations Activation Guide - Code-Server Platform
**Date:** May 1, 2026  
**Status:** Platform Ready for Full Operations Handoff  
**Next Action:** Activate Operations Team

---

## Executive Summary

The code-server platform is **PRODUCTION READY** with complete operational infrastructure. This guide activates the operations team to independently manage the platform.

**Deployment Status:** ✅ Complete  
**CI/CD Automation:** ✅ Wired  
**Operational Runbooks:** ✅ Comprehensive  
**Monitoring/Alerting:** ✅ Ready  
**Team Training Materials:** ✅ Complete  

**Current Team:** GitHub Copilot Agent (automated deployment)  
**Handoff To:** Your Operations Team (ongoing management)

---

## Part 1: Immediate Activation Tasks (Week 1)

### Task 1.1: Team Setup (Day 1)

**What:** Form operations team and assign roles

**Steps:**
1. Identify team members:
   - [ ] Ops Lead (escalation point)
   - [ ] DBA (database management)
   - [ ] Monitoring Engineer (alerting setup)
   - [ ] 2-3 On-Call Engineers (24/7 coverage)

2. Provide team access:
   - [ ] SSH to 192.168.168.31 (primary) - all team
   - [ ] SSH to 192.168.168.42 (replica) - all team
   - [ ] Grafana admin account - monitoring engineer
   - [ ] Slack #code-server-ops channel - all team
   - [ ] GitHub repository access - all team
   - [ ] On-call pager setup - on-call engineers

3. Schedule kickoff meeting:
   - [ ] Date/time set
   - [ ] All team members attending
   - [ ] 90 minutes allocated
   - [ ] Recording enabled

### Task 1.2: Documentation Review (Day 2)

**What:** Team reviews all operational documentation

**Required Reading (2-3 hours per person):**
- [ ] [Team Operations Handoff](TEAM_OPERATIONS_HANDOFF.md) - CRITICAL
- [ ] [Incident Response Playbook](docs/INCIDENT_RESPONSE_PLAYBOOK.md) - CRITICAL
- [ ] [Operations SOP Checklists](docs/OPERATIONS_SOP_CHECKLISTS.md) - CRITICAL
- [ ] [Monitoring & Alerting Setup](MONITORING_ALERTING_SETUP.md) - For monitoring engineer
- [ ] [Disaster Recovery Testing](DISASTER_RECOVERY_TESTING.md) - For DBA + Ops Lead

**Team Meeting:** Q&A session (1 hour)

### Task 1.3: Access Verification (Day 3)

**What:** Verify all team members have necessary access

**Checklist:**
```bash
# Each team member should run:

# 1. SSH Access
for host in 192.168.168.31 192.168.168.42; do
  echo "Testing $host..."
  ssh akushnir@$host 'echo "SUCCESS"'
done

# 2. Repository access
git clone https://github.com/kushin77/code-server.git
cd code-server
git log --oneline -1

# 3. Grafana access (for monitoring engineer)
# Visit: http://192.168.168.250:3000
# Login with: admin / [password]
# Should see dashboards

# 4. Slack integration
# Verify you're in #code-server-ops and #code-server-alerts channels
```

### Task 1.4: Monitoring Setup (Day 3-4)

**What:** Configure alerting and verify monitoring stack

**Steps:**
1. [ ] Review [Monitoring & Alerting Setup](MONITORING_ALERTING_SETUP.md)
2. [ ] Configure Slack webhook for alerts
3. [ ] Test alert channels (send test alert)
4. [ ] Verify Grafana dashboards loading
5. [ ] Run `ssh akushnir@192.168.168.31 'docker compose ps'` to verify all monitoring services running
6. [ ] Create custom dashboards for your key metrics

**Expected Result:** Team can access Grafana, Slack alerts firing, Prometheus collecting metrics

---

## Part 2: First Week Operations (Days 5-7)

### Day 5: Morning Checks Practice

**What:** Practice daily operational routine

**Procedure:**
1. Each on-call engineer runs morning checklist
   - [ ] [Operations SOP Checklists](docs/OPERATIONS_SOP_CHECKLISTS.md) - Morning section
   - [ ] Duration: ~10 minutes
   - [ ] All checks should PASS
   - [ ] Document results

2. Team lead reviews results
   - [ ] All team members successful
   - [ ] No issues found
   - [ ] Team confident in procedure

### Day 6: Incident Simulation Drill

**What:** Practice incident response with mock scenario

**Scenario:** "Service X is down and returning 500 errors"

**Process:**
1. On-call engineer detects issue
2. Follow [Incident Response Playbook](docs/INCIDENT_RESPONSE_PLAYBOOK.md)
3. Execute procedures step-by-step
4. Document what you did
5. Team lead reviews response

**Expected Outcome:** 
- [ ] Team confident in incident procedures
- [ ] All team members understand escalation
- [ ] Response time documented

### Day 7: Deployment Procedure Review

**What:** Walk through deployment process (dry-run only)

**Steps:**
1. Review [Deployment Execution Runbook](DEPLOYMENT_EXECUTION_RUNBOOK.md)
2. Walk through manually (don't actually deploy):
   ```bash
   # Dry-run deployment process
   cd /home/akushnir/code-server
   
   # Step 1: Validation
   bash scripts/ci/validate-pre-apply.sh
   
   # Step 2: Terraform plan (view but don't apply)
   cd terraform/environments/private
   terraform plan -out=tfplan
   
   # Step 3: Review changes
   terraform show tfplan
   # Cancel with Ctrl+C or rm tfplan
   ```
3. Team lead signs off on understanding

---

## Part 3: Monitoring Configuration (Week 2)

### Monitoring Engineer Tasks

**Task 3.1: Alert Configuration**
- [ ] Review [Monitoring & Alerting Setup - Part 4](MONITORING_ALERTING_SETUP.md#part-4-alert-configuration)
- [ ] Configure all alert channels (Slack, email, pager)
- [ ] Validate each channel with test alert
- [ ] Document alert routing in team wiki

**Task 3.2: Dashboard Setup**
- [ ] Review existing dashboards in Grafana
- [ ] Create team-specific SLO dashboard
- [ ] Create on-call dashboard (critical metrics only)
- [ ] Document dashboard access for team

**Task 3.3: Alert Rules Validation**
- [ ] Review all configured alerts: `docker exec prometheus cat /etc/prometheus/alert_rules.yml`
- [ ] Verify severity levels are appropriate
- [ ] Test that alerts fire when thresholds exceeded
- [ ] Document which alerts are critical vs. informational

**Task 3.4: Custom Metrics**
- [ ] Identify 5 most important custom metrics to track
- [ ] Create Grafana panels for each
- [ ] Set up alerts for each metric
- [ ] Document metrics and their meaning

**Success Criteria:**
- ✅ All alert channels working
- ✅ Test alerts received successfully
- ✅ Dashboards viewable and auto-refreshing
- ✅ Team trained on interpreting metrics

---

## Part 4: On-Call Rotation Setup (Week 2-3)

### On-Call Engineer Tasks

**Task 4.1: Rotation Schedule**
- [ ] Create on-call rotation (weekly or bi-weekly)
- [ ] Get agreement from all team members
- [ ] Post to #code-server-ops channel
- [ ] Set up pager alerts to on-call person

**Task 4.2: On-Call Preparation**
Each engineer preparing for on-call should:
- [ ] Review [Team Operations Handoff](TEAM_OPERATIONS_HANDOFF.md) again
- [ ] Review [Incident Response Playbook](docs/INCIDENT_RESPONSE_PLAYBOOK.md) again
- [ ] Practice morning checklist independently
- [ ] Review recent incidents (if any)
- [ ] Ensure access to all systems
- [ ] Test pager/escalation flow

**Task 4.3: Handoff Procedure**
- [ ] Create handoff protocol between on-call engineers
- [ ] Daily handoff checklist created
- [ ] Documented in team wiki
- [ ] Practiced at shift changes

**Example Handoff Checklist:**
```
ON-CALL HANDOFF (Each change of shift)
=====================================
Incoming on-call engineer: _______________
Outgoing on-call engineer: _______________

[ ] System status reviewed:
    - All services running? YES / NO
    - Any alerts active? YES / NO
    - Any ongoing issues? YES / NO

[ ] Issues/concerns communicated:
    _________________________________

[ ] Pager/escalation tested

[ ] Contact info confirmed:
    [ ] Ops lead phone in contacts
    [ ] Team Slack accessible
    [ ] GitHub checked for pending deployments

[ ] Incoming engineer confirms readiness: YES / NO

Handoff time: _______________
Outgoing engineer signature: _______________
```

---

## Part 5: Disaster Recovery Testing (Week 3-4)

### DBA Tasks

**Task 5.1: DR Plan Review**
- [ ] Review [Disaster Recovery Testing](DISASTER_RECOVERY_TESTING.md) completely
- [ ] Understand each test scenario
- [ ] Identify any gaps or risks

**Task 5.2: Test 1 - Single Container Failure**
- [ ] Schedule test (1 hour window)
- [ ] Execute [Test 1 procedure](DISASTER_RECOVERY_TESTING.md#part-3-test-1---single-container-failure)
- [ ] Document results
- [ ] Brief team on findings

**Task 5.3: Test 2 - Database Replication**
- [ ] Schedule test (2 hour window, off-hours)
- [ ] Execute [Test 2 procedure](DISASTER_RECOVERY_TESTING.md#part-4-test-2---database-failover)
- [ ] Verify replica can be promoted
- [ ] Verify recovery procedure
- [ ] Document results

**Task 5.4: Automated DR Validation**
- [ ] Create automated daily DR health check script
- [ ] Schedule as cron job
- [ ] Verify running daily
- [ ] Review results

**Success Criteria:**
- ✅ Both tests completed successfully
- ✅ Failover time documented and within SLA
- ✅ Team confident in recovery procedures
- ✅ No data loss in any scenario
- ✅ Automated health checks running

---

## Part 6: Deployment Readiness (Week 4)

### Ops Lead Tasks

**Task 6.1: Deployment Authorization**
After Team completes all above tasks:
- [ ] Team has passed all training modules
- [ ] All access verified and working
- [ ] Morning checklist passing consistently
- [ ] Incident drill completed successfully
- [ ] Monitoring configured and alerting
- [ ] DR testing completed
- [ ] Team signed off as ready

**Decision:** Ready for production deployments? YES / NO

**Task 6.2: First Deployment**
When team is ready for first production deployment:
1. [ ] Schedule deployment window (off-hours recommended)
2. [ ] Review [Deployment Execution Runbook](DEPLOYMENT_EXECUTION_RUNBOOK.md)
3. [ ] Team coordination meeting held
4. [ ] All prerequisites checked
5. [ ] Execute deployment via GitHub Actions
6. [ ] Monitor deployment in real-time
7. [ ] Validate post-deployment checks
8. [ ] Document deployment metrics

**Deployment Checklist:**
```bash
# Pre-Deployment
[ ] All morning checks passing
[ ] No uncommitted changes: git status --porcelain
[ ] Team assembled and ready
[ ] Runbook open and reviewed
[ ] Rollback plan documented
[ ] Stakeholders notified

# During Deployment
[ ] GitHub workflow triggered
[ ] Each phase monitored
[ ] Logs reviewed for errors
[ ] Team communicates every 5 minutes
[ ] Slack channel updated

# Post-Deployment
[ ] All services healthy: docker compose ps
[ ] Health checks passing: curl http://localhost/health
[ ] Monitoring showing normal metrics
[ ] No alerts firing
[ ] Team validation complete

# Handoff
[ ] Documentation updated
[ ] Metrics recorded
[ ] Post-mortem (if needed)
[ ] Team debriefing
```

---

## Part 7: Ongoing Operations (Month 2+)

### Weekly Team Standup (30 minutes)

**Every Monday @ [TIME]**

Agenda:
1. [ ] Previous week metrics review (availability, error rate)
2. [ ] Any incidents/issues that occurred
3. [ ] Upcoming deployments or changes
4. [ ] Alert tuning review (too many false positives?)
5. [ ] Training needs identified

### Monthly Maintenance Window (2-4 hours)

**First Sunday of month @ [TIME]**

Activities:
- [ ] OS/container security patches
- [ ] Dependency updates (if applicable)
- [ ] Database maintenance (VACUUM, reindex)
- [ ] Certificate renewal checks
- [ ] Capacity planning review

### Quarterly DR Testing

**Per [Disaster Recovery Testing - Part 9](DISASTER_RECOVERY_TESTING.md#part-9-dr-testing-schedule)**

- [ ] Test 1: Single container failure (any time)
- [ ] Test 2: Database replication (scheduled)
- [ ] Test 3: Network partition (scheduled)
- [ ] Test 4: Storage failure (scheduled)

### Annual Review

**Each anniversary of platform go-live**

- [ ] Full capacity audit
- [ ] Cost optimization review
- [ ] Team training refresh
- [ ] Security audit
- [ ] DR testing at scale

---

## Part 8: Success Metrics

### Team Readiness Checklist

By end of Month 1, all boxes should be checked:

**Training & Knowledge:**
- [ ] All team members read all critical docs
- [ ] All team members understand incident procedures
- [ ] All team members can run morning checks
- [ ] DBA can execute database operations
- [ ] Monitoring engineer configured alerts

**Access & Tools:**
- [ ] All team members can SSH to both hosts
- [ ] Grafana accessible with login
- [ ] GitHub access verified
- [ ] Slack channels configured
- [ ] Pager alerts routing correctly

**Procedures Tested:**
- [ ] Morning checklist run successfully (3x)
- [ ] Incident simulation completed
- [ ] Deployment procedure dry-run completed
- [ ] Single container failure test passed
- [ ] Database replication test passed

**Escalation & Communication:**
- [ ] Incident commander identified
- [ ] Escalation procedures documented
- [ ] Team communication plan created
- [ ] Contact tree up-to-date
- [ ] Escalation tested (sent test alert)

**Operations Ready:**
- [ ] On-call rotation active
- [ ] Daily handoffs happening
- [ ] Monitoring dashboard reviewed daily
- [ ] Weekly standup happening
- [ ] Deployment procedures documented

### Platform Operational Metrics

Track these starting Month 1:

| Metric | Target | Measurement |
|--------|--------|-------------|
| Availability | 99.5% | % uptime |
| Response Time | <200ms p99 | Grafana SLO dashboard |
| Error Rate | <0.1% | Prometheus alerts |
| MTTR (Mean Time To Repair) | <30 min | From incident start to resolution |
| Change Success Rate | >95% | Deployments without rollback |
| Alert Accuracy | >80% | (True positives / total alerts) |
| On-Call Response Time | <5 min | From page to first action |

---

## Part 9: Document Reference Guide

### Critical Documents (Read First)

1. **[Team Operations Handoff](TEAM_OPERATIONS_HANDOFF.md)** ← START HERE
   - Architecture overview
   - Quick start for on-call
   - Escalation procedures
   - Training checklist

2. **[Incident Response Playbook](docs/INCIDENT_RESPONSE_PLAYBOOK.md)**
   - Incident severity levels
   - Step-by-step procedures
   - Specific incident types covered
   - Escalation procedures

3. **[Operations SOP Checklists](docs/OPERATIONS_SOP_CHECKLISTS.md)**
   - Daily morning checklist
   - Pre-deployment checklist
   - Weekly maintenance
   - Monthly review

### Supporting Documents

4. **[Monitoring & Alerting Setup](MONITORING_ALERTING_SETUP.md)**
   - Alert configuration
   - Dashboard setup
   - Custom metrics
   - SLO tracking

5. **[Disaster Recovery Testing](DISASTER_RECOVERY_TESTING.md)**
   - DR test scenarios
   - Failover procedures
   - Recovery validation
   - Testing schedule

6. **[Deployment Execution Runbook](DEPLOYMENT_EXECUTION_RUNBOOK.md)**
   - Pre-deployment steps
   - Deployment procedure
   - Workflow monitoring
   - Post-deployment validation

7. **[Operational Runbook](docs/OPERATIONAL_RUNBOOK.md)**
   - Detailed operational procedures
   - Common tasks
   - Troubleshooting guide
   - Best practices

### Reference Documents

- Deployment Readiness: [DEPLOYMENT_READINESS_2026-05-01.md](DEPLOYMENT_READINESS_2026-05-01.md)
- Deployment Completion: [DEPLOYMENT_COMPLETION_REPORT.md](DEPLOYMENT_COMPLETION_REPORT.md)
- Secrets Management: [GITHUB_SECRETS_SETUP_GUIDE.md](GITHUB_SECRETS_SETUP_GUIDE.md)
- Security Guide: [SECURITY_HARDENING_GUIDE.md](SECURITY_HARDENING_GUIDE.md)

---

## Part 10: Q&A - Frequently Asked Questions

### "What if I can't SSH to a host?"

**Solution:**
1. Check network connectivity: `ping 192.168.168.31`
2. Verify SSH service running: `sudo systemctl status ssh`
3. Check SSH key permissions: `ls -la ~/.ssh/id_rsa` (should be -rw-------)
4. Verify in authorized_keys: `ssh akushnir@192.168.168.31 'cat ~/.ssh/authorized_keys'`
5. Contact Ops Lead if still failing

### "How do I check if database replication is working?"

**Solution:**
```bash
ssh akushnir@192.168.168.31
docker compose exec postgres psql -U postgres -c "SELECT slot_name, active FROM pg_replication_slots;"
# Should show 'true' for active

docker compose exec postgres psql -U postgres -c "SELECT now() - pg_last_wal_receive_time();"
# Should be <1 second
```

### "What's the difference between CRITICAL and HIGH severity?"

**Solution:**
- **CRITICAL:** Full service outage, immediate action needed (<5 min)
- **HIGH:** Significant degradation, urgent response (<15 min)
- See [Incident Response Playbook - Part 1](docs/INCIDENT_RESPONSE_PLAYBOOK.md#severity-levels) for full definitions

### "How do I know if my on-call week is starting?"

**Solution:**
1. Check on-call rotation schedule (posted in #code-server-ops)
2. Verify pager alerts routing to you (test notification)
3. Confirm all access working (SSH, Grafana, GitHub)
4. Review morning checklist
5. Call outgoing on-call engineer for handoff

### "I think there's an issue but I'm not sure - should I escalate?"

**Solution:**
YES. Always escalate if unsure. Better to check and be wrong than to miss a real issue.

1. Document what you observe
2. Run diagnostics: `docker compose ps`, logs, basic checks
3. Page Ops Lead with full context
4. Ops Lead makes escalation decision

---

## Implementation Timeline

```
Week 1 (May 1-7, 2026)
├─ Day 1: Team Setup & Access
├─ Day 2: Documentation Review
├─ Day 3: Access Verification & Monitoring Setup
├─ Day 4: Complete Monitoring Setup
├─ Day 5: Morning Checks Practice
├─ Day 6: Incident Simulation Drill
└─ Day 7: Deployment Review (dry-run)

Week 2 (May 8-14, 2026)
├─ Alert Configuration
├─ Dashboard Setup
├─ Alert Rules Validation
└─ Custom Metrics Setup

Week 3 (May 15-21, 2026)
├─ On-Call Rotation Setup
├─ DR Test 1: Single Container
└─ DR Test 2: Database Replication

Week 4 (May 22-28, 2026)
├─ Deployment Authorization
└─ First Production Deployment (if ready)

Month 2+ (Jun 1+, 2026)
├─ Weekly Standups
├─ Monthly Maintenance
├─ Quarterly DR Testing
└─ Continuous Improvements
```

---

## Final Activation Checklist

**Operations Team Lead: Review and sign off**

By signing below, you confirm:

- [ ] All team members assigned and notified
- [ ] All documentation reviewed
- [ ] Access verification completed
- [ ] Training schedule created
- [ ] First week tasks scheduled
- [ ] Monitoring configuration started
- [ ] On-call rotation created
- [ ] Team ready for handoff

**Team Lead Name:** _______________  
**Date:** _______________  
**Signature:** _______________

---

**Questions?**

1. Check the relevant documentation section above
2. Review the referenced operational guide
3. Post in #code-server-ops Slack channel
4. Contact Ops Lead for urgent issues

**Next Step:** Print this document and use it as your activation playbook for the next 4 weeks.

✅ **Platform Ready for Operations Handoff**

Your operations team now has everything needed to independently manage and operate the code-server platform. Follow this guide, complete the activation tasks, and you'll have a fully operational platform by end of Month 1.

**Good luck! 🚀**
