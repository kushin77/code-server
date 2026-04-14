# Automatic Merge → Cleanup → Redeploy: Checklist & Verification

**Last Updated**: April 14, 2026
**Purpose**: Verify the automation is working correctly
**Target Audience**: Everyone

---

## ✅ Pre-Implementation Checklist

Use this to verify everything is set up before using the automation.

### Workflow Files
- [ ] `.github/workflows/post-merge-cleanup-deploy.yml` exists
- [ ] `.github/workflows/deploy.yml` exists and supports `workflow_dispatch`
- [ ] `.github/workflows/ci-validate.yml` exists and runs on PRs
- [ ] All workflow files have valid YAML syntax

**Check:**
```bash
ls -la .github/workflows/
yamllint .github/workflows/*.yml
```

### Documentation
- [ ] `AUTO-MERGE-CLEANUP-DEPLOY-MANDATE.md` created
- [ ] `DEPLOYMENT_ORCHESTRATION_GUIDE.md` created
- [ ] `pull_request_template.md` updated with issue linking

**Check:**
```bash
grep -l "AUTO-DEPLOY MANDATE" .github/*.md
grep -l "DEPLOYMENT_ORCHESTRATION" .github/*.md
```

### Scripts
- [ ] `scripts/redeploy.sh` exists and is executable
- [ ] `scripts/redeploy.ps1` exists and is executable
- [ ] `scripts/deploy-phase-12-all.sh` exists

**Check:**
```bash
ls -la scripts/redeploy.*
ls -la scripts/deploy-phase-12-all.sh
chmod +x scripts/redeploy.sh scripts/deploy-phase-12-all.sh
```

### Branch Protection Rules
- [ ] Main branch is protected
- [ ] Require 2 pull request reviews enabled
- [ ] Require status checks to pass enabled
- [ ] Require branches to be up to date enabled
- [ ] Code owner review required (if applicable)

**Check:**
```
Settings → Branches → main → Branch protection rules
```

### Secrets & Configuration
- [ ] `SLACK_WEBHOOK_URL` configured (optional but recommended)
- [ ] Deploy credentials are valid and not expiring
- [ ] Docker registry access is working

**Check:**
```
Settings → Secrets and variables → Actions
```

---

## 🧪 Test Workflow Checklist

### 1. Create a Test Issue

- [ ] Go to GitHub Issues
- [ ] Click "New Issue"
- [ ] Title: `[TEST] Auto-deploy verification`
- [ ] Description:
  ```
  Testing the automated merge → cleanup → redeploy pipeline.

  Closes #[issue-number]
  ```
