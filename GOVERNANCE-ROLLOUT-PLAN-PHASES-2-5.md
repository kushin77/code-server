# Governance Rollout Plan: Phases 2-5 Implementation Guide

**Document**: Governance & Guardrails Rollout Plan  
**Status**: Phase 2 Complete ✅ | Phases 3-5 In Planning  
**Timeline**: April 14 - May 2, 2026  
**Owner**: @kushin77 (DevOps/Platform Lead)  

---

## Master Timeline

| Phase | Dates | Focus | Owner | Status |
|-------|-------|-------|-------|--------|
| Phase 2 | Apr 14-21 | CI validation workflow | @kushin77 | ✅ Deployed |
| Phase 3 | Apr 21-28 | Governance rollout | @kushin77 | ⏳ Next |
| Phase 4 | Apr 25-May 2 | Enforcement ramp-up | @kushin77 | 📋 Ready |
| Phase 5 | May 2+ | Full enforcement | @kushin77 | 📋 Ready |

---

## Phase 2: CI Validation Deployment (April 14-21)

### ✅ COMPLETE - April 14 @ 13:37 UTC

**Deployment**: `.github/workflows/validate-config.yml`

**What Was Deployed**:
- Docker Compose syntax validation
- Caddyfile (Caddy v2) validation
- Terraform format & validation
- Shell script syntax checking + ShellCheck
- Secrets scanning (TruffleHog + patterns)
- Obsolete file detection
- Configuration composition testing

**Next Steps** (This Week):

1. **Enable PR Status Checks** (April 17)
   ```
   Settings → Branches → main
   → Require status checks to pass before merging
   → Select: "configuration-validation" workflow jobs
   ```

2. **Create Test PR** (April 17-18)
   - Modify docker-compose.yml → Should PASS
   - Modify Caddyfile → Should PASS
   - Add plaintext "secret" → Should FAIL secrets scanning
   - Verify all checks run and report properly

3. **Team Notification** (April 18)
   - Post in #engineering Slack channel
   - Link to CONTRIBUTING.md CI section
   - Explain why checks are running (non-blocking preview)

4. **Collect Feedback** (April 19-21)
   - Ask team: Any false positives?
   - Ask: Are validation messages clear?
   - Ask: Missing any important checks?

**Success Criteria**:
- [x] Workflow deployed and running
- [ ] Status checks enabled on main
- [ ] Test PR confirms all jobs execute
- [ ] Team feedback collected
- [ ] Workflow refined based on feedback

---

## Phase 3: Governance Implementation (April 21-28)

