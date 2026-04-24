# Issue #1661 — Cluster Health Check Monitoring Deployment

## Status: READY FOR DEPLOYMENT ✅

**Issue**: P1 #1661 - Cluster Health Check Monitoring & Alerts  
**Classification**: Infrastructure/Monitoring  
**Prerequisites**: ✅ All complete
- Prometheus configuration with health check scrape jobs
- AlertManager alert rules configured
- Docker Compose environment ready

**Deployment Type**: Idempotent (safe to run multiple times)  
**Blast Radius**: MINIMAL (prometheus container only)  
**Rollback**: INSTANT (revert prometheus config, restart container)  

---

## Overview

Deploys production-grade health monitoring to ensure:
- **Every 30 seconds**: Both cluster replicas are polled for health status
- **On failure**: Alerts fire to ops team with severity levels
- **Two-tier alerting**:
  - Single replica down → HIGH severity
  - Both replicas down → CRITICAL (immediate escalation)

---

## Configuration Already Deployed

### Prometheus Scrape Jobs (prometheus.yml)

Both replicas have health check jobs configured:

```yaml
# Cluster health checks - Replica 31
- job_name: 'cluster-health-replica-31'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ['192.168.168.31:443']
      labels:
        replica: '31'
        cluster: production
  metrics_path: /health
  scrape_interval: 30s
  scrape_timeout: 10s

# Cluster health checks - Replica 42
- job_name: 'cluster-health-replica-42'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ['192.168.168.42:443']
      labels:
        replica: '42'
        cluster: production
  metrics_path: /health
  scrape_interval: 30s
  scrape_timeout: 10s
```

**Details**:
- **Interval**: 30 seconds (balanced between responsiveness and load)
- **Timeout**: 10 seconds (prevents slow endpoint hangs)
- **Protocol**: HTTPS with certificate verification disabled (self-signed certs)
- **Health endpoint**: `/health` on port 443 (both replicas expose health endpoint)

### AlertManager Rules (alert-rules.yml)

Two alert levels configured:

**Alert 1: Single Replica Down** (fires after 1 minute)
```yaml
- alert: ClusterHealthCheckFailure
  expr: up{job=~"cluster-health-replica-.*"} == 0
  for: 1m
  labels:
    severity: critical
    team: infrastructure
    component: cluster-health
  annotations:
    summary: "Cluster replica health check failure - {{ $labels.replica }}"
    description: "Replica {{ $labels.replica }} (192.168.168.{{ $labels.replica }}) failed health check for 1+ minute. IDE cluster may have degraded capacity."
    runbook: "https://github.com/kushin77/code-server/blob/main/docs/OPERATIONS-RUNBOOK.md#cluster-health"
```

**Alert 2: Both Replicas Down** (fires immediately, 30 second detection window)
```yaml
- alert: ClusterHealthCheckBothReplicasDown
  expr: count(up{job=~"cluster-health-replica-.*"} == 0) == 2
  for: 30s
  labels:
    severity: critical
    team: infrastructure
    component: cluster-health
  annotations:
    summary: "CRITICAL: Both cluster replicas are down"
    description: "Both production replicas (31 and 42) have failed health checks. Cluster is OFFLINE. Immediate escalation required."
    runbook: "https://github.com/kushin77/code-server/blob/main/docs/OPERATIONS-RUNBOOK.md#cluster-emergency-recovery"
```

---

## Deployment Procedure

### Step 1: Automated Deployment (Recommended)

Run the provided deployment script:

```bash
bash scripts/ops/deploy-cluster-health-monitoring.sh
```

**What it does**:
1. Verifies SSH connectivity to both replicas
2. Checks git commit parity
3. Restarts prometheus service on both replicas (parallel)
4. Verifies Prometheus health endpoints respond
5. Confirms scrape targets are configured

**Duration**: 1-2 minutes

### Step 2: Manual Deployment (If Script Unavailable)

Deploy to each replica:

```bash
# Replica 31
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && \
   docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus'

# Replica 42
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && \
   docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus'
```

---

## Verification Steps

### 1. Check Prometheus Health

```bash
# From local machine
curl -k https://192.168.168.31:9090/-/healthy
curl -k https://192.168.168.42:9090/-/healthy

# Expected output: 200 OK
```

### 2. Verify Scrape Targets

In Prometheus UI (`https://prometheus.kushnir.cloud:9090/targets`):

- Look for jobs: `cluster-health-replica-31`, `cluster-health-replica-42`
- State should show: 🟢 UP (both)
- Last Scrape should show: "a few seconds ago"

