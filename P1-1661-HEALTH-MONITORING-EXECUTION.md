# P1 #1661 — Cluster Health Monitoring Deployment (IaC)

**Date**: April 23, 2026  
**Priority**: P1 — Production monitoring  
**Objective**: Deploy Prometheus health check configuration to both replicas  
**Governance**: 100% IaC/immutable/idempotent compliance

---

## Current Status

✅ **Configuration Complete** (already in place):
- `prometheus.yml` — Health check scrape jobs configured (lines 261-290)
- `alert-rules.yml` — Alert rules defined for replica health (lines 1000-1027)

❌ **Deployment Pending**:
- [ ] Deploy prometheus.yml to both replicas
- [ ] Deploy alert-rules.yml to both replicas  
- [ ] Restart Prometheus on both replicas
- [ ] Verify scrape targets are healthy
- [ ] Test alert routing

---

## Task Breakdown

### Task 1: Verify Current Configuration (5 min)

**Files to verify**:
1. `prometheus.yml` — Health check scrape jobs present
2. `alert-rules.yml` — Alert rules configured
3. `docker-compose.yml` — Prometheus container configured

**Verification command**:
```bash
# Check prometheus.yml has health check jobs
grep -A 5 "cluster-health-replica-31" prometheus.yml
grep -A 5 "cluster-health-replica-42" prometheus.yml

# Check alert-rules.yml has alert definitions
grep -A 3 "ClusterHealthCheckFailure" alert-rules.yml
grep -A 3 "ClusterHealthCheckBothReplicasDown" alert-rules.yml

# Verify docker-compose references these files
grep -E "prometheus.yml|alert-rules.yml" docker-compose.yml
```

---

### Task 2: Deploy Configuration to Both Replicas (10 min)

**Strategy**: Use new IaC orchestrator to deploy configuration changes

**Procedure** (IaC-compliant):
```bash
# 1. Verify code is committed
cd /mnt/c/code-server-enterprise
git status  # Must be clean

# 2. Commit prometheus.yml + alert-rules.yml if not already committed
git add prometheus.yml alert-rules.yml
git commit -m "ops: add cluster health monitoring config (replicas 31 & 42)"  # If needed

# 3. Push to origin/main
git push origin main

# 4. Deploy using IaC orchestrator (both replicas, parallel)
bash scripts/ops/deploy-production-iac.sh

# 5. Verify health check scrape targets are responding
curl -s https://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job | contains("cluster-health"))'
curl -s https://192.168.168.42:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job | contains("cluster-health"))'
```

**Expected output**:
```json
{
  "labels": {
    "job": "cluster-health-replica-31",
    "instance": "192.168.168.31:443"
  },
  "state": "up",
  "lastScrape": "2026-04-23T...",
  "scrapeInterval": "30s"
}
```

---

### Task 3: Verify Health Checks Are Working (5 min)

**Manual health check test**:
```bash
# Test health endpoint on R31
curl -k https://192.168.168.31/health
# Expected: 200 OK + JSON response

# Test health endpoint on R42
curl -k https://192.168.168.42/health
# Expected: 200 OK + JSON response

# Check Prometheus metrics from R31
curl -s https://192.168.168.31:9090/api/v1/query?query=up{job="cluster-health-replica-31"}
curl -s https://192.168.168.31:9090/api/v1/query?query=up{job="cluster-health-replica-42"}
# Expected: Both return value: "1" (up)
```

---

### Task 4: Test Alert Firing (Optional, 10 min)

**Simulate replica failure** (to test alerting):
```bash
# On R31, temporarily block incoming traffic to R42
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  "sudo iptables -I INPUT 1 -s 192.168.168.42 -j DROP"

# Wait 2-3 minutes for Prometheus to detect failure
# Alert should fire: ClusterHealthCheckBothReplicasDown

# Check Prometheus for active alerts
curl -s https://192.168.168.31:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname | contains("ClusterHealthCheck"))'

# Restore traffic
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  "sudo iptables -D INPUT -s 192.168.168.42 -j DROP"
```

---

## Governance Compliance

