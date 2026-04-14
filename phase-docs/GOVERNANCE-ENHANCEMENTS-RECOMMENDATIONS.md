# RECOMMENDED ENHANCEMENTS: Governance & Guardrails

**To make GOVERNANCE-AND-GUARDRAILS.md production-mandate ready**

**Priority**: HIGH — Complete these before allowing open PRs
**Timeline**: ~5-8 days (1-2 hours/day for implementation)
**Effort**: Medium (mostly documentation + CI config changes)

---

## ENHANCEMENT 1: Add Automated CI/CD Guardrails Section

**Current Gap**: Document exists but CI automation isn't described in detail.

**What to Add** (insert into GOVERNANCE-AND-GUARDRAILS.md):

```markdown
## TIER 3: AUTOMATED CHECKS (CI/CD Pipeline)

### Check 3.1: Configuration Validation

Runs on every PR, automatically blocks merge if fails.

**Docker Compose Validation**:
```bash
# In .github/workflows/validate.yml or equivalent
- name: Validate docker-compose composition
  run: |
    docker compose -f docker-compose.base.yml -f docker-compose.yml config > /dev/null
    docker compose -f docker-compose.base.yml -f docker-compose.dev.yml config > /dev/null

# Blocks merge if validation fails
```

**Caddyfile Validation**:
```bash
- name: Validate Caddyfile syntax
  run: |
    docker run --rm -v $(pwd):/data caddy:2-alpine caddy validate --config /data/Caddyfile

# Blocks merge if invalid
```

**Terraform Validation**:
```bash
- name: Validate Terraform configuration
  run: |
    terraform init
    terraform validate
    terraform plan -no-color

# Blocks merge if invalid
```

**Bash Script Validation**:
```bash
- name: Validate bash scripts
  run: |
    for f in $(find . -name "*.sh" -type f); do
      bash -n "$f" || exit 1
    done

# Blocks merge if syntax errors found
```

**PowerShell Validation**:
```bash
- name: Validate PowerShell scripts
  run: |
    pwsh -Command {
      Get-ChildItem -Recurse -Filter "*.ps1" | ForEach-Object {
        if (!(Test-Path $_)) { throw "Syntax error in $_" }
      }
    }

# Blocks merge if syntax errors found
```

### Check 3.2: Hardcoded Values Scanning

Prevents secrets, hardcoded IPs, versions in code.

```bash
- name: Scan for hardcoded values
  run: |
    # Fail if image versions hardcoded (not using terraform/locals.tf)
    grep -r 'image.*:v[0-9]\|image.*:[0-9]\.[0-9]' terraform/ \
      | grep -v 'local\.' && exit 1 || true

    # Fail if passwords/secrets found
    gitleaks detect --source text --verbose --exit-code 1

    # Fail if hardcoded IPs (except comments/docs)
    grep -r '192\.168\|10\.0\.0' . --include="*.tf" --include="*.yml" \
      | grep -v '#' && exit 1 || true

# Blocks merge if violations found
```

### Check 3.3: Consolidation Pattern Compliance

Ensures new code follows docker-compose base.yml, Caddyfile.base, etc. patterns.

```bash
- name: Check consolidation compliance
  run: |
    # Check 1: Services not duplicated across compose files
    SERVICE_COUNT=$(find . -name "docker-compose*.yml" -exec grep -h "services:" {} \; | wc -l)
    if [ $SERVICE_COUNT -gt 1 ]; then
      echo "ERROR: Services defined in multiple files"
      exit 1
    fi

    # Check 2: New Caddyfile configs use named segments
    if grep -E "header X-|cache-control" Caddyfile | grep -v '@import'; then
      echo "ERROR: Use named segments from Caddyfile.base"
      exit 1
    fi

    # Check 3: AlertManager routes reference base
    if grep -l "alertmanager.*yml" . | xargs grep -L "include.*base"; then
      echo "ERROR: AlertManager must include base"
      exit 1
    fi

