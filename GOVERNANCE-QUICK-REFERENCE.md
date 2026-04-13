# GitHub Actions & API Governance - Quick Reference

**Status**: Ready for Rollout  
**Effective Date**: April 14, 2026  
**Owner**: DevOps Team  

---

## The Problem

- **GitHub Actions sprawl**: Uncontrolled workflows costing $500+/month
- **API overages**: Multiple external APIs without tracking or approval
- **No governance**: Any developer can add any workflow, call any API
- **Visibility gap**: No cost forecasting, reactive billing surprises
- **No enforcement**: Broken workflows run until manually disabled, wasting money

---

## The Solution: Four-Part Framework

```
┌─────────────────────────────────────────────────────────────┐
│ 1. POLICIES          → .github/GOVERNANCE.md                 │
│    Define rules, quotas, approval gates, monitoring          │
├─────────────────────────────────────────────────────────────┤
│ 2. RULES             → config/github-rules.yaml              │
│    Machine-readable enforcement, thresholds, budgets         │
├─────────────────────────────────────────────────────────────┤
│ 3. AUTOMATION        → scripts/enforce-governance.sh         │
│    Daily checks, compliance reports, alerts                  │
├─────────────────────────────────────────────────────────────┤
│ 4. COST TRACKING     → .github/workflows/cost-monitoring.yml │
│    Weekly reports, trend analysis, budget alerts             │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Controls

### Workflow Quotas (Per Category, Per Month)

| Category | Quota | Purpose |
|----------|-------|---------|
| ci-tests | 300 | Unit & integration tests |
| ci-lint | 200 | Linting & formatting |
| ci-security | 150 | SAST, DAST, scanning |
| ci-build | 100 | Build artifacts & images |
| deploy-staging | 50 | Manual staging deployments |
| deploy-prod | 30 | Automatic production |
| scheduled-jobs | 20 | Cron/scheduled tasks |
| manual-admin | 25 | Administrative tasks |
| experimental | 50 | POCs and testing |

**Enforcement**: Auto-skip runs exceeding quota (requires lead approval to override)

---

### Branch Protection (Universal Standard)

**main branch**:
```
✓ Require 1 approval
✓ Dismiss stale reviews
✓ Require status checks: lint, tests, security-scan
✓ No force pushes
✓ No deletions
✓ No bypass for admins
```

**develop branch**:
```
✓ Allow fast-forward merges
✓ No approval required (for velocity)
✓ Allow force pushes
✓ Allow deletions
```

**release/* branches**:
```
✓ Require 2 approvals
✓ Require code owner review
✓ Require 4 status checks (+ build)
```

---

### Approved External APIs

**Production** (no limit):
- GitHub API
- Cloudflare API
- GCP APIs
- Slack (webhooks only)
- Docker Registry

**Development** (quota: $500/month per team):
- OpenAI/Claude APIs
- Anthropic (with approval)

**Forbidden**:
- Unknown 3rd-party APIs
- Unapproved SaaS
- Eval-based systems

---

### Cost Thresholds & Alerts

```
┌─────────────────────────────────────┐
│ 🟢 Below 80%  → Monitor            │  OK
├─────────────────────────────────────┤
│ 🟡 80-100%    → Team Standup       │  Discuss
├─────────────────────────────────────┤
│ 🟠 100-150%   → Lead Review (24h)  │  Action Required
├─────────────────────────────────────┤
│ 🔴 >150%      → CTO Escalation     │  Emergency
└─────────────────────────────────────┘
```

---

## Governance Rollout (30 Days)

```
Week 1: Foundation
├─ Publish policies & enforcement
├─ Setup monitoring & alerting
└─ Team briefing

Week 2: Pilot Rollout
├─ Apply to 2-3 pilot repos
├─ Identify issues & exceptions
└─ Create templates

Week 3: Repository Rollout
├─ Apply to all 20+ repos
├─ Weekly compliance checks
└─ 100% compliance target

