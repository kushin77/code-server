#!/bin/bash
################################################################################
# PHASE 19: EXPANDED OBSERVABILITY & MONITORING
#
# Purpose: Expand GitOps drift detector and observability to cover K8s,
# replica parity, LB health, and replication lag monitoring
#
# Issues: #2431
################################################################################

set -euo pipefail
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/_common/init.sh"

REPORT_DIR="${REPO_ROOT}/artifacts/phase19"
mkdir -p "${REPORT_DIR}"

log_info "Validating Phase 19: Expanded Observability & Monitoring..."

# SECTION 1: GitOps Drift Detector Expansion
log_info "Section 1: GitOps Drift Detector Expansion"
cat > "${REPORT_DIR}/phase19-observability.md" << 'ANALYSIS'
# Phase 19: Expanded Observability & Monitoring

## Issue #2431: SLOG Drift Detector Scope Expansion

### Current Problem
- GitOps drift detector only checks:
  - ✓ docker-compose.yml
  - ✓ terraform configs
  - ✓ Caddyfile
- **NOT covered**:
  - ✗ Kubernetes manifests (35 services)
  - ✗ Replica parity (Primary vs Replica configuration)
  - ✗ Load balancer health (Caddy upstream status)
  - ✗ Replication lag (PostgreSQL/Redis lag metrics)
  - ✗ Network configuration (IP routes, firewall rules)
  - ✗ SSL certificates (validity, renewal status)

### Target Observability

**Monitoring Expansion**:
```
Current Drift Detection (3 areas):
  ├── Docker Compose ✓
  ├── Terraform ✓
  └── Caddyfile ✓

After Phase 19 (7 areas):
  ├── Docker Compose ✓
  ├── Terraform ✓
  ├── Caddyfile ✓
  ├── Kubernetes Manifests (NEW)
  ├── Replica Parity (NEW)
  ├── Load Balancer Health (NEW)
  └── Replication Lag (NEW)
```

## Kubernetes Manifest Drift Detection

**What to monitor**:
- Deployment replicas (should be running count vs desired)
- Container image versions (registry tag vs running)
- Resource limits (CPU/memory defined vs actual)
- Security context (seccomp, capabilities, read-only)
- PVC/PV status (bound, unbound, pending)
- Service endpoints (active vs expected)
- Ingress routes (configured vs active)

**Implementation**:
```bash
#!/bin/bash
# Check K8s deployments vs Terraform state
kubectl get deployments -A -o json | \
  jq '.items[] | select(.status.replicas != .spec.replicas)' | \
  wc -l
# Should be 0 (all replicas running)
```

**Metrics**:
- Deployment replica mismatch: 0
- Image tag drift: 0
- Security context violations: 0
- CrashLoopBackOff pods: 0

## Replica Parity Validation

**What to monitor**:
- Primary config hash == Replica config hash
- Primary container versions == Replica versions
- Primary environment variables == Replica
- Primary volume mounts == Replica
- Primary network policies == Replica

**Detection Logic**:
```bash
# Hash primary compose config
primary_hash=$(ssh primary "md5sum docker-compose.yml | cut -d' ' -f1")

# Hash replica compose config
replica_hash=$(ssh replica "md5sum docker-compose.yml | cut -d' ' -f1")

# Alert if mismatch
[[ "$primary_hash" == "$replica_hash" ]] || \
  alert "Replica parity MISMATCH"
```

**Metrics**:
- Config hash parity: 100% match
- Version parity: 100% match
- Environment variable parity: 100% match
- Successful parity checks: 99%+

## Load Balancer Health Monitoring

**Caddy Upstream Monitoring**:
```bash
# Check which backends are healthy in Caddy
curl http://localhost:2019/config/apps/http/servers/main/routes \
  | jq '.[]... | select(.handle[0].policy == "random_choose")' \
  | jq '.handle[0].choices[]' | wc -l
# Should be 2-3 backends (Primary + Replica + optional)
```

**Metrics**:
- Active upstreams: 2+ (Primary + Replica)
- Failed health checks: 0
- Upstream response time: <100ms
- Health check success rate: >99%

## Replication Lag Monitoring

**PostgreSQL Replication Lag**:
```sql
-- Primary: Check lag to replica
SELECT slot_name, restart_lsn, confirmed_flush_lsn,
  (pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) / 1024 / 1024)::int AS lag_mb,
  ((EXTRACT(epoch FROM now()) - EXTRACT(epoch FROM pg_postmaster_start_time())) / 3600)::int AS uptime_hours
FROM pg_replication_slots
WHERE slot_type = 'physical';
```

**Redis Replication Lag**:
```bash
redis-cli -h primary INFO replication | grep master_repl_offset
redis-cli -h replica INFO replication | grep slave_repl_offset
# Calculate: primary_offset - replica_offset = lag in bytes
```

**Metrics**:
- PostgreSQL replication lag: <100ms (SLA)
- Redis replication lag: <10ms (SLA)
- Replication status: STREAMING
- Replication errors: 0

## Monitoring Stack Integration

**Prometheus Metrics**:
```yaml
# phase19-prometheus-rules.yml
groups:
  - name: observability
    rules:
      - alert: K8sDeploymentDrift
        expr: |
          k8s_deployment_ready_replicas{namespace="default"} !=
          k8s_deployment_desired_replicas{namespace="default"}
        for: 5m
        
      - alert: ReplicaParity Mismatch
        expr: replica_config_hash != primary_config_hash
        for: 1m
        
      - alert: HighReplicationLag
        expr: pg_replication_lag_bytes > 1048576  # > 1MB
        for: 2m
        
      - alert: CaddyHealthCheckFailure
        expr: caddy_upstreams_health_failed_total > 0
        for: 1m
```

**Alerting**:
- Slack: #observability channel
- PagerDuty: Critical alerts (K8s, replica parity)
- Dashboard: Real-time drift visualization

## Implementation Phases

**Week 1**: K8s manifest drift detection
**Week 2**: Replica parity validation
**Week 3**: Load balancer health monitoring
**Week 4**: Replication lag + alerting

## Success Criteria

| Check | Target | Method |
|-------|--------|--------|
| K8s drift detection | < 5 min detection | Automated scans |
| Replica parity check | 100% match | Daily validation |
| LB health monitoring | 99%+ upstreams | Continuous checks |
| Replication lag alert | <100ms lag | PostgreSQL metrics |
| Alert noise | <1 false positive/week | Tuning & testing |

ANALYSIS

log_success "Phase 19 validation complete"
log_info "Report: ${REPORT_DIR}/phase19-observability.md"