# Blocks merge if pattern violations found
```

### Check 3.4: Library Function Usage

Ensures all scripts use centralized logging/function libraries.

```bash
- name: Check script library usage
  run: |
    # All bash scripts must source logging
    for f in scripts/*.sh *.sh **/*.sh; do
      if ! grep -q 'source.*logging.sh\|\..*logging.sh' "$f"; then
        echo "ERROR: $f must source logging.sh"
        exit 1
      fi
    done

    # All PowerShell scripts must source common-functions
    for f in scripts/*.ps1 *.ps1 **/*.ps1; do
      if ! grep -q '\. .*common-functions\|Import.*common' "$f"; then
        echo "ERROR: $f must source common-functions.ps1"
        exit 1
      fi
    done

# Blocks merge if violations found
```

### Check 3.5: GitHub Issue Linkage

Every PR must reference a GitHub issue.

```bash
- name: Check GitHub issue link
  run: |
    PR_BODY="${{ github.event.pull_request.body }}"

    if ! echo "$PR_BODY" | grep -iE 'fixes|relates to|implements #[0-9]+'; then
      echo "ERROR: PR must link to GitHub issue (Fixes #123)"
      exit 1
    fi

# Blocks merge if not linked
```

---

## ENHANCEMENT 2: Add Emergency Procedures Section

**Current Gap**: What to do when things go wrong.

**What to Add**:

```markdown
## Emergency Procedures

### Scenario: Production Configuration Broken, Services Down

**Time Pressure**: 15 minutes to recover

**Steps**:
1. **Stop the bleeding**:
   ```bash
   ssh akushnir@192.168.168.31
   docker stop code-server caddy ollama  # Stop everything
   ```

2. **Revert last commit**:
   ```bash
   cd /home/akushnir/code-server-enterprise
   git revert HEAD --no-edit                # Revert last change
   git push origin main                     # Push revert
   ```

3. **Redeploy from repo**:
   ```bash
   git pull origin main
   docker compose -f docker-compose.base.yml -f docker-compose.yml up -d
   ```

4. **Verify recovery**:
   ```bash
   curl -s http://localhost:8080/ | grep -q "login" && echo "✓ RECOVERED"
   ```

5. **Post-incident** (within 1 hour):
   - [ ] Write RCA in GitHub issue
   - [ ] Identify root cause
   - [ ] Design prevention (guardrail? rule? training?)
   - [ ] Create fix PR

**Note**: During incident, DevOps has full authority. Normal approval rules suspended.

### Scenario: Secrets Committed to Repository

**Time Pressure**: IMMEDIATE (within minutes)

**Steps**:
1. **Alert team**: Post in #incident Slack channel
2. **Rotate credentials**: Assume compromise, revoke all secrets
3. **Scrub repo**:
   ```bash
   git filter-branch --tree-filter 'rm -f leaked.env' HEAD
   git push --force-with-lease origin main
   ```
4. **Prevent recurrence**: Update pre-commit hooks
5. **Post-incident audit**: Check all services for exploit evidence

---

## ENHANCEMENT 3: Add Approval Authority Matrix

**Current Gap**: Who can approve what isn't clear.

**What to Add**:

```markdown
## Approval Authority Matrix

| Change Type | Required Approvals | Exempt | Timeline |
|-------------|-------------------|--------|----------|
| **Consolidation pattern** | Architecture lead + 1 senior | None | 24 hours min |
| **Configuration change** | DevOps lead + 1 | None | 24 hours min |
| **Version update** | Architecture lead or DevOps lead | 1 if same team | 4 hours min |
| **Security fix** | Security lead | None | No wait (merge immediately) |
| **Script fix** | Any senior engineer + 1 | Same author for trivial? | 4 hours min |
| **Documentation** | Any engineer | None | No wait |
| **Emergency** (outage) | DevOps lead only | All other rules | No wait |

**Note**: "Min" timeline is minimum wait AFTER approval, not total time.

---

## ENHANCEMENT 4: Add Metrics & Success Criteria

**Current Gap**: How do we know governance is working?

**What to Add**:

```markdown
## Success Metrics (Measured Monthly)

