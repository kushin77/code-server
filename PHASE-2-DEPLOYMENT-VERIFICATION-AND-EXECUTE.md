# Phase 2 Deployment: WebSocket to Production (IaC Execution)

**Date**: April 23, 2026  
**Objective**: Deploy Collab-9 WebSocket task synchronization to both production replicas  
**Governance**: IaC (Infrastructure as Code), Immutable, Idempotent, Reversible  
**Duration**: 15-20 minutes (deployment) + 10 minutes (verification)  

---

## Pre-Deployment Verification Checklist

### ✅ Code Immutability Checkpoint
- **Current Local HEAD**: Must be `2d4d0c08`
- **Deployment Target**: Replicas to `2d4d0c08`
- **Verification Command**:
  ```bash
  cd /mnt/c/code-server-enterprise
  git rev-parse --short HEAD
  ```
- **Expected Output**: `2d4d0c08`

### ✅ Infrastructure as Code Verification
- **Docker Compose**: `docker-compose.yml` (git-controlled)
- **Environment**: `.env` (loaded from GSM, schema validated)
- **Scripts**: `scripts/ops/collab-9-deploy.sh` (shared library based)
- **Configuration**: All in git, no runtime overrides

### ✅ Idempotency Check
All Phase 2 operations are idempotent:
- `git pull --ff-only origin main` — Safe to retry (fails if conflicts)
- `docker compose pull` — No-op if images are current
- `docker compose up -d` — Creates/updates containers (idempotent by design)
- `docker compose ps` — Read-only verification

---

## Phase 2 Deployment Procedure

### Step 1: Verify SSH Access to Both Replicas

```bash
# Test Replica 1
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 'echo "Replica 1 SSH: OK"'

# Test Replica 2
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 'echo "Replica 2 SSH: OK"'
```

**Success Criteria**: Both return "OK"  
**Failure Action**: Check SSH key permissions (~/.ssh/id_rsa_onprem) and passwordless sudo setup

---

### Step 2: Verify Git State on Both Replicas

```bash
# Check Replica 1 commit
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git rev-parse --short HEAD'

# Check Replica 2 commit
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git rev-parse --short HEAD'
```

**Success Criteria**: Both show `2d4d0c08`  
**If Different**: Run Phase 1 (git pull) first before Phase 2

---

### Step 3: Verify Docker Connectivity

```bash
# Replica 1 container count
ssh akushnir@192.168.168.31 'docker ps --quiet | wc -l'

# Replica 2 container count
ssh akushnir@192.168.168.42 'docker ps --quiet | wc -l'
```

**Success Criteria**: Both show >= 35 (services running)  
**If Lower**: Docker may not be running; check `docker compose ps`

---

### Step 4: Execute Deployment (Dry-Run First - RECOMMENDED)

```bash
# Navigate to repo
cd /mnt/c/code-server-enterprise

# DRY-RUN: Preview what will happen (safe, no changes)
DRY_RUN=1 bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42
```

**Expected Output**:
- SSH connectivity verification
- Container restart preview
- Health check preview
- No actual changes made

**If Errors**: Review output and fix before real execution

---

### Step 5: Execute Deployment (REAL)

```bash
# Real deployment to both replicas in parallel
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42
```

**Expected Output**:
```
Deploying to replica 192.168.168.31...
- Pulling latest code (git pull --ff-only)
- Fetching container images (docker compose pull)
- Starting services (docker compose up -d)
- Waiting for health checks (10 retries, 5s each)
✓ Replica 1 health check: HTTP 200 on /health/ready

Deploying to replica 192.168.168.42...
- Pulling latest code (git pull --ff-only)
- Fetching container images (docker compose pull)
- Starting services (docker compose up -d)
- Waiting for health checks (10 retries, 5s each)
✓ Replica 2 health check: HTTP 200 on /health/ready

✓ DEPLOYMENT COMPLETE: Both replicas on 2d4d0c08 with WebSocket deployed
```

**Duration**: 15-20 minutes  
**Troubleshooting**: See below if errors occur

---

## Post-Deployment Verification

### Verification 1: Commit Parity

```bash
echo "=== COMMIT PARITY ===" && \
git -C /mnt/c/code-server-enterprise rev-parse --short HEAD && \
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git rev-parse --short HEAD' && \
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git rev-parse --short HEAD'
```

**Success**: All three lines show `2d4d0c08`

---

### Verification 2: Git Drift Check (Idempotency Proof)

```bash
echo "=== GIT DRIFT ===" && \
echo "Replica 1 dirty files:" && \
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git status --short | wc -l' && \
echo "Replica 2 dirty files:" && \
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git status --short | wc -l'
```

**Success**: Both show `0` (clean state)

---

### Verification 3: Container Health

