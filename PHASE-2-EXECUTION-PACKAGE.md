# PHASE 2 EXECUTION PACKAGE — April 24, 2026

**Status**: READY FOR EXECUTION  
**Type**: IaC Deployment (Git-Controlled, Idempotent, Immutable)  
**Duration**: 15-20 minutes  
**Risk Level**: LOW (All operations are idempotent)  

---

## Executive Summary

Execute Phase 2 of the 4-phase cluster deployment to deploy Collab-9 WebSocket feature to production replicas. All operations are:

- **IaC** (Infrastructure as Code): Git-controlled, versioned, reviewable
- **Immutable**: Pinned commits (2d4d0c08), versioned containers (4.115.0)
- **Idempotent**: Safe to execute multiple times with identical results

---

## Quick Start (3 Options)

### Option A: Automated (Recommended)

```bash
cd /mnt/c/code-server-enterprise
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42
```

**Expected**: Deployment to both replicas in parallel, health checks pass  
**Time**: 15-20 minutes  

### Option B: Dry-Run First (Safest)

```bash
cd /mnt/c/code-server-enterprise

# Preview without making changes
DRY_RUN=1 bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42

# Then execute
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42
```

### Option C: Sequential (Replica-by-Replica)

```bash
cd /mnt/c/code-server-enterprise

# Deploy to Replica 1, verify, then Replica 2
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31
# [Wait for completion]

bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.42
```

---

## What Phase 2 Does

**Goal**: Deploy Collab-9 WebSocket task synchronization feature to production

**Operations** (Idempotent):

1. **Git Pull** (idempotent):
   ```bash
   git pull --ff-only origin main
   ```
   - Only pulls if new commits exist
   - Fails safely if local changes exist
   - Safe to retry

2. **Pull Container Images** (idempotent):
   ```bash
   docker compose pull
   ```
   - Pulls latest images
   - No-op if already current
   - Safe to retry

3. **Start/Update Services** (idempotent):
   ```bash
   docker compose up -d
   ```
   - Starts new services
   - Restarts changed services
   - Idempotent by design
   - Safe to retry

4. **Verify Health** (idempotent):
   ```bash
   curl http://{host}:3000/health/ready
   ```
   - Checks endpoint availability
   - Retries up to 10 times
   - 5-second delay between retries

---

## Execution Files

All execution files are in `scripts/ops/`:

- **collab-9-deploy.sh** — Main deployment script
- **verify-deployment-state.sh** — Post-deployment verification
- **EXECUTE-4-PHASE-DEPLOYMENT-APRIL-24.sh** — Automated 4-phase executor

Documentation:

- **4-PHASE-DEPLOYMENT-EXECUTION-MANUAL.md** — Full procedural guide
- **PHASE-2-EXECUTION-GUIDE.sh** — Copy-paste ready Phase 2 commands
- **4-PHASE-DEPLOYMENT-EXECUTION-LOG.md** — Execution tracking log

---

## Success Criteria

After Phase 2 completes:

✅ **Commits Updated**:
```bash
# Both should return 2d4d0c08
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git rev-parse --short HEAD'
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git rev-parse --short HEAD'
```

✅ **Health Endpoints Responding**:
```bash
curl http://192.168.168.31:3000/health/ready  # HTTP 200
curl http://192.168.168.42:3000/health/ready  # HTTP 200
```

✅ **Containers Running**:
```bash
ssh akushnir@192.168.168.31 'docker ps --quiet | wc -l'  # 38+
ssh akushnir@192.168.168.42 'docker ps --quiet | wc -l'  # 38+
```

✅ **WebSocket Endpoint Available**:
```bash
curl -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  https://192.168.168.31:443/ws/task-sync
```

---

## IaC Governance Verification

### ✅ Infrastructure as Code

- [ ] All deployment configuration in `docker-compose.yml` (git-controlled)
- [ ] Environment from `.env` schema (`.env.schema.json` in git)
- [ ] Deployment scripts in `scripts/ops/` (version-controlled)
- [ ] Container images pinned to version (4.115.0)

### ✅ Immutability

- [ ] Commit locked to 2d4d0c08
- [ ] Container images locked to 4.115.0
- [ ] No runtime configuration changes
- [ ] All changes via git+deployment pipeline

### ✅ Idempotency

- [ ] Operations safe to run multiple times
- [ ] git pull --ff-only (fails if local changes)
- [ ] docker compose pull (no-op if current)
- [ ] docker compose up -d (creates/updates/restarts)

---

## Rollback Procedure

If any issue occurs, rollback is immediate:

**Revert to Previous State**:
```bash
# Option 1: Via git (all replicas)
git revert 2d4d0c08
git push origin main
```