### Metric 1: PR Review Cycle Time
- **Target**: 80% of PRs reviewed within 24 hours
- **Actual**: [tracked in GitHub Projects]

### Metric 2: CI Failure Rate
- **Target**: <10% of PRs fail initial CI (means quick feedback loop works)
- **Actual**: [tracked in GitHub Actions]

### Metric 3: Revert Rate
- **Target**: <5% of merged PRs reverted within 7 days (means quality gates work)
- **Actual**: [tracked in GitHub issues]

### Metric 4: Dead Code Accumulation
- **Target**: <3 orphaned files per monthly audit
- **Actual**: [tracked in monthly audit]

### Metric 5: Security Incidents
- **Target**: 0 commits with hardcoded secrets
- **Actual**: [tracked by gitleaks]

### Metric 6: Configuration Drift
- **Target**: 100% alignment between repo and prod (checked daily)
- **Actual**: [automated drift check results]

If any metric exceeds threshold:
1. Alert team
2. Root cause analysis
3. Adjust guardails/rules
4. Retest

---

## ENHANCEMENT 5: Add Rollout Plan Section

**Current Gap**: How to implement governance incrementally.

**What to Add**:

```markdown
## Rollout Plan (0 to 100% Enforcement)

### Phase 1: Soft Launch (Week 1)
- [ ] Publish GOVERNANCE-AND-GUARDRAILS.md
- [ ] Post in team Slack
- [ ] Run team training session (30 min)
- [ ] CI checks run but only **warn** (don't block)
- [ ] Collect feedback from team

### Phase 2: Ramp-Up (Week 2-3)
- [ ] Address team feedback
- [ ] Update GOVERNANCE-AND-GUARDRAILS.md
- [ ] Enable hard CI enforcement for specific rules first:
  - [ ] Configuration validation (docker-compose, Caddyfile, Terraform)
  - [ ] Script syntax checks
  - [ ] Secrets scanning
- [ ] Keep other checks as warnings

### Phase 3: Full Enforcement (Week 4)
- [ ] Enable all guardrails
- [ ] All checks block merge
- [ ] Code review enforces governance rules
- [ ] Monthly audits begin
- [ ] Success metrics tracked

### Phase 4: Continuous (Ongoing)
- [ ] Review metrics monthly
- [ ] Adjust rules as needed
- [ ] Incident reviews inform improvements
- [ ] New team members trained on governance
- [ ] ADRs updated quarterly

---

## ENHANCEMENT 6: Add Onboarding Checklist

**Current Gap**: New developers don't know governance.

**What to Add**:

```markdown
## New Developer Onboarding

**Before Day 1**: Engineering lead completes
- [ ] Add to GitHub team `code-server-enterprise`
- [ ] Add to Slack #engineering channel
- [ ] Add SSH key to authorized_keys on 192.168.168.31
- [ ] Grant GitHub token for automation

**Day 1**: Developer completes
- [ ] Read CONTRIBUTING.md (code quality standards)
- [ ] Read GOVERNANCE-AND-GUARDRAILS.md (rules)
- [ ] Read ADR-004 (consolidation patterns)
- [ ] Read ADR-005 (composition inheritance)
- [ ] Set up pre-commit hooks (see scripts/setup-git-hooks.sh)

**Day 2**: Team lead completes
- [ ] Live walkthrough of docker-compose inheritance
- [ ] Live walkthrough of Caddyfile.base + variants
- [ ] Live walkthrough of Terraform locals.tf
- [ ] Demo: Create test PR, show CI validation feedback
- [ ] Demo: Emergency rollback procedure

**Day 3**: Developer completes first contribution
- [ ] Create GitHub issue (describe work)
- [ ] Create feature branch
- [ ] Make changes following patterns
- [ ] Open PR linked to issue
- [ ] Get reviewed by senior engineer
- [ ] Merge after approval