Week 4: Automation & Tuning
├─ Continuous enforcement
├─ Cost reports & dashboards
└─ Policy adjustments
```

**Timeline**: [See GOVERNANCE-ROLLOUT.md](GOVERNANCE-ROLLOUT.md)

---

## For Repository Owners: 7-Step Checklist

1. **Branch Protection**: `gh api` call from enforcement script ✓
2. **Workflows**: Add `COST_CATEGORY` + `timeout-minutes` to each
3. **Secrets**: No hardcoded secrets (use GitHub secrets)
4. **Cost Estimate**: Document monthly projections
5. **Documentation**: Create `.github/README.md`
6. **Testing**: Verify protection rules work
7. **Sign-Off**: Lead approval + governance stamp

**Time**: ~2 hours per repo  
**Support**: [GOVERNANCE-ONBOARDING.md](GOVERNANCE-ONBOARDING.md)

---

## For Developers: What Changes

### Before
- ❌ Add any workflow without review
- ❌ Call external APIs freely
- ❌ Leave workflows running indefinitely
- ❌ No visibility into costs

### After
- ✅ Workflow templates provided
- ✅ Cost preapproved in budget
- ✅ Workflows auto-optimized (caching, parallelization)
- ✅ Weekly cost reports (transparent)
- ✅ Fast-track approval for legitimate needs

**The good news**: Workflows become **faster** and **cheaper**  
**The constraint**: Budget discipline + approval process

---

## For DevOps: What's Automated

### Daily (9 AM UTC)
- [ ] Check branch protection rules
- [ ] Audit workflow compliance
- [ ] Monitor cost trends
- [ ] Create issue for violations

### Weekly (Fridays 9 AM)
- [ ] Full governance audit
- [ ] Cost trend analysis
- [ ] Generate team reports
- [ ] Review exceptions

### Monthly
- [ ] Comprehensive cost review
- [ ] Quota adjustments (if needed)
- [ ] Policy updates (if needed)
- [ ] Team retrospective

**Implementation**: [scripts/enforce-governance.sh](scripts/enforce-governance.sh) + [.github/workflows/cost-monitoring.yml](.github/workflows/cost-monitoring.yml)

---

## Cost Impact Projection

| Period | Spend | Savings |
|--------|-------|---------|
| **Today** | $500/mo | Baseline |
| **Week 1** | $300/mo | -40% (disable unused, cache, cancel stale) |
| **Week 2** | $200/mo | -60% (parallelize, batch scheduled jobs) |
| **Week 4** | $150/mo | -70% (smart skipping, custom runners) |
| **Annual** | $1,800 | **$4,200 savings** |

**Key Optimizations** (see [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md)):
1. Disable unused workflows: -15%
2. Caching: -20%
3. Parallelize: -10%
4. Batch scheduled jobs: -30% of scheduled
5. Smart skipping: -10%
6. Custom runners: -20% (for selected jobs)

---

## Documentation Map

```
.github/
├─ GOVERNANCE.md                      (Policies & framework)
├─ workflows/
│  ├─ cost-monitoring.yml            (Weekly cost reports)
│  └─ TEMPLATE-*.yml                 (Reference implementations)

config/
├─ github-rules.yaml                 (Machine-readable rules)

scripts/
├─ enforce-governance.sh             (Daily enforcement)
└─ apply-governance.sh               (Batch application)

