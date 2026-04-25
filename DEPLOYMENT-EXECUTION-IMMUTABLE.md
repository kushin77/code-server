# DEPLOYMENT EXECUTION - Immutable, Idempotent, IaC-Ready 

**Date:** April 25, 2026, 18:50 UTC  
**Status:** ✅ IaC VALIDATED - Ready for deployment  
**Approach:** Immutable infrastructure, fully idempotent  
**Timeline:** ~1 hour post-prerequisite

---

## 🔴 PREREQUISITE: One-Time Manual Sudoers Config

**Required to unblock all automation**

From ANY terminal (Linux/Mac/WSL - NOT Windows PowerShell):
```bash
ssh -t akushnir@192.168.168.31 'echo "akushnir ALL=(ALL) NOPASSWD: /usr/local/bin/k3s" | sudo tee /etc/sudoers.d/k3s-install > /dev/null && sudo chmod 0440 /etc/sudoers.d/k3s-install && sudo visudo -c -q'
```

**Verify it worked:**
```bash
ssh akushnir@192.168.168.31 "sudo -n echo ok"
# Must print: ok (without password prompt)
```

**Why:** K3s provisioner needs passwordless sudo. This is a **one-time setup**, after which all deployment is fully automated and idempotent.

**Blocker Status:** 🔴 REQUIRED - After this, 🟢 ALL CLEAR

---

## ✅ DEPLOYMENT CHECKLIST (Post-Sudoers)

### Step 1: Pre-Deployment Validation (2 minutes)
```bash
cd /mnt/c/code-server-enterprise

# Verify infrastructure connectivity
echo "=== Checking SSH connectivity ==="
ssh akushnir@192.168.168.31 "sudo -n echo PRIMARY_OK"      # Should print: PRIMARY_OK
ssh akushnir@192.168.168.42 "echo REPLICA_OK"             # Should print: REPLICA_OK

# Verify scripts are in place
echo "=== Checking infrastructure scripts ==="
test -f scripts/ops/provision-k3s-cluster.sh && echo "✓ K3s provisioner"
test -f scripts/ops/cluster-sync-daemon.sh && echo "✓ Cluster sync daemon"
test -f scripts/ops/setup-k3s-sudoers.sh && echo "✓ Sudoers helper"

# All should print ✓
```

### Step 2: Deploy Single-Node K3s (5-7 minutes)
```bash
cd /mnt/c/code-server-enterprise

# DRY-RUN (test without executing)
export PRIMARY_HOST=192.168.168.31 SKIP_AGENT=true
bash scripts/ops/provision-k3s-cluster.sh --dry-run
# Review output, ensure no errors

# EXECUTE (deploy K3s to primary only)
bash scripts/ops/provision-k3s-cluster.sh

# VERIFY (should show 1 ready node)
kubectl get nodes
# Expected output:
#   NAME                STATUS   ROLES                 
#   192.168.168.31      Ready    control-plane,master

# Check system pods
kubectl get pods -A | head -20
# Expected: coredns, metrics-server, cert-manager running
```

### Step 3: Deploy Full 2-Node K3s Cluster (5-7 minutes)
```bash
cd /mnt/c/code-server-enterprise

# DRY-RUN for 2-node deployment
export SKIP_AGENT=false
bash scripts/ops/provision-k3s-cluster.sh --dry-run

# EXECUTE (deploy agent to 192.168.168.42)
bash scripts/ops/provision-k3s-cluster.sh

# VERIFY (should show 2 ready nodes)
kubectl get nodes
# Expected output:
#   NAME                STATUS   ROLES                
#   192.168.168.31      Ready    control-plane,master 
#   192.168.168.42      Ready    agent

# Verify all system pods are running
kubectl get pods -A
```

### Step 4: Enable Cluster Sync Daemon (2 minutes)
```bash
# This ensures config stays synchronized between nodes (immutable via git)

# Install cron job on replica
ssh akushnir@192.168.168.42 \
    'cd ~/code-server-enterprise && bash scripts/ops/cluster-sync-daemon.sh --install-cron'

# Verify it's running and idempotent
bash scripts/ops/cluster-sync-daemon.sh --status

# Test idempotency (should be no-op)
bash scripts/ops/cluster-sync-daemon.sh --sync
bash scripts/ops/cluster-sync-daemon.sh --sync  # Run again - should detect no changes
```

### Step 5: Run Full E2E Test Suite (20-30 minutes)
```bash
cd /mnt/c/code-server-enterprise

# Set kubeconfig context
export KUBECONFIG=${HOME}/.kube/k3s-config
kubectl config use-context code-server-enterprise

# Run unit tests
pnpm test:unit

# Run integration tests
pnpm test:integration

# Run E2E tests (Playwright)
pnpm test:e2e

# Run load testing
pnpm test:load
pnpm test:load:stress
pnpm test:load:spike

# All tests are idempotent - can run multiple times
```

### Step 6: Production Deployment (4-8 hours)
```bash
# Deploy application stack via Helm or Docker Compose
# Run full validation suite
# Update DNS/routing if needed
# Enable monitoring
# Stakeholder handoff
```

---

## Idempotency Guarantee

All steps are **safe to run multiple times**:

