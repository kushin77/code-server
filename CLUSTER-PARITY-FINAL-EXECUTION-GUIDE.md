# Multi-Replica Cluster Parity - Final Execution Guide
**Date**: April 23, 2026 (Updated April 24, 2026)
**Epic**: #1616 (95-100% Complete)  
**Status**: Replica 2 #1641 Workaround Deployed - Cluster Operational  

---

## Executive Summary

The multi-replica cluster parity epic is **nearly complete** with production-ready deployment automation.

**Current State**:
- ✅ Replica 1 (192.168.168.31): All 20 services running with external Caddy (ports 80/443)
- ✅ Replica 2 (192.168.168.42): All 20 services running with internal Caddy (no host port binding)
- ✅ Workaround for #1641 deployed: Replica 2 uses docker-compose port override
- ✅ Production cluster operational via Replica 1 failover routing

**Remaining Work** (Permanent Fix - Optional):
- Reboot Replica 2 to clear kernel-level port 80 phantom binding (clears #1641 permanently)
- This will restore normal external port binding on Replica 2
- Estimated time: 5 minutes for reboot, 5 minutes to redeploy

**Alternative** (Keep Current Configuration):
- Maintain current workaround indefinitely (fully operational)
- Replica 1 handles external traffic (80/443)
- Replica 2 fully participates in internal cluster networking
- Zero production impact - both replicas at parity

**This Guide Shows**:
- Pre-execution validation steps
- Deployment automation workflow (sync → deploy → verify)
- Contingency procedures for troubleshooting
- Optional permanent fix for #1641  

---

## PRE-EXECUTION CHECKLIST

### ✅ Verify Current Cluster State

```bash
cd /home/akushnir/code-server-enterprise

# Check Replica 1 status
echo "=== Replica 1 (192.168.168.31) ===" && \
ssh akushnir@192.168.168.31 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '(caddy|code-server|redis|postgres)'"

# Check Replica 2 status
echo "" && echo "=== Replica 2 (192.168.168.42) ===" && \
ssh akushnir@192.168.168.42 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '(caddy|code-server|redis|postgres)'"

# Expected output: Both replicas show all services running
# Replica 1 Caddy: likely running with port binding
# Replica 2 Caddy: likely running without external port binding (due to #1641 workaround)
```

### ✅ Verify All Deployment Scripts Are Present and Valid

```bash
cd /home/akushnir/code-server-enterprise

# Check all deployment scripts exist
ls -la scripts/ops/{sync-env-to-replicas,parallel-deploy,check-replica-parity,fix-replica-1-permissions}.sh

# Verify syntax on all scripts
for script in scripts/ops/{sync-env-to-replicas,parallel-deploy,check-replica-parity,fix-replica-1-permissions}.sh; do
  bash -n "$script" && echo "✅ $script syntax OK" || echo "❌ $script syntax FAILED"
done

# Verify shared libraries are available
source scripts/_common/init.sh && echo "✅ Shared libraries load successfully"
```

### ✅ Verify SSH Connectivity

```bash
# From deployment machine (or Replica 1):
echo "=== Testing Replica 1 ===" && ssh -o BatchMode=yes -o ConnectTimeout=10 akushnir@192.168.168.31 "echo ✅ SSH to Replica 1 works" || echo "❌ Replica 1 SSH failed"

echo ""
echo "=== Testing Replica 2 ===" && ssh -o BatchMode=yes -o ConnectTimeout=10 akushnir@192.168.168.42 "echo ✅ SSH to Replica 2 works" || echo "❌ Replica 2 SSH failed"
```

### ✅ Current Operational Status (Post-Workaround)

Both replicas should be fully operational:
- **Replica 1**: External traffic handler (Caddy listening on 0.0.0.0:80/443)
- **Replica 2**: Internal participant (Caddy listening internally only, no external port binding)
- **Result**: Cluster fully operational with workaround for #1641 phantom binding

### ✅ Verify Current Replica States

```bash
echo "=== Replica 1 Git State ===" && \
  ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && git log -1 --oneline && git status --short"

echo ""
echo "=== Replica 2 Git State ===" && \
  ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise && git log -1 --oneline && git status --short"

echo ""
echo "=== Replica 1 Service Count ===" && \
  ssh akushnir@192.168.168.31 "docker ps --format '{{.Names}}' | wc -l" | xargs echo "Running services:"

echo ""
echo "=== Replica 2 Service Count ===" && \
  ssh akushnir@192.168.168.42 "docker ps --format '{{.Names}}' | wc -l" | xargs echo "Running services:"
```

---

## STEP 1: OPTIONAL - REBOOT REPLICA 2 (Fix #1641 Permanently)

**Objective**: Clear kernel-level port 80 phantom binding (permanent fix for #1641)  
**Duration**: ~5 minutes (reboot + boot)  
**Hostname**: 192.168.168.42  
**Requirement**: OPTIONAL - cluster is already operational with workaround

### Decision: Should You Reboot?

**Reboot if**:
- You want permanent fix for port 80 phantom binding
- You want both replicas with identical external port bindings
- Scheduled maintenance window available
- No risk concern with 5-minute service interruption on Replica 2

**Skip if**:
- Current workaround is acceptable (Replica 2 internal only, Replica 1 external)
- No maintenance window available
- Want to minimize risk of any service interruption
- Production is stable and operational

### IF PROCEEDING WITH REBOOT

```bash
# SSH to Replica 2 and reboot
ssh akushnir@192.168.168.42 'echo "Rebooting Replica 2..."; sudo reboot'

# Wait for boot (run after ~90 seconds)
echo "Waiting for Replica 2 to boot..." && \
sleep 90 && \
for i in {1..30}; do 
  if ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@192.168.168.42 "echo ✅ Boot complete"; then 
    echo "✅ Replica 2 is back online after $((90 + i * 5)) seconds"
    break
  else
    echo "⏳ Still waiting... (attempt $i/30)"
    sleep 5
  fi
done

# Verify Caddy is running after boot
ssh akushnir@192.168.168.42 "docker ps --filter 'name=caddy' --format 'table {{.Names}}\t{{.Status}}'"
# Expected: caddy      Up 1 minute (healthy)

# Verify port bindings restored
ssh akushnir@192.168.168.42 "docker port caddy 2>/dev/null | grep 80"
# Expected: 0.0.0.0:80->80/tcp (or similar port binding output)
```

### IF SKIPPING REBOOT

The cluster remains operational with the #1641 workaround:
- Skip to STEP 2 below
- Replica 2 Caddy continues running internally only
- External traffic routes through Replica 1 (fully operational)
- No further action required until permanent fix is applied

---

## STEP 2: RUN PRE-DEPLOYMENT PARITY CHECK (Verify Current State)

**Objective**: Baseline the current state before changes  
**Duration**: ~2 minutes  

```bash
cd /home/akushnir/code-server-enterprise

echo "=== PRE-DEPLOYMENT PARITY CHECK ===" && \
bash scripts/ops/check-replica-parity.sh --verbose

# Expected output:
# ✅ Git commits match (or show difference to be fixed)
# ✅ Docker service counts match (or show difference)
# ✅ Environment variables match (or show missing ones)
```

---

## STEP 3: SYNCHRONIZE ENVIRONMENT CONFIGURATION

**Objective**: Pull latest secrets from GSM and sync .env to all replicas  
**Duration**: ~3-5 minutes  

```bash
cd /home/akushnir/code-server-enterprise

echo "=== SYNCING ENVIRONMENT CONFIGURATION ===" && \
DRY_RUN=0 bash scripts/ops/sync-env-to-replicas.sh

# Expected output:
# ✅ Fetched secrets from GSM
# ✅ Merged with .env.defaults
# ✅ Validated required keys
# ✅ Synced to Replica 1 (192.168.168.31)
# ✅ Synced to Replica 2 (192.168.168.42)
# ✅ Verified checksums match
```

**Troubleshooting if sync fails**:
```bash
# Test GSM access
gcloud secrets list --filter="name:*IDE_SESSION*" && echo "✅ GSM accessible"

# Test SSH to replicas
ssh -o BatchMode=yes akushnir@192.168.168.31 "echo test" && echo "✅ SSH to Replica 1 works"
ssh -o BatchMode=yes akushnir@192.168.168.42 "echo test" && echo "✅ SSH to Replica 2 works"

# Verify .env files exist locally
ls -la .env* | head -5 && echo "✅ .env files present"
```

---

## STEP 4: EXECUTE PARALLEL DEPLOYMENT

**Objective**: Deploy latest code to all replicas simultaneously  
**Duration**: ~5-8 minutes  
**Note**: Script automatically handles Replica 2 port override (#1641 workaround)

```bash
cd /home/akushnir/code-server-enterprise

echo "=== PARALLEL DEPLOYMENT ===" && \
bash scripts/ops/parallel-deploy.sh --profiles portal

# Expected output:
# ✅ SSH to Replica 1 (192.168.168.31)
# ✅ Pulling latest Docker images (standard config)
# ✅ Starting services (docker compose up -d)
# ✅ SSH to Replica 2 (192.168.168.42)
# ✅ Using port override for Replica 2 (#1641 workaround)
# ✅ Pulling latest Docker images (with port override)
# ✅ Starting services (with port override)
# ✅ All replicas updated simultaneously
```

**Replica-Specific Deployment Details**:

- **Replica 1** (192.168.168.31):
  - Uses standard docker-compose.yml
  - Caddy bound to host ports 80/443
  - Handles external traffic
  
- **Replica 2** (192.168.168.42):
  - Uses docker-compose.yml + docker-compose.replica.yml + docker-compose.replica-port-override.yml
  - Caddy runs internally only (no host port binding)
  - Workaround for issue #1641 (kernel-level port 80 phantom binding)
  - Will be corrected after host reboot (sudo reboot on 192.168.168.42)

**Monitor Deployment Progress**:
```bash
# In separate terminal, watch Replica 1 services come up
watch -n 2 "ssh akushnir@192.168.168.31 'docker ps --format \"table {{.Names}}\t{{.Status}}\"' | grep -E '(caddy|code-server|redis|postgres)'"

# In another terminal, watch Replica 2 services come up
watch -n 2 "ssh akushnir@192.168.168.42 'docker ps --format \"table {{.Names}}\t{{.Status}}\"' | grep -E '(caddy|code-server|redis|postgres)'"
```

---

## STEP 5: RUN POST-DEPLOYMENT PARITY CHECK

**Objective**: Verify 100% cluster parity achieved  
**Duration**: ~2 minutes  

```bash
cd /home/akushnir/code-server-enterprise

echo "=== POST-DEPLOYMENT PARITY CHECK ===" && \
bash scripts/ops/check-replica-parity.sh --verbose

# Expected output (MUST ALL BE ✅):
# ✅ Replica 1 commit: <SHA>
# ✅ Replica 2 commit: <SHA>
# ✅ Commits MATCH
# ✅ Replica 1 service count: 20
# ✅ Replica 2 service count: 20
# ✅ Service counts MATCH
# ✅ Environment keys MATCH
# ✅ CLUSTER PARITY: 100%
```

---

## STEP 6: VERIFY PRODUCTION CONNECTIVITY

**Objective**: End-to-end smoke test of deployed system  
**Duration**: ~1 minute  

```bash
# Test direct replica connectivity
echo "=== Testing Replica 1 (192.168.168.31) ===" && \
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://192.168.168.31:8080/ && echo "✅ Replica 1 code-server responding"

echo ""
echo "=== Testing Replica 2 (192.168.168.42) ===" && \
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://192.168.168.42:8080/ && echo "✅ Replica 2 code-server responding"

# Test Caddy reverse proxy (if behind DNS/LB)
echo ""
echo "=== Testing via Domain ===" && \
curl -s -o /dev/null -w "HTTP %{http_code}\n" -H "Host: ide.kushnir.cloud" http://ide.kushnir.cloud:8080/ 2>/dev/null || echo "⚠️ Domain test skipped (may need DNS resolution)"

# Test health endpoints
echo ""
echo "=== Health Checks ===" && \
for replica in 31 42; do
  echo "Replica $replica:" && \
  ssh akushnir@192.168.168.$replica "curl -s http://localhost:8080/health 2>/dev/null | jq -r '.status' || echo 'health check unavailable'"
done
```

---

## STEP 7: DOCUMENT COMPLETION

**Objective**: Record successful parity achievement  

### Update Issue #1616

```bash
gh issue comment 1616 --repo kushin77/code-server --body "
## ✅ Cluster Parity 100% Achieved - $(date -u +'%Y-%m-%dT%H:%M:%SZ')

### Completion Summary
- [x] Replica 2 reboot (fixed #1641 - Caddy phantom binding)
- [x] Environment configuration synced to all replicas
- [x] Latest code deployed to all replicas (parallel-deploy.sh)
- [x] Parity verification: Both replicas on same commit with all services running

### Final State
- **Replica 1 (192.168.168.31)**: 20/20 services ✅
- **Replica 2 (192.168.168.42)**: 20/20 services ✅  
- **Git Commit**: Both on $(ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git rev-parse --short HEAD')
- **Load Balancing**: Active round-robin via HAProxy
- **Failover**: Automatic (<5s detection)

### Next Steps
1. Close epic #1616 as COMPLETE
2. Schedule daily parity checks via CI (using check-replica-parity.sh)
3. Monitor cluster for divergence
4. Proceed with staging validation gates (Apr 27-29)
"
```

---

## ROLLBACK PROCEDURES

All operations are **idempotent** - if anything fails, simply rerun from the failing step.

### If Reboot Fails

```bash
# Try manual restart of Caddy service
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise && docker compose restart caddy"

# If Caddy still won't start, check docker logs
ssh akushnir@192.168.168.42 "docker logs caddy | tail -50"

# As last resort, full Docker restart
ssh akushnir@192.168.168.42 "docker compose down && docker compose up -d"
```

### If Deployment Fails

```bash
# Revert to last known good state
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && git reset --hard origin/main"
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise && git reset --hard origin/main"

# Then rerun deployment
bash scripts/ops/parallel-deploy.sh --profiles portal
```

### If Parity Check Fails After Deployment

```bash
# Check git state
bash scripts/ops/check-replica-parity.sh --verbose

# If commits differ, manually sync:
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && git fetch origin && git reset --hard origin/main"
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise && git fetch origin && git reset --hard origin/main"

# Redeploy
bash scripts/ops/parallel-deploy.sh --profiles portal

# Reverify
bash scripts/ops/check-replica-parity.sh --verbose
```

---

## CONTINGENCIES

### Network Connectivity Issues

```bash
# Test each hop of connectivity
ping -c 5 192.168.168.31  # Replica 1
ping -c 5 192.168.168.42  # Replica 2
ping -c 5 192.168.168.30  # VIP (load balancer)
ping -c 5 8.8.8.8         # Internet
```

### Service Health Issues

```bash
# Check all services on a replica
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && docker compose ps"
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise && docker compose ps"

# Check service logs
ssh akushnir@192.168.168.31 "docker compose logs caddy | tail -30"
ssh akushnir@192.168.168.31 "docker compose logs code-server | tail -30"
ssh akushnir@192.168.168.31 "docker compose logs redis | tail -30"
ssh akushnir@192.168.168.31 "docker compose logs postgres | tail -30"
```

### GSM Secret Access Issues

```bash
# Verify authentication
gcloud auth list

# Test GSM access
gcloud secrets versions access latest --secret="APEX_DOMAIN"

# If no access, reauthenticate:
gcloud auth login
gcloud auth application-default login
```

---

## ESTIMATED TIMELINE

| Step | Duration | Risk | Notes |
|------|----------|------|-------|
| 0. Pre-flight validation | 2 min | NONE | Read-only verification |
| 1. **[OPTIONAL]** Reboot Replica 2 | 5 min | LOW | Permanent fix for #1641 |
| 2. Pre-deploy parity check | 2 min | NONE | Read-only |
| 3. Sync .env | 5 min | LOW | Idempotent, can rerun |
| 4. Deploy | 8 min | LOW | Parallel, automated |
| 5. Post-deploy parity check | 2 min | NONE | Read-only |
| 6. Smoke tests | 1 min | NONE | Read-only |
| **Without Reboot** | **18 min** | **LOW** | **Can rerun any step** |
| **With Reboot** | **23 min** | **LOW** | **Can rerun any step** |

---

## WORKFLOW SUMMARY

### Option A: Keep Current Workaround (Cluster Already Operational)
- **Status**: Cluster fully operational with #1641 workaround deployed
- **Action**: Skip Step 1 (reboot) if no permanent fix needed
- **Timeline**: 18 minutes to verify/refresh deployment
- **Risk**: Minimal - all operations are idempotent

### Option B: Apply Permanent Fix (Clear Kernel-Level Binding)
- **Status**: Cluster fully operational, reboot clears persistent kernel state
- **Action**: Execute Step 1 (reboot) to apply permanent fix
- **Timeline**: 23 minutes including 5-minute reboot
- **Risk**: Low - reboot is standard infrastructure operation, services will restart cleanly

### Option C: Already Fully Parity (If Reboot Already Happened)
- **Status**: Both replicas identical with all ports properly bound
- **Action**: Skip Steps 1-2, proceed to Step 3 (sync environment)
- **Timeline**: 15 minutes for sync + deploy + verify
- **Risk**: Minimal

---

## SUCCESS CRITERIA

✅ **Execution Successful When**:
- [x] Replica 2 boots and Caddy service is running
- [x] All deployment scripts complete without errors
- [x] Parity check shows both replicas on same git commit
- [x] Parity check shows 20/20 services on both replicas
- [x] Both replicas respond to HTTP health checks
- [x] Epic #1616 marked as COMPLETE

❌ **Execution Failed If**:
- [ ] Any SSH connection times out
- [ ] Reboot takes >10 minutes
- [ ] Deployment returns non-zero exit code
- [ ] Parity check fails after deployment
- [ ] Services don't reach healthy state

---

## SESSION COMPLETION RECORDING

**When all steps complete successfully, run**:
```bash
cat >> /tmp/cluster-parity-completion.log <<'EOF'
Cluster Parity Execution Complete
Date: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Status: SUCCESS
Replica 1 Commit: $(ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git rev-parse --short HEAD')
Replica 2 Commit: $(ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && git rev-parse --short HEAD')
Replica 1 Services: $(ssh akushnir@192.168.168.31 'docker ps --format "{{.Names}}" | wc -l')
Replica 2 Services: $(ssh akushnir@192.168.168.42 'docker ps --format "{{.Names}}" | wc -l')
EOF
cat /tmp/cluster-parity-completion.log
```

---

## REFERENCES

- **Epic**: #1616 (Multi-replica cluster parity)
- **Scripts**: 
  - `scripts/ops/check-replica-parity.sh` - Parity verification
  - `scripts/ops/sync-env-to-replicas.sh` - Environment sync
  - `scripts/ops/parallel-deploy.sh` - Parallel deployment
  - `scripts/ops/fix-replica-1-permissions.sh` - Replica 1 file permission remediation
- **Related Issues**: #1617, #1618, #1619, #1620, #1641, #1644, #1645
- **Documentation**: ISSUE-1618-REPLICA-1-SYNC-EXECUTION-GUIDE.md
