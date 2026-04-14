# Phase 3: Governance Training Materials

**Session Date**: April 21, 2026 @ 2:00 PM UTC (10:00 AM EDT / 7:00 AM PDT)
**Duration**: 30 minutes
**Audience**: All engineers
**Format**: Video call + Slack Q&A
**Owner**: @kushin77 (DevOps/Platform Lead)

---

## Pre-Training Setup (April 19-20)

### Materials to Distribute
- [ ] Email: "Governance Training - April 21" (send Apr 19)
- [ ] Slack message with video call link (send Apr 20)
- [ ] Link to GOVERNANCE-AND-GUARDRAILS.md (include in all comms)
- [ ] Link to this document for follow-up reference

### Tech Setup
- [ ] Video recording enabled (for asynchronous access)
- [ ] Slack workspace ready for Q&A channel
- [ ] GitHub Actions test PR prepared (for demo)
- [ ] Sample violations queued to show (real examples)

---

## Training Agenda (30 minutes)

### Segment 1: Why Governance Matters (2 minutes)

**Talking Points**:
- Phase 1 identified 15+ duplicate files, 40+ gaps, 6 critical CI/CD gaps
- Goal: Prevent configuration errors, credential leakage, deployment surprises
- Our team follows FAANG-level code review standards
- Governance makes everyone's life better (faster deploys, fewer surprises)

**Visual**:
```
Before Governance          After Governance
─────────────────         ──────────────────
❌ Secrets in git         ✅ Secrets never in git
❌ Config errors          ✅ Config validated before merge
❌ Script crashes         ✅ Scripts tested before merge
❌ Manual checks          ✅ Automated checks everywhere
❌ 20% PRs fail deploy    ✅ 0% PRs fail deploy
```

**Key Message**: "Governance is about catching problems BEFORE they reach main branch."

---

### Segment 2: The Five New CI Checks (5 minutes)

**Check 1: Secrets Scanning** (5-6 min into talk)

**What it does**: Detects hardcoded credentials before they're committed

**Examples of violations**:
```
❌ WRONG - Hardcoded AWS key:
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

❌ WRONG - API key in config:
openai_api_key = "sk-proj-abc123..."
stripe_key = "sk_live_..."

❌ WRONG - Private key in file:
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA5g...
-----END RSA PRIVATE KEY-----
```

**How it's detected**:
- Pattern matching: `AKIA[0-9A-Z]{16}` for AWS keys
- Pattern matching: `api_key\s*=\s*"sk-"` for API keys
- Pattern matching: `BEGIN.*PRIVATE KEY` for key files
- TruffleHog verification (real secret or dummy?)

**How to comply**:
```bash
# ✅ RIGHT - Use .env file (git-ignored):
echo "API_KEY=sk-123..." >> .env
# .env is in .gitignore, never committed

# ✅ RIGHT - Use Vault (production):
vault write secret/my-app api_key=sk-123...
# App reads from Vault at startup

# ✅ RIGHT - Use environment variables:
export API_KEY="sk-123..."
# Set in deployment automation, not in code
```

---

**Check 2: Configuration Validation** (6-7 min into talk)

**What it does**: Ensures docker-compose.yml, Caddyfile, etc. are syntactically correct

**Examples of violations**:
```yaml
# ❌ WRONG - Invalid YAML (missing colon)
services:
  code-server
    image: codercom/code-server:4.115.0

# ✅ RIGHT - Valid YAML (proper indentation)
services:
  code-server:
    image: codercom/code-server:4.115.0
```

**How it's detected**:
```bash
# docker-compose validation
docker-compose config > /dev/null

# Caddyfile validation
caddy validate --config Caddyfile

# Terraform validation
terraform validate
```

**How to comply**:
```bash
# Test locally BEFORE pushing:
docker-compose config > /dev/null  # Should output valid config
caddy validate --config Caddyfile  # Should say "OK"
cd terraform && terraform validate  # Should say "Success"

# If error, fix it locally and retry
git add .
git commit -m "fix: Caddyfile syntax"
git push
```

---

**Check 3: Script Syntax Validation** (7-8 min into talk)

**What it does**: Ensures bash and PowerShell scripts are syntactically correct

**Examples of violations**:
```bash
# ❌ WRONG - Missing closing 'fi'
if [ "$1" = "test" ]; then
  echo "Testing"
# Missing: fi

# ✅ RIGHT - Proper if/fi syntax
if [ "$1" = "test" ]; then
  echo "Testing"
fi
```