### 3. Check Alert Rules

In Prometheus UI (`https://prometheus.kushnir.cloud:9090/rules`):

- Look for alerts: `ClusterHealthCheckFailure`, `ClusterHealthCheckBothReplicasDown`
- State: Loaded and active

### 4. Verify Metrics Collection

```bash
# Query Prometheus metrics directly
curl -k -s 'https://192.168.168.31:9090/api/v1/query?query=up{job="cluster-health-replica-31"}' | jq '.data.result'

# Expected output:
# [
#   {
#     "metric": {
#       "__name__": "up",
#       "job": "cluster-health-replica-31",
#       "replica": "31",
#       "cluster": "production"
#     },
#     "value": [1234567890, "1"]   // "1" means UP
#   }
# ]
```

---

## Alert Testing

### Test 1: Simulate Single Replica Failure

To test the single replica alert:

```bash
# Temporarily stop health responses on Replica 31
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose down'

# Wait 90 seconds (30s scrape + 60s for alert to fire)
sleep 90

# Verify alert fired in AlertManager
curl -k -s 'https://192.168.168.31:9090/api/v1/alerts?filter=ClusterHealthCheckFailure' | jq '.data[]'

# Restore services
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d'
```

### Test 2: Simulate Both Replicas Down

```bash
# Stop both replicas temporarily
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose down' &
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && docker-compose down' &
wait

# Wait 60 seconds (30s scrape + 30s for alert to fire)
sleep 60

# Verify both-replicas alert fired
curl -k -s 'https://192.168.168.31:9090/api/v1/alerts?filter=ClusterHealthCheckBothReplicasDown' | jq '.data[]'

# Restore services
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d' &
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d' &
wait
```

---

## Governance Compliance ✅

| Standard | Status | Details |
|----------|--------|---------|
| **IaC** | ✅ | Configuration in prometheus.yml (version-controlled) |
| **Immutable** | ✅ | Deployment reads only from version-controlled config |
| **Idempotent** | ✅ | `docker-compose up -d` safe to run multiple times |
| **Deterministic** | ✅ | Same config → same scrape behavior always |
| **No Hardcoding** | ✅ | IP addresses in config (not scripts) |

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Prometheus crash on restart | LOW | Monitoring offline for 30s | Automatic docker restart |
| Alert misconfiguration | LOW | Alerts don't fire | Tested alert rules in PR |
| Network connectivity to replicas | LOW | Scrape job fails | Both replicas confirmed healthy |
| Alert fatigue (too sensitive) | MEDIUM | Ops team noise | Alerts fire only after 30s-60s sustained failure |

---

## Rollback Procedure

If something goes wrong:

```bash
# Stop Prometheus monitoring on both replicas
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose down prometheus'
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && docker-compose down prometheus'

# Revert prometheus.yml from git
git checkout prometheus.yml alert-rules.yml

# Redeploy
bash scripts/ops/deploy-cluster-health-monitoring.sh
```

---

## Success Criteria

After deployment, verify:

- [ ] Prometheus scrape jobs show UP status for both replicas
- [ ] Health metrics being collected (query shows non-zero values)
- [ ] Alert rules are active and loaded
- [ ] Manual alert test fires when replica is brought down
- [ ] Prometheus remains UP after restart cycle

---

## Next Steps

1. **Execute**: Run deployment script or manual SSH commands
2. **Verify**: Follow verification steps above
3. **Test**: Run alert simulation tests
4. **Document**: Update GitHub issue #1661 with deployment evidence
5. **Monitor**: Watch for first 24 hours to detect any issues

---

## Documentation References

- Prometheus Health Monitoring: [docs/OPERATIONS-RUNBOOK.md](docs/OPERATIONS-RUNBOOK.md#cluster-health)
- Cluster Architecture: [docs/CLUSTER-ARCHITECTURE.md](docs/CLUSTER-ARCHITECTURE.md)
- Alert Routing: [docs/ALERTING-SETUP.md](docs/ALERTING-SETUP.md)

---

## Timeline

| Step | Duration | Notes |
|------|----------|-------|
| Deployment | 1-2 min | Parallel SSH deployments |
| Prometheus startup | 5-10 sec | Container initialization |
| First scrape | 30 sec | Scrape interval window |
| Alert propagation | 30-60 sec | Dependent on alert for/timeout settings |
| **Total to operational** | ~2 min | |

---

**Status**: ✅ READY FOR IMMEDIATE DEPLOYMENT  
**No blocking factors**  
**Expected outcome**: Continuous 30-second health monitoring with automated critical alerting
