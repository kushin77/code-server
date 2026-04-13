# 🛠️ Phase 9 Validate Check - Debugging & Fix Guide

**Priority**: 🔴 CRITICAL - Blocking all phase merges  
**Created**: 2026-04-13 14:42 UTC  
**Action**: Follow this guide to identify and fix the validate check failure

---

## Quick Start: 3 Steps to Resolution

### Step 1: Get the Actual Error (RIGHT NOW)
```powershell
# Navigate to GitHub Actions log
# URL: https://github.com/kushin77/code-server/actions/runs/24346218260

# Find job: "710877028" (Run repository validation)
# Look for the STDERR or error output
# Copy the exact error message
```

**Expected to see something like**:
```
##[error] terraform validate failed
##[error] syntax error in main.tf line 42
##[error] pre-commit hook failed
```

### Step 2: Reproduce Locally (Validation)
```powershell
cd c:\code-server-enterprise

# Run the same validation script that failed
bash scripts/validate.sh

# This will show you the exact error
```

### Step 3: Apply Fix & Test
```powershell
# Based on error, fix the issue
# Examples:
  terraform fmt -recursive  # Fix terraform formatting
  # OR fix the problematic file
  # OR update pre-commit config

# Re-run validation
bash scripts/validate.sh

# If passes, commit and push
git add .
git commit -m "fix: resolve Phase 9 validate check failure - [describe fix]"
git push origin fix/phase-9-remediation-final
```

---

## Detailed Troubleshooting by Error Type

### Error Type 1: Terraform Format Issue

**Symptom**:
```
##[error] terraform fmt failed 
terraform format check returned code 1
```

**Fix**:
```powershell
cd c:\code-server-enterprise

# Auto-fix terraform formatting
terraform fmt -recursive

# Verify it's fixed
terraform fmt -check -recursive  # Should return 0

# Commit
git add -A
git commit -m "fix: terraform fmt - phase 9"
git push origin fix/phase-9-remediation-final
```

### Error Type 2: Terraform Validation Issue

**Symptom**:
```
##[error] terraform validate failed
Error: resource block required but not found
Error: invalid argument ...
```

**Fix**:
```powershell
cd c:\code-server-enterprise

# Find the problem file
terraform validate 2>&1 | grep -i error

# Fix the reported error (syntax, argument, etc.)
# Then re-validate
terraform init -backend=false
terraform validate

# Commit when passes
git add terraform/
git commit -m "fix: terraform validation - [describe fix]"
git push origin fix/phase-9-remediation-final
```

### Error Type 3: Pre-commit Hook Failure

**Symptom**:
```
##[error] Pre-commit failed
black failed
pylint failed
yamllint failed
```

**Fix**:
```powershell
cd c:\code-server-enterprise

# Install pre-commit locally
pip install pre-commit

# Run pre-commit to see failures
pre-commit run --all-files

# Most pre-commit hooks auto-fix, re-run:
git add .
pre-commit run --all-files

# Commit fixed files
git commit -m "fix: pre-commit checks - [what was fixed]"
git push origin fix/phase-9-remediation-final
```

### Error Type 4: Missing Script or File

**Symptom**:
```
##[error] scripts/validate.sh: No such file or directory
```

**Facts**:
- Script exists in your repo: ✅ Verified
- Likely workflow issue, not file issue

**Fix**:
- Check `.github/workflows/validate.yml` for correct path
- Should be: `bash scripts/validate.sh`

### Error Type 5: Python/Virtualenv Issue

**Symptom**:
```
##[error] python: command not found
##[error] python -m venv failed
```

**Fix**:
- Workflow uses `ubuntu-latest` runner
- Should have Python 3.12
- If this is the error, it's likely a GitHub Actions permission/environment issue
- Escalate to team or try workflow restart

---

## Testing Locally Before Pushing

**Best Practice**: Test fixes locally first before pushing

