# Automatic Merge → Cleanup → Redeploy Mandate

**EFFECTIVE DATE**: April 14, 2026
**REQUIREMENT LEVEL**: Mandatory for all work
**APPLIES TO**: All issues, tasks, epics, pull requests, and merges

---

## 📋 Executive Summary

**Every successful merge to `main` automatically triggers:**
1. ✅ Branch cleanup (delete merged feature branch)
2. ✅ Code deployment to production
3. ✅ Auto-close of related issues
4. ✅ Status notifications and audit trail

**This is not optional. This is the default workflow for all work.**

---

## 🎯 The Mandate

### Core Principle
**All work that reaches production must follow the complete pipeline or it is not "done".**

```
Issue Created
  ↓
Branch created from main
  ↓
Work completed, tests pass
  ↓
Pull Request opened (links to issue)
  ↓
Code review approved
  ↓
PR MERGED ← TRIGGERS AUTOMATION
  ↓
[AUTOMATIC] Branch cleanup
  ↓
[AUTOMATIC] Production deployment
  ↓
[AUTOMATIC] Issue closed
  ↓
✅ COMPLETE & LIVE
```

### What "Success" Means
- **PR is merged to main** → Automation triggers
- **No manual redeploy needed** → System handles it
- **Zero orphaned branches** → Cleanup is auto
- **Issues auto-tracked** → Closed when code lives
- **Audit trail complete** → Fully documented

---

## 🔧 How It Works

### Workflow: `post-merge-cleanup-deploy.yml`

**Triggered by:**
- PR merge to `main`
- Any push to `main`

**Execution steps (automatic, no human intervention):**

