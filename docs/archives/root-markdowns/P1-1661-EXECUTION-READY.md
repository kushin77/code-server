# April 23, 2026 — P1 #1661 Cluster Health Monitoring Deployment Ready

**Date**: April 23, 2026  
**Priority**: P1 — Production monitoring  
**Status**: ✅ READY FOR EXECUTION  
**Governance**: 100% IaC/immutable/idempotent compliant

---

## Objective

Deploy Prometheus cluster health monitoring configuration to both production replicas (192.168.168.31 and 192.168.168.42).

---

## Pre-Execution Verification ✅

**Configuration Files**:
- ✅ `prometheus.yml` — Health check scrape jobs configured
  - cluster-health-replica-31: 192.168.168.31:443/health (30s interval)
  - cluster-health-replica-42: 192.168.168.42:443/health (30s interval)
- ✅ `alert-rules.yml` — Alert rules configured
  - ClusterHealthCheckFailure: Single replica down (fires after 1 minute)
  - ClusterHealthCheckBothReplicasDown: Both replicas down (fires after 30 seconds)

**Deployment Script**:
- ✅ `scripts/ops/deploy-cluster-health-monitoring.sh` — Deployment orchestrator
  - Parallel deployment to both replicas
  - Automatic Prometheus restart
  - Health verification included
  - GOV-002 metadata headers present

---

## Deployment Procedure (IaC-Compliant)

### Option 1: Automated Deployment (Recommended)

```bash
# Execute deployment script (uses IaC orchestrator internally)
bash scripts/ops/deploy-cluster-health-monitoring.sh
```

**What it does**:
1. Verifies configuration files exist
2. Checks git state
3. Deploys to both replicas in parallel (via SSH)
4. Restarts Prometheus on both replicas
5. Verifies health check targets are active
6. Reports summary with next steps

**Estimated time**: 3-5 minutes

### Option 2: Manual Verification Before Deployment

```bash
# Verify configuration only (no deployment)
bash scripts/ops/deploy-cluster-health-monitoring.sh --verify-only

# Then deploy when ready
bash scripts/ops/deploy-cluster-health-monitoring.sh
```

---

## Governance Compliance

All work meets kushnir.cloud standards:

| Standard | Status | Verification |
|----------|--------|--------------|
| **IaC** | ✅ PASS | Configuration versioned in prometheus.yml + alert-rules.yml |
| **Immutable** | ✅ PASS | Deployment via script (not manual), no ad-hoc changes |
| **Idempotent** | ✅ PASS | Script safe to run multiple times with same result |
| **Deterministic** | ✅ PASS | Same configuration → same scrape jobs every time |
| **Reversible** | ✅ PASS | Rollback via `git reset --hard` + redeploy |
| **Linux-Native** | ✅ PASS | Bash script only, no PowerShell |
| **Metadata** | ✅ PASS | GOV-002 headers present |

---

## Success Criteria

After deployment, verify:

```bash
# 1. Health endpoints responding
curl -k https://192.168.168.31/health  # Should return 200 OK + JSON
curl -k https://192.168.168.42/health  # Should return 200 OK + JSON

# 2. Prometheus scrape targets active
curl -s https://192.168.168.31:9090/api/v1/targets | grep cluster-health
curl -s https://192.168.168.42:9090/api/v1/targets | grep cluster-health
# Should show "state": "up" for both replica jobs

# 3. Alert rules active
curl -s https://192.168.168.31:9090/api/v1/rules | grep ClusterHealthCheck
# Should show ClusterHealthCheckFailure and ClusterHealthCheckBothReplicasDown rules
```

---

## Post-Deployment Validation

**Quick Check** (1 minute):
```bash
# SSH to R31 and check Prometheus health
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  "docker exec prometheus curl -f -s http://localhost:9090/-/healthy"
# Should return "Prometheus Server is Healthy."
```

**Full Validation** (5 minutes):
1. Open Prometheus: https://prometheus.kushnir.cloud:9090/targets
2. Verify "cluster-health-replica-31" and "cluster-health-replica-42" jobs show "UP"
3. Open AlertManager: https://alertmanager.kushnir.cloud:9093
4. Verify alert rules are loaded