```powershell
cd c:\code-server-enterprise

# Simulate the GitHub Actions workflow locally
python -m venv .venv
. .venv/bin/activate  # On PowerShell: .\.venv\Scripts\Activate

# Install requirements
pip install --upgrade pip setuptools wheel

# Try installing pre-commit
pip install pre-commit

# Run the validation script (same as GitHub Actions)
bash scripts/validate.sh

# If it passes, you're good to push
# If it fails, fix and repeat
```

---

## When to Escalate (If Stuck >30 min)

**Escalation Criteria**:
- Error message is unclear
- Fix doesn't resolve the issue
- Multiple failures in sequence
- Environmental issues (GitHub Actions specific)

**Escalation Steps**:
1. Document the exact error message
2. Document what you've tried
3. Note time spent troubleshooting
4. Share with team for guidance
5. Consider:
   - Rebase PR to remove problematic commit?
   - Create new PR with filtered changes?
   - Deep investigation of root cause?

---

## Prevention: How to Avoid This Next Time

### Before Creating Phase PRs
1. Run `bash scripts/validate.sh` locally
2. Ensure it passes
3. Then push to branch
4. Verify CI passes before creating PR

### During Development
```powershell
# After any changes, validate
bash scripts/validate.sh

# If it fails, fix immediately before committing
```

### Pre-PR Checklist
- [ ] Run `bash scripts/validate.sh` locally
- [ ] All terraform files formatted with `terraform fmt -recursive`
- [ ] Pre-commit checks pass with `pre-commit run --all-files`
- [ ] No linting errors
- [ ] Terraform validate passes
- [ ] All above verified locally BEFORE pushing

---

## Reference: Full Validate Workflow

**File**: `.github/workflows/validate.yml`  
**Trigger**: On push to main or PR to main  
**Steps**:
1. Checkout code
2. Set up Python 3.12
3. Create virtualenv
4. Install pre-commit
5. Run `bash scripts/validate.sh`
   - Pre-commit checks
   - Terraform fmt check
   - Terraform validate
   - tflint (optional)

**Success**: All steps complete with exit code 0

---

## Key Files to Check

If still unclear after running local validation:

```powershell
# Workflow definition
cat .github/workflows/validate.yml

# Validation script
cat scripts/validate.sh

# Pre-commit config
cat .pre-commit-config.yaml

# Terraform main config
cat terraform/phase-12/main.tf

# Any recent terraform files
Get-ChildItem terraform/phase-12/*.tf
```

---

## Timeline for Resolution

```
Now: 14:42 UTC
│
├─ 14:45-14:50 UTC     → Get error from GitHub Actions log
├─ 14:50-15:00 UTC     → Reproduce locally with bash scripts/validate.sh
├─ 15:00-15:15 UTC     → Identify fix type and apply
├─ 15:15-15:20 UTC     → Verify fix locally (bash scripts/validate.sh should pass)
├─ 15:20-15:25 UTC     → Commit and push
│
└─ 15:30 UTC           → Fresh CI run starts (10-15 min for all checks)
   └─ 15:45-16:00 UTC   → All checks should PASS
      └─ 16:00+ UTC     → Ready for Phase 9 merge
```

---

## Do NOT Guess

**Important**: Don't try random fixes without understanding the error.

**Instead**:
1. Get the actual error from GitHub Actions log
2. Search for that error in Phase 9 files
3. Make targeted fix
4. Test locally
5. Push

---

## Question Checklist

If you're stuck, answer these:

1. [ ] Have you viewed the GitHub Actions log?
2. [ ] Do you have the exact error message?
3. [ ] Can you reproduce it locally?
4. [ ] Do you understand what caused it?
5. [ ] Do you understand what the fix should be?
6. [ ] Have you tested the fix locally?
7. [ ] Is bash scripts/validate.sh passing locally?

If answer to any is "no", go back to that step.

---

**Use This Guide To**: Systematically debug and fix the Phase 9 validate check failure  
**Expected Outcome**: Validate check will PASS, enabling Phase 9 merge  
**Time to Complete**: 30-60 minutes for most common fixes  
**Status**: 🔴 CRITICAL - Do this NOW