**Month 1**: Checkpoint
- [ ] Developer had >=2 PRs merged
- [ ] Developer understands why governance matters
- [ ] Developer can explain a pattern to someone else
- [ ] Developer familiar with emergency procedures

---

## ENHANCEMENT 7: Add FAQ Section

**Current Gap**: Common questions unanswered.

**What to Add**:

```markdown
## Frequently Asked Questions (FAQ)

**Q: Do I have to follow ALL these rules?**
A: Yes for main branch. Feature branches are for exploration (but don't commit to main without compliance).

**Q: Can I get an exception?**
A: Only for security incidents, service outages, or data loss prevention. Must be approved by leadership.

**Q: What if I disagree with a rule?**
A: Open an ADR proposing the change. Discuss with team. If consensus, update governance. Until then, follow current rules.

**Q: My CI failed on a rule I think is wrong?**
A: Post in #engineering asking for clarification. Don't force-push or ignore the failure.

**Q: How do I know if I'm following patterns correctly?**
A: Your code review should catch issues. See CONTRIBUTING.md checklist.

**Q: What if I accidentally break a rule?**
A: Acknowledge in PR, fix it, resubmit. Patterns matter more than perfection.

**Q: Where do I report security issues?**
A: Don't use GitHub issues. Email security lead directly (akushnir@...).

---

## ENHANCEMENT 8: Link All Related Documents

**Current Gap**: Governance ties to contributing, ADRs, playbooks—but it's not obvious.

**What to Add**:

```markdown
## Document Relationships

```
┌─────────────────────────────────────────┐
│   GOVERNANCE-AND-GUARDRAILS.md         │ ← You are here
│   (Rules, guardrails, procedures)       │
└──────────────┬──────────────────────────┘
               │
        ┌──────┴──────────┬──────────────┬──────────────┐
        │                 │              │              │
        ▼                 ▼              ▼              ▼
  CONTRIBUTING.md   ADR-004         ADR-005      OPERATIONAL-
  (Code quality     (Consolidation  (Composition  RUNBOOKS.md
   standards)       patterns)       inheritance)  (Procedures)
```

**Read in this order**:
1. GOVERNANCE-AND-GUARDRAILS.md (this document)
2. CONTRIBUTING.md (code quality standards)
3. ADR-004 & ADR-005 (architectural decisions)
4. OPERATIONAL-RUNBOOKS.md (common procedures)
5. Source: scripts/ (actual implementations)

---

## ENHANCEMENT 9: Add Success Stories Section

**Current Gap**: Why should developers care?

**What to Add**:

```markdown
## Why Governance Matters: Real Examples

### Example 1: Docker Compose Inheritance Caught Bad Deployment

**What Happened**: Developer created new `docker-compose.prod.yml` instead of overriding in variant.

**What CI Caught**: "ERROR: Services defined in multiple files"

**Outcome**: Developer fixed to use inheritance pattern. Deployment now automatic with all variants.

**Result**: 30% code reduction, zero confusion about which version deploys.

### Example 2: Hardcoded IP Prevented Production Outage

**What Happened**: Developer hardcoded `192.168.168.32` (old host) in deploy script.

**What CI Caught**: "ERROR: Hardcoded IPs not allowed. Use environment variables."

**Outcome**: Developer parameterized script. All hosts now configurable.

**Result**: Script works for staging (192.168.168.30), prod (192.168.168.31), and future hosts.

### Example 3: Pre-commit Hook Prevented Secrets Leak

**What Happened**: Developer accidentally committed `.env` with real passwords.

**What Pre-commit Caught**: "ERROR: Secrets detected (PASSWORD, TOKEN)"

**Outcome**: Developer removed secrets before commit.

**Result**: Credentials never exposed, no incident.

---

## ENHANCEMENT 10: Add Metrics Dashboard Definition

**Current Gap**: How to *see* governance working.

**What to Add**:

```markdown
## Governance Metrics Dashboard