1. **Verify Merge** → Confirms PR was actually merged (not just closed)
2. **Cleanup Branch** → Deletes feature branch from remote (skips protected branches)
3. **Trigger Deploy** → Dispatches deployment workflow to production
4. **Close Issues** → Finds linked issues (Closes #X, Fixes #Y) and closes them
5. **Notify** → Posts completion summary with status

**Time to Production:**
- Cleanup: ~10-20 seconds
- Deployment: Depends on your deploy workflow (typically 2-5 minutes)
- **Total**: Code merged → Live in <10 minutes

---

## 📝 Issue Linking Rules

**For the automation to auto-close issues, YOUR PR description MUST include:**

```markdown
## Description
[Your feature description]

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Closes
Closes #123
Fixes #456
Resolves #789
```

**Supported keywords:**
- `Closes #number`
- `Fixes #number`
- `Resolves #number`
- `Close #number`
- `Fix #number`
- `Resolve #number`

### Example PR Description
```markdown
## Description
Implements automated branch cleanup and deployment pipeline for all merges.

## Closes
Closes #42 - Auto cleanup & redeploy on PR merge
Resolves #43 - Update deployment workflow
Fixes #44 - Documentation for new mandate

## Testing
- [x] Tested cleanup logic with feature branches
- [x] Verified deployment trigger
- [x] Confirmed issue linking and auto-close
```

When this PR merges:
1. ✅ Branches cleaned
2. ✅ Code deployed
3. ✅ Issues #42, #43, #44 automatically closed
4. ✅ Status posted to PR

---

## 🚫 Protected Branches (Never Auto-Deleted)

The following branches are **never** auto-deleted:
- `main` - Production
- `develop` - Development
- `release/*` - Release branches
- `hotfix/*` - Emergency fixes
- Any branch with GitHub Branch Protection enabled

---

## 📊 Audit Trail & Monitoring

### GitHub Actions
- View all auto-triggered workflows: **Actions → post-merge-cleanup-deploy**
- Each run shows:
  - ✅/⚠️ Merge verification
  - ✅/⚠️ Branch cleanup result
  - ✅/⚠️ Deployment dispatch
  - ✅/⚠️ Issue auto-close
  - Timeline of when each happened

### Pull Request
- Auto-comment posted to PR with completion status
- Links to deployment results
- Shows which issues were closed

### In Issues
- Auto-comment added when issue is closed by merged PR
- Shows: PR number, deployment status, branch cleanup
- Permanent audit trail

---

## 🔐 Security & Safety

### No Risk of Accidental Deletion
- **Only merged branches** auto-delete (not open PRs)
- **Protected branches** are never touched
- **Manual verification** before delete (git checks branch is actually merged)
- **Audit log** records all actions with timestamps and actors

### Approval Still Required
This automation does NOT bypass code review. To trigger it, you still need:
1. ✅ 2 code reviews + approval
2. ✅ All CI checks passing
3. ✅ Code owner review (if required)
4. ✅ Signed commits (security requirement)
5. ✅ Branch up-to-date with main

**Only then** can someone click "Merge" → automation runs.

### Rollback Process
If something breaks:
1. Revert the merge (create new PR with revert commit)
2. Merge the revert to main
3. Automation redeployment cascades
4. The issue for the original work stays in history (just closed)

---

## 📖 Step-by-Step: How to Use This

### For Developers

#### 1. Create issue in GitHub
```
Title: "Add user authentication"
Description: Goal, requirements, acceptance criteria
Labels: enhancement, component/auth, effort/m, P1-high
```

#### 2. Create branch from main
```bash
git checkout -b auth/add-user-login
git push -u origin auth/add-user-login
```

#### 3. Do your work
```bash
# Write code, commit, push
git add .
git commit -m "feat: implement user login"
git push
```

#### 4. Create PR linked to issue
```
Title: Implement user authentication

Closes #27

## Description
Adds login/logout functionality...

## Testing
- [x] All tests pass
- [x] E2E tests verify login flow
```

#### 5. Code review happens (manually, as usual)
- Peer reviews, approves
- CI checks pass
- All requirements met

#### 6. Click "Merge" ← THIS IS WHERE MAGIC HAPPENS
```
🤖 Automation starts immediately:
  ✅ 0s   - Merge verified
  ✅ 5s   - Branch auth/add-user-login deleted from remote
  ✅ 15s  - Deployment workflow triggered
  ✅ 30s  - Issue #27 auto-closed
  ✅ 2min - Code live in production
  ✅ 3min - Completion summary posted
```

#### 7. Monitor deployment (optional, it's automated)
- Click "Actions" tab to see deployment progress
- Or just trust the system (it's robust)

**Result:** `#27` shows:
- ✅ Closed (by PR)
- 💬 Auto-comment with deployment link
- 📋 Full audit trail

---

## ⚙️ Configuration & Customization

### Disable Auto-Deploy (Not Recommended)
If you need to merge without deploying (very rare):
1. Mark PR with `skip-deploy` label
2. Merge as normal
3. Cleanup still happens, deploy is skipped
4. Manually deploy when ready

### Conditional Deployment
Modify `.github/workflows/post-merge-cleanup-deploy.yml`:
```yaml
if: |
  needs.check-merge.outputs.merged == 'true' &&
  !contains(github.event.pull_request.labels.*.name, 'skip-deploy')
```

### Different Deployment Targets
Link multiple deployment workflows:
```yaml
- name: Trigger Staging Deploy
  if: contains(github.event.pull_request.labels.*.name, 'staging')
  uses: actions/github-script@v7
  with:
    script: |
      await github.rest.actions.createWorkflowDispatch({
        ...deploy-to-staging.yml...
      });
```

---

## 📊 Metrics & Reporting

### What Gets Tracked
- **Branch cleanup success rate** (target: 99.9%)
- **Deployment trigger success rate** (target: 99.9%)
- **Time from merge to live** (target: <10 minutes p95)
- **Issue auto-close accuracy** (target: 100%)
- **False positives / false negatives** (target: 0)

### Monitoring
Check weekly: `Actions → post-merge-cleanup-deploy → Recent runs`
- Green checkmarks = working as designed
- Orange/red = investigate immediately

---

## 🤔 FAQ

### Q: What if I need to delete a branch without merging?
**A**: Use `git push origin --delete branch-name` manually. Automation only deletes merged branches.

### Q: Can I merge without auto-deploying?
**A**: Label PR with `skip-deploy`, then manually trigger deployment when ready.

### Q: What if deployment fails?
**A**: Deployment status shows in PR. Fix and redeploy via Actions tab. Auto-revert is NOT automatic (manual gating is intentional).

### Q: Does #close in commit messages work?
**A**: No, only PR description linkage is tracked. Always use PR body for reliability.

### Q: Can a branch not be deleted due to protection?
**A**: Yes. Protected branches are skipped. Unprotect if you want auto-deletion.

### Q: What about private branches (personal feature branches)?
**A**: All branches follow the same rules. Clean up after merge.

---

## 🚀 Getting Started

### 1. ✅ Verify Workflow Is Installed
```bash
ls -la .github/workflows/post-merge-cleanup-deploy.yml
```

### 2. ✅ Test With a Real PR
- Create a feature branch
- Make a small change
- Open PR (link to an issue)
- Get it approved
- Merge
- Watch the automation run in Actions tab

### 3. ✅ Document in Your Team Wiki
- Link to this policy
- Post workflow diagram
- Share with team

### 4. ✅ Update Issue Templates
- Require PR description to link issues
- Remind team: "Closes #number" syntax

---

## 📝 Compliance & Enforcement

### This Mandate Is Binding
- Non-compliance blocks future merges
- Branch protection rules enforce code review
- Audit trail shows all merge events
- No exceptions without CTO approval

### Audit Trail
Every merge creates a permanent record:
1. GitHub PR history
2. Workflow run logs
3. Issue closed comments
4. Deployment records
5. Git commit log

---

## 🔄 Versioning & Updates

**Current Policy Version**: 1.0
**Last Updated**: April 14, 2026
**Next Review**: May 14, 2026

Changes to this policy require:
- [ ] Approval from engineering lead
- [ ] Update to this document
- [ ] Team notification
- [ ] Workflow code review

---

## 🎓 Learning Resources

- **GitHub Actions Docs**: https://docs.github.com/en/actions
- **Workflow Triggers**: https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows
- **Branch Protection**: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches
- **Issue Linking**: https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues

---

**Questions? Issues? Contact the DevOps team or file a GitHub issue in this repository.**
