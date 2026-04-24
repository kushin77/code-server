# Issue #1661 Execution Ready — Cluster Health Monitoring Deployment

**Date**: April 24, 2026  
**Issue**: #1661 (P1)  
**Title**: Cluster Health Check Monitoring & Alerts  
**Status**: ✅ READY FOR IMMEDIATE EXECUTION  

---

## Task Summary

Deploy production health monitoring to both cluster replicas:
- Prometheus scrape jobs every 30 seconds on health endpoints
- AlertManager rules for single replica (HIGH) and dual replica (CRITICAL) failures
- All configuration already committed to git

**Type**: Infrastructure/Monitoring  
**Blast Radius**: Minimal (Prometheus container restart only)  
**Risk Level**: Low (idempotent, instant rollback)  
**Estimated Time**: 2-5 minutes  

---

## Execution Options

### Option A: Automated Deployment (Recommended)

```bash
bash scripts/ops/deploy-cluster-health-monitoring.sh
```

**What it does**:
1. ✓ Verifies SSH connectivity to both replicas
2. ✓ Checks git commit parity
3. ✓ Restarts prometheus service on both replicas (parallel)
4. ✓ Verifies Prometheus health endpoints respond
5. ✓ Confirms scrape targets are configured

### Option B: Manual Deployment (Direct SSH)

Deploy to both replicas in parallel:

```bash
# Deploy to Replica 31 & 42 in parallel
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus' &

ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus' &

wait  # Wait for both to complete
```

### Option C: Individual Replica Deployment (Sequential)

If parallel deployment unavailable:

```bash
# Replica 31
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus'

# Replica 42
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus'
```

---

## Configuration Summary

### Prometheus Scrape Jobs (Already in prometheus.yml)

**Replica 31 Health Check**:
- Target: `192.168.168.31:443`
- Endpoint: `/health`
- Interval: 30 seconds
- Timeout: 10 seconds
- Protocol: HTTPS (self-signed cert OK)

**Replica 42 Health Check**:
- Target: `192.168.168.42:443`
- Endpoint: `/health`
- Interval: 30 seconds
- Timeout: 10 seconds
- Protocol: HTTPS (self-signed cert OK)

### AlertManager Rules (Already in alert-rules.yml)

**Alert 1: Single Replica Down** (HIGH)
- Condition: One replica fails health check
- Threshold: 1 minute of failures
- Severity: HIGH
- Action: Notify ops team

**Alert 2: Both Replicas Down** (CRITICAL)
- Condition: Both replicas fail health check
- Threshold: 30 seconds of failures
- Severity: CRITICAL
- Action: Immediate escalation

---

## Post-Deployment Verification

### Step 1: Confirm Prometheus Running

```bash
# Check process on Replica 31
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'docker ps | grep prometheus'

# Check process on Replica 42
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'docker ps | grep prometheus'
```

**Expected**: `prometheus` container showing status "Up X minutes"

### Step 2: Check Prometheus Health

```bash
# Replica 31
curl -k -s https://192.168.168.31:9090/-/healthy

# Replica 42  
curl -k -s https://192.168.168.42:9090/-/healthy
```

**Expected**: HTTP 200 OK

### Step 3: Verify Scrape Targets

```bash
# Query Prometheus for active targets
curl -k -s 'https://192.168.168.31:9090/api/v1/targets?state=active' | \
  jq '.data.activeTargets[] | select(.labels.job | contains("cluster-health")) | {job: .labels.job, health: .health}'
```

**Expected**:
```json
{
  "job": "cluster-health-replica-31",
  "health": "up"
}
{
  "job": "cluster-health-replica-42",
  "health": "up"
}
```

### Step 4: Check Alert Rules

Access Prometheus UI: `https://prometheus.kushnir.cloud:9090/rules`

**Expected**:
- ✅ Alert `ClusterHealthCheckFailure` - Loaded
- ✅ Alert `ClusterHealthCheckBothReplicasDown` - Loaded

---

## Success Criteria

- [x] Configuration files committed (prometheus.yml, alert-rules.yml)
- [ ] Prometheus service deployed to both replicas
- [ ] Both replicas health endpoint responding to scrape jobs
- [ ] Scrape targets showing "UP" status
- [ ] Alert rules loaded and active
- [ ] Production monitoring now operational

---

## Quick Reference Files

- **Deployment Script**: [scripts/ops/deploy-cluster-health-monitoring.sh](scripts/ops/deploy-cluster-health-monitoring.sh)
- **Configuration Guide**: [1661-HEALTH-MONITORING-DEPLOYMENT.md](1661-HEALTH-MONITORING-DEPLOYMENT.md)
- **Quick Commands**: [1661-QUICK-DEPLOYMENT-REFERENCE.md](1661-QUICK-DEPLOYMENT-REFERENCE.md)
- **Prometheus Config**: [prometheus.yml](prometheus.yml)
- **Alert Rules**: [alert-rules.yml](alert-rules.yml)

---

## Implementation Checklist

### Pre-Deployment
- [x] SSH keys available on local machine
- [x] Git committed and pushed (idempotent)
- [x] Prometheus config files verified
- [x] Alert rules verified

### Deployment
- [ ] Execute deployment script OR manual SSH commands
- [ ] Monitor both replicas during restart
- [ ] Confirm zero errors during deployment

### Post-Deployment
- [ ] Verify Prometheus health endpoint responding (200 OK)
- [ ] Confirm scrape targets "UP" on both replicas
- [ ] Check alert rules loaded and active
- [ ] Monitor first scrape cycle (~30 seconds)

### Verification
- [ ] Query metrics from Prometheus API
- [ ] Check Prometheus UI for active targets
- [ ] Review alert rules in Prometheus UI
- [ ] Test alert delivery (if applicable)

---

## Expected Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| Pre-flight checks | 15 seconds | SSH connectivity, git state |
| Deployment | 1-2 minutes | Restart prometheus on both replicas |
| Health verification | 1 minute | Scrape cycle + metrics collection |
| Alert rules load | <30 seconds | Prometheus rule reload |
| **Total** | **3-5 minutes** | **From start to fully operational** |

---

## Rollback Plan (If Needed)

If Prometheus fails to start:

```bash
# Stop Prometheus (both replicas)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose stop prometheus'

ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && docker-compose stop prometheus'

# Then re-execute deployment
bash scripts/ops/deploy-cluster-health-monitoring.sh
```

No data loss risk (monitoring config only).

---

## Next Task After #1661

**Issue #1662** - Integration Testing (Collab-9 staging validation)
- GitHub task webhook → WebSocket broadcast flow validation
- Load testing baseline (5 concurrent users, 100 requests)
- Metrics & observability validation
- Expected: Complete by April 25, 2026

---

## Status Summary

✅ **All Preparation Complete**
✅ **Configuration Committed & Ready**
✅ **Deployment Scripts Available**
✅ **Documentation Comprehensive**
✅ **Ready for Immediate Execution**

---

**Prepared**: April 24, 2026  
**Next Task**: Execute Option A (automated deployment) or Option B/C (manual deployment)  
**Governance**: ✅ IaC compliant (git-controlled, idempotent, instant rollback)
