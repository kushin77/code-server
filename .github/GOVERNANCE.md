# GitHub Actions & API Governance Framework

**Purpose**: Control GitHub Actions sprawl, API costs, and enforce organizational standards across all repositories.

## Executive Summary

- **Problem**: Unlimited Actions runs, uncontrolled API calls, orphaned workflows costing $$$
- **Solution**: Repository-level rules, workflow quotas, approval gates, and automated enforcement
- **Timeline**: 30-day rollout with monitoring and adjustment

---

## 1. Cost Control Mechanisms

### 1.1 Workflow Execution Limits

| Trigger | Max/Month | Max/Day | Max/Hour | Notes |
|---------|-----------|---------|----------|-------|
| `push` | 500 | 50 | 10 | Prevents CI thrashing |
| `pull_request` | 300 | 30 | 5 | Code review workflows |
| `schedule` | 100 | 4 | 1 | Cron jobs (limited) |
| `workflow_dispatch` | 50 | 10 | 2 | Manual triggers (audited) |
| `repository_dispatch` | 25 | 5 | 1 | External signals (strict) |

**Enforcement**: 
- GitHub API rate limiter + custom quota service
- Auto-disable workflows exceeding limits
- Slack notifications to team leads

### 1.2 Runner Resource Constraints

**GitHub-Hosted Runners**:
- Max 6 concurrent jobs per workflow
- Max 360 minutes/month per repository
- 2 CPU, 7 GB RAM default

**Self-Hosted Runners** (if used):
- CPU: 4-core minimum, 8-core maximum
- Memory: 16 GB limit with swapfile disabled
- Disk: 50 GB workspace cleanup on completion
- Timeout: 6 hours absolute maximum

### 1.3 API Rate Limiting

