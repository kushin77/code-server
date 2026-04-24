# PR #952 Merge Resolution Guide

## Current Status
PR #952 has merge conflicts that prevent automatic merge. This guide provides step-by-step instructions to resolve them.

## Conflict Files
Based on earlier merge attempt, these files have conflicts:
- docker-compose.yml
- scripts/ci/detect-config-drift.sh
- scripts/ops/redeploy.sh

## Resolution Steps

### Option 1: Accept Branch Version (Recommended for Issue #950 fixes)
```bash
cd c:\code-server-enterprise

# Fetch the latest
git fetch origin

# Check out a temporary branch to resolve conflicts
git checkout -b merge-issue-950 origin/main

# Merge, preferring our (deployment branch) version
git merge -X theirs origin/sanitized/redeploy-pr

# If there are still conflicts, manually resolve them:
# For each conflicted file, choose the version you want

# Commit the merge
git commit -m "Merge Issue #950 deployment epic - resolved conflicts preferring deployment branch"

# Push back to main
git push origin merge-issue-950:main
```

### Option 2: Automated GitHub Resolution (via GitHub UI)
1. Go to PR #952: https://github.com/kushin77/code-server/pull/952
2. Click "Resolve conflicts" button
3. GitHub's conflict editor will appear
4. For each conflict, choose the correct version:
   - For docker-compose.yml: Choose the sanitized/redeploy-pr version (has our fixes)
   - For scripts: Choose the sanitized/redeploy-pr version (has our improvements)
5. Click "Mark as resolved"
6. Click "Commit merge"

### Option 3: Force Merge (if authorized)
```bash
gh pr merge 952 --repo kushin77/code-server --admin --merge --force
```

## After Merge
Once PR #952 is merged to main:

1. GitHub Actions deploy.yml will automatically trigger
2. Monitor at: https://github.com/kushin77/code-server/actions?workflow=deploy.yml
3. Approve the "production" environment when prompted
4. Deployment completes automatically

## Verification
After deployment completes:
```bash
ssh akushnir@192.168.168.31 'docker compose ps'
```

All 10 services should show "Up" or "healthy".

## Support
- Issue #950: https://github.com/kushin77/code-server/issues/950
- PR #952: https://github.com/kushin77/code-server/pull/952
- Deployment Guide: /ISSUE-950-DEPLOYMENT-EXECUTION-GUIDE.md
