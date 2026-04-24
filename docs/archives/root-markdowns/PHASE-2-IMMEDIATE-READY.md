# Phase 2 Deployment: IMMEDIATE EXECUTION READY

**Date**: April 23, 2026  
**Status**: ✅ ALL EXECUTION FILES PREPARED - READY FOR IMMEDIATE START  
**Governance**: IaC, Immutable, Idempotent, Reversible  

---

## Quick Start (Copy-Paste)

```bash
cd /mnt/c/code-server-enterprise

# Execute all phases in sequence:
bash PHASE-2-EXECUTE-NOW.sh          # Deploy WebSocket (~20 min)
# Wait 30 minutes for monitoring
bash PHASE-3-EXECUTE-NOW.sh          # Fix Replica 1 permissions (~15 min)
bash PHASE-4-EXECUTE-NOW.sh          # Validate cluster parity (~10 min)
```

---

## Execution Files Available

### Ready to Execute Immediately:

1. **PHASE-2-EXECUTE-NOW.sh** — Interactive WebSocket deployment
   - Pre-deployment verification
   - Dry-run preview
   - Real deployment with user confirmation
   - Post-deployment verification
   - Status: ✅ READY

2. **PHASE-3-EXECUTE-NOW.sh** — Fix Replica 1 permissions (P0 #1650)
   - Prerequisites check
   - Dry-run preview
   - Real permission fix
   - Post-fix verification
   - Status: ✅ READY (after Phase 2)

3. **PHASE-4-EXECUTE-NOW.sh** — Validate cluster parity
   - Comprehensive verification
   - Detailed parity report
   - Health checks
   - Container status
   - Status: ✅ READY (after Phases 2-3)

### Reference Documentation:

- **COMPLETE-4-PHASE-EXECUTION-GUIDE.md** — Master guide (600+ lines)
- **PHASE-2-DEPLOYMENT-VERIFICATION-AND-EXECUTE.md** — Detailed Phase 2 procedures
- **PHASE-2-3-4-READINESS-CHECK.sh** — Pre-flight verification
- **4-PHASE-DEPLOYMENT-EXECUTION-MANUAL.md** — Step-by-step procedures
- **4-PHASE-DEPLOYMENT-EXECUTION-LOG.md** — Execution tracking

---

## What's Happening in Each Phase

### Phase 2: Deploy WebSocket (Collab-9 Task Sync)

**What**: Deploy WebSocket gateway to both production replicas for real-time task synchronization

**How**:
1. Verify SSH connectivity to both replicas
2. Dry-run to preview changes (no modifications)
3. Real deployment with user confirmation
4. Parallel deployment to both 192.168.168.31 and 192.168.168.42
5. Health check validation (10 retries, 5s each)

**Duration**: 15-20 minutes (deployment) + 5 minutes (verification)

**Expected Output**:
- Both replicas on commit 2d4d0c08
- All 38+ services deployed
- HTTP 200 health check responses
- WebSocket endpoints responding

**Rollback**: Instant via `git revert <commit>` and redeploy

---

### Phase 3: Fix Replica 1 Permissions (P0 #1650)

**What**: Remediate file ownership/permission issues blocking git operations on Replica 1

**How**:
1. Verify passwordless sudo configured
2. Dry-run to preview fixes
3. Apply fixes: chown, git reset, git pull
4. Redeploy services to Replica 1
5. Verify git state clean

**Duration**: 10-15 minutes

**Prerequisites**:
- Phase 2 must complete successfully
- Passwordless sudo required on Replica 1

**Expected Output**:
- Replica 1 ownership: akushnir:akushnir
- Git state clean (0 dirty files)
- Services redeployed and healthy

---

### Phase 4: Validate Cluster Parity

**What**: Comprehensive verification that all replicas are synchronized and production-ready

**How**:
1. Run comprehensive verification script
2. Check commit parity (all = 2d4d0c08)
3. Check git drift (all = 0 dirty files)
4. Check container health (all >= 38 services)
5. Check network connectivity
6. Generate parity report

**Duration**: 5-10 minutes

**Prerequisites**:
- Phase 2 and Phase 3 must complete successfully

**Expected Output**:
- Commit parity confirmed
- Git state clean
- All containers healthy
- Network connectivity verified
- Cluster ready for production

---

## Governance Compliance Verified

### ✅ Infrastructure as Code (IaC)
- **docker-compose.yml**: Source of truth (git-controlled)
- **.env.schema.json**: Configuration schema (git-controlled)
- **scripts/ops/collab-9-deploy.sh**: Deployment script (versioned)
- **All deployment logic**: In git, reviewed, immutable

**Evidence**:
```bash
cd /mnt/c/code-server-enterprise
git log --oneline docker-compose.yml | head -5  # See history
git log --oneline scripts/ops/collab-9-deploy.sh | head -5
```

### ✅ Immutable Deployment
- **Commits**: Fixed to 2d4d0c08 (no automatic updates)
- **Container images**: Versioned (e.g., codercom/code-server:4.115.0)
- **Configuration**: Schema-validated, no runtime overrides
- **No drift**: All changes via git commits and deployments

**Evidence**:
```bash
# Verify commit
git rev-parse HEAD  # Will stay at 2d4d0c08 until explicitly changed

# Verify container versions
grep "image:" docker-compose.yml | head -10
```

### ✅ Idempotent Operations
- **git pull --ff-only**: Safe to retry (fails if conflicts exist)
- **docker compose pull**: No-op if images already current
- **docker compose up -d**: Idempotent (creates/updates safely)
- **Scripts**: All operations safe to run multiple times

**Evidence**:
```bash
# Run Phase 2 twice:
bash PHASE-2-EXECUTE-NOW.sh
# ... (completes successfully)
bash PHASE-2-EXECUTE-NOW.sh
# ... (second run is no-op, all services already current)
```

### ✅ Reversible Changes
- **Full git history**: No commits lost
- **Instant rollback**: `git revert <commit> && git push`
- **No data loss**: All data persisted in volumes
- **Automatic failover**: Replicas continue on previous version

**Evidence**:
```bash
# If deployment causes issues:
git log --oneline | head -5  # Find last good commit
git revert --no-edit <commit_hash>
git push origin main
# Services automatically redeploy with previous version
```

---

## Pre-Flight Verification (Optional)

Before starting Phase 2, verify environment is ready:

```bash
# Run readiness check
bash PHASE-2-3-4-READINESS-CHECK.sh

# This will output:
# - Files present and correct
# - SSH connectivity to both replicas
# - Passwordless sudo status
# - Prerequisites status
# - Governance compliance summary
```

---

## Terminal Requirements

All phases use only standard Linux/bash utilities:
- `ssh` (remote connection)
- `bash` (scripts)
- `git` (version control)
- `docker` (container operations)
- `curl` (health checks)
- `grep`, `wc`, `awk` (text processing)

**No special tools required** — runs on any Linux/WSL environment with Docker Desktop and SSH key configured.

---

## Expected Timeline

| Phase | Task | Duration | Status |
|-------|------|----------|--------|
| 1 | Pull latest code | 5 min | ✅ COMPLETE |
| 2 | Deploy WebSocket | 20 min | ✅ READY |
| 3 | Fix Replica 1 (P0) | 15 min | ✅ READY |
| 4 | Validate parity | 10 min | ✅ READY |
| **Total** | **All 4 phases** | **~50 minutes** | **✅ READY** |

Plus 30 minutes recommended monitoring after Phase 2.

---

## Post-Deployment Tasks

After Phase 4 completes successfully:

1. **Close GitHub issues**:
   ```bash
   gh issue close 1616 --repo kushin77/code-server -c "Cluster parity validated. Both replicas on 2d4d0c08."
   gh issue close 1650 --repo kushin77/code-server -c "Replica 1 permissions fixed. Git operations restored."
   ```

2. **Monitor cluster** for 24 hours:
   - Check CPU/memory usage
   - Monitor network traffic
   - Watch for error logs
   - Verify WebSocket connections

3. **Next priority work**:
   - Issue #1662 (Collab-9 staging validation)
   - Additional features from roadmap

---

## Troubleshooting Quick Reference

### SSH Connection Failed
```bash
# Check SSH key
ls -la ~/.ssh/id_rsa_onprem
# Should show: -rw------- (600 permissions)

# Fix if needed
chmod 600 ~/.ssh/id_rsa_onprem

# Test connection
ssh -v akushnir@192.168.168.31 'echo test'
```

### Docker Pull Failed
```bash
# Check docker login
docker login

# Retry with no-parallel
docker compose pull --no-parallel
```

### Health Check Failed
```bash
# Check service logs on the replica
ssh akushnir@192.168.168.31 'docker compose logs -f'

# Wait and retry
sleep 30
bash PHASE-2-EXECUTE-NOW.sh
```

### Git State Issues
```bash
# Check git status on replica
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git status'

# Reset to known good state
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git reset --hard origin/main'
```

---

## Files Location

All execution files located at repository root:
```
/mnt/c/code-server-enterprise/

├── PHASE-2-EXECUTE-NOW.sh                    ← Start here
├── PHASE-3-EXECUTE-NOW.sh                    ← After Phase 2
├── PHASE-4-EXECUTE-NOW.sh                    ← After Phase 3
├── PHASE-2-3-4-READINESS-CHECK.sh            ← Pre-flight check
├── COMPLETE-4-PHASE-EXECUTION-GUIDE.md       ← Master guide
├── PHASE-2-DEPLOYMENT-VERIFICATION-AND-EXECUTE.md
├── 4-PHASE-DEPLOYMENT-EXECUTION-MANUAL.md
├── 4-PHASE-DEPLOYMENT-EXECUTION-LOG.md
├── scripts/ops/collab-9-deploy.sh
├── scripts/ops/fix-replica-1-permissions.sh
└── scripts/ops/verify-deployment-state.sh
```

---

## Immediate Next Action

```bash
# START PHASE 2 NOW:
cd /mnt/c/code-server-enterprise
bash PHASE-2-EXECUTE-NOW.sh
```

The script will:
1. Verify SSH connectivity
2. Show pre-deployment state
3. Run dry-run preview (no changes)
4. Ask for user confirmation
5. Execute real deployment to both replicas
6. Verify all services deployed and healthy
7. Provide post-deployment status

---

**Status**: ✅ ALL FILES READY - PROCEED TO PHASE 2  
**Last Updated**: April 23, 2026  
**Estimated Start to Completion**: 45-60 minutes (Phases 2-4)