```bash
echo "=== CONTAINER HEALTH ===" && \
echo "Replica 1 running containers:" && \
ssh akushnir@192.168.168.31 'docker ps --quiet | wc -l' && \
echo "Replica 2 running containers:" && \
ssh akushnir@192.168.168.42 'docker ps --quiet | wc -l'
```

**Success**: Both show >= 38 (all services deployed)

---

### Verification 4: WebSocket Endpoint Health

```bash
echo "=== WEBSOCKET HEALTH ===" && \
echo "Replica 1 /health/ready:" && \
curl -s -o /dev/null -w "%{http_code}" https://ide.kushnir.cloud/health/ready || echo "N/A" && \
echo "" && \
echo "Replica 2 failover health:" && \
curl -s -o /dev/null -w "%{http_code}" https://ide-failover.kushnir.cloud/health/ready || echo "N/A"
```

**Success**: Both return `200`

---

### Verification 5: Task Sync Functional Test

```bash
# Check if WebSocket service is responding
ssh akushnir@192.168.168.31 'docker logs websocket-gateway 2>&1 | tail -20'
```

**Success**: No errors in recent logs; task sync events visible

---

## Rollback Procedure (If Needed)

### Immediate Rollback (Revert to Previous Commit)

```bash
# Only if deployment caused issues

# Identify last good commit (usually one before)
git log --oneline -5

# Revert deployment
git revert --no-edit <commit_hash>
git push origin main

# Redeploy to both replicas (idempotent)
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42
```

**Note**: Rollback is safe because git history is preserved and deployment is idempotent

---

## Troubleshooting

### Issue 1: SSH Connection Timeout

**Symptom**: `Connection timed out` when connecting to 192.168.168.31 or 192.168.168.42

**Root Causes**:
- Network connectivity issue
- SSH key permissions incorrect
- Firewall blocking port 22

**Fix**:
```bash
# Check SSH key permissions
ls -la ~/.ssh/id_rsa_onprem
# Should be: -rw------- (600)

# Fix if needed
chmod 600 ~/.ssh/id_rsa_onprem

# Test connectivity with verbose output
ssh -v akushnir@192.168.168.31 'echo test'
```

---

### Issue 2: Docker Compose Pull Fails

**Symptom**: `docker compose pull` fails with authentication error

**Root Causes**:
- Docker registry credentials missing
- Network connectivity to registry
- Rate limiting

**Fix**:
```bash
# Check docker login status
docker login

# Retry pull
docker compose pull --no-parallel
```

---

### Issue 3: Health Check Fails

**Symptom**: "Health check failed after 10 retries"

**Root Causes**:
- Service startup timeout
- Configuration error
- Database connectivity

**Fix**:
```bash
# Check service logs on the replica
ssh akushnir@192.168.168.31 'docker compose logs -f --tail 50'

# Wait a bit longer and retry
sleep 30
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42
```

---

### Issue 4: Git Pull Fails

**Symptom**: `git pull --ff-only` fails

**Root Causes**:
- Local changes not committed
- Remote branch has incompatible commits
- Permission issues

**Fix**:
```bash
# SSH to the replica and check git status
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git status'

# Reset to known good state
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git reset --hard origin/main'

# Retry deployment
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42
```

---

## Governance Compliance Summary

✅ **IaC (Infrastructure as Code)**
- All deployment config in git
- Deployment scripts versioned and reviewed
- No hardcoded values or secrets

✅ **Immutable**
- Commits pinned to 2d4d0c08
- Container images versioned in docker-compose.yml
- No runtime modifications allowed

✅ **Idempotent**
- All operations safe to run multiple times
- git pull --ff-only fails if conflicts (safe)
- docker compose up -d is idempotent by design
- Can retry any step safely

✅ **Reversible**
- Full rollback via git revert
- No data loss
- Instant failover to previous version

---

## Next Steps After Success

1. **Monitor cluster for 30 minutes**: Check logs for errors
2. **Verify failover health**: Test failover between replicas
3. **Close GitHub issue #1616**: Mark cluster parity complete
4. **Execute Phase 3**: Fix Replica 1 permissions (P0 #1650)
5. **Execute Phase 4**: Validate final cluster parity

---

## Commands Quick Reference

```bash
# All 4 verification steps in one script
cd /mnt/c/code-server-enterprise && \
bash scripts/ops/verify-deployment-state.sh

# Monitor deployment in real-time
watch -n 5 'echo "=== LOCAL ===" && git -C /mnt/c/code-server-enterprise rev-parse --short HEAD && \
echo "=== R1 ===" && ssh akushnir@192.168.168.31 "cd code-server-enterprise && git rev-parse --short HEAD" && \
echo "=== R2 ===" && ssh akushnir@192.168.168.42 "cd code-server-enterprise && git rev-parse --short HEAD"'
```

---

**Status**: ✅ READY FOR EXECUTION  
**Last Updated**: April 23, 2026  
**Maintainer**: Infrastructure Team