**How it's detected**:
```bash
bash -n script.sh  # Test syntax without running

powershell -NoProfile -Command "Test-Path deploy.ps1"  # PowerShell check
```

**How to comply**:
```bash
# Test locally:
bash -n deploy.sh  # Should output nothing (success)
bash -n rollback.sh
bash -n backup.sh

# If error, fix syntax
git add .
git commit -m "fix: script syntax"
git push
```

---

**Check 4: Terraform Validation** (8-9 min into talk)

**What it does**: Ensures all Terraform code is syntactically correct

**Examples of violations**:
```hcl
# ❌ WRONG - Missing closing brace
resource "aws_instance" "main" {
  ami = "ami-abc123"
  instance_type = "t3.micro"
# Missing: }

# ✅ RIGHT - Proper syntax
resource "aws_instance" "main" {
  ami           = "ami-abc123"
  instance_type = "t3.micro"
}
```

**How it's detected**:
```bash
cd terraform
terraform validate  # Should say "Success! The configuration is valid."
```

**How to comply**:
```bash
# Before pushing:
cd terraform
terraform validate

# If error, fix it
# Common errors:
#   - Missing closing brace
#   - Invalid argument names
#   - Type mismatches
#   - Missing required variables

terraform validate  # Retry until success
git add .
git commit -m "fix: terraform syntax"
git push
```

---

**Check 5: Obsolete File Detection** (9-10 min into talk)

**What it does**: Warns about phase-specific files that should be archived

**Examples of violations**:
```
⚠️ Found: docker-compose-phase-15.yml
   Should be: archived/docker-compose-phase-15.yml

⚠️ Found: Caddyfile.bak
   Should be: archived/Caddyfile.bak

⚠️ Found: .env.backup
   Should be: Removed (use git history instead)
```

**How it's detected**:
```bash
# Pattern matching for obsolete files
docker-compose-phase-*.yml
Caddyfile.*.bak
.env.backup
prometheus-production.yml
alertmanager-production.yml
```

**How to comply**:
```bash
# Move old files to archived/:
mv docker-compose-phase-15.yml archived/
mv Caddyfile.bak archived/
# Remove .env.backup entirely
rm .env.backup

git add archived/ docker-compose.yml
git commit -m "chore: archive obsolete files"
git push
```

---

### Segment 3: What Violations Look Like (5 minutes)

**Demo: Test PR with CI Results**

**Show in PR**:
```
Checks
✅ configuration-validation / secrets-scanning — Passed
✅ configuration-validation / docker-compose-validate — Passed
✅ configuration-validation / caddyfile-validate — Passed
✅ configuration-validation / terraform-validate — Passed
✅ configuration-validation / shell-script-validate — Passed
⚠️ configuration-validation / shell-check-lint — Passed (informational)

CI Check Results Comment:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ Configuration Validation Results

The following issues were detected (non-blocking preview):

✅ docker-compose.yml: Valid
✅ Caddyfile: Valid
✅ terraform/: terraform validate passed
✅ scripts/: All bash scripts valid
⚠️ Secrets: No potential secrets detected
⚠️ Obsolete files: None detected

This is a PREVIEW. Checks will be non-blocking until Phase 4.
Fix issues before Phase 4 enforcement begins (April 25).
```

**Show real violation example**:
```
❌ Failed: Secrets Scanning

Detected AWS key pattern:
Line 42 in .env.backup: AWS_KEY="AKIA0123456789ABC"

Fix:
- Remove from .env.backup (or delete file)
- Use .env (git-ignored) instead
- Push fix
```

---

### Segment 4: How to Fix Violations (3 minutes)

**Fix Process** (simple flowchart):

```
1. PR fails CI check
           ↓
2. Read check output
           ↓
3. Understand the error
           ↓
4. Fix locally: git add → git commit → git push
           ↓
5. CI re-runs automatically
           ↓
6. If still failing, repeat from step 3
           ↓
7. All checks green → Merge! 🎉
```

**Examples**:

**Example 1: Fix Secrets**
```bash
# See: AWS_KEY found in .env.backup
git rm .env.backup  # Remove file
# OR: echo 'AWS_KEY=value' >> .env  # Move to ignored file

git add .
git commit -m "fix: remove hardcoded secret"
git push
# CI re-runs → secrets check passes
```

**Example 2: Fix Caddyfile**
```bash
# See: Caddyfile has invalid syntax
caddy validate --config Caddyfile
# Output: Error on line 15: missing closing brace

# Edit Caddyfile, add closing brace
git add Caddyfile
git commit -m "fix: Caddyfile syntax"
git push
# CI re-runs → Caddyfile check passes
```