| Standard | Status | Method |
|----------|--------|--------|
| **IaC** | ✅ PASS | Use deploy-production-iac.sh orchestrator |
| **Immutable** | ✅ PASS | No manual prometheus.yml edits; versioned config only |
| **Idempotent** | ✅ PASS | Redeploy using same script multiple times safely |
| **Deterministic** | ✅ PASS | Same config → same scrape jobs every time |
| **Reversible** | ✅ PASS | Instant rollback: `git reset --hard <previous>` + redeploy |
| **Linux-Native** | ✅ PASS | Bash scripts and standard Linux tools only |

---

## Success Criteria

- [x] Prometheus configuration present in repository
- [ ] Configuration deployed to both replicas
- [ ] Health check scrape targets show "up" in Prometheus UI
- [ ] Alert rules configured and active
- [ ] Health endpoints responding on both replicas
- [ ] Prometheus metrics collecting health data

---

## Execution Script (Automated)

To automate this entire task, create `scripts/ops/deploy-health-monitoring.sh`:

```bash
#!/usr/bin/env bash
# Deploy cluster health monitoring config to both replicas (IaC-compliant)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Step 1: Verify config files exist
log_info "Verifying health monitoring configuration..."
[[ -f prometheus.yml ]] || { log_fatal "prometheus.yml not found"; exit 2; }
[[ -f alert-rules.yml ]] || { log_fatal "alert-rules.yml not found"; exit 2; }

# Step 2: Commit configuration if needed
log_info "Ensuring configuration is committed..."
cd /mnt/c/code-server-enterprise
if ! git diff-index --quiet HEAD; then
  log_info "Committing health monitoring config..."
  git add prometheus.yml alert-rules.yml
  git commit -m "ops: deploy cluster health monitoring (replica health checks + alerts)"
fi

# Step 3: Push to origin
log_info "Pushing to origin/main..."
git push origin main

# Step 4: Deploy using IaC orchestrator
log_info "Deploying health monitoring to both replicas..."
bash "$SCRIPT_DIR/deploy-production-iac.sh"

# Step 5: Verify health checks
log_info "Verifying health check scrape targets..."
sleep 5  # Give prometheus time to reload
for replica in 192.168.168.31 192.168.168.42; do
  log_info "Checking replica: $replica"
  if curl -s https://$replica:9090/api/v1/targets | grep -q "cluster-health"; then
    log_info "✅ Health check scrape target active on $replica"
  else
    log_warn "⚠️  Health check scrape target not yet active on $replica"
  fi
done

log_info "✅ Cluster health monitoring deployment complete"
```

---

## Timeline

- **Phase 1** (5 min): Verify current configuration
- **Phase 2** (10 min): Deploy to both replicas using IaC orchestrator
- **Phase 3** (5 min): Verify health checks working
- **Phase 4** (Optional, 10 min): Test alert firing

**Total**: 20-30 minutes (30-40 with optional testing)

---

## Expected Outcome

After execution:
- ✅ Prometheus health check scrape jobs active on both replicas
- ✅ Alert rules configured and monitoring for failures
- ✅ Health endpoint (/health) being scraped every 30 seconds
- ✅ Alerts will fire if either replica becomes unavailable
- ✅ All configuration versioned in Git (IaC compliant)
- ✅ Deployment repeatable and reversible

---

## Next Steps After Completion

1. **Team notification** — Update #1661 with completion evidence
2. **Monitoring validation** — Observe health metrics in Grafana for 1 hour
3. **Alert test** — Run failover simulation to confirm alerts work
4. **Documentation** — Update ops runbooks with health monitoring procedures

---

## Related Documentation

- Deployment procedure: `scripts/ops/deploy-production-iac.sh`
- Operations reference: `docs/IaC-DEPLOYMENT-REFERENCE.md`
- Failover procedures: `docs/FAILOVER-RUNBOOK.md`

---

**Status**: 🟡 READY FOR EXECUTION  
**Priority**: P1 (production monitoring)  
**Complexity**: 20-30 min manual + automated deployment  
**Risk**: 🟢 LOW (configuration only, no code changes)
