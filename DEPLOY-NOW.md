# DEPLOY NOW — QUICK START GUIDE

**Status:** ✅ All Blockers Resolved  
**Deployment Time:** 20-30 minutes (including tests)  
**Complexity:** Low (fully automated)

---

## 3-STEP DEPLOYMENT

### Step 1: Validate with Dry-Run (2 minutes)
```bash
cd /code-server-enterprise
export DRY_RUN=true
bash scripts/ops/provision-k3s-cluster.sh
```
**Expected Output:**
- ✅ Pre-flight checks pass
- ✅ SSH credentials retrieved from Vault/GSM
- ✅ All steps logged as [DRY-RUN]
- ✅ No changes made to infrastructure

### Step 2: Deploy Single-Node K3s (5 minutes)
```bash
export SKIP_AGENT=true
unset DRY_RUN
bash scripts/ops/provision-k3s-cluster.sh
```
**Expected Output:**
- ✅ k3s server installed on 192.168.168.31
- ✅ 1 node in Ready state
- ✅ Kubeconfig written to ~/.kube/k3s-config
- ✅ cert-manager installed
- ✅ metrics-server installed

### Step 3: Deploy 2-Node Cluster + Test (15-20 minutes)
```bash
export SKIP_AGENT=false
bash scripts/ops/provision-k3s-cluster.sh
# ~10 min: Full 2-node cluster deployment
```

**Then run tests:**
```bash
export KUBECONFIG=~/.kube/k3s-config
pnpm test:e2e
# ~5-10 min: All 235+ tests pass
```

---

## VERIFY SUCCESS

```bash
# Check nodes
kubectl get nodes -o wide
# Expected: 2 nodes, both Ready

# Check system pods
kubectl get pods -A
# Expected: All Running (cert-manager, metrics-server, coredns, etc)

# Check kubeconfig
export KUBECONFIG=~/.kube/k3s-config
kubectl cluster-info
# Expected: Control Plane + CoreDNS running
```

---

## CREDENTIAL SETUP (Already Done)
✅ SSH keys configured in service account  
✅ Service account has `NOPASSWD` sudoers access  
✅ Vault/GSM secrets configured  
✅ gcloud/vault CLI available (optional fallback)

**If SSH key not locally available, provisioner will:**
1. Try to retrieve from GSM (Google Secret Manager)
2. Try to retrieve from Vault (HashiCorp)
3. Fall back to default SSH auth (~/.ssh/id_rsa)

---

## ROLLBACK (If Needed)

```bash
# Destroy cluster on primary node
ssh akushnir@192.168.168.31 "sudo /usr/local/bin/k3s-uninstall.sh"

# Destroy cluster on secondary node
ssh akushnir@192.168.168.42 "sudo /usr/local/bin/k3s-agent-uninstall.sh"

# Then rerun provisioner
bash scripts/ops/provision-k3s-cluster.sh
```

---

## MONITORING & LOGS

### Real-time logs
```bash
tail -f artifacts/k3s-cluster-provision/provision-*.log
```

### Cluster events
```bash
kubectl get events -A --sort-by='.lastTimestamp'
```

### System pods
```bash
kubectl get pods -A -w  # Watch mode
```

---

## TROUBLESHOOTING

### "Cannot reach SSH"
```bash
# Check SSH connectivity manually
ssh -i ~/.ssh/k3s-service-account akushnir@192.168.168.31 "echo ok"
# Should output: ok
```

### "Sudo command failed"
```bash
# Check sudoers configuration on target host
ssh akushnir@192.168.168.31 "sudo -l"
# Should show: NOPASSWD entry for akushnir
```

### "Kubectl get nodes shows NotReady"
```bash
# SSH to primary node and check k3s status
ssh akushnir@192.168.168.31 "sudo systemctl status k3s"
# Should show: active (running)
```

---

## NEXT ACTIONS AFTER DEPLOYMENT

1. **Merge to main branch**
   ```bash
   git add scripts/ops/provision-k3s-cluster.sh scripts/ops/cluster-sync-daemon.sh
   git commit -m "feat(infra): SSH key-based auth for K3s provisioner"
   git push origin main
   ```

2. **Enable cluster sync daemon** (automatic updates every 5 min)
   ```bash
   ssh akushnir@192.168.168.42 "sudo crontab -e"
   # Add: */5 * * * * bash /path/to/cluster-sync-daemon.sh
   ```

3. **Run full test suite**
   ```bash
   pnpm test        # All 235+ tests
   pnpm test:e2e    # 5 E2E tests
   pnpm test:load   # 3 load tests
   ```

4. **Validate CVE patches**
   ```bash
   npm audit         # Should show 0 vulnerabilities (direct)
   # Review transitive CVEs in DEPLOYMENT-CREDENTIAL-INFRASTRUCTURE-COMPLETE.md
   ```

---

## SUCCESS CRITERIA

- ✅ Both nodes show `Ready` status
- ✅ All system pods show `Running`
- ✅ Kubeconfig accessible and valid
- ✅ kubectl commands work: `kubectl get nodes`, `kubectl get pods -A`
- ✅ All 235+ tests pass
- ✅ No errors in provision logs
- ✅ Cluster sync daemon operational (if enabled)

---

**Estimated Total Time:** 25-30 minutes  
**Previous Blockers:** All resolved ✅  
**Ready to Deploy:** YES ✅  

**Execute Step 1 now →**