**Per-Repository Limits**:
- GraphQL API: 5,000 points/hour
- REST API: 5,000 requests/hour (vs GitHub's 60 default)
- Workflow logs retention: 90 days (auto-purge)

**Monitoring**:
- Rate limit tracking via `X-RateLimit-*` headers
- Alerting at 80%, auto-throttle at 90%
- Weekly cost reports by workflow

---

## 2. Repository Rules & Enforcement

### 2.1 Branch Protection Rules

**All Repositories** inherit these standards:

```yaml
main:
  required_status_checks:
    - lint (required)
    - unit-tests (required)
    - security-scan (required)
  required_approvals: 1
  dismiss_stale_reviews: true
  require_code_owner_review: false
  restrict_dismissals: true
  allow_force_pushes: false
  allow_deletions: false

develop:
  required_status_checks:
    - unit-tests (required)
  required_approvals: 0
  allow_force_pushes: true
  allow_deletions: true
```

### 2.2 Workflow Standards

**All workflows** must:

1. **Define resource limits**:
   ```yaml
   jobs:
     test:
       runs-on: ubuntu-latest
       timeout-minutes: 15
   ```

2. **Include step-level timeouts**:
   ```yaml
   - name: Test
     run: npm test
     timeout-minutes: 10
   ```

3. **Tag with cost category**:
   ```yaml
   env:
     COST_CATEGORY: "ci-tests"  # ci-tests, builds, deploys, scheduled, manual
   ```

4. **Report metrics**:
   ```yaml
   - name: Report metrics
     run: |
       echo "::notice::Duration: ${GITHUB_RUN_DURATION}s"
       echo "::notice::Cost-Category: ci-tests"
   ```

5. **Cleanup resources**:
   ```yaml
   - name: Cleanup
     if: always()
     run: docker system prune -af
   ```

### 2.3 Workflow Categories & Quotas

```
┌─────────────────────────────────────────────────────────┐
│  WORKFLOW CATEGORY      │  PURPOSE              │ QUOTA  │
├─────────────────────────────────────────────────────────┤
│  ci-tests               │  Unit/Integration     │ 300/mo │
│  ci-lint                │  Linting/Format       │ 200/mo │
│  ci-security            │  SAST/DAST/Scanning   │ 150/mo │
│  ci-build               │  Artifacts/Images     │ 100/mo │
│  deploy-staging         │  Manual staging       │  50/mo │
│  deploy-prod            │  Automatic production │  30/mo │
│  scheduled-jobs         │  Cron tasks           │  20/mo │
│  manual-admin           │  Admin tasks          │  25/mo │
│  experimental           │  POCs/Testing         │  50/mo │
└─────────────────────────────────────────────────────────┘
```

---

## 3. API Sprawl Prevention

### 3.1 Approved External APIs

**Production-Approved**:
- ✅ GitHub API (REST + GraphQL)
- ✅ Cloudflare API (for routing/security)
- ✅ GCP APIs (defined in landing zone)
- ✅ Slack API (notifications only)
- ✅ Docker Registry API (image pulls)

**Development/Testing**:
- ⚠️ OpenAI/Claude APIs (quota: $500/month per team)
- ⚠️ External SaaS tools (must have cost forecast)

**Forbidden**:
- ❌ Undocumented external API calls
- ❌ Commercial services without approval
- ❌ Third-party CI/CD overlays

### 3.2 API Governance Gates

```
Code Review
    ↓
    ├─→ Detect new API calls (grep for http://, curl, requests)
    ↓
Approval Matrix
    ├─→ <$0:      Auto-approve (internal APIs)
    ├─→ $1-100:   Lead approval
    ├─→ $100+:    CTO approval + budget tracking
    ↓
Cost Modeling
    ├─→ Monthly forecast
    ├─→ Alert at 80% of budget
    ├─→ Hard stop at 100%
    ↓
Continuous Monitoring
    └─→ Slack alerts + weekly reports
```

---

## 4. Governance Policies

### 4.1 Approval Requirements

| Change Type | Approval Required | Timeline | Cost Impact Check |
|-------------|-------------------|----------|-------------------|
| New workflow | Lead | 24hrs | Required if >$50/mo |
| Workflow delete | None | Immediate | None |
| API endpoint add | Lead | 48hrs | Required if >$10/mo |
| Quota increase | CTO | 5 business days | Required |
| Budget override | Finance | 7 business days | Mandatory |

### 4.2 Audit & Compliance

**Monthly Audits**:
1. Unused workflows (disabled >30 days) → auto-delete
2. Failed runs (>10 consecutive failures) → disable + notify owner
3. Orphaned artifacts (>90 days old) → delete
4. API overspending (>10% of budget) → investigate

**Quarterly Reviews**:
1. Cost trend analysis
2. Resource utilization vs. team size
3. ROI by workflow category
4. Optimization recommendations

### 4.3 Incident Response

**Threshold Alerts**:
- **🔴 Critical**: Monthly spend >150% of budget → immediate action
  - Disable non-essential workflows
  - Investigate new api calls
  - Escalate to CTO
  
- **🟠 High**: Monthly spend 100-150% of budget → 24-hour review
  - Identify cost drivers
  - Plan optimization
  - Notify team leads

- **🟡 Medium**: Monthly spend 80-100% of budget → discuss in standup
  - Forecast next 2 weeks
  - Plan optimizations
  - Adjust quotas if needed

---

## 5. Repository Onboarding Checklist

New repos must follow this checklist before merge:

```
GOVERNANCE COMPLIANCE CHECKLIST
───────────────────────────────────────────────────

Repository: _______________________
Owner: _______________________

BRANCH PROTECTION
─────────────────
□ main branch protected
□ require_status_checks enabled (lint, test, security)
□ required_approvals = 1
□ dismiss_stale_reviews = true
□ allow_force_pushes = false
□ allow_deletions = false

WORKFLOWS
─────────
□ All workflows have timeout-minutes defined
□ All workflows tagged with COST_CATEGORY
□ No hardcoded secrets (use Action secrets)
□ No external API calls without approval
□ Cleanup step in each workflow (if applicable)
□ Resource limits defined (no unbounded parallelism)

MONITORING & ALERTING
──────────────────────
□ Failed runs trigger Slack alerts
□ Cost metrics exported weekly
□ Workflow quota tracked
□ API rate limits monitored

DOCUMENTATION
──────────────
□ README includes CI/CD pipeline overview
□ Workflow documentation in .github/workflows/README.md
□ Budget forecast documented
□ SLA for deployments defined

APPROVAL
─────────
Approved by: _______________  Date: _______________
  (Team Lead or CTO)
```

---

## 6. Configuration Files

See companion files:
- [config/github-rules.yaml](../config/github-rules.yaml) - Repository rules definitions
- [scripts/enforce-governance.sh](../scripts/enforce-governance.sh) - Enforcement script
- [.github/cost-monitor.yml](.github/cost-monitor.yml) - Cost tracking workflow
- [.github/enforcement.yml](.github/enforcement.yml) - Automated policy enforcement

---

## 7. Success Metrics

| Metric | Target | Current | Owner |
|--------|--------|---------|-------|
| Monthly Actions cost | <$500 | TBD | DevOps Lead |
| > Workflow CPU utilization | >70% | TBD | Eng Manager |
| Failed run rate | <2% | TBD | QA Lead |
| Mean time to detect cost spike | <1hr | TBD | DevOps Lead |
| Governance compliance | 100% repos | TBD | CTO |

---

## 8. Implementation Timeline

**Week 1**: Rules definition & automation
**Week 2**: Repository onboarding + enforcement
**Week 3**: Monitoring & alerting setup
**Week 4**: Review, tune, and document

See [GOVERNANCE-ROLLOUT.md](GOVERNANCE-ROLLOUT.md) for detailed timeline.