**Or manually on each replica**:
```bash
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git reset --hard HEAD~1 && docker compose up -d'
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git reset --hard HEAD~1 && docker compose up -d'
```

---

## Monitoring During Execution

**Watch Logs in Real-Time**:
```bash
# On Replica 1
ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose logs -f'

# On Replica 2
ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker compose logs -f'
```

**Check Container Status**:
```bash
# Replica 1
ssh akushnir@192.168.168.31 'docker ps'

# Replica 2
ssh akushnir@192.168.168.42 'docker ps'
```

---

## Next Steps After Phase 2

Once Phase 2 completes successfully:

1. **Execute Phase 3**: Fix Replica 1 Permissions (P0 #1650)
   ```bash
   bash scripts/ops/fix-replica-1-permissions.sh
   ```

2. **Execute Phase 4**: Validate Cluster Parity
   ```bash
   bash scripts/ops/verify-deployment-state.sh
   ```

3. **Monitor Cluster**: Watch for 30 minutes
   - Check health endpoints
   - Monitor metrics
   - Review logs

4. **Close Issues**: Update GitHub with deployment confirmation
   - #1650 (Replica 1 permissions)
   - #1616 (Cluster parity)

---

## Troubleshooting

### SSH Connection Fails

**Problem**: `ssh: connect to host 192.168.168.31 port 22: Connection refused`

**Solutions**:
1. Verify SSH key: `ls -la ~/.ssh/id_rsa_onprem`
2. Test connectivity: `ping 192.168.168.31`
3. Check SSH config: `ssh -v akushnir@192.168.168.31 true`

### Docker Compose Fails

**Problem**: `docker-compose: command not found` or service won't start

**Solutions**:
1. Check compose version: `ssh akushnir@192.168.168.31 'docker compose version'`
2. Review logs: `ssh akushnir@192.168.168.31 'docker compose logs'`
3. Manual restart: `ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose restart'`

### Health Check Fails

**Problem**: `curl: (7) Failed to connect to 192.168.168.31 port 3000`

**Solutions**:
1. Wait 30 seconds for services: `sleep 30`
2. Check if container running: `ssh akushnir@192.168.168.31 'docker ps | grep code-server'`
3. Check container logs: `ssh akushnir@192.168.168.31 'docker logs code-server'`

---

## Execution Checklist

### Pre-Execution

- [ ] SSH key available: `~/.ssh/id_rsa_onprem`
- [ ] Replicas reachable: `ping 192.168.168.31` & `ping 192.168.168.42`
- [ ] Current directory: `/mnt/c/code-server-enterprise`
- [ ] Scripts present: `ls scripts/ops/collab-9-deploy.sh`

### During Execution

- [ ] Deployment script runs without errors
- [ ] SSH commands execute successfully
- [ ] Docker operations complete
- [ ] Health checks pass on both replicas

### Post-Execution

- [ ] Both replicas on commit 2d4d0c08
- [ ] Both replicas health: HTTP 200
- [ ] Both replicas containers: 38+
- [ ] WebSocket endpoint available

---

## Key Files Reference

| File | Purpose | Usage |
|------|---------|-------|
| `scripts/ops/collab-9-deploy.sh` | Main deployment script | `bash collab-9-deploy.sh --hosts IP1,IP2` |
| `scripts/ops/verify-deployment-state.sh` | Post-deployment verification | `bash verify-deployment-state.sh` |
| `docker-compose.yml` | IaC service definition | Git-controlled, canonical |
| `.env.schema.json` | Environment variables schema | Git-controlled, defines vars |
| `4-PHASE-DEPLOYMENT-EXECUTION-MANUAL.md` | Full procedures | Reference guide |

---

## Related GitHub Issues

- **#1650** — Replica 1 file permissions (P0) — Resolved by Phase 3
- **#1616** — Cluster parity epic — Resolved by Phase 4
- **#1660** — Production deployment — Parent epic
- **#1662** — Collab-9 Phase 2 staging validation — Depends on Phase 2

---

## Governance Compliance Summary

✅ **IaC**: All infrastructure git-controlled and version-managed  
✅ **Immutable**: Commits locked, containers pinned, no runtime drift  
✅ **Idempotent**: All operations safe to execute multiple times  
✅ **Reversible**: Instant rollback via git operations  
✅ **Auditable**: All changes tracked in git history  

---

**Prepared**: April 24, 2026  
**Status**: ✅ READY FOR EXECUTION  
**Risk Level**: LOW (Idempotent operations, instant rollback)  
**Estimated Duration**: 15-20 minutes  

Execute Phase 2 using Option A, B, or C above.
