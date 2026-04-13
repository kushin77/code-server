# Repository Governor Onboarding Template

**Use this checklist when adding a new repository to the kushin77 organization.**

---

## 1. Pre-Governance Assessment

- [ ] Repository purpose understood
- [ ] Team/owner identified
- [ ] Current workflow count documented
- [ ] Estimated monthly Actions spend recorded
- [ ] Critical workflows identified

**Assessment Notes**:
```
Repository: ___________________________
Team: ___________________________
Workflows: ___________________________
Current Spend: $________________/month
```

---

## 2. Branch Protection Configuration

### Main Branch

Create/verify protection rules:

```bash
gh api repos/kushin77/$REPO/branches/main/protection \
  -X PUT \
  -F required_status_checks.strict=true \
  -F required_status_checks.contexts='["lint","unit-tests","security-scan"]' \
  -F required_pull_request_reviews.required_approving_review_count=1 \
  -F required_pull_request_reviews.dismiss_stale_reviews=true \
  -F required_pull_request_reviews.require_code_owner_review=false \
  -F enforce_admins=true \
  -F allow_force_pushes=false \
  -F allow_deletions=false
```

- [ ] Required status checks enabled
- [ ] Test checks: ✓ lint, ✓ tests, ✓ security
- [ ] Required approvals: 1
- [ ] Stale PR review dismissal: enabled
- [ ] Force push disabled
- [ ] Deletion protection enabled

---

## 3. Workflow Governance

### 3.1 Add Required Fields to All Workflows

Every workflow needs:

```yaml
name: CI Tests

env:
  COST_CATEGORY: "ci-tests"  # Required: categorize workflow

on:
  push:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15        # Required: set time limit

    steps:
      - uses: actions/checkout@v4
      - run: npm test
      
      - name: Cleanup           # Required: cleanup resources
        if: always()
        run: docker system prune -af
```

**Checklist**:
- [ ] All workflows have `COST_CATEGORY` env var
- [ ] All workflows have `timeout-minutes`
- [ ] All workflows have cleanup step
- [ ] No hardcoded secrets (use repo secrets)
- [ ] No HTTP URLs (must use HTTPS)
- [ ] No unbounded matrix jobs

### 3.2 Create Cost Estimate

```markdown
# Cost Estimate: [Repo Name]

## Monthly Workflow Cost Projection

| Workflow | Frequency | Duration | Monthly Runs | Cost (est) |
|----------|-----------|----------|--------------|-----------|
| CI Tests | per push | 10 min | 100 | $13.33 |
| CI Lint | per push | 5 min | 100 | $6.67 |
| Build & Push | per main push | 20 min | 10 | $2.67 |
| Deploy Staging | manual | 15 min | 4 | $0.80 |
| **TOTAL** | | | | **$23.47** |

## Budget Allocation

| Category | Quota | Budget |
|----------|-------|--------|
| ci-tests | 50/month | $6.67 |
| ci-lint | 50/month | $6.67 |
| ci-build | 10/month | $2.67 |
| deploy-staging | 4/month | $0.80 |
| **TOTAL** | | **$17** |

## Contingency

Buffer: +$5 (unexpected runs)
Monthly limit: **$22**
```

- [ ] Cost estimate created
- [ ] Budget allocation documented
- [ ] Contingency buffer added (10-20%)
- [ ] Owner acknowledges and approves

---

## 4. API & Secret Management

### 4.1 Scan for Hardcoded Secrets

```bash
# Scan for common patterns
git log -p | grep -E "password|api_key|token|secret" || \
git grep -E "password|api_key|token|secret"
```

- [ ] Repository scanned
- [ ] No hardcoded secrets found
- [ ] All secrets in GitHub secrets manager
- [ ] Rotation schedule documented

### 4.2 Document External APIs

List all external APIs used in CI/CD:

```markdown
## External API Usage

### Approved (Production)
- [ ] GitHub API (included)
- [ ] Cloudflare API (included)
- [ ] GCP APIs (via landing zone)

### Development Only
- None

### In Review
- None
```

- [ ] All APIs documented
- [ ] All APIs approved
- [ ] Rate limits understood
- [ ] Cost tracking enabled

---

## 5. Documentation

### 5.1 Create .github/README.md

