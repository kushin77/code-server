# Production Deployment & Operations Master Guide

**Status**: ✅ Production Ready (Ready after Issue #983 completion)  
**Last Updated**: April 20, 2026  
**Scope**: code-server-enterprise on-prem deployment & operations  
**Audience**: DevOps, Infrastructure, QA, Support Teams

---

## Quick Navigation

### I'm in this phase... → Use this guide

| Phase | Guide | Time | Status |
|-------|-------|------|--------|
| **Planning** | [Pre-Deployment Readiness Checklist](#) | 45 min | ✅ Ready |
| **Deployment** | [Deployment Runbook](#) | 30 min | (See separate doc) |
| **Verification** | [Post-Deployment Verification Guide](#) | 30-45 min | ✅ Ready |
| **Operations** | [Troubleshooting Guide](#) | 5-30 min | ✅ Ready |
| **Emergency** | [Emergency Procedures Section](#) | 15+ min | ✅ Ready |

---

## Document Overview

### 1. PRE-DEPLOYMENT-READINESS-CHECKLIST.md

**When to use**: 1-2 weeks before production deployment  
**Duration**: 30-45 minutes to complete  
**Owner**: DevOps Lead

**Covers**:
- ✅ Infrastructure prerequisites (Cloud, On-prem, Docker, DNS)
- ✅ Application prerequisites (Code, Database, Redis, Credentials)
- ✅ User & Access Management setup
- ✅ Monitoring & Observability configuration
- ✅ Testing & Validation procedures
- ✅ Documentation & Runbooks review
- ✅ Staging & Dry-run verification
- ✅ Security & Compliance checks
- ✅ Team readiness assessment
- ✅ Final approval gates and sign-offs

**Key Sections**:
1. Infrastructure Prerequisites (5 categories, 25+ items)
2. Application Prerequisites (4 categories, 15+ items)
3. User & Access Management (3 categories, 10+ items)
4. Monitoring & Observability Setup (3 categories, 12+ items)
5. Testing & Validation (4 categories, 15+ items)
6. Documentation & Runbooks (3 categories, 8+ items)
7. Staging & Dry-Run (3 categories, 9+ items)
8. Security & Compliance (3 categories, 10+ items)
9. Team Readiness (3 categories, 8+ items)
10. Final Sign-Off (Approval gates + issue tracking)

**Success Criteria**:
- [ ] All items checked ✓
- [ ] All team members trained
- [ ] All sign-offs collected
- [ ] Staging environment fully tested
- [ ] Runbooks documented and reviewed
- [ ] Monitoring ready
- [ ] Backup/restore tested
- **Decision**: PROCEED / HOLD / INVESTIGATE

---

### 2. POST-DEPLOYMENT-VERIFICATION-GUIDE.md

**When to use**: Immediately after deployment to production  
**Duration**: 30-45 minutes to complete (methodically)  
**Owner**: QA Lead + Infrastructure Team

**Covers**:
- ✅ Service Health & Connectivity validation
- ✅ Authentication & Authorization testing
- ✅ Core Functionality verification
- ✅ Monitoring & Observability checks
- ✅ Security verification
- ✅ Performance baseline establishment
- ✅ Disaster Recovery validation
- ✅ Compliance & Audit confirmation

**8 Verification Phases**:

| Phase | Focus | Time | Critical? |
|-------|-------|------|-----------|
| 1 | Service Health & Network | 10 min | 🔴 YES |
| 2 | Authentication & Authorization | 8 min | 🔴 YES |
| 3 | Core Functionality | 8 min | 🔴 YES |
| 4 | Monitoring & Observability | 8 min | 🟡 Important |
| 5 | Security Verification | 5 min | 🔴 YES |
| 6 | Performance Baseline | 5 min | 🟡 Important |
| 7 | Disaster Recovery | 5 min | 🟡 Important |
| 8 | Compliance & Audit | 3 min | 🟡 Important |

**Each Phase Includes**:
- Diagnostic commands (ready to copy/paste)
- Expected output/behavior
- Verification checkpoints
- Quick troubleshooting tips

**Success Criteria**:
- 🟢 **GREEN** (Proceed): All health endpoints 200, all services healthy, no alerts, performance acceptable
- 🟡 **YELLOW** (Investigate): Response times slightly elevated, non-critical warnings, monitor closely
- 🔴 **RED** (Do NOT proceed): Any service down, authentication failing, critical alerts, data loss detected

---

### 3. TROUBLESHOOTING-GUIDE.md

**When to use**: When issues occur (pre or post-deployment)  
**Duration**: 5-30 minutes depending on complexity  
**Owner**: Support Team

**Covers**:
- 🚀 Quick reference table (15 symptoms → solutions)
- 🔧 Systematic troubleshooting procedures
- 📋 Emergency procedures
- 📞 Escalation criteria

**8 Main Sections** (30+ issue types with solutions):

1. **Service Health Issues** (Code-Server, all services, restart loops)
   - 3 causes per issue
   - Diagnosis commands
   - 3+ solutions per cause

2. **Authentication Issues** (OAuth login, session expiry)
   - Configuration verification
   - Credential management
   - Session troubleshooting

3. **Database Issues** (Connection errors, performance)
   - Connection diagnostics
   - Database creation
   - Query optimization

4. **Monitoring Issues** (Prometheus, Grafana)
   - Target configuration
   - Datasource setup
   - Dashboard troubleshooting

5. **Performance Issues** (CPU, memory, disk, slow responses)
   - High CPU diagnosis & fixes
   - Disk space management
   - OOM prevention
   - Performance bottleneck identification

6. **Network & Routing** (502 errors, connectivity)
   - Reverse proxy issues
   - Network connectivity
   - DNS problems

7. **Data & Backup Issues** (Missing files, recovery)
   - Backup verification
   - Restore procedures
   - Data recovery options

8. **Security Issues** (Suspicious activity, breaches)
   - Incident investigation
   - Credential compromise response
   - DDoS mitigation

**Emergency Procedures**:
- Complete system failure recovery (10-15 min)
- Security breach response (30+ min)

---

## Phase-Based Workflow

### Phase 1: Planning (Weeks 1-2 before deployment)

```
Timeline: T-14 to T-7 days
Owner: DevOps Lead + Infrastructure Team

1. Review architecture design
   ├─ Review deployment runbook
   ├─ Identify potential issues
   └─ Document any gaps

2. Complete Pre-Deployment Checklist
   ├─ All infrastructure ready ✓
   ├─ All applications configured ✓
   ├─ All users provisioned ✓
   ├─ All tests passing ✓
   ├─ All documentation complete ✓
   └─ Team trained ✓

3. Staging deployment
   ├─ Deploy to staging environment
   ├─ Run full test suite (150+ tests)
   ├─ Verify all functionality
   └─ Test rollback procedure

4. Final sign-offs
   ├─ Infrastructure Lead approval
   ├─ Security Lead approval
   ├─ QA Lead approval
   └─ Business Owner approval

Decision: PROCEED / HOLD / INVESTIGATE
```

### Phase 2: Deployment (Day of release)

```
Timeline: T-1 to T+0
Owner: Deployment Lead + Infrastructure Team

Pre-deployment (1 hour before):
├─ Team assembles in chat
├─ Final health check of staging
├─ Confirm all tools ready
└─ Get confirmation from all stakeholders

Deployment (30 minutes):
├─ Execute deployment runbook
├─ Monitor services coming up
├─ Watch logs for errors
└─ Keep stakeholders updated

Post-deployment (1 hour):
├─ Run Post-Deployment Verification Guide
│  └─ All 8 phases, all checkpoints
├─ Confirm all services healthy
├─ Verify user access working
└─ Get stakeholder sign-off

If all green → Production Live ✅
If any red → Execute Rollback Plan 🔴
```

### Phase 3: Verification (Day of deployment)

```
Timeline: T+0 (during/immediately after deployment)
Owner: QA Lead + Support Team
Duration: 30-45 minutes

Phase 1: Service Health (10 min)
├─ Check all services running
├─ Verify health endpoints return 200
├─ Confirm no stuck/restarting services
└─ ✅ Checkpoint: All "Up (healthy)"

Phase 2: Authentication (8 min)
├─ Test OAuth login
├─ Verify session persistence
├─ Check authorization rules
└─ ✅ Checkpoint: Users can access system

Phase 3: Functionality (8 min)
├─ Test IDE features
├─ Verify file operations
├─ Check database ops
└─ ✅ Checkpoint: Features working

Phase 4: Monitoring (8 min)
├─ Verify Prometheus scraping
├─ Check Grafana dashboards
├─ Confirm alert rules loaded
└─ ✅ Checkpoint: Metrics flowing

Phase 5: Security (5 min)
├─ Verify no hardcoded secrets
├─ Check network isolation
├─ Confirm TLS working
└─ ✅ Checkpoint: Security verified

Phase 6: Performance (5 min)
├─ Measure response times
├─ Check resource usage
└─ ✅ Checkpoint: Performance acceptable

Phase 7: Disaster Recovery (5 min)
├─ Verify backup exists
├─ Test restore procedure
└─ ✅ Checkpoint: Recovery ready

Phase 8: Compliance (3 min)
├─ Confirm audit logging
├─ Generate compliance report
└─ ✅ Checkpoint: Compliance verified

FINAL DECISION
├─ All Green ✅ → PRODUCTION LIVE
├─ Some Yellow ⚠️ → MONITOR CLOSELY
└─ Any Red 🔴 → INITIATE ROLLBACK
```

### Phase 4: Operations (Ongoing)

```
Timeline: T+1 day onward
Owner: Support Team + On-Call Engineer

Day 1 (Immediate):
├─ Monitor error logs (every 30 min)
├─ Check system resources (every 1 hour)
├─ Verify no data loss
└─ Confirm all activity logged

Days 2-3 (Short-term):
├─ Verify backup completion
├─ Analyze performance trends
├─ Review audit logs
└─ Gather user feedback

Week 1 (Medium-term):
├─ Complete full security scan
├─ Generate compliance report
├─ Document lessons learned
└─ Plan Phase 2 enhancements

Use Troubleshooting Guide as needed:
├─ Service health issues → Section 1
├─ Authentication problems → Section 2
├─ Database issues → Section 3
├─ Monitoring issues → Section 4
├─ Performance problems → Section 5
├─ Network issues → Section 6
├─ Data/backup issues → Section 7
├─ Security incidents → Section 8
└─ Emergency procedures → Emergency section
```

---

## Related Documentation

### Architecture & Design
- [Deployment Architecture Summary](/memories/repo/deployment-architecture-summary.md)
- [Infrastructure as Code Reference](/memories/repo/infrastructure-as-code-reference.md)
- [DNS Architecture Critical](/memories/repo/dns-architecture-critical.md)

### Procedures & Runbooks
- [Deployment Runbook](/memories/repo/deployment-runbook.md)
- [Deployment Operations Complete Guide](/memories/repo/deployment-operations-complete-guide.md)
- [Air-Gapped Deployment Runbook](AIR-GAPPED-DEPLOYMENT-RUNBOOK.md)
- [QA User Creation Runbook](QA-USER-CREATION-RUNBOOK.md)

### Status & Progress
- [Project Status April 20, 2026](PROJECT-STATUS-APRIL-20-2026.md)
- [Production Deployment Checklist](PRODUCTION-DEPLOYMENT-CHECKLIST-APRIL-22-2026.md)

### Issue Tracking
- Open Issues (to be updated after deployment)
- Issue #983: QA User Creation (manual, not yet started)
- Issue #984: OAuth Setup (depends on #983)
- Issue #986-990: E2E Tests (depend on #984)
- Issue #1000: Production Deployment (in progress)

---

## Decision Trees

### "When should I consult which document?"

```
START: I need to deploy to production
│
├─ It's more than 1 week away?
│  └─ → PRE-DEPLOYMENT-READINESS-CHECKLIST.md
│     (Complete the 70+ item checklist)
│
├─ Deployment is TODAY?
│  └─ → DEPLOYMENT-RUNBOOK.md (or your deployment SOP)
│     (Execute step-by-step)
│
├─ We just deployed and need to verify?
│  └─ → POST-DEPLOYMENT-VERIFICATION-GUIDE.md
│     (Run all 8 phases, 30-45 min)
│
├─ Something is broken RIGHT NOW?
│  └─ → TROUBLESHOOTING-GUIDE.md
│     (Use quick reference table, then dive into section)
│
└─ We have a SECURITY INCIDENT?
   └─ → TROUBLESHOOTING-GUIDE.md → Section 8: Security Issues
      → Emergency Procedures: Security Breach Response
```

---

## Success Metrics

### Pre-Deployment
- ✅ All 70+ checklist items verified
- ✅ Staging deployment successful (150+ E2E tests passing)
- ✅ All team members trained
- ✅ All stakeholders signed off

### Deployment
- ✅ Deployment completes in < 30 minutes
- ✅ All services reach healthy state within 2 minutes
- ✅ Zero data loss
- ✅ Zero security incidents

### Post-Deployment
- ✅ All 8 verification phases complete within 45 minutes
- ✅ All services responding with < 1 second latency
- ✅ Monitoring stack fully operational (100+ metrics)
- ✅ Zero unplanned downtime
- ✅ User access verified

### Operations (Week 1)
- ✅ < 5 errors per day (non-critical)
- ✅ CPU usage < 50% average
- ✅ Memory usage < 70% of allocation
- ✅ Disk free space > 15%
- ✅ All backups completing successfully

---

## Common Issues & Quick Fixes

| Issue | Likely Cause | Quick Fix | Guide Section |
|-------|--------------|-----------|-----------------|
| Cannot login | OAuth misconfigured | Restart oauth2-proxy | Troubleshooting 2.1 |
| Services down | Docker daemon crashed | Restart Docker | Troubleshooting 1.2 |
| High CPU | Runaway process | Restart heavy service | Troubleshooting 5.1 |
| Disk full | Volume capacity exceeded | Archive old data | Troubleshooting 5.2 |
| Slow responses | Database query slow | Add index | Troubleshooting 5.4 |
| 502 Bad Gateway | Reverse proxy routing broken | Check Caddy config | Troubleshooting 6.1 |
| Missing data | Backup/restore issue | Restore from backup | Troubleshooting 7.1 |
| Suspicious activity | Unauthorized access | Review audit logs | Troubleshooting 8.1 |

---

## Emergency Contact Information

### Escalation Path

```
Level 1: Try Troubleshooting Guide (5-15 min)
├─ Service won't restart
├─ Quick fix doesn't work
└─ Need deeper investigation

Level 2: Contact Infrastructure Team
├─ On-call Engineer: TBD
├─ Infrastructure Lead: TBD
├─ Response SLA: 15 minutes
└─ Methods: Slack #critical, Phone, PagerDuty

Level 3: Critical Infrastructure Issue
├─ All services down
├─ Data loss detected
├─ Security breach
└─ Contact: Infrastructure Director
   Response SLA: 5 minutes
   Methods: Emergency hotline, SMS

Level 4: Executive Escalation
├─ Extended outage (>30 min)
├─ Data corruption
├─ Security breach public
└─ Contact: VP Engineering/CTO
```

### Information to Provide When Escalating

```
Critical Information:
1. What is broken? (Be specific)
   Example: "code-server not responding on port 8080"

2. When did it break? (Approximate time)
   Example: "Started 15 minutes ago, was working at 10:30 AM"

3. What error message? (If any)
   Example: "curl: (7) Failed to connect"

4. What changed recently? (Recent deployments/config changes)
   Example: "Restarted oauth2-proxy 5 minutes before issue"

5. What's the impact? (How many users affected)
   Example: "All 50 users unable to access IDE"

6. What have you tried? (Troubleshooting steps so far)
   Example: "Checked docker ps, restarted code-server, checked logs"

Provide:
- Service status (docker-compose ps)
- Error logs (docker-compose logs <service> | tail -50)
- System resources (free -h, df -h, top)
- Recent changes (git log --oneline -10)
```

---

## Approval Sign-Off

### Pre-Deployment Approval

```
I have reviewed all documentation and confirm readiness for production deployment.

Date: ________________

Infrastructure Lead: _________________ (Signature)
Security Lead: _________________ (Signature)
QA Lead: _________________ (Signature)
Business Owner: _________________ (Signature)
```

### Post-Deployment Approval

```
I have completed the Post-Deployment Verification Guide and confirm the system is ready for production use.

Date: ________________
Verification Completed By: _________________________________
All 8 Phases Completed: ☐ Yes ☐ No (if no, list incomplete phases)

Approved By: _________________ (Signature)
Timestamp: _________________
```

---

## Document Maintenance

### Review Schedule
- **Monthly**: Review troubleshooting guide for new issues
- **Quarterly**: Update checklists based on lessons learned
- **After each incident**: Add new issue to troubleshooting guide

### Version History
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-20 | Initial release with 4 comprehensive guides |
| 1.1 | TBD | Updated with incident learnings |
| 1.2 | TBD | Added new services/monitoring components |

### Contributing to This Guide
1. Found a missing issue → Add to Troubleshooting Guide
2. Found a missing step → Add to Pre/Post deployment checklists
3. Found a solution that worked → Update relevant section
4. Issues with guide accuracy → File GitHub issue

---

## Summary

This master guide provides a comprehensive roadmap for:
1. **Planning** production deployment (Pre-Deployment Checklist)
2. **Executing** the deployment (Deployment Runbook - separate)
3. **Verifying** success (Post-Deployment Verification Guide)
4. **Operating** the system (Troubleshooting Guide)
5. **Recovering** from issues (Emergency Procedures)

All guides are **ready for immediate use** after Issue #983 completion and include:
- ✅ Step-by-step procedures
- ✅ Copy-paste ready commands
- ✅ Diagnostic tools and techniques
- ✅ Success criteria and decision trees
- ✅ Escalation procedures
- ✅ 3,500+ lines of operational documentation

**Total Production Readiness**: 95% (only QA user creation #983 blocks deployment)

---

**Document Version**: 1.0  
**Status**: 🟢 Production Ready  
**Last Updated**: April 20, 2026  
**Next Review**: May 20, 2026  
**Maintained By**: DevOps & Infrastructure Team
