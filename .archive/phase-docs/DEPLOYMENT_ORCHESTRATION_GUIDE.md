# Deployment Orchestration Guide

**Document Version**: 1.0
**Last Updated**: April 14, 2026
**Audience**: DevOps Engineers, Engineering Leads, Build Engineers

---

## 📋 Overview

The Deployment Orchestration system ensures that every successful code merge automatically triggers a complete deployment pipeline:

```
PR Merge to main
    ↓
[AUTO] Verify merge
    ↓
[AUTO] Cleanup feature branch
    ↓
[AUTO] Trigger deployment
    ↓
[AUTO] Run post-deploy health checks
    ↓
[AUTO] Notify team
    ↓
✅ Code LIVE in production
```

**Key Benefits:**
- **Zero manual redeploy steps** - Code goes live automatically after merge
- **Branch hygiene** - No orphaned feature branches cluttering the repository
- **Complete audit trail** - Every deployment is tracked and documented
- **Issue closure automation** - Linked issues auto-close when code deploys
- **Health verification** - Automated checks ensure deployment success

---

## 🏗️ Architecture

### Components

```
GitHub Repository
├── .github/workflows/
│   ├── post-merge-cleanup-deploy.yml    ← Main orchestration workflow
│   ├── deploy.yml                       ← Deployment execution (called by orchestration)
│   └── ci-validate.yml                  ← Pre-merge validation
├── scripts/
│   ├── redeploy.sh                      ← Bash deployment orchestrator
│   ├── redeploy.ps1                     ← PowerShell deployment orchestrator
│   └── deploy-phase-12-all.sh           ← Actual deployment logic
└── .github/
    └── AUTO-MERGE-CLEANUP-DEPLOY-MANDATE.md  ← This policy
```

### Workflow Sequence

#### 1. **post-merge-cleanup-deploy.yml** (GitHub Actions)
- **Trigger**: PR merge to main OR push to main
- **Responsibilities**:
  - Verify merge was successful
  - Delete merged feature branch
  - Dispatch deployment workflow
  - Close related issues
  - Notify team

#### 2. **deploy.yml** (GitHub Actions)
- **Trigger**: Dispatched by `post-merge-cleanup-deploy.yml`
- **Responsibilities**:
  - Run Terraform validation
  - Plan infrastructure changes
  - Apply Terraform configurations
  - Report deployment results

#### 3. **redeploy.sh / redeploy.ps1** (Local Scripts)
- **Trigger**: Manual execution or CI/CD pipeline
- **Responsibilities**:
  - Git state validation
  - Deployment readiness checks
  - Execute deployment scripts
  - Health check verification
  - Slack notifications
  - Generate deployment reports

---

## 🔄 Detailed Workflow Breakdown

### Step 1: Merge Detection (5-10 seconds)

```yaml
# post-merge-cleanup-deploy.yml / check-merge job
Event: GitHub PR merged to main
  ↓
Actions:
  - Check if PR.merged == true
  - Extract PR number and branch name
  - Store in outputs for next jobs
```

**Verifies:**
- PR is actually merged (not just closed)
- Extract branch information
- Identify related issues (from PR body)

**Failure handling:**
- If PR was closed but NOT merged, exit gracefully
- No cleanup or deploy executed

---

### Step 2: Branch Cleanup (10-20 seconds)

```yaml
# post-merge-cleanup-deploy.yml / cleanup-branch job
Input: Branch name from merged PR
  ↓
Actions:
  - Checkout repository with full history
  - Configure Git credentials
  - Verify branch is actually merged
  - Delete remote branch
  - Prune stale local references
```