**Functional Test** (optional, 10 minutes):
```bash
# Simulate R31 failure (network isolation)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  "sudo iptables -I INPUT 1 -s 192.168.168.42 -j DROP"

# Wait 1-2 minutes, then check alerts in AlertManager
# Alert "ClusterHealthCheckFailure" should fire

# Restore network
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  "sudo iptables -D INPUT -s 192.168.168.42 -j DROP"
```

---

## Execution Checklist

- [ ] Verify configuration files are in place (prometheus.yml, alert-rules.yml)
- [ ] Run pre-flight check: `bash scripts/ops/deploy-cluster-health-monitoring.sh --verify-only`
- [ ] Execute deployment: `bash scripts/ops/deploy-cluster-health-monitoring.sh`
- [ ] Wait for Prometheus to reload (5-10 seconds)
- [ ] Verify health endpoints: `curl -k https://192.168.168.31/health`
- [ ] Verify scrape targets in Prometheus UI (/targets endpoint)
- [ ] Post completion evidence to GitHub issue #1661

---

## Rollback Procedure (if needed)

If deployment causes issues:

```bash
# Revert configuration changes
git log --oneline -5  # Find previous commit
git reset --hard PREVIOUS_COMMIT

# Redeploy previous version using IaC orchestrator
bash scripts/ops/deploy-production-iac.sh
```

**Rollback time**: ~5 minutes

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Prometheus overload | 🟢 LOW | 🟠 MEDIUM | 30s scrape interval is reasonable |
| Configuration syntax error | 🟢 LOW | 🟠 MEDIUM | Pre-flight checks validate syntax |
| SSH connectivity issues | 🟢 LOW | 🔴 HIGH | Pre-flight checks SSH before deployment |
| Service disruption | 🟡 MEDIUM | 🟠 MEDIUM | Prometheus restart is atomic, idempotent |

**Overall Risk**: 🟢 LOW

---

## Expected Outcomes

✅ **After deployment**:
- Prometheus scraping /health endpoints every 30 seconds on both replicas
- Alert rules configured and monitoring for failures
- Health endpoint data flowing into Prometheus time-series database
- Alerts will fire if either replica becomes unavailable for > 1 minute
- All changes versioned in git (IaC compliant)
- Deployment repeatable and reversible

---

## Timeline

- **Preparation**: ✅ COMPLETE (config verified, script ready)
- **Execution**: ⏳ READY (estimated 3-5 minutes)
- **Verification**: ⏳ READY (estimated 1-5 minutes for checks)
- **Total**: ~10 minutes (including verification)

---

## GitHub Integration

After deployment completes, update issue #1661 with:
- ✅ Configuration deployed to both replicas
- ✅ Prometheus scrape targets verified active
- ✅ Alert rules verified loaded
- ✅ Health endpoints responding
- Link to deployment commit in git history

---

## Next Steps After Completion

1. **Monitoring observation** — Monitor health metrics in Grafana for 1+ hour
2. **Alert testing** — Simulate replica failure to verify alerts work
3. **Documentation** — Update ops runbooks with health monitoring procedures
4. **Team training** — Brief team on monitoring dashboard and alert response

---

## Related Documentation

- Deployment script: `scripts/ops/deploy-cluster-health-monitoring.sh`
- IaC orchestrator: `scripts/ops/deploy-production-iac.sh`
- Failover procedures: `docs/FAILOVER-RUNBOOK.md`
- Operations reference: `docs/IaC-DEPLOYMENT-REFERENCE.md`

---

**Status**: 🟢 READY FOR IMMEDIATE EXECUTION  
**Priority**: P1 (production monitoring)  
**Complexity**: 10 minutes (deployment + verification)  
**Risk**: 🟢 LOW (configuration only, no code changes)  

**Next Action**: Execute `bash scripts/ops/deploy-cluster-health-monitoring.sh` when ready