```bash
# Run provisioner 3 times - result identical, no errors
bash scripts/ops/provision-k3s-cluster.sh
bash scripts/ops/provision-k3s-cluster.sh  # No-op: detects installed
bash scripts/ops/provision-k3s-cluster.sh  # No-op: detects installed

# Run tests 3 times - result identical
pnpm test:e2e
pnpm test:e2e  # Re-runs all tests, can fail/pass independently
pnpm test:e2e  # Same results

# Run cluster sync 3 times - no-op if no changes
bash scripts/ops/cluster-sync-daemon.sh --sync
bash scripts/ops/cluster-sync-daemon.sh --sync  # No-op: already synced
bash scripts/ops/cluster-sync-daemon.sh --sync  # No-op: already synced

# All idempotent ✅
```

---

## Immutability Verification

After each phase, verify immutability:

```bash
# Configuration should only come from Git
git log --oneline scripts/ops/provision-k3s-cluster.sh
# Shows full version history, nothing hardcoded

# No manual state changes
kubectl describe node 192.168.168.31 | grep "Labels"
# Should match provisioner's node-labels

# All logs tracked
ls -la artifacts/k3s-cluster-provision/provision-*.log
# Each run creates timestamped log
```

---

## Rollback Procedure (If Needed)

All operations are reversible:

```bash
# Rollback K3s cluster (revert to previous commit)
cd /mnt/c/code-server-enterprise
git log --oneline  # Find previous good commit
git reset --hard <commit-hash>
bash scripts/ops/provision-k3s-cluster.sh FORCE_REINSTALL=true

# Or destroy and redeploy
ssh akushnir@192.168.168.31 "sudo /usr/local/bin/k3s-uninstall.sh"
ssh akushnir@192.168.168.42 "sudo /usr/local/bin/k3s-agent-uninstall.sh"
bash scripts/ops/provision-k3s-cluster.sh  # Fresh deployment
```

---

## Monitoring & Validation

```bash
# Real-time pod status
watch kubectl get pods -A

# Node resource usage
kubectl top nodes
kubectl top pods -A

# Check service endpoints
kubectl get svc -A

# Inspect logs
kubectl logs -n kube-system -l k8s-app=metrics-server
kubectl logs -n cert-manager -l app=cert-manager
```

---

## Troubleshooting

| Issue | Diagnosis | Solution |
|---|---|---|
| `kubectl: command not found` | kubectl not installed locally | `brew install kubectl` (macOS) or `snap install kubectl` (Linux) |
| `error: connection refused` | K3s not running | Check: `ssh akushnir@192.168.168.31 "sudo k3s kubectl get nodes"` |
| `1 node not Ready` | Agent join failed | Check logs: `ssh akushnir@192.168.168.42 "sudo journalctl -u k3s-agent"` |
| `Sync daemon error` | Git fetch failed | Check: `cd ~/code-server-enterprise && git fetch origin && git status` |
| `Tests failing` | Environment mismatch | Verify kubeconfig: `kubectl config current-context` (should be `code-server-enterprise`) |

---

## Success Criteria

### Single-Node Deployment ✅
```bash
kubectl get nodes
# NAME                STATUS   ROLES                 AGE
# 192.168.168.31      Ready    control-plane,master  5m

kubectl get pods -A --no-headers | wc -l
# Should show 15+ system pods (coredns, metrics, cert-manager, etc.)
```

### 2-Node Deployment ✅
```bash
kubectl get nodes
# NAME                STATUS   ROLES         AGE
# 192.168.168.31      Ready    control-plane 15m
# 192.168.168.42      Ready    agent         5m

kubectl get nodes --no-headers | wc -l
# Should show 2 nodes ready
```

### Cluster Sync ✅
```bash
bash scripts/ops/cluster-sync-daemon.sh --status
# Should show: Last sync: <recent>, Status: healthy

# Verify idempotency
bash scripts/ops/cluster-sync-daemon.sh --sync
bash scripts/ops/cluster-sync-daemon.sh --sync
# Both should complete with "Already up-to-date"
```

### Tests ✅
```bash
pnpm test:e2e
# All 60+ E2E tests pass

pnpm test:load
# Load test completes without errors

kubectl get pods  # All should be Running
```

---

## Expected Timeline (After Sudoers)

| Step | Time | Cumulative |
|------|------|-----------|
| Pre-deployment validation | 2 min | 2 min |
| Single-node K3s | 5 min | 7 min |
| 2-node K3s | 5 min | 12 min |
| Cluster sync setup | 2 min | 14 min |
| E2E test suite | 30 min | 44 min |
| **Total to validated deployment** | **~45 min** | **~45 min** |
| Production deployment | 4-8 hrs | **~5 hrs** |

---

## Final Notes

1. **All operations are immutable:** Configuration comes from Git, nothing manual
2. **All operations are idempotent:** Can run multiple times safely
3. **All operations are auditable:** Full logs in artifacts/ and Git history
4. **All operations are reversible:** Can rollback to previous Git commit
5. **All operations are environment-driven:** No hardcoding, all config via env vars

**Status:** ✅ **READY FOR EXECUTION**

---

**Next Action:** Configure sudoers on 192.168.168.31 (2 min manual step), then proceed with Step 1 of deployment checklist.