```markdown
# CI/CD Pipeline

## Workflows

- **CI Tests**: Runs on every push (10 min)
- **CI Lint**: Runs on every push (5 min)
- **Build & Push**: Runs after merge to main (20 min)
- **Deploy Staging**: Manual workflow (15 min)

## Adding a New Workflow

1. Copy template: `TEMPLATE-*.yml`
2. Customize with repo-specific settings
3. Add `COST_CATEGORY` env var
4. Set reasonable `timeout-minutes`
5. Add cleanup step
6. Document in this README
7. Create PR with new workflow
8. Ask devops-team for review

## Cost Estimate

Total monthly: $23.47 (see COST-ESTIMATE.md)

## Troubleshooting

- Check Actions tab for logs
- Long runs? Parallelize or optimize dependencies
- Failures? Check status checks
- Cost spike? See COST-ESTIMATE.md and notify team

## Contact

- Workflow maintainer: @username
- Team lead: @team-lead
- Help: Post in #devops-governance
```

- [ ] Pipeline documentation created
- [ ] Workflow templates documented
- [ ] Cost estimate linked
- [ ] Contact info provided

### 5.2 Create COST-ESTIMATE.md

(See section 3.2 above)

- [ ] Cost estimate document created
- [ ] Monthly budget defined
- [ ] Owner approved

---

## 6. Testing & Validation

### 6.1 Test Branch Protection

```bash
# Create a test branch and try to push without approval
git checkout -b test/governance
echo "test" >> README.md
git commit -am "Test push"
git push origin test/governance

# Create a PR (should require approval)
gh pr create --title "Test PR" --body "Testing governance"

# Try to merge without approval (should fail)
gh pr merge --auto 2>/dev/null || echo "✓ Merge blocked (expected)"

# Clean up
gh pr close --delete-branch
```

- [ ] Branch protection tested
- [ ] PR approval required works
- [ ] Force push blocked
- [ ] Clean up test artifacts

### 6.2 Run Cost Estimation

```bash
# Estimate weekly cost
gh api repos/kushin77/$REPO/actions/runs \
  -F per_page=50 \
  --jq '[.workflow_runs[] | select(.updated_at > (now - 7*24*60*60 | todate))] | length' \
  > weekly_runs

WEEKLY_RUNS=$(cat weekly_runs)
ESTIMATED_WEEKLY=$((WEEKLY_RUNS * 15 * 0.008))  # Assume 15 min avg, $0.008/min
echo "Estimated weekly cost: $$ESTIMATED_WEEKLY"
```

- [ ] Cost estimate calculated
- [ ] Baseline metrics recorded
- [ ] Targets set for optimization

---

## 7. Compliance Sign-Off

### Team Lead Review

- [ ] Branch protection configured correctly
- [ ] All workflows compliant
- [ ] Cost estimate reasonable
- [ ] Documentation complete
- [ ] No security issues

**Reviewed by**: ________________  **Date**: ________

**Comments**:
```
[Add any notes or recommendations]
```

### Governance Team Review

- [ ] Follows organization standards
- [ ] Budget within limits
- [ ] No prohibited patterns
- [ ] Approved for production use

**Approved by**: ________________  **Date**: ________

**Approval ID**: [Link to approval issue/comment]

---

## 8. Post-Onboarding

### Ongoing Monitoring

- [ ] Cost monitoring enabled (auto)
- [ ] Weekly cost reports enabled (auto)
- [ ] Compliance checks enabled (auto)
- [ ] Alerts configured (auto)

### Monthly Review

**Action Items for Month 1**:
1. Monitor cost vs. estimate
2. Resolve any governance violations
3. Optimize slow workflows
4. Document lessons learned

---

## 9. Help & Support

### Common Issues

**Q: One of my workflows is timing out**
A: If workflow normally takes >20 min, request exemption with business justification.

**Q: My cost estimate seems high**
A: Check for parallel matrix jobs, unused dependencies, or frequent pushes. Optimize first, then document.

**Q: I need to call an unapproved API**
A: Post in #devops-governance with business case, cost estimate, and timeline. Review takes 48 hours.

### Resources

- Governance framework: [.github/GOVERNANCE.md](../.github/GOVERNANCE.md)
- Rules & quotas: [config/github-rules.yaml](../../config/github-rules.yaml)
- Rollout timeline: [GOVERNANCE-ROLLOUT.md](../../GOVERNANCE-ROLLOUT.md)
- Templates: `.github/workflows/TEMPLATE-*.yml`

### Support Channels

- Questions: `#devops-governance` Slack
- Issues: GitHub issues labeled `governance`
- Escalations: email devops-team@example.com

---

## Completion

This repository is **governance-compliant** when all checkboxes are marked.

**Overall Status**: ☐ In Progress  ☐ Complete  ☐ Exception

**Completion Date**: _______________

**Notes for Future Reference**:
```
[Add any repository-specific notes, decisions, or patterns]
```