### Objective
Roll out governance rules and team training with **soft enforcement** (checks warn but don't block).

### Step 1: Team Training (April 21, ~30 minutes)

**Preparation**:
- Review [GOVERNANCE-AND-GUARDRAILS.md](./GOVERNANCE-AND-GUARDRAILS.md)
- Prepare 5-slide deck:
  1. Why governance matters (2 min)
  2. New CI checks explained (5 min)
  3. What violations look like (5 min)
  4. How to fix violations (3 min)
  5. Q&A (5 min)

**Training Agenda**:
```
Time: April 21 2PM UTC (10AM EDT / 7AM PDT)
Duration: 30 minutes
Audience: All engineers
Format: Video call + Slack Q&A

Topics:
1. No hardcoded secrets in files
   - Why: Prevent credential leakage to git
   - Example: API_KEY="sk-..." is detected and blocked
   - How to fix: Use .env files (gitignore) or Vault
   
2. Configuration must validate
   - Why: Prevent deployment failures
   - Example: docker-compose.yml must have valid YAML
   - How to fix: Run locally: `docker-compose config`
   
3. Scripts must pass syntax checks
   - Why: Prevent runtime failures
   - Example: bash -n script.sh must pass
   - How to fix: Test locally before PR
   
4. Terraform must validate
   - Why: Prevent infrastructure errors
   - Example: terraform validate must pass
   - How to fix: Run in terraform/ directory
   
5. Obsolete files detection
   - Why: Keep codebase clean
   - Example: don't merge phase-15-docker-compose.yml
   - How to fix: Archive to archived/ subdirectory
```

**After Training**:
- Post training slides in #engineering
- Link to governance docs
- Open Q&A: "Governance Questions?" thread in Slack

### Step 2: Publish Governance Document (April 22)

**Action**: Post final version of GOVERNANCE-AND-GUARDRAILS.md

**Content**:
- What rules are enforced
- Why each rule exists
- How to comply
- Common violations & fixes
- Escalation path (if questions)

**Distribution**:
- Post to #engineering Slack
- Link from README.md
- Reference in CONTRIBUTING.md
- Add to onboarding checklist

### Step 3: Soft Launch CI Checks (April 23)

**Configuration**: Set workflow checks to **WARN** mode
- Secrets scanning → Log violation, don't block
- Terraform validation → Log violation, don't block
- Syntax validation → Log violation, don't block

**PR Comment Generator**: Workflow adds comment:
```
⚠️ Configuration Validation Results

The following issues were detected (non-blocking preview):

✅ docker-compose.yml: Valid
❌ Caddyfile: Invalid YAML on line 15
   Expected: valid Caddyfile syntax
   Found: Missing closing brace
   
⚠️ Secrets: 1 potential secret detected
   Pattern: AWS_ACCESS_KEY="AKIA..."
   Fix: Move to .env or use Vault
   
📋 Terraform: terraform validate passed

This is a PREVIEW. Checks will be non-blocking until Phase 4.
Fix issues before Phase 4 enforcement begins.
```

**Expectation**: Engineers see PR comments with suggestions, not blockers.

### Step 4: Team Feedback Window (April 24-27)

**Daily Standup Questions**:
1. Are CI check messages clear?
2. Are there false positives?
3. Which checks are most helpful?
4. Anything missing?

**Collection Method**:
- Slack reactions to thread
- Google Form: "Governance Feedback" (link in Slack)
- Quick retro on Apr 26 (15 min)

**Sample Form Questions**:
```
1. Clarity of CI validation messages (1-5 stars)
2. Are checks too strict? Too lenient?
3. Which checks are most useful?
4. Anything blocking your work?
5. Requests for additional checks?
6. Overall comfort level with governance (1-5)
```

### Step 5: Refine Based on Feedback (April 27-28)

**Actions**:
- Review feedback
- Update GOVERNANCE-AND-GUARDRAILS.md if needed
- Adjust workflow messages for clarity
- Document FAQ in CONTRIBUTING.md

**Example Refinements**:
- Add ShellCheck output interpretation guide
- Clarify "obsolete file" detection rules
- Add examples of compliant configurations

**Success Criteria for Phase 3**:
- [x] Team trained on governance
- [x] Governance doc published
- [x] CI checks running in warn mode
- [x] Feedback collected
- [x] Refined based on input
- [x] Team confidence >4/5 stars

---

## Phase 4: Enforcement Ramp-Up (April 25 - May 2)

### Transition to Hard Blocking

**April 25**: Enable blocking for **critical** checks
- Secrets scanning → BLOCKS MERGE
- Terraform validation → BLOCKS MERGE
- Shell syntax validation → BLOCKS MERGE
- Docker Compose syntax → BLOCKS MERGE
- Caddyfile syntax → BLOCKS MERGE

**Keep as warnings**:
- ShellCheck linting (code quality, not correctness)
- Terraform formatting (style, not functionality)
- Obsolete file detection (informational)

### Workflow Configuration

```yaml
# In .github/workflows/validate-config.yml

jobs:
  secrets-scanning:
    name: Secrets Scanning (BLOCKING)
    runs-on: ubuntu-latest
    # If this job fails, PR merge is blocked

  docker-compose-validate:
    name: Docker Compose (BLOCKING)
    # If this job fails, PR merge is blocked

  caddyfile-validate:
    name: Caddyfile (BLOCKING)
    # If this job fails, PR merge is blocked

  terraform-validate:
    name: Terraform (BLOCKING)
    # If this job fails, PR merge is blocked

  shell-script-validate:
    name: Shell Scripts (BLOCKING)
    # If this job fails, PR merge is blocked

  shell-check-lint:
    name: ShellCheck Linting (warning)
    # If this job fails, it reports but doesn't block
    continue-on-error: true

  obsolete-file-detection:
    name: Obsolete Files (warning)
    # Non-blocking warning
    continue-on-error: true
```

### Branch Protection Settings

**Required Status Checks**:
✅ configuration-validation / secrets-scanning  
✅ configuration-validation / docker-compose-validate  
✅ configuration-validation / caddyfile-validate  
✅ configuration-validation / terraform-validate  
✅ configuration-validation / shell-script-validate  

**Allowed Failures**:
⚠️ configuration-validation / shell-check-lint  
⚠️ configuration-validation / obsolete-file-detection  

### Escalation Path

**If a PR is blocked by CI checks**:

1. **Verify violation is real** (not a false positive)
   ```bash
   # Example: Local Caddyfile validation
   caddy validate --config Caddyfile
   
   # Example: Local docker-compose validation
   docker-compose config > /dev/null
   ```

2. **Fix the violation**
   ```bash
   # Example: Fix syntax error
   # Edit Caddyfile, retest locally
   # Commit and push
   ```

3. **If false positive**: Comment in PR
   ```
   @kushin77 This appears to be a false positive:
   
   [Explain why check result is incorrect]
   
   Requested: Check this or disable this check
   ```

4. **Owner reviews and decides**:
   - Override "just this once" (if legitimate edge case)
   - Fix workflow (if false positive pattern found)
   - Suggest workaround (if limitation exists)

### Timeline

- **April 25**: Enable blocking for core checks
- **April 26-May 1**: Monitor for false positives, support team
- **May 1**: Retro on blocking phase
- **May 2**: Evaluate readiness for Phase 5

**Success Criteria for Phase 4**:
- [x] Hard blocking enabled for critical checks
- [x] Zero secrets leaked to main branch
- [x] <1 false positive per day
- [x] Team successfully fixes violations
- [x] No team complaints about blocking
- [x] Ready for Phase 5

---

## Phase 5: Full Enforcement & Monitoring (May 2+)

### Complete Governance Framework

**All checks BLOCKING**:
- Secrets scanning → BLOCKS
- Configuration validation → BLOCKS
- Terraform validation → BLOCKS
- Script syntax → BLOCKS
- Obsolete files → BLOCKS (enforce cleanup)
- ShellCheck linting → BLOCKS (code quality enforced)

### Code Review Integration

**Phase 5 adds**: Code review enforces governance

**PR Review Checklist**:
```markdown
## Code Review - Governance Checklist

- [ ] Does PR pass all CI checks? (should be required)
- [ ] Does PR introduce custom governance exceptions?
      - If NO → Approve (common case)
      - If YES → Evaluate exception → Approve/Reject
- [ ] Are all secrets properly handled?
      - Secrets in .env (gitignore)? ✅
      - Using Vault for production? ✅
      - No plaintext credentials? ✅
- [ ] Configuration files follow patterns?
      - docker-compose.yml uses base inheritance? ✅
      - Caddyfile modular? ✅
      - Terraform uses locals? ✅
- [ ] Scripts follow standards?
      - Bash: Uses logging.sh + shellcheck ✅
      - PowerShell: Uses common-functions.ps1 ✅
      - All scripts documented? ✅
```

### Production Governance Dashboard

**Create**: GOVERNANCE-METRICS.md (auto-updated weekly)

```markdown
# Governance Metrics (Week of May 5, 2026)

## Overall Compliance
- PRs submitted: 12
- PRs passing all checks: 12 (100%) ✅
- PRs with violations detected: 0 (0%)
- Avg time to fix violation: 8 min
- Secrets leaked to main: 0 (target: 0) ✅

## By Check Type

### Secrets Scanning
- PRs scanned: 12
- Violations detected: 0 ✅
- False positives: 0
- Time to fix: N/A

### Configuration Validation
- Docker Compose violations: 0 ✅
- Caddyfile violations: 0 ✅
- Terraform validation failures: 0 ✅

### Script Validation
- Bash syntax violations: 0 ✅
- PowerShell syntax violations: 0 ✅
- ShellCheck warnings: 3 (fixed w/ compliance)

### Obsolete File Detection
- Phase-specific files merged: 0 ✅
- Archival compliance: 100% ✅

## Team Satisfaction
- Survey responses: 11/12 (92%)
- Governance satisfaction: 4.2/5.0 ⭐
- "Checks are helpful": 10/11 (91%)
- "Process is clear": 11/11 (100%)

## Recommended Actions
1. ShellCheck warnings → Treat as errors (Phase 5+)
2. Document frequently-asked governance questions
3. Monthly training refresh (best practices)
4. Quarterly governance review (rules adjustment)
```

### Monthly Governance Audit

**First Monday of Month**: Review compliance metrics

**Agenda**:
1. Violations last month? (none expected)
2. False positives encountered? (fix if found)
3. Team feedback on governance? (continuous improvement)
4. Update governance docs if needed
5. Optional: Celebrate zero-violation month!

### Escalation for Exceptions

**Rare case**: PR needs governance exception

**Process**:
1. PR submitter explains exception request in PR body:
   ```markdown
   ## Governance Exception Request
   
   Check: Secrets Scanning
   Violation: AWS key pattern detected (false positive)
   Reason: This is a public example key from AWS docs
   Proof: [Link to AWS docs]
   ```

2. Code review approver evaluates
3. Owner (@kushin77) makes final decision
4. Decision logged in GOVERNANCE-EXCEPTIONS.md
5. Workflow rule may be updated if pattern recurs

**Success Criteria for Phase 5**:
- [x] 100% of PRs pass all checks
- [x] Zero secrets leaked to main (goal: lifetime)
- [x] Zero obsolete files merged to main
- [x] 100% configuration validation pass rate
- [x] All scripts pass syntax + linting
- [x] Monthly governance report generated
- [x] Team satisfaction maintained (>4/5)
- [x] Zero critical governance violations
- [x] Governance framework production-ready

---

## Governance Rules Summary

### 1. No Hardcoded Secrets (BLOCKING - Phase 4+)

**What it prevents**: Credential leakage to git

**Violations detected**:
- AWS access key pattern: `AKIA[0-9A-Z]{16}`
- API keys: `api_key = "sk-..."`
- Private PEM keys: `-----BEGIN PRIVATE KEY-----`

**How to comply**:
```bash
# ❌ WRONG: Secrets in file
echo "PASSWORD=mysecret" >> .env

# ✅ RIGHT: Secrets in .env (which is .gitignore'd)
echo "PASSWORD=mysecret" >> .env
# .env is NOT committed

# ✅ RIGHT: Secrets in Vault
vault write secret/my-app password=mysecret
# App retrieves from Vault at runtime
```

**Fix a violation**:
```bash
# 1. Remove secret from file
git rm secrets.yml
# OR edit to remove secret: git add secrets.yml

# 2. Move to .env (non-committed)
echo "SECRET=value" >> .env

# 3. Commit
git commit -m "Remove hardcoded secret"

# 4. Force-push if secret was committed
git push --force-with-lease
```

### 2. Configuration Must Validate (BLOCKING - Phase 4+)

**What it prevents**: Deployment-time configuration errors

**Validations**:
- Docker Compose YAML structure
- Caddyfile Caddy v2 syntax
- Terraform plan succeeds
- Environment variable structure

**How to comply**:
```bash
# Test locally before committing
docker-compose config > /dev/null
caddy validate --config Caddyfile
cd terraform && terraform validate

# Fix any errors
# git add && git commit && git push
```

### 3. Scripts Must Have Valid Syntax (BLOCKING - Phase 4+)

**What it prevents**: Runtime script failures

**Checks**:
- Bash syntax: `bash -n script.sh`
- PowerShell syntax: test in PS Studio
- Shell errors caught early

**How to comply**:
```bash
# Bash: Test locally
bash -n deploy.sh
# Fix any errors
# commit & push

# All scripts: Use logging libraries
# source scripts/logging.sh  (bash)
# . scripts/common-functions.ps1  (PowerShell)
```

### 4. Terraform Must Validate (BLOCKING - Phase 4+)

**What it prevents**: Infrastructure syntax errors

**Check**: `terraform validate` passes

**How to comply**:
```bash
cd terraform
terraform validate
# Should output: "Success! The configuration is valid."

# If errors, fix them
terraform validate
# Repeat until valid
```

### 5. No Obsolete Files in Root (WARNING - Phase 5 Blocking)

**What it prevents**: Codebase clutter, confusion

**Obsolete patterns**:
- `docker-compose-phase-*.yml` → Move to `archived/`
- `Caddyfile.bak`, `Caddyfile.tpl` → Move to `archived/`
- `.env.backup` → Remove (use git history)

**How to comply**:
```bash
# Move old files to archived/
mv docker-compose-phase-15.yml archived/docker-compose-phase-15.yml
git add archived/ docker-compose.yml
git commit -m "Archive obsolete docker-compose variant"
```

---

## Decision Matrix for PRs

| Check Result | Blocking? | Action |
|--------------|-----------|--------|
| ✅ All pass | Yes | Merge immediately (once code reviewed) |
| ❌ Secrets detected | Yes | Fix violation, push, retry |
| ❌ Config invalid | Yes | Fix locally, push, retry |
| ❌ Script syntax error | Yes | Fix locally, push, retry |
| ⚠️ ShellCheck warning (Phase 4) | No | Optional: Address or ignore |
| ⚠️ Obsolete file detected (Phase 4) | No | Optional: Archive or update |
| ❓ False positive (Phase 5) | Yes | Comment on PR, owner overrides |

---

## Rollback Plan

**If governance causes major issues**:

1. **Disable specific check** (if false positive):
   ```yaml
   # In .github/workflows/validate-config.yml
   - name: Problematic Check
     run: ...
     continue-on-error: true  # Downgrade to warning
   ```

2. **Disable all checks** (if critical blocker):
   ```bash
   # Disable workflow entirely
   git mv .github/workflows/validate-config.yml \
        .github/workflows/validate-config.yml.disabled
   ```

3. **Communicate to team**: "We're reverting governance due to [reason]. Will re-launch on [date]."

**Rollback should be rare**. Phased approach (warn → enforce) prevents surprises.

---

## FAQ

**Q: Can I merge a PR that fails CI checks?**  
A: No (after Phase 4). Checks block merge. Fix violations or request exception.

**Q: What if CI is wrong (false positive)?**  
A: Comment in PR. Owner evaluates and may override or fix workflow.

**Q: How do I handle secrets properly?**  
A: Use .env files (git-ignored) or Vault for production.

**Q: Can I ignore ShellCheck warnings?**  
A: During Phase 4 (warnings) yes. Phase 5 onwards, ShellCheck violations block.

**Q: What if a governance rule doesn't make sense?**  
A: Propose change in #engineering Slack. Owner evaluates, may update rule.

---

## Success Metrics by Phase

| Metric | Phase 3 | Phase 4 | Phase 5 |
|--------|---------|---------|---------|
| PRs passing checks | TBD | 95%+ | 100% |
| Secrets leaked | 0 | 0 | 0 |
| Team training | ✅ | - | - |
| Check clarity | 4.0+ /5 | 4.2+/5 | 4.3+/5 |
| Time to fix violation | 15 min | 10 min | 5 min |
| False positives/day | 1-2 | <1 | 0 |

---

## References

- **Governance Rules**: GOVERNANCE-AND-GUARDRAILS.md
- **CI Workflow**: .github/workflows/validate-config.yml
- **Contributing**: CONTRIBUTING.md (CI section)
- **Master Issue**: #256 (Code Review Remediation)
- **Owner**: @kushin77

---

**Last Updated**: April 14, 2026  
**Next Review**: April 21, 2026 (Phase 3 execution)
