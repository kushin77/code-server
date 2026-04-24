# P1 #1661 Execution — Cluster Health Monitoring Deployment

**Date**: April 23, 2026  
**Priority**: P1 — Production infrastructure  
**Status**: 🟢 READY TO EXECUTE  
**Governance**: 100% IaC/immutable/idempotent  

---

## Execution Plan

This execution deploys Prometheus health check configuration to both production replicas using the IaC-compliant deployment script.

### Prerequisites ✅
- ✅ Configuration files in place (prometheus.yml + alert-rules.yml)
- ✅ Deployment script available (scripts/ops/deploy-cluster-health-monitoring.sh)
- ✅ SSH access to both replicas available
- ✅ Prior IaC orchestration established (deploy-production-iac.sh)

---

## Execution Steps (IaC-Compliant)

### Step 1: Pre-Flight Verification (2 min)

```bash
# Verify configuration files exist
ls -la prometheus.yml alert-rules.yml

# Verify health check jobs are configured
grep -A 5 "cluster-health-replica-31" prometheus.yml
grep -A 5 "cluster-health-replica-42" prometheus.yml

# Verify alert rules are configured
grep "ClusterHealthCheckFailure" alert-rules.yml
grep "ClusterHealthCheckBothReplicasDown" alert-rules.yml
```

### Step 2: Verify Script (1 min)

```bash
# Run with --verify-only flag (no changes)
bash scripts/ops/deploy-cluster-health-monitoring.sh --verify-only
```

Expected output: "Verify-only mode: configuration is valid"

### Step 3: Execute Deployment (5-7 min)

```bash
# Deploy to both replicas (parallel execution)
bash scripts/ops/deploy-cluster-health-monitoring.sh
```

**What the script does**:
1. Verifies SSH connectivity to both replicas
2. Checks local git state (clean working tree)
3. Commits configuration if needed
4. Pushes to origin/main
5. Uses IaC orchestrator to deploy to both replicas
6. Verifies Prometheus scrape targets are healthy

### Step 4: Post-Deployment Verification (2-3 min)

```bash
# Check health endpoints
echo "=== HEALTH ENDPOINTS ==="
curl -k https://192.168.168.31/health
curl -k https://192.168.168.42/health

# Check Prometheus targets (should show "UP")
echo "=== PROMETHEUS TARGETS ==="
curl -s https://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job | contains("cluster-health"))'

# Check Alert rules loaded
echo "=== ALERT RULES ==="
curl -s https://192.168.168.31:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.name | contains("ClusterHealthCheck"))'
```

---

## Governance Compliance Verification

| Standard | Verification Command |
|----------|---------------------|
| **IaC** | `git log --oneline prometheus.yml alert-rules.yml` |
| **Immutable** | No manual SSH commands (all via script) |
| **Idempotent** | Can re-run script multiple times safely |
| **Deterministic** | Same config → identical deployment every time |
| **Reversible** | `git reset --hard HEAD~1 && bash scripts/ops/deploy-production-iac.sh` |
| **Linux-Native** | `head -1 scripts/ops/deploy-cluster-health-monitoring.sh` → `#!/usr/bin/env bash` |

---

## Success Criteria

✅ **All deployments must pass**:
- [ ] Health endpoints respond with 200 OK
- [ ] Prometheus scrape targets show "UP" status
- [ ] Alert rules loaded and active in Prometheus
- [ ] No errors in deployment script output
- [ ] Health data being collected every 30 seconds

---

## Rollback Procedure (if needed)

```bash
# Find previous working commit
git log --oneline -5

# Rollback to previous commit
git reset --hard <previous-commit>

# Re-deploy previous configuration
bash scripts/ops/deploy-production-iac.sh
```

**Rollback time**: ~5 minutes

---

## Risk Assessment

| Risk | Level | Mitigation |
|------|-------|-----------|
| Configuration syntax error | 🟢 LOW | Pre-flight checks validate YAML |
| SSH connectivity failure | 🟢 LOW | Pre-flight validates SSH to both replicas |
| Prometheus restart | 🟡 MEDIUM | Restart is atomic, <1s interruption, idempotent |
| Service disruption | 🟢 LOW | No app code changes, config only |

**Overall Risk**: 🟢 **LOW**

---

## Timeline

| Phase | Time | Activity |
|-------|------|----------|
| Pre-flight | 2 min | Verify configuration files |
| Verification | 1 min | Run script with --verify-only |
| Execution | 5-7 min | Deploy to both replicas |
| Post-verification | 2-3 min | Check health endpoints, targets, alerts |
| **Total** | **10-13 min** | **End-to-end execution** |

---

## Execution Command (Quick Reference)

```bash
# Verify first (non-destructive)
bash scripts/ops/deploy-cluster-health-monitoring.sh --verify-only

# Then execute (if verify passes)
bash scripts/ops/deploy-cluster-health-monitoring.sh
```

---

## Post-Execution Actions

1. **✅ Update GitHub #1661** — Post completion evidence
   - Deployment timestamp
   - Verification results
   - Health metrics snapshot

2. **✅ Monitor for 1 hour** — Observe metrics collection
   - Check Prometheus metrics at: https://prometheus.kushnir.cloud/targets
   - Verify no alerts firing
   - Check Grafana dashboards

3. **✅ Document procedures** — Update operational runbooks
   - Add health monitoring to deployment procedures
   - Add alert response procedures
   - Link to failover procedures

4. **✅ Team notification** — Brief team on monitoring setup

---

## Related Documentation

- Deployment script: `scripts/ops/deploy-cluster-health-monitoring.sh`
- IaC orchestrator: `scripts/ops/deploy-production-iac.sh`
- Pre-flight checks: `scripts/ops/pre-flight-deployment-check.sh`
- Operations reference: `docs/IaC-DEPLOYMENT-REFERENCE.md`
- Failover runbook: `docs/FAILOVER-RUNBOOK.md`

---

## Next Task (After Completion)

Once #1661 deployment is complete and verified:
- **P1 #1667** — Session Lifecycle Coordinator (Hibernation + Broker orchestration)
- **P1 #1669** — Network Resilience Coordinator (Delta Sync + Migration orchestration)

---

**Status**: 🟢 **READY FOR IMMEDIATE EXECUTION**  
**Governance**: ✅ 100% IaC/immutable/idempotent  
**Risk**: 🟢 **LOW**  
**Next**: Execute `bash scripts/ops/deploy-cluster-health-monitoring.sh --verify-only` then main deployment

---

*For detailed documentation, see P1-1661-EXECUTION-READY.md*
