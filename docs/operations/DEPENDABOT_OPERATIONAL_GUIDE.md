# Dependabot Integration Operational Guide
**Automated Base Image & Dependency Update Pipeline — April 29, 2026**

---

## Quick Start

```bash
# No action required - Dependabot runs automatically!
# Just review and merge PRs as they appear

# View pending updates:
gh pr list --label dependencies --state open

# Monitor auto-merge status:
gh pr list --label dependencies --author dependabot[bot] --state closed
```

---

## How It Works

### Daily Monitoring

```
Every day at 3:00 AM UTC:
├─ Dependabot checks Docker Hub for base image updates
├─ Checks PyPI for Python package updates
├─ Checks npm registry for npm updates
└─ Checks GitHub Actions marketplace for workflow updates
```

### When Update Available

```
1. Dependabot detects: python:3.11.3 → 3.11.4
2. Creates branch: dependabot/docker/python-3.11.4
3. Updates Dockerfile: FROM python:3.11.4-slim
4. Creates PR to develop branch
5. Workflow runs: .github/workflows/dependabot-auto-merge.yml
6. Tests pass? → Auto-merge (squash)
7. Merge → GitHub Actions builds new images
```

---

## PR Types

### 1. Base Image Updates

```
Title: chore(deps): Bump python from 3.11.3 to 3.11.4
Files changed:
  - Dockerfile (1 line: FROM python:3.11.4-slim)
Auto-merge: Yes (patch update)
Trigger: New images built automatically
```

### 2. Dependency Version Bumps

```
Title: chore(deps): Bump torch from 2.0.0 to 2.1.0
Files changed:
  - apps/multimodal-ai/requirements.txt (torch line updated)
Auto-merge: Conditional (minor = manual review)
Rebuild: If auto-merged, all services using torch rebuild
```

### 3. Security Updates

```
Title: chore(deps): Bump setuptools to 65.5.1 (CVE-2024-1234)
Files changed:
  - apps/*/requirements.txt (setuptools pinned)
Label: security
Auto-merge: Always (critical priority)
Alert: Slack/email notification
```

---

## Monitor Updates

### GitHub UI

```
1. Go to https://github.com/kushnir/code-server/pulls
2. Filter: Label "dependencies"
3. View all Dependabot PRs
```

### Command Line

```bash
# List open Dependabot PRs
gh pr list --label dependencies --state open

# Example output:
#  Nº    TITLE                                          STATE  AUTHOR
#  123   chore(deps): Bump python from 3.11.3...      OPEN   dependabot[bot]
#  124   chore(deps): Bump torch from 2.0.0...        OPEN   dependabot[bot]
#  125   chore(deps): Bump transformers from 4.30...  OPEN   dependabot[bot]

# Check specific PR status
gh pr checks 123

# View PR diff
gh pr diff 123
```

---

## Manual Approval

### For Patch/Minor Updates (should auto-merge)

If PR doesn't auto-merge:

```bash
# 1. Review changes
gh pr view 123

# 2. Check workflow failures
gh pr checks 123

# 3. If no issues, manually merge
gh pr merge 123 --squash

# 4. Delete branch
gh pr delete 123 --delete-branch
```

### For Major Updates (manual required)

```bash
# 1. Review changelog
gh pr view 124 --web  # Opens in browser

# 2. Check breaking changes
# Look at:
# - CHANGELOG in base image/package
# - Code examples in PR description
# - Test results in workflow

# 3. If safe, approve:
gh pr review 124 --approve

# 4. Merge (not auto-merge for major):
gh pr merge 124 --squash --auto
```

---

## Common Tasks

### Reject a PR

```bash
# If update causes issues:
gh pr close 123 --delete-branch

# Or revert if already merged:
git revert HEAD~1  # Revert last merge
git push
```

### Adjust Update Frequency

```bash
# Edit .dependabot/config.yml:
updates:
  - package-ecosystem: "docker"
    schedule:
      interval: "weekly"   # or "daily", "monthly"
      day: "monday"        # which day
      time: "03:00"        # UTC

# Commit and push
git add .dependabot/config.yml
git commit -m "chore: adjust dependabot frequency"
git push
```

### Skip a Service

```yaml
# In .dependabot/config.yml:
ignore:
  - dependency-name: "python"
    versions: ["3.13.*"]  # Skip Python 3.13 for now
```