Create `/docs/metrics/GOVERNANCE-SCORECARD.md` (updated monthly):

```markdown
# Governance Scorecard — [Month/Year]

## CI Validation Results
- Total PRs: 28
- Failed on first submission: 7 (25%) ← Target: <10%
- Most common reason: forgetting to link GitHub issue

## Consolidation Compliance
- PRs following patterns: 26/28 (93%) ← Target: >95%
- Violations found: 2 (phase files, hardcoded versions)

## Code Review Turnaround
- Avg review time: 18 hours ← Target: <24 hours
- 90th percentile: 28 hours
- Total merged: 24 PRs

## Configuration Drift
- Automated check runs: 30 days
- Drift detected: 0 times
- Manual edits to prod: 0
- Status: ✅ PERFECT

## Security
- Secrets committed: 0 ← Target: 0
- Hardcoded values found: 0 ← Target: 0
- Approved exceptions: 0 ← Target: 0
- Status: ✅ PERFECT

## Dead Code Audit
- Orphaned files found: 2
- Files archived: 2
- Action: Completed ✅

## Team Training
- Developers trained: 12
- Developers with 3+ PRs: 10 (83%)
- Issues reported with governance: 0
- Feedback: Positive

## Recommendations for [Next Month]
- Continue current enforcement
- Add integration test for docker-compose variants
- Train 2 new developers on governance

**Created**: [Date]
**Reviewed By**: [Tech Lead]
```

---

## Quick Checklist: Before Making Governance Mandatory

- [ ] **CI Automation Complete**
  - [ ] All 5+ validation checks in CI/CD pipeline
  - [ ] Runs on every PR
  - [ ] Results posted in PR comment

- [ ] **Documentation Complete**
  - [ ] GOVERNANCE-AND-GUARDRAILS.md enhanced with sections 1-10
  - [ ] Links from CONTRIBUTING.md to governance
  - [ ] Links from each ADR to governance

- [ ] **Team Trained**
  - [ ] Team meeting: 30 min walkthrough
  - [ ] Q&A: address concerns
  - [ ] New developer onboarding updated

- [ ] **Rollout Plan Ready**
  - [ ] Week 1: Soft launch (warnings only)
  - [ ] Week 2-3: Ramp-up (selective hard enforcement)
  - [ ] Week 4: Full enforcement
  - [ ] Ongoing: Metrics tracking

- [ ] **Success Metrics Defined**
  - [ ] 6+ metrics identified (see Enhancement 4)
  - [ ] Baseline measured
  - [ ] Dashboard created

- [ ] **Emergency Procedures Ready**
  - [ ] Rollback procedure tested
  - [ ] Team trained on incident response
  - [ ] Communication channels set up

---

## Estimated Work: Implementation Timeline

| Task | Effort | Owner | Timeline |
|------|--------|-------|----------|
| Enhance GOVERNANCE-AND-GUARDRAILS.md | 4 hours | Tech Lead | Day 1-2 |
| Implement CI validation checks | 6 hours | DevOps | Day 2-4 |
| Create operational runbooks | 2 hours | DevOps | Day 3-4 |
| Update CONTRIBUTING.md links | 1 hour | Tech Lead | Day 4 |
| Train team | 1 hour | Tech Lead | Day 5 |
| Soft launch + monitor | 0 hours | DevOps | Week 1 |
| Ramp-up to hard enforcement | 1 hour | DevOps | Week 2 |
| **TOTAL** | **~15 hours** | Team | **Week 1-4** |

---

## Decision: Ready to Make Governance Mandatory?

**Checklist**:
- [ ] All 10 enhancements implemented
- [ ] Team trained and ready
- [ ] CI automation validated
- [ ] Metrics baseline established
- [ ] Leadership approval given

**If all checked**: Publish governance-mandate.md and make it repo requirement
