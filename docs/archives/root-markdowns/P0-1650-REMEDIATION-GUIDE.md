# P0 Issue #1650 Remediation Guide - Replica 1 File Permissions

**Issue**: P0 Infrastructure - Replica 1 (192.168.168.31) file permission blocker  
**Status**: In Remediation  
**Created**: 2026-04-24 (Session response to April 23 issue)  

## Problem Summary

Replica 1 has file ownership issues that prevent git operations and deployments:
- Files in `tests/e2e/test-results` owned by different user
- Config files in `config/iam/` and `config/grafana/` not writable
- Blocks: git reset, git clean, code deployment, service updates
- Blocks: Epic #1616 (multi-replica cluster parity)
- Blocks: Failover continuity tests

Current Status:
- Replica 1: Commit 2724df72 (BEHIND)
- Replica 2: Commit ca7ff080+ (CURRENT)
- Main: Commit 2355eb97 (LATEST - just committed)

## Root Cause

Docker containers running as different user than `akushnir`. File ownership mismatch prevents git operations and service management.

## Solution Steps

### Option 1: Using Automated Remediation Script (Recommended)

```bash
# From local machine:
# Option A - Dry run first (safe, shows what would happen)
DRY_RUN=1 bash scripts/ops/fix-replica-1-permissions.sh

# Option B - Execute remediation
bash scripts/ops/fix-replica-1-permissions.sh
```

### Option 2: Manual SSH Commands

Execute on Replica 1 (192.168.168.31):

```bash
# 1. Fix file ownership
sudo chown -R akushnir:akushnir ~/code-server-enterprise/

# 2. Clean git state
cd ~/code-server-enterprise
git clean -fdx
git reset --hard origin/main

# 3. Redeploy services
docker compose pull
docker compose up -d

# 4. Verify
git rev-parse --short HEAD
git status
```

### Option 3: SSH Commands from Local Machine

```bash
# Fix ownership
ssh akushnir@192.168.168.31 'sudo chown -R akushnir:akushnir ~/code-server-enterprise/'

# Clean and sync
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git clean -fdx && git reset --hard origin/main'

# Redeploy
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker compose pull && docker compose up -d'

# Verify
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git rev-parse --short HEAD'
```

## Verification Checklist

After remediation, verify:

```bash
# 1. Check Replica 1 commit matches main
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git rev-parse --short HEAD'
# Should output: 2355eb97 (or latest main commit)

# 2. Check git status is clean
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git status'
# Should output: "On branch main, nothing to commit, working tree clean"

# 3. Check docker services are running
ssh akushnir@192.168.168.31 'docker compose ps'
# Should show all services as "Up"

# 4. Check file ownership
ssh akushnir@192.168.168.31 'ls -ld ~/code-server-enterprise'
# Should show: drwxr-xr-x akushnir akushnir

# 5. Check both replicas are now synced
echo "=== Replica 1 ===" && ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git rev-parse --short HEAD'
echo "=== Replica 2 ===" && ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && git rev-parse --short HEAD'
# Both should output the same commit SHA
```

## Deployment Parallel Execute After Fix

Once Replica 1 is fixed, execute full cluster parity:

```bash
# Deploy latest to both replicas in parallel
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42

# Verify health after deployment
for host in 192.168.168.31 192.168.168.42; do
  echo "=== $host ===" 
  curl -s http://${host}:3000/health/ready | jq .
done
```

## Rollback Plan

If remediation causes issues:

```bash
# Restore to known-good state on Replica 1
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git reset --hard HEAD~1'

# Or restore from Replica 2 (if it's known-good)
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git fetch origin && git checkout origin/main'
```

## Related Issues

- Fixes: #1650 (this issue)
- Blocks: #1616 (Epic - multi-replica cluster parity)
- Related: Failover continuity tests in test/e2e/

## Governance Notes

This remediation:
- ✅ Uses automated script (reusable, idempotent)
- ✅ Includes dry-run mode (safe preview)
- ✅ Follows infrastructure-as-code principles
- ✅ Has rollback plan documented
- ✅ Includes verification steps

## Success Criteria

✅ **Issue Resolved When**:
1. Replica 1 file permissions fixed (chown succeeds)
2. Replica 1 git status is clean
3. Replica 1 commit matches main branch
4. Both replicas are identical (same commit)
5. Services are running on both replicas
6. Failover tests can execute

---

**Remediation Script**: scripts/ops/fix-replica-1-permissions.sh  
**Status**: READY FOR EXECUTION  
**Created**: 2026-04-24  
**Priority**: P0 (blocks cluster parity)
