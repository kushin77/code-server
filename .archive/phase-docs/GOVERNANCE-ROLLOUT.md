# GitHub Actions & API Governance Framework - 30-Day Rollout

**Timeline**: 30 days
**Start Date**: April 13, 2026
**End Date**: May 13, 2026
**Owner**: DevOps Team
**Status**: Implementation In Progress

---

## Phase 1: Foundation & Monitoring (Days 1-7)

### Objectives
- Deploy governance framework
- Enable monitoring and alerting
- Establish baseline metrics

### Tasks

**Day 1-2: Setup & Deployment**
- [ ] Create governance policy repository (or use .github/governance)
- [ ] Deploy cost-monitor.yml workflow
- [ ] Deploy enforcement.yml workflow
- [ ] Create Slack integration for alerts
- [ ] Setup initial billing alerts (Google Cloud Billing API)

**Day 3-4: Baseline Metrics**
- [ ] Run historical analysis on last 90 days
  - Total Actions spend
  - Costs by workflow
  - Costs by repository
  - Peak usage times
- [ ] Document findings in BASELINE-METRICS.md
- [ ] Create dashboard in Grafana (or alternative)

**Day 5-7: Team Training**
- [ ] Record governance training video (15 min)
- [ ] Send explanation email to all engineers
- [ ] Host live Q&A session
- [ ] Update wiki/documentation site

### Success Criteria
- [ ] Monitoring operational and collecting data
- [ ] All team members aware of new policies
- [ ] Baseline metrics documented
- [ ] Dashboard displaying real-time costs

**Owner**: DevOps Lead
**Effort**: 20 hours
**Risk**: Low

---

## Phase 2: Repository Onboarding (Days 8-21)

### Objectives
- Apply governance rules to all repositories
- Enforce branch protection standards
- Update all workflows with quotas

### Batch Approach

Repositories processed in batches of 5 per day (14 days for ~70 repos):

**Days 8-9: Mission-Critical Repos** (5 repos)
- code-server
- eiq-linkedin
- GCP-landing-zone
- code-server-enterprise
- (1 additional high-priority)

Actions per repo:
1. [ ] Enable branch protection on main
2. [ ] Import required_status_checks
3. [ ] Audit existing workflows
4. [ ] Add cost category to workflows
5. [ ] Update resource limits
6. [ ] Configure quotas
7. [ ] Test CI/CD pipeline
8. [ ] Get sign-off from team lead

**Days 10-21: Remaining Repos** (65 repos, 5/day)
- Same process as Days 8-9
- Prioritize by criticality and cost
- Stagger to avoid API rate limits

### High-Priority Pattern

```yaml
name: Governance Compliance Check

on:
  pull_request:
    paths:
      - '.github/workflows/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Validate Workflow Compliance
        run: |
          # Check 1: Timeout defined
          grep -q "timeout-minutes:" .github/workflows/*.yml || exit 1

          # Check 2: Resource limits
          grep -q "runs-on:" .github/workflows/*.yml || exit 1

          # Check 3: Cost category
          grep -q "COST_CATEGORY:" .github/workflows/*.yml || exit 1

          echo "✓ All workflows compliant"
```

### Automation Scripts
- [ ] scripts/enforce-governance.sh - Apply rules to all repos
- [ ] scripts/validate-governance.sh - Check compliance
- [ ] scripts/cost-report.sh - Generate cost reports

### Success Criteria
- [ ] 100% of critical repos (5/5) fully compliant
- [ ] 90%+ of total repos (60+/70) fully compliant
- [ ] CI/CD pipelines all passing
- [ ] No complaints from teams

**Owner**: DevOps Lead + Release Engineer
**Effort**: 60 hours
**Risk**: Medium (may break workflows temporarily)

**Mitigation**:
- Test each repo in staging branch first
- Runbook for quick rollback available
- Batch approach allows gradual rollout

---

## Phase 3: Monitoring, Optimization & Tuning (Days 22-30)