docs/
├─ GOVERNANCE-ROLLOUT.md             (30-day rollout plan)
├─ GOVERNANCE-ONBOARDING.md          (Per-repo checklist)
├─ COST-OPTIMIZATION.md              (14 quick wins)
└─ GOVERNANCE-QUICK-REFERENCE.md     (This file)
```

---

## Quick Start

### I'm a DevOps Engineer
1. Read: [GOVERNANCE.md](.github/GOVERNANCE.md)
2. Run: `bash scripts/enforce-governance.sh`
3. Monitor: [.github/workflows/cost-monitoring.yml](.github/workflows/cost-monitoring.yml)

### I'm a Repository Owner
1. Read: [GOVERNANCE-ONBOARDING.md](GOVERNANCE-ONBOARDING.md)
2. Follow: 7-step checklist
3. Wait: ~2 hours per repo
4. Verify: Compliance check passes

### I'm a Developer
1. Check: Do workflows exist? (Yes → use them)
2. Add new workflow? Use [TEMPLATE-ci-tests.yml](.github/workflows/TEMPLATE-ci-tests.yml)
3. Questions? Post in `#devops-governance`

### I Need Cost Optimization
1. Read: [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md)
2. Implement: Week 1 quick wins (↓40%)
3. Track: Weekly cost reports

---

## Decision Tree: "Can I Do This?"

```
"I want to add/change a workflow"
  ├─ Is it in templates? → YES
  │  └─ Use template ✓
  ├─ Does it need a new API?
  │  ├─ Approved API? → YES → Use it ✓
  │  └─ New API? → Post in governance + 48h review
  ├─ Will it cost >$10/mo?
  │  ├─ Fits budget? → YES → Green light ✓
  │  └─ Over budget? → Request exemption (needs business case)
  └─ Is there a quota?
     ├─ Room available? → YES → Go ahead ✓
     └─ Quota exceeded? → Wait for reset or override approval

"I need to call an external API"
  ├─ GitHub, Cloudflare, GCP? → Auto-approved ✓
  └─ Other → Governance review (48 hours, cost estimate required)

"My workflow is slow"
  ├─ Add caching → Usually fixes it
  ├─ Parallelize jobs → Reduces duration
  └─ Check COST-OPTIMIZATION.md for patterns

"I need more quota"
  ├─ Quota increase approved? → CTO approval (5 days)
  └─ Temporary exemption? → Lead approval (24 hours)
```

---

## Success Metrics (30 Days)

| Metric | Target | Owner |
|--------|--------|-------|
| Compliance | 100% repos | DevOps |
| Cost reduction | ↓40% | Finance |
| Budget adherence | ±10% | Finance |
| MTTR (cost spike) | <1 hour | DevOps |
| Team satisfaction | >90% | Eng Lead |

---

## Escalation Path

```
Issue Detected
    ↓
Team Lead Review (24-48 hrs)
    ↓
CTO Approval (if >$100 impact)
    ↓
Finance Notification (if >$500/mo impact)
    ↓
Implementation & Monitoring
```

---

## FAQ

**Q: Why are we doing this now?**  
A: GitHub Actions spend is unlimited without enforcement. We hit $500+/month in Q1.

**Q: Will this slow down development?**  
A: No — optimizations (caching, parallelization) often speed up builds.

**Q: What if I legitimately need more quota?**  
A: Submit exemption with business case. Approved within 24-48 hours if justified.

**Q: Are there penalties for going over quota?**  
A: No penalties — workflows auto-skip with team notification. Lead can approve override.

**Q: How long does onboarding take?**  
A: ~2 hours per repo (mostly automated by script).

**Q: What about legacy repos?**  
A: Exemptions available — document and request. Will be phased in by Q3.

---

## Support & Contact

**Slack**: `#devops-governance`  
**Email**: devops-team@example.com  
**Escalation**: CTO (cto@example.com)  
**On-call**: `pagerduty/devops` (for incidents)

---

## Next Steps

### This Week
1. Review this document + supporting links
2. Schedule team briefing (30 min)
3. Pilot 2-3 repos (identify issues)

### Next Week
1. Apply to all repositories start
2. Daily standup on blockers
3. Weekly cost report #1

### Week 3+
1. Achieve 100% compliance
2. Monitor & optimize
3. Celebrate cost savings

---

**Last Updated**: April 13, 2026  
**Next Review**: April 20, 2026  
**Version**: 1.0 (Stable)
