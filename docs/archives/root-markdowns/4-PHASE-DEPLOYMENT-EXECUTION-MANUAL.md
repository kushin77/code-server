# 4-Phase Cluster Deployment Execution Manual — April 24, 2026

**Status**: ✅ READY FOR IMMEDIATE EXECUTION  
**Priority**: HIGH (P0 #1650 blocks cluster parity)  
**Duration**: ~45-60 minutes  
**Prepared**: April 24, 2026  

---

## Overview

Execute three recent commits to production cluster:
- **ca7ff080** — WebSocket task sync + JWT diagnostics
- **0c050374** — Replica 1 remediation script  
- **2355eb97 / 2d4d0c08** — Documentation

**Objective**: Achieve full cluster parity with both replicas running identical code and state.

---

## Prerequisites

✅ SSH key available: `~/.ssh/id_rsa_onprem`  
✅ Replica 1: 192.168.168.31 (akushnir user)  
✅ Replica 2: 192.168.168.42 (akushnir user)  
✅ Local git repository: `/mnt/c/code-server-enterprise` (WSL) or `C:\code-server-enterprise` (Windows)  

---

## PHASE 1: Pull Latest Code

**Duration**: 5 minutes  
**Location**: Local machine

### Option A: Automated (Recommended)

```bash
bash scripts/ops/EXECUTE-4-PHASE-DEPLOYMENT-APRIL-24.sh 1
```

### Option B: Manual

```bash
cd /mnt/c/code-server-enterprise

# Pull latest code
git pull origin main

# Verify commits
git log --oneline -5
```

### Expected Output

```
2d4d0c08 docs: session work summary
2355eb97 docs: session completion
0c050374 fix(ops): Replica 1 remediation  
ca7ff080 feat(collab-9): WebSocket task sync
[... previous commits ...]
```

### Success Criteria

✅ Git pull completes without errors  
✅ Local HEAD is at commit 2d4d0c08  
✅ All five commits present in history  

---

## PHASE 2: Deploy WebSocket to Both Replicas

**Duration**: 15-20 minutes  
**Location**: Both replicas (parallel execution recommended)

### Option A: Automated (Recommended)

```bash
# Dry-run first (no changes)
bash scripts/ops/EXECUTE-4-PHASE-DEPLOYMENT-APRIL-24.sh 2 --dry-run

# Execute
bash scripts/ops/EXECUTE-4-PHASE-DEPLOYMENT-APRIL-24.sh 2
```

### Option B: Manual - Replica by Replica

```bash
# Deploy to Replica 1
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31

# Deploy to Replica 2
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.42
```

### Option C: Manual - Parallel Deployment

```bash
# Start both in background
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31 &
DEPLOY_PID_1=$!

bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.42 &
DEPLOY_PID_2=$!

# Wait for both to complete
wait $DEPLOY_PID_1
wait $DEPLOY_PID_2

echo "Both deployments complete"
```

### Expected Output

```
Collab-9 production deployment
Deploy user: akushnir
Deploy dir: code-server-enterprise
Targets: 192.168.168.31 192.168.168.42
Dry run: no

[... deployment progress ...]

✓ Replica 1 deployment completed
✓ Replica 2 deployment completed
```

### Success Criteria

✅ Both replicas receive WebSocket code  
✅ docker-compose pull completes on both  
✅ Services restart without errors  
✅ WebSocket endpoint available  

### Verification (Optional)

```bash
# Test WebSocket endpoint on Replica 1
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  https://192.168.168.31:443/ws/task-sync

# Check JWT diagnostics
curl -s https://192.168.168.31:443/diagnostics/jwt/health | jq .
```

---

## PHASE 3: Fix Replica 1 Permissions (P0 #1650)

**Duration**: 10-15 minutes  
**Location**: Replica 1 (192.168.168.31)

### Critical Note

This phase fixes file permissions and git state on Replica 1. **Requires sudo passwordless access** on Replica 1 for akushnir user.

**Verify sudo is configured:**

```bash
ssh akushnir@192.168.168.31 "sudo -l | grep NOPASSWD"
# Should show passwordless sudo is available
```

If sudo is NOT passwordless, you must configure it first:

```bash
ssh akushnir@192.168.168.31 "echo 'akushnir ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/akushnir"
```

### Option A: Automated (Recommended)

```bash
# Dry-run first
DRY_RUN=1 bash scripts/ops/fix-replica-1-permissions.sh

# Execute
bash scripts/ops/fix-replica-1-permissions.sh
```

### Option B: Manual Step-by-Step

```bash
# SSH to Replica 1
ssh akushnir@192.168.168.31

# Fix file ownership
sudo chown -R akushnir:akushnir code-server-enterprise/

# Clean git state
cd code-server-enterprise
git clean -fdx
git reset --hard origin/main

# Pull latest and redeploy
git pull --ff-only origin main
docker compose pull
docker compose up -d

# Verify git status
git status
# Should show: "On branch main, nothing to commit, working tree clean"

exit
```

### Expected Output

```
Replica 1 Permission Remediation
Host: 192.168.168.31
User: akushnir
Deploy dir: code-server-enterprise
Dry run: no

SSH access verified
Fixing file ownership on 192.168.168.31...
✓ File ownership fixed

Cleaning git state on 192.168.168.31...
✓ Git state cleaned

Redeploying on 192.168.168.31...
✓ Redeployment completed

Verifying git status on 192.168.168.31...
Replica 1 commit: 2d4d0c08
✓ Verification passed
```

### Success Criteria

✅ File ownership fixed to akushnir:akushnir  
✅ Git state cleaned (no uncommitted changes)  
✅ Latest code pulled and services redeployed  
✅ Replica 1 commit is 2d4d0c08 (latest)  
✅ Git status shows "working tree clean"  

---

## PHASE 4: Validate Cluster Parity

**Duration**: 5-10 minutes  
**Location**: Both replicas

### Option A: Automated (Recommended)

```bash
bash scripts/ops/EXECUTE-4-PHASE-DEPLOYMENT-APRIL-24.sh 4
```

### Option B: Manual Validation

```bash
# ========== VERIFY COMMITS MATCH ==========
echo "=== COMMIT PARITY ===" 
for h in 192.168.168.31 192.168.168.42; do
  echo -n "$h: "
  ssh akushnir@$h 'cd code-server-enterprise && git rev-parse --short HEAD'
done

# ========== VERIFY GIT STATUS CLEAN ==========
echo ""
echo "=== GIT STATUS ===" 
for h in 192.168.168.31 192.168.168.42; do
  echo "$h:"
  ssh akushnir@$h 'cd code-server-enterprise && git status --short' || echo "  (error)"
done

# ========== VERIFY SERVICES RUNNING ==========
echo ""
echo "=== RUNNING CONTAINERS ===" 
for h in 192.168.168.31 192.168.168.42; do
  echo "$h:"
  ssh akushnir@$h 'docker ps --quiet | wc -l' | xargs -I {} echo "  Count: {}"
done

# ========== VERIFY HEALTH ENDPOINTS ==========
echo ""
echo "=== HEALTH ENDPOINTS ===" 
for h in 192.168.168.31 192.168.168.42; do
  echo -n "$h: "
  curl -s -o /dev/null -w "HTTP %{http_code}\n" http://${h}:3000/health/ready
done

# ========== VERIFY WEBSOCKET DEPLOYMENT ==========
echo ""
echo "=== WEBSOCKET ENDPOINTS ===" 
for h in 192.168.168.31 192.168.168.42; do
  echo "$h:"
  curl -s https://${h}:443/diagnostics/jwt/health | jq '.status' || echo "  (error or not ready)"
done
```

### Expected Output

```
=== COMMIT PARITY ===
192.168.168.31: 2d4d0c08
192.168.168.42: 2d4d0c08

=== GIT STATUS ===
192.168.168.31:
192.168.168.42:
(both should show no output = clean)

=== RUNNING CONTAINERS ===
192.168.168.31:
  Count: 38
192.168.168.42:
  Count: 38

=== HEALTH ENDPOINTS ===
192.168.168.31: HTTP 200
192.168.168.42: HTTP 200

=== WEBSOCKET ENDPOINTS ===
192.168.168.31:
  "ok"
192.168.168.42:
  "ok"
```

### Success Criteria

✅ Both replicas on commit **2d4d0c08**  
✅ Both replicas have **clean git status** (no uncommitted changes)  
✅ Both replicas running **38+ containers**  
✅ Both replicas return **HTTP 200** on health checks  
✅ WebSocket endpoints return **"ok"** status  
✅ **CLUSTER PARITY ACHIEVED** ✓  

---

## EXECUTION SUMMARY

| Phase | Task | Duration | Status |
|-------|------|----------|--------|
| 1 | Pull latest code | 5 min | Ready |
| 2 | Deploy WebSocket to replicas | 15-20 min | Ready |
| 3 | Fix Replica 1 permissions | 10-15 min | Ready |
| 4 | Validate cluster parity | 5-10 min | Ready |
| **TOTAL** | **Full Execution** | **~45-60 min** | **READY** |

---

## Troubleshooting

### Phase 1 - Git pull fails

```bash
# Check git state
git status

# If you have local changes, stash them
git stash

# Try pull again
git pull origin main
```

### Phase 2 - Deployment script not found

```bash
# Verify script exists
ls -la scripts/ops/collab-9-deploy.sh

# If missing, git pull again and verify
git status
```

### Phase 3 - Sudo password required

**Problem**: Script prompts for sudo password  
**Solution**: Configure passwordless sudo on Replica 1

```bash
ssh akushnir@192.168.168.31 "echo 'akushnir ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/akushnir"
```

Then retry Phase 3.

### Phase 3 - Git operations fail

```bash
# SSH to Replica 1 manually
ssh akushnir@192.168.168.31

# Check what's blocking git
cd code-server-enterprise
git status

# If files are locked or corrupted, reset harder
git clean -ffdx
git reset --hard origin/main

exit
```

### Phase 4 - Health checks fail

```bash
# Check if containers are running
ssh akushnir@192.168.168.31 "docker ps"

# Check logs on failed service
ssh akushnir@192.168.168.31 "docker compose logs [service-name]"

# Restart services if needed
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker compose restart"
```

---

## Rollback Procedure

If any phase fails and you need to rollback:

```bash
# Option 1: Revert to previous commit
git revert 2d4d0c08
git push origin main

# Option 2: If not yet pushed, reset locally
git reset --soft HEAD~1

# Notify operations team and investigate failure
```

---

## Post-Execution Checklist

- [ ] Phase 1: Code pulled successfully
- [ ] Phase 2: WebSocket deployed to both replicas
- [ ] Phase 3: Replica 1 permissions fixed and redeployed
- [ ] Phase 4: Cluster parity validated (both on 2d4d0c08)
- [ ] Health checks passing on both replicas
- [ ] No uncommitted changes on either replica
- [ ] WebSocket endpoints responding correctly
- [ ] Epic #1616 unblocked (cluster parity achieved)

---

## Next Steps After Execution

Once all 4 phases complete:

1. **Close related issues**: 
   - Issue #1650 (Replica 1 permissions)
   - Issue #1616 (Cluster parity epic)

2. **Enable failover testing**:
   - Run failover simulation tests
   - Verify automatic recovery

3. **Monitor cluster**:
   - Watch health checks for 30 minutes
   - Monitor metrics in Prometheus
   - Check logs in Loki

4. **Document execution**:
   - Create post-execution report
   - Update runbooks if needed
   - Archive logs for audit trail

---

## Contact & Support

**On-Premises Cluster**: 192.168.168.31 / 192.168.168.42  
**Deploy User**: akushnir  
**SSH Key**: `~/.ssh/id_rsa_onprem`  
**Repository**: kushin77/code-server (main branch)  

For issues or blockers, check:
- Deployment script logs
- GitHub issue comments (#1650, #1616)
- Docker compose logs on affected replica
- SSH connectivity and permissions

---

**Prepared**: April 24, 2026  
**Version**: 1.0  
**Status**: READY FOR EXECUTION