---

## Troubleshooting

### PR stuck (not auto-merging)

```bash
# Check workflow status
gh pr checks <PR_NUMBER>

# If workflow failed:
gh pr view <PR_NUMBER> --web  # View logs

# Common issues:
# 1. Tests failed → Must fix before merge
# 2. Branch protection requires approval → Approve manually
# 3. Merge conflict → Rebase (Dependabot auto-rebases weekly)
```

### Too many PRs (rate limiting)

```bash
# Reduce in .dependabot/config.yml:
open-pull-requests-limit: 3  # (instead of 5)

# Or close some manually:
gh pr close <NUMBER> --delete-branch
```

### Update breaks something

```bash
# Identify the issue
# Check logs in GitHub Actions

# Revert the merge
git revert <COMMIT_HASH>
git push

# Post comment on related Dependabot PR
gh pr comment <NUMBER> -b "Reverted due to X issue. Please fix and retry."

# Create issue to track problem
gh issue create --title "Fix dependency compatibility" --body "..."
```

---

## Performance Expectations

### Frequency

```
Base images:      1-3 updates/week
Python packages:  2-5 updates/week
npm packages:     1-3 updates/week (if applicable)
Security alerts:  1-10 updates/month (varies by ecosystem)
```

### Time to Production

```
Auto-merged (patch):    5-10 minutes
Manual-merged (minor):  24-48 hours
Security updates:       2-5 minutes
```

### Build Impact

```
Per update:
├─ Auto-test time:   1-2 minutes
├─ Build time:       2-5 minutes
├─ Push to registry: 1-2 minutes
└─ Total per PR:     4-9 minutes

Monthly impact:
├─ ~30-40 updates
├─ ~150-360 minutes build time
└─ ≈ 2.5-6 hours CI/CD per month
```

---

## Best Practices

1. **Review Major Updates** - Don't auto-merge major versions
2. **Monitor Security Alerts** - Act immediately on CVE fixes
3. **Keep Branches Fresh** - Dependabot rebases stale PRs weekly
4. **Test Before Merge** - Let workflows run fully
5. **Use Auto-Merge for Patches** - Speed up safe updates
6. **Document Breaking Changes** - Track what changed each release

---

## Integration with CI/CD

### Build Pipeline

```
Dependabot PR merged
        ↓
GitHub commit detected (in develop/main)
        ↓
.github/workflows/build-docker-images.yml triggers
        ↓
Git diff detects changed Dockerfile or requirements.txt
        ↓
Services affected by change rebuild
        ↓
New images tagged and pushed to registry
        ↓
docker-compose.registry-override.yml can pull new versions
```

### Example Flow

```bash
# Commit 1: Dependabot updates python:3.11 in Dockerfile
# ↓
# CI/CD detects: Dockerfile changed
# ↓
# Rebuilds all services using this base
# ↓
# New images: multimodal-ai:1.0.0, multimodal-ai:latest, etc.
# ↓
# Pushed to registry
# ↓
# Staged rollout can now use new version:
./scripts/staged-rollout.sh --stage canary --version=1.0.0
```

---

## Monitoring & Alerts

### GitHub Actions Notifications

```
Opt in to notifications:
Settings → Notifications → Custom → Enable "All"

You'll see:
- PR created: "Dependabot created pull request #123"
- Status checks: Pass/fail of tests
- Auto-merge: "Auto-merge enabled" or "Merge failed"
```

### Slack Integration (Optional)

```bash
# Set up GitHub App in Slack workspace
# Slack will notify on:
# - PR created
# - PR auto-merged
# - PR failed tests
# - PR closed/reverted

# Or use GitHub Actions to post:
- name: Notify Slack on security update
  if: contains(github.event.pull_request.labels, 'security')
  run: |
    curl -X POST $SLACK_WEBHOOK \
      -d "Security update merged: $PR_TITLE"
```

---

## Summary

**Dependabot automates the tedious task of updating dependencies.**

You just need to:
1. ✅ Let it run automatically (no config needed after setup)
2. ✅ Review PRs as they arrive (focus on major versions)
3. ✅ Trust auto-merge for patches/security fixes
4. ✅ Enjoy up-to-date base images and packages

The entire pipeline from update detection to production deployment is fully automated.
