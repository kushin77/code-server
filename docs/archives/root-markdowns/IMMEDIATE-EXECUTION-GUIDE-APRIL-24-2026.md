# IMMEDIATE EXECUTION GUIDE - April 24, 2026

**Priority**: HIGH  
**Audience**: Operations Team  
**Timeline**: Execute in this order  

## What Changed

Three commits added to main branch:

1. **ca7ff080** - WebSocket task sync + JWT diagnostics (feature)
2. **0c050374** - Replica 1 remediation script (P0 fix)  
3. **2355eb97** + **2d4d0c08** - Documentation

## Execution Roadmap

### ⏱️ PHASE 1: Pull Latest Code (5 minutes)

On your local machine:
```bash
cd code-server-enterprise
git pull origin main
```

Then verify the three new commits are present:
```bash
git log --oneline -5
# Should show:
# 2d4d0c08 docs: session work summary
# 0c050374 fix(ops): Replica 1 remediation  
# 2355eb97 docs: session completion
# ca7ff080 feat(collab-9): WebSocket task sync
```

### ⏱️ PHASE 2: Deploy WebSocket Task Sync to Both Replicas (15-20 minutes)

**Pre-check - Dry Run**:
```bash
bash scripts/ops/collab-9-deploy.sh --dry-run --hosts 192.168.168.31,192.168.168.42
```

**Deploy**:
```bash
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42
```

**Health Check**:
```bash
# Should return healthy status
curl https://ide.kushnir.cloud/diagnostics/jwt/health | jq .

# Check websocket endpoint
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  https://ide.kushnir.cloud/ws/task-sync
```

### ⏱️ PHASE 3: Fix Replica 1 Permissions (P0 #1650) (10-15 minutes)

**Critical**: This blocks multi-replica cluster parity

**Pre-check - Dry Run**:
```bash
DRY_RUN=1 bash scripts/ops/fix-replica-1-permissions.sh
```

**Execute**:
```bash
bash scripts/ops/fix-replica-1-permissions.sh
```

**Verify**:
```bash
# Both replicas should show same commit
echo "Replica 1:" && ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git rev-parse --short HEAD'
echo "Replica 2:" && ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && git rev-parse --short HEAD'
# Both should output: 2d4d0c08 (or latest main)

# Check git status on Replica 1
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git status'
# Should output: "On branch main, nothing to commit, working tree clean"
```

### ⏱️ PHASE 4: Validate Cluster Parity (5-10 minutes)

After Replica 1 fix, verify both replicas are identical:

```bash
# Verify commits match
for h in 192.168.168.31 192.168.168.42; do
  echo "$h commit:" && ssh akushnir@$h 'cd ~/code-server-enterprise && git rev-parse --short HEAD'
done

# Verify services are running on both
for h in 192.168.168.31 192.168.168.42; do
  echo "=== $h services ===" 
  ssh akushnir@$h 'docker compose ps' | grep -E "CONTAINER ID|Up"
done

# Verify health endpoints
for h in 192.168.168.31 192.168.168.42; do
  echo "=== $h health ===" 
  curl -s http://${h}:3000/health/ready | jq '.status'
done
```

## Quick Reference Commands

```bash
# Deploy WebSocket sync to both replicas
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42

# Fix Replica 1 permissions
bash scripts/ops/fix-replica-1-permissions.sh

# Dry-run any operation first
DRY_RUN=1 bash scripts/ops/<script>.sh

# Verify both replicas are synced
for h in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$h 'cd ~/code-server-enterprise && git rev-parse --short HEAD'
done

# Check services on both replicas
for h in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$h 'docker compose ps'
done
```

## Rollback If Needed

If issues occur at any phase:

```bash
# Revert to previous state
git revert 2d4d0c08  # OR 0c050374 OR ca7ff080
git push origin main

# OR if not yet pushed, just reset
git reset --soft HEAD~1
```

## Expected Results

✅ **After PHASE 2 (WebSocket Deploy)**:
- Both replicas have WebSocket endpoint at /ws/task-sync
- JWT diagnostics available at /diagnostics/jwt/health
- Real-time issue updates working

✅ **After PHASE 3 (Replica 1 Fix)**:
- Replica 1 file permissions corrected
- Replica 1 git status clean
- Both replicas on same commit

✅ **After PHASE 4 (Validation)**:
- Cluster parity achieved (identical state on both replicas)
- Epic #1616 unblocked
- Failover tests can execute

## Issues & Support

- **Phase 2 fails**: Check docker-compose.yml syntax, ensure oauth2-proxy config correct
- **Phase 3 fails**: Verify sudo passwordless on akushnir@192.168.168.31
- **Health checks fail**: Run `docker compose logs` on failed replica

## Timeline Summary

| Phase | Task | Duration | Status |
|-------|------|----------|--------|
| 1 | Pull latest | 5 min | Ready |
| 2 | Deploy WebSocket | 15-20 min | Ready |
| 3 | Fix Replica 1 | 10-15 min | Ready |
| 4 | Validate | 5-10 min | Ready |
| **Total** | **Full Execution** | **~45-60 min** | **READY** |

---

**Prepared**: April 24, 2026  
**Status**: READY FOR IMMEDIATE EXECUTION  
**Priority**: HIGH (P0 infrastructure issue blocks cluster parity)  
**Requester**: Operations Team