- [ ] Click "Submit new issue"
- Note the issue number (e.g., #1234)

**Expected**: Issue created, showing in issues list

---

### 2. Create a Test Branch & PR

```bash
# Create feature branch
git checkout -b test/auto-deploy-verification

# Make a small, harmless change (like updating README)
echo "# Test deployment $(date)" >> TEST_DEPLOY.md

# Commit
git add TEST_DEPLOY.md
git commit -m "test: verify auto-deploy pipeline"

# Push
git push origin test/auto-deploy-verification
```

- [ ] Branch created
- [ ] Changes pushed to remote
- [ ] Visible in GitHub

**Check:**
```
GitHub → Code → Branches → test/auto-deploy-verification
```

---

### 3. Create Pull Request

- [ ] Go to GitHub repository
- [ ] Click "New pull request"
- [ ] Set base: `main`, compare: `test/auto-deploy-verification`
- [ ] Fill in title: `test: verify auto-deploy pipeline`
- [ ] Fill in body:
  ```
  ## Description
  Testing automated deployment orchestration.

  ## Linked Issues
  Closes #1234

  ## Testing
  - [x] Code is ready for deployment
  ```
- [ ] Click "Create pull request"

**Expected**: PR created, shows required status checks

---

### 4. Verify CI Checks Pass

- [ ] Wait 30-60 seconds for CI to start
- [ ] GitHub Actions tab shows running workflows
- [ ] `ci-validate` workflow is running
- [ ] `security` workflow is running (if enabled)

**Check:**
```
PR → Checks tab → Running workflows
```

---

### 5. Get Code Review & Approval

- [ ] Assign a reviewer or approve yourself (if allowed)
- [ ] Wait for approval
- [ ] All CI checks show ✅ green

**Note**: If branch protection requires 2 approvals, get both

---

### 6. Merge the PR

- [ ] Click "Merge pull request"
- [ ] Select "Create a merge commit"
- [ ] Click "Confirm merge"
- [ ] PR shows as merged

**Expected**: PR marked [MERGED], branch appears deleted immediately (or within seconds)

---

### 7. Monitor Auto-Cleanup & Deploy

After merge, watch these happen automatically:

#### Step 1: Observe Auto-Cleanup (wait 10-20 seconds)

```bash
# The test branch should disappear
git fetch origin --prune
git branch -r | grep test/auto-deploy

# Should return empty (branch deleted)
```

- [ ] Access GitHub repository
- [ ] Go to Code → Branches
- [ ] `test/auto-deploy-verification` branch is gone
- [ ] Branch was auto-deleted

**Check in GitHub:**
```
Repository → Code → Branches → Search for "test/"
# Should be empty
```

#### Step 2: Observe Auto-Deploy Trigger (wait 5-10 seconds)

- [ ] Go to GitHub repository
- [ ] Click "Actions" tab
- [ ] Find `post-merge-cleanup-deploy` workflow
- [ ] Latest run is your test PR's merge
- [ ] Status shows: ⏳ In progress or ✅ Success

**Watch the jobs:**
1. `check-merge` - Verifying merge ✅
2. `cleanup-branch` - Deleting branch ✅
3. `trigger-deploy` - Dispatching deployment ✅
4. `close-related-issues` - Closing linked issues ✅
5. `notify-completion` - Sending notifications ✅

---

### 8. Verify Issue Auto-Closure

- [ ] Go to GitHub Issues
- [ ] Find issue #1234 from step 1
- [ ] Status shows: Closed ✅
- [ ] See auto-added comment with:
  - PR number
  - "Branch cleaned up"
  - "Code deployed to production"
  - Timestamp

**Example comment:**
```
✅ **Resolved by PR#5678**

- Branch cleaned up
- Code deployed to production
- Issue marked complete

Deployment Details:
- Commit: abc1234
- Branch: test/auto-deploy-verification
- Deployed to: production
- Timestamp: 2026-04-14 14:32:00 UTC
```

---

### 9. Verify Deployment Completion

- [ ] Go to Actions → `post-merge-cleanup-deploy` → Latest run
- [ ] All 5 jobs show ✅ Success
- [ ] Check job execution times
- [ ] Click "post-merge-cleanup-deploy" summary

**Expected output:**
```
✅ Merge verified
✅ Branch cleanup: success
✅ Deployment triggered: success
✅ Related issues closed: 1 issue closed
```

---

### 10. Check Deployment Logs (Optional)

```bash
# View local deployment logs (if redeploy.sh was executed)
tail -f logs/deployments/redeploy_*.log

# View GitHub Actions logs
gh run view <run-id> --repo kushin77/code-server-enterprise
```

**Expected logs:**
```
✅ Git state validated
✅ Deployment readiness checked
✅ Pre-deployment health check performed
✅ Deployment executed
✅ Post-deployment health check performed
✅ Deployment verified
```

---

## ✨ Success Criteria

All of the following should be true:

- [ ] **Timing**: Merge → cleanup + deploy in <10 minutes
- [ ] **Branch**: Test branch auto-deleted from remote
- [ ] **Issue**: Issue #1234 auto-closed with comment
- [ ] **Deployment**: All workflow jobs completed successfully
- [ ] **No errors**: No red ❌ in any workflow job
- [ ] **Audit trail**: Full logs visible in Actions and issue comments

**If all boxes are checked: ✅ SYSTEM IS WORKING CORRECTLY**

---

## 🔍 Troubleshooting

### ❌ Branch NOT deleted after merge

**Possible causes:**
1. Branch protection preventing deletion
2. Cleanup job failed
3. Branch not actually merged

**Debug:**
```bash
# Check if branch is actually merged
git branch -r --merged origin/main | grep test/

# Check cleanup job logs
gh run view <run-id> --log --job cleanup-branch
```

**Fix:**
- [ ] Manual delete: `git push origin --delete test/auto-deploy-verification`
- [ ] Check branch protection rules

### ❌ Issue NOT auto-closed

**Possible causes:**
1. Issue number not in PR body
2. PR body syntax wrong (use "Closes #1234", not "close #1234")
3. Issue already closed

**Debug:**
```bash
# Check PR body for issue reference
gh pr view <pr-number> --json body

# Check close-related-issues job logs
gh run view <run-id> --log --job close-related-issues
```

**Fix:**
- [ ] Verify PR has: `Closes #1234` in body
- [ ] Manually close issue if needed

### ❌ Deployment workflow NOT triggered

**Possible causes:**
1. `deploy.yml` workflow not found
2. `workflow_dispatch` not enabled
3. Permissions issue

**Debug:**
```bash
# Check deploy workflow exists
ls -la .github/workflows/deploy.yml

# Check if workflow dispatch is enabled
grep -A 2 "workflow_dispatch" .github/workflows/deploy.yml
```

**Fix:**
- [ ] Add `workflow_dispatch:` to deploy.yml
- [ ] Manually run: `gh workflow run deploy.yml`

### ❌ GitHub Actions workflow not running

**Possible causes:**
1. Workflow disabled
2. YAML syntax error
3. Event filters not matching

**Debug:**
```bash
# Validate YAML syntax
yamllint .github/workflows/post-merge-cleanup-deploy.yml

# Check workflow is enabled
gh workflow list --repo kushin77/code-server-enterprise
```

**Fix:**
- [ ] Fix YAML syntax errors
- [ ] Enable workflow in GitHub UI
- [ ] Re-merge to trigger

---

## 📊 Regular Health Checks

### Daily (5 minutes)
- [ ] Latest `post-merge-cleanup-deploy` run shows ✅
- [ ] No red errors in Actions tab
- [ ] Team Slack notifications showing successful deploys

### Weekly (15 minutes)
```bash
# Check deployment success rate
gh run list --workflow post-merge-cleanup-deploy.yml -L 50 | grep -c "✓"
# Target: 48-50 successful runs (out of 50)

# Check for any failed cleanup
gh run list --workflow post-merge-cleanup-deploy.yml -L 50 | grep "✗"
# Target: 0 failures
```

### Monthly (30 minutes)
- [ ] Review all failed deployments from past month
- [ ] Check branch protection rules are still correct
- [ ] Verify Slack webhook is still working
- [ ] Update documentation if needed

---

## 🎓 Team Signoff

When setting up this automation for a team, have:

- [ ] **Developers**: Acknowledge they understand auto-deploy behavior
- [ ] **DevOps**: Confirm monitoring and health checks are in place
- [ ] **Engineering Lead**: Approve deployment policy
- [ ] **Security**: Review access controls and audit logging

---

## 📋 Post-Verification Sign-Off

**Verification Completed By**: _________________________ **Date**: _______

**System Status**: ☐ READY FOR USE | ☐ ISSUES FOUND (see section: \_\_\_\_\_\_\_\_)

**Approvals**:
- [ ] DevOps Lead: _________________________ Date: _______
- [ ] Engineering Lead: _________________________ Date: _______
- [ ] Security Review: _________________________ Date: _______

**Next Steps**:
- [ ] Announce to development team
- [ ] Schedule training session
- [ ] Monitor first week of deployments closely
- [ ] Adjust thresholds/timeouts if needed

---

## 📞 Support

**Have questions?**
1. Check `AUTO-MERGE-CLEANUP-DEPLOY-MANDATE.md`
2. Check `DEPLOYMENT_ORCHESTRATION_GUIDE.md`
3. Review this checklist
4. File an issue: `Question: Auto-deploy behavior`

**Found a bug?**
1. Note: Which step failed (cleanup, deploy, issue close, etc.)
2. Collect: Workflow run ID and error message
3. File an issue: `Bug: Auto-deploy failure in [step]`
4. Tag: `automation`, `bug`, `p1-high`

---

**Last verified**: _________________________ Date: _______
**Next verification due**: _________________________ Date: _______