### Objectives
- Fine-tune quotas based on actual usage
- Identify and implement quick wins
- Establish ongoing governance process

### Tasks

**Day 22-24: Analysis**
- [ ] Generate 2-week cost report (Days 1-14)
- [ ] Analyze by:
  - Repository
  - Workflow
  - Team
  - Trigger type
- [ ] Identify top 5 cost drivers
- [ ] Create optimization plan

**Day 25-27: Quick Wins**
- [ ] Implement 3-5 quick optimizations
  - Disable orphaned workflows
  - Batch scheduled jobs
  - Reduce artifact retention
  - Optimize Docker layer caching
  - Parallel test sharding
- [ ] Measure impact
- [ ] Document savings

**Day 28-30: Finalization**
- [ ] Adjust quotas based on 2-week data
- [ ] Document final policies
- [ ] Create runbook for ongoing governance
- [ ] Schedule quarterly reviews
- [ ] Get sign-off from CTO

### Success Criteria
- [ ] Cost reduction of 20-30% identified
- [ ] Final policies documented and approved
- [ ] Governance process is repeatable
- [ ] Team trained on ongoing procedures

**Owner**: DevOps Lead
**Effort**: 30 hours
**Risk**: Low

---

## Weekly Checkpoints

**Week 1 Review** (Day 7)
```
- Monitoring operational? YES/NO
- Baseline metrics complete? YES/NO
- Team trained? YES/NO
- Proceed to Phase 2? YES/NO
```

**Week 2 Review** (Day 14)
```
- 10 repos onboarded? YES/NO
- CI/CD all passing? YES/NO
- Any blockers? ___________
- Adjust timeline if needed
- Proceed to Phase 3? YES/NO
```

**Week 3 Review** (Day 21)
```
- 60+ repos compliant? YES/NO
- Cost trends visible? YES/NO
- Optimization opportunities identified? YES/NO
- Quick wins attempted? YES/NO
```

**Week 4 Review** (Day 30)
```
- 100% compliance achieved? YES/NO
- Cost reduction >20%? YES/NO
- Governance process documented? YES/NO
- Phase 1 approval complete? YES/NO
- PROJECT GATE APPROVAL? YES/NO
```

---

## Resource Requirements

| Role | Hours/Week | Total | Notes |
|------|-----------|-------|-------|
| DevOps Lead | 15 | 60 | Governance design, repo onboarding, tuning |
| Release Eng | 10 | 40 | Batch automation, validation |
| Security | 3 | 12 | Policy review, compliance audit |
| SRE | 2 | 8 | Monitoring setup, alerting |
| **Total** | **30** | **120** | ~3 FTE-weeks  |

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Workflows break | High | Test before deploying, runbook ready |
| Cost increases | Medium | Quotas enforced, alerts at thresholds |
| Team resistance | Medium | Early communication, training, feedback |
| GitHub API limits | Low | Batch processing, rate-limit handling |

---

## Success Metrics (Final)

| Metric | Target | Goal |
|--------|--------|------|
| Monthly Actions cost | Baseline -30% | $350-400 |
| Governance compliance | 100% repos | 100% |
| Mean time to fix | <24 hours | <2 hours |
| Automation rate | 90%+ | 95%+ |
| Team satisfaction | 8/10 | 8+/10 |

---

## Escalation Path

- **Daily Blockers**: Slack #governance-support
- **Policy Questions**: DevOps Lead
- **Budget Overruns**: CTO
- **Project Delays**: Director of Engineering
- **Emergency**: Page Infrastructure Lead

---

## Approval Sign-Off

- [ ] DevOps Lead: _____________ Date: _______
- [ ] CTO / Infrastructure Lead: _____________ Date: _______
- [ ] Finance / Budget Owner: _____________ Date: _______

---

**Status**: Ready for Phase 1 execution
**Last Updated**: April 13, 2026
**Versio**n: 1.0