**Example 3: Fix Bash Script**
```bash
# See: deploy.sh has syntax error
bash -n deploy.sh
# Output: line 42: unexpected 'fi'

# Edit deploy.sh, fix the 'if' statement
git add scripts/deploy.sh
git commit -m "fix: script syntax"
git push
# CI re-runs → syntax check passes
```

---

### Segment 5: Q&A (5 minutes)

**Common Questions to Answer**:

**Q: Will these checks block my PRs?**
A: Not until Phase 4 (April 25). Phase 2-3 are non-blocking (preview). You'll see results, but can still merge.

**Q: What if the check is wrong (false positive)?**
A: Comment in the PR. Owner will review and either fix the check or override it.

**Q: Do I need to test locally before pushing?**
A: Recommended! It's faster than push → CI run → fix → push again. Test locally first.

**Q: What if I have multiple violations?**
A: Fix all of them in one commit. Push. CI re-runs for all checks.

**Q: Can I merge a PR with CI failures (after Phase 4)?**
A: No. Checks will block merge. Must fix violations first (or get exception from owner).

**Open Q&A**: Ask in #engineering Slack anytime.

---

## Post-Training Instructions

### Immediately After (April 21)

1. **Post slides** in #engineering Slack
2. **Post training link** (video recording)
3. **Open Q&A channel**: "governance-questions" thread
4. **Set up feedback form**: "Governance Feedback - Quick Survey" (Google Form link)
5. **Soft-launch checks**: Non-blocking mode active

### April 21-24 (Soft Launch Window)

**What's happening**:
- All PRs get CI checks and comments
- Violations are reported (but don't block)
- Team gets familiar with the process
- Questions and feedback collected

**Daily stand-up check-in**:
- Any false positives? (circ fix if found)
- Are messages clear?
- Anything confusing?
- Anything helpful?

### April 24-25 (Feedback Review)

**Owner reviews**:
- Feedback from team
- Any patterns in violations?
- False positives to fix?
- Messages to clarify?

**Update governance docs**:
- FAQ section expanded
- Common violation patterns documented
- Troubleshooting guide updated

### April 25+ (Hard Enforcement)

- Phase 4 begins
- Critical checks block merge
- Non-critical checks warn (but don't block)
- Team expected to fix violations before merge

---

## Attendance Confirmation

**Please confirm in Slack thread**:
```
✅ I can attend April 21 @ 2:00 PM UTC
⏰ I'll watch the recording later
❓ I have questions before the session
```

---

## Resources

- **Governance Rules**: [GOVERNANCE-AND-GUARDRAILS.md](./GOVERNANCE-AND-GUARDRAILS.md)
- **Rollout Plan**: [GOVERNANCE-ROLLOUT-PLAN-PHASES-2-5.md](./GOVERNANCE-ROLLOUT-PLAN-PHASES-2-5.md)
- **CI Workflow**: [.github/workflows/validate-config.yml](.github/workflows/validate-config.yml)
- **Contributing**: [CONTRIBUTING.md](./CONTRIBUTING.md) (CI section)
- **Issue #256**: [Code Review Remediation](https://github.com/kushin77/code-server/issues/256)

---

## Slides Summary

**Slide 1** (Title): Governance & Code Quality
**Slide 2** (Why):  Why governance matters
**Slide 3** (What): The 5 CI checks (secrets, config, scripts, terraform, obsolete files)
**Slide 4** (Demo): Real PR example with CI results
**Slide 5** (How): How to fix violations + Q&A

**Estimated timing**: 2 min + 5 min + 5 min + 3 min + 5 min = 20 min + 10 min buffer

---

## Training Completion Checklist

- [ ] Send attendance request (April 19)
- [ ] Record session (April 21)
- [ ] Post recording to Slack (April 21)
- [ ] Collect attendance confirmations
- [ ] Monitor Q&A thread (April 21-24)
- [ ] Collect feedback (via form)
- [ ] Review feedback (April 24)
- [ ] Update docs based on feedback (April 24)
- [ ] Mark Phase 3 complete (April 24)

---

**Training Leader**: @kushin77
**Expected Attendance**: All engineers in code-server-enterprise project
**Follow-up**: Monthly governance training refresh (best practices)

---

**Last Updated**: April 14, 2026
**Next Session**: Weekly governance sync (proposed: Mondays 2:00 PM UTC)