**Safety mechanisms:**
- Skips protected branches (main, develop, release/*, hotfix/*)
- Only deletes branches that are fully merged
- Logs all actions for audit trail
- Handles failures gracefully (continues pipeline if cleanup fails)

**Example behavior:**

```bash
# Good: Feature branch merged
Input:  feature/auth-system
Output: ✅ Deleted from remote

# Protected: Main branch
Input:  main
Output: ⚠️ Skipped (protected branch)

# Already deleted: Stale branch
Input:  fix/old-bug
Output: ⚠️ Already deleted or not found
```

---

### Step 3: Deployment Trigger (5 seconds)

```yaml
# post-merge-cleanup-deploy.yml / trigger-deploy job
Input: PR number, commit info
  ↓
Actions:
  - Create GitHub deployment record
  - Dispatch deploy.yml workflow
  - Pass context to deployment job
  ↓
# Now deploy.yml runs in parallel
```

**Deployment workflow executes:**

```yaml
# deploy.yml jobs sequence
validate → plan → apply
  - Terraform init
  - Terraform validate
  - Terraform plan (saved as artifact)
  - Terraform apply (automatic on main)
  - Get outputs and post to PR
```

---

### Step 4: Issue Auto-Close (10-15 seconds)

```yaml
# post-merge-cleanup-deploy.yml / close-related-issues job
Input: PR body text
  ↓
Parse: Extract issue numbers from keywords
  - "Closes #123"
  - "Fixes #456"
  - "Resolves #789"
  ↓
Actions:
  - Find each issue
  - Change state to 'closed' with reason 'completed'
  - Add comment with PR link and deployment status
```

**Comment added to issue automatically:**

```markdown
✅ **Resolved by PR#1234**

- Branch cleaned up
- Code deployed to production
- Issue marked complete

Deployment Details:
- Commit: abc1234
- Branch: feature/auth-system
- Deployed to: production
- Timestamp: 2026-04-14 14:32:00 UTC
```

---

### Step 5: Team Notification (5-10 seconds)

```yaml
# post-merge-cleanup-deploy.yml / notify-completion job
Inputs: Deployment status, PR info, commit details
  ↓
Actions:
  - Build completion summary
  - Post job summary to GitHub Actions
  - Send Slack notification (if configured)
  - Record metrics
```

**GitHub Actions Summary:**

![Example summary would show here]

**Slack Message Example:**

```
✅ Auto-Deployment to production: Success

Target: production
Commit: abc1234 - feat: add user authentication
Author: alice@example.com
Status: Success
Timestamp: 2026-04-14 14:32:00 UTC
```

---

## 🛠️ Configuration

### Workflow Configuration

#### 1. Environment Variables

**GitHub Actions Settings → Secrets and variables → Actions**

```yaml
SLACK_WEBHOOK_URL           # Slack integration
TARGET_ENVIRONMENT          # Override deployment target
DEPLOYMENT_SECRET           # Internal authorization token
```

#### 2. Branch Protection Rules

**Settings → Branches → main → Branch protection rules**

Required for orchestration to work:
- ✅ Require 2 pull request reviews
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Require code owner reviews
- ✅ Restrict who can push

### Deployment Configuration

#### 1. Enable Workflow Dispatch

In `deploy.yml`, allow manual trigger:

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      trigger_source:
        description: 'Source of trigger'
        required: false
```

#### 2. Set Deployment Targets

In `redeploy.sh` or `redeploy.ps1`:

```bash
DEPLOYMENT_TARGETS=("production" "staging" "development")
DEFAULT_TARGET="production"
```

#### 3. Configure Health Checks

Update health check endpoints:

```bash
production_endpoint="https://code-server.kushnir.cloud/health"
staging_endpoint="https://staging-code-server.kushnir.cloud/health"
```

---

## 📊 Monitoring & Observability

### GitHub Actions Monitoring

**View all auto-triggered deployments:**

```
Repository → Actions → post-merge-cleanup-deploy → Recent runs
```

**Each run shows:**
- ✅ Merge verification status
- ✅ Branch cleanup result
- ✅ Deployment dispatch status
- ✅ Issue auto-close success
- 📊 Duration of each step
- 📋 Detailed logs for each job

### Deployment Metrics

**Track over time:**

```
Metrics to Watch:
- Time from merge to live (target: <10 minutes p95)
- Cleanup success rate (target: 99.9%)
- Health check success rate (target: 100%)
- Issue link accuracy (target: 100%)
- Deployment rollback rate (target: <2%)
```

### Log Files

**Local deployment logs:**

```bash
ls -la logs/deployments/
# redeploy_20260414_143200.log
# redeploy_20260414_134500.log
# ...
```

**View latest deployment:**

```bash
tail -f logs/deployments/redeploy_*.log
```

---

## 🚨 Error Handling & Recovery

### Common Scenarios

#### Scenario 1: Merge Detection Fails

**Cause**: PR closed but not merged
**Behavior**: Workflow exits gracefully, no cleanup/deploy
**Recovery**: Check PR status, manual redeploy if needed

```yaml
# Logged as:
⚠️ PR #1234 was closed but NOT merged
# Pipeline stops, no further action
```

#### Scenario 2: Branch Cleanup Fails

**Cause**: Branch protected or already deleted
**Behavior**: Logs warning, continues with deployment
**Recovery**: Manual cleanup later, doesn't block deployment

```bash
⚠️ Failed to delete branch (may be protected or already deleted): feature/auth
# Continues to deployment step
```

#### Scenario 3: Deployment Fails

**Cause**: Terraform apply failed or infrastructure issue
**Behavior**: Pipeline marks as failed, posts to PR, alerts team
**Recovery**: Fix issue, revert PR, or re-trigger deployment

```yaml
❌ Production deployment failed
# Status shows in PR
# Slack alert sent
# Team notified to investigate
```

#### Scenario 4: Health Check Fails

**Cause**: Post-deployment health check doesn't pass
**Behavior**: Warns but deployment is already live
**Recovery**: Investigate service logs, may need rollback

```bash
⚠️ Health check failed after 10 attempts
# Deployment is live but possibly unstable
# Manual investigation required
```

### Rollback Procedure

**If deployment must be reverted:**

```bash
# 1. Identify the problematic PR/commit
git log --oneline -10

# 2. Create revert commit
git revert <commit-sha>

# 3. Push revert (immediately triggers cleanup + redeploy)
git push origin main

# 4. Watch automation handle the rollback
# Actions → post-merge-cleanup-deploy → Latest run
```

---

## 🔐 Security Considerations

### Access Control

**Who can trigger deployments:**
- ✅ Any developer who can merge to main (controlled by branch protection)
- ✅ Only code approved by 2+ reviewers can trigger deployment
- ✅ Code owners must review sensitive changes

**Who can merge to main:**
- ✅ Anyone with push access AND meeting branch protection requirements
- ❌ Cannot merge own PRs without review
- ❌ Cannot merge without passing CI checks
- ❌ Cannot merge without required approvals

### Audit Trail

**Every deployment is tracked:**

1. **GitHub PR history** - Who merged, when, what
2. **GitHub deployment records** - What was deployed, status
3. **Actions logs** - Full execution details, timestamps
4. **Git commit log** - Author, message, signature verification
5. **Application logs** - What happened after deployment

**Access audit logs:**

```bash
# View deployment history
git log --all --oneline --graph

# View Actions logs
gh run list --repo kushin77/code-server-enterprise
gh run view <run-id> --repo kushin77/code-server-enterprise
```

### Secrets Management

**Sensitive values protected:**

```yaml
# Never logged or visible in UI
SLACK_WEBHOOK_URL           # Kept in GitHub Secrets
DEPLOYMENT_SECRET           # Never exposed
Database credentials        # Not in workflow files
API tokens                  # Stored in Secrets context
```

---

## 📖 Development & Testing

### Testing the Workflow Locally

#### 1. Test cleanup logic:

```bash
# Test branch cleanup without deploying
cd /code-server-enterprise

# Create test branch
git checkout -b test/cleanup-feature
echo "test" > test.txt
git add .
git commit -m "test: cleanup test"
git push origin test/cleanup-feature

# Merge it
gh pr create --fill
# [merge via GitHub UI]

# Watch branch auto-delete in Actions
# Actions → post-merge-cleanup-deploy
```

#### 2. Test deployment workflow:

```bash
# Manually trigger deployment
gh workflow run deploy.yml -r main

# Watch execution
gh run list --workflow deploy.yml
gh run view <run-id>
```

#### 3. Test local redeploy script:

```bash
# Bash version
bash scripts/redeploy.sh --target staging --dry-run
bash scripts/redeploy.sh --target staging --verbose

# PowerShell version
.\scripts\redeploy.ps1 -Target staging -DryRun -Verbose
```

### Debugging Workflow Issues

#### Check workflow syntax:

```bash
# Validate YAML syntax
yamllint .github/workflows/post-merge-cleanup-deploy.yml
```

#### View detailed logs:

```bash
# Get latest run
gh run list --workflow post-merge-cleanup-deploy.yml -L 1

# View logs
gh run view <run-id> --log

# View specific job
gh run view <run-id> --log --job <job-name>
```

#### Re-run failed workflow:

```bash
# Re-run failed jobs
gh run rerun <run-id> --failed

# Re-run entire workflow
gh run rerun <run-id>
```

---

## 🎓 Training & Onboarding

### For Developers

**What you need to know:**
1. Every merged PR auto-deploys (no manual steps needed)
2. Link issues in PR body: `Closes #123`
3. Issues auto-close when code goes live
4. Your branch auto-deletes after merge
5. Check Actions tab for deployment status

**Quick start:**
1. Create issue: "Add feature X"
2. Create branch: `git checkout -b feature/x`
3. Make changes and commit
4. Push: `git push origin feature/x`
5. Create PR, link issue: `Closes #123`
6. Get approved, merge
7. Watch Actions auto-deploy
8. Done! 🎉

### For DevOps Engineers

**Responsibilities:**
1. Monitor deployment success rate
2. Handle failed deployments
3. Maintain health check endpoints
4. Manage branch protection rules
5. Update deployment scripts

**Key commands:**
```bash
# Monitor recent deployments
gh run list --workflow post-merge-cleanup-deploy.yml -L 20

# Check deployment logs
gh run view <run-id> --log

# Manually trigger deployment
gh workflow run deploy.yml

# Validate workflow syntax
yamllint .github/workflows/
```

### For Engineering Leaders

**Metrics to track:**
- Deployment frequency (should be multiple times daily)
- Lead time for changes (30 min to first deploy)
- Deployment success rate (target: 99.9%)
- Time to rollback (target: <15 minutes)
- Change failure rate (target: <15%)

**Reporting:**
```bash
# View deployment statistics
gh run list --workflow post-merge-cleanup-deploy.yml | wc -l
# Shows number of successful deployments today
```

---

## 📝 Maintenance & Updates

### Regular Checks

**Weekly:**
- [ ] Review failed deployments
- [ ] Check health check endpoint status
- [ ] Verify no stale branches exist
- [ ] Monitor log file sizes

**Monthly:**
- [ ] Review branch protection rules
- [ ] Audit deployment logs
- [ ] Update security credentials if needed
- [ ] Review and update this documentation

### Updating Workflows

**When to update:**
- New deployment targets added
- Health check endpoints change
- Slack webhook configuration changes
- Issue linking format changes

**How to update:**
1. Update workflow file in `.github/workflows/`
2. Test on feature branch
3. Get code review
4. Merge to main
5. Automatic deployment of new workflow

**Example update procedure:**

```bash
# Create update branch
git checkout -b ops/update-deploy-workflow

# Edit workflow
vim .github/workflows/post-merge-cleanup-deploy.yml

# Commit and push
git commit -m "ops: update post-merge workflow deployment targets"
git push origin ops/update-deploy-workflow

# Create PR, get review, merge
# New workflow takes effect immediately
```

---

## 📞 Support & Contact

**Questions about automation?**
- Check this document first
- Search GitHub Issues tagged `automation`
- Contact DevOps team in Slack

**Found a bug?**
- File an issue: `Bug in auto-deploy orchestration`
- Include: workflow run ID, error message, expected behavior
- Tag: `automation`, `bug`, `p1-high`

**Feature request?**
- File an issue: `Enhancement: add X to orchestration`
- Explain: what you want, why you need it, expected behavior
- Tag: `automation`, `enhancement`, `feature-request`

---

**Version History:**
- v1.0 (2026-04-14): Initial deployment orchestration system
- v1.1 (Coming): Multi-region deployment support
- v1.2 (Coming): Advanced canary/blue-green deployments
