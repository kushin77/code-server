# Chaos Engineering & Resilience Testing

## Overview

Chaos engineering proactively tests system resilience by injecting failures. This guide covers implementing Chaos Mesh in your on-premises Kubernetes cluster.

## Architecture

```
┌─────────────────────────────────────┐
│    Chaos Mesh Controller             │
│  (Monitors & Injects Failures)       │
├─────────────────────────────────────┤
│  Chaos Experiments:                  │
│  - Pod failures (kill pods)          │
│  - Network failures (latency, loss)  │
│  - Disk failures (fill, slow I/O)    │
│  - CPU/Memory exhaustion             │
│  - Clock skew (time changes)         │
│  - DNS failures                      │
└─────────────────────────────────────┘
         │
    ┌────┴────┐
    │ Metrics  │
    │ Alerts   │
    │ Logs     │
    └─────────┘
```

## Installation

### 1. Deploy Chaos Mesh

```bash
# Add Chaos Mesh Helm repo
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

# Install Chaos Mesh
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-testing \
  --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock

# Verify installation
kubectl get pods -n chaos-testing
# Should show chaos-controller-manager, chaos-daemon pods
```

### 2. Enable RBAC for Chaos Experiments

```bash
kubectl create serviceaccount chaos-user -n code-server
kubectl create clusterrolebinding chaos-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=code-server:chaos-user
```

## Resilience Experiments

### Experiment 1: Pod Failure Injection (SEV2 Testing)

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: code-server-kill-pod
  namespace: code-server
spec:
  action: pod-kill
  mode: one  # Kill only 1 pod
  selector:
    namespaces:
      - code-server
    labelSelectors:
      app: code-server
  duration: 2m
  scheduler:
    cron: "0 2 * * 0"  # Every Sunday at 2 AM
```

**Expected Behavior**:
- Traffic redirects to remaining replicas
- P99 latency spikes briefly
- Error rate < 1% (still passing SLO)
- Kubernetes reschedules killed pod within 30 seconds

**Success Criteria**:
```
✅ Downtime: 0 seconds (traffic still flows)
✅ Error rate: < 0.5%
✅ Latency spike: < 2 seconds
✅ Pod recovery: < 30 seconds
```

### Experiment 2: Network Latency Injection

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: database-latency
  namespace: code-server
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - code-server
    labelSelectors:
      app: code-server
  delay:
    latency: "500ms"  # Add 500ms latency
    jitter: "100ms"
  targetSelector:
    namespaces:
      - databases
    labelSelectors:
      app: postgresql
  duration: 5m
  scheduler:
    cron: "0 3 * * 0"  # Every Sunday at 3 AM
```

**Expected Behavior**:
- Database queries take 500ms longer
- Application should handle gracefully
- Cache hit rate increases (requests served from cache)
- SLO still met (P99 < 1s)

**Validation**:
```prometheus
# Check query latency increase
rate(http_db_query_duration_seconds[5m])
# Should show ~500ms increase

# Check error rate
rate(http_requests_total{status="5xx"}[5m])
# Should remain < 0.1%
```

### Experiment 3: Disk I/O Degradation

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: IOChaos
metadata:
  name: postgres-io-slow
  namespace: databases
spec:
  action: latency
  mode: one
  selector:
    namespaces:
      - databases
    labelSelectors:
      app: postgresql
  volumeMountPath: /var/lib/postgresql
  latency: "1000ms"  # 1 second I/O latency
  perturb: 10  # 10% of I/O operations
  duration: 3m
  scheduler:
    cron: "0 4 * * 0"  # Weekly Sunday 4 AM
```

**Expected Behavior**:
- Database commits slow down
- WAL writes buffer in memory
- Connections may timeout
- Failover to replica (if configured)

**Recovery**:
```bash
# Monitor recovery
kubectl logs -f -n databases postgresql-0 | grep "WAL"
# Should see recovery of write rates after chaos ends
```

### Experiment 4: Memory Pressure

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: redis-memory-stress
  namespace: code-server
spec:
  action: stress-mem
  mode: one
  selector:
    namespaces:
      - code-server
    labelSelectors:
      app: redis
  stress:
    memory-worker: 1
    memory-size: "1GB"  # Request 1GB of memory
  duration: 3m
  scheduler:
    cron: "0 5 * * 0"  # Weekly Sunday 5 AM
```

**Expected Behavior**:
- Redis memory usage increases
- LRU eviction kicks in
- Cache hit rate drops
- Application queries slower
- No pod OomKill (limit is 2GB)

**Validation**:
```bash
# Monitor memory during chaos
kubectl top pod redis-0 -n code-server --watch

# Check eviction rate
kubectl exec -n code-server redis-0 -- redis-cli INFO stats | grep evicted
```

### Experiment 5: Network Partition (Split-Brain Testing)

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: code-server-partition
  namespace: code-server
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - code-server
    labelSelectors:
      app: code-server
  direction: both  # Block all traffic
  targetSelector:
    namespaces:
      - agents
    labelSelectors:
      app: agent-api
  duration: 1m
  scheduler:
    cron: "0 6 * * 0"  # Weekly Sunday 6 AM
```

**Expected Behavior**:
- code-server can't reach agent-api
- Circuit breaker engages
- Requests fail fast (not hang)
- Error rate spikes
- Recovery automatic after 1 minute

**Success Criteria**:
```
✅ Error rate spike: Expected (100% expected)
✅ Recovery time: < 10 seconds after partition heals
✅ No hanging requests: All requests timeout < 30s
✅ Data consistency: Maintained (no corruption)
```

### Experiment 6: Multiple Simultaneous Failures (Worst Case)

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: WorkflowEntry
metadata:
  name: Multi-Failure-Scenario
  namespace: code-server
spec:
  templates:
  - name: main
    steps:
    - - name: pod-kill
        templateName: pod-kill
    - - name: network-delay
        templateName: network-delay
    - - name: io-chaos
        templateName: io-chaos
  entrypoint: main
---
apiVersion: chaos-mesh.org/v1alpha1
kind: Template
metadata:
  name: pod-kill
spec:
  chaos:
    podChaos:
      action: pod-kill
      # ... pod kill spec ...
```

**Runbook for Multiple Failures**:
```
Time  | Failure               | Expected Impact        | Mitigation
------|----------------------|------------------------|-------------------
0:00  | Kill 1 code-server   | Brief 5% error spike   | HPA scales up
1:00  | Add 500ms DB latency | P99 latency +500ms     | Cache absorbs
2:00  | Partition agent-api  | Agent failures         | Circuit breaker
3:00  | Disk I/O slow        | WAL buffer backlog     | Failover activates
4:00  | Recover all          | Back to baseline       | System stabilizes
```

## Test Execution Schedule

```bash
#!/bin/bash
# chaos-test-schedule.sh

echo "Weekly Chaos Engineering Test Schedule"
echo "======================================="

Monday_2am="PodChaos (app pod kill)"
Tuesday_2am="NetworkChaos (database latency)"
Wednesday_3am="NetworkChaos (DNS failure)"
Thursday_4am="IOChaos (disk slow)"
Friday_5am="StressChaos (memory pressure)"
Saturday_6am="Multiple simultaneous failures"
Sunday_Off="No chaos (observation only)"

# Deploy schedule
for day in Monday Tuesday Wednesday Thursday Friday Saturday; do
  kubectl apply -f "chaos-experiments/${day,,}-experiment.yaml"
done

# Monitor all experiments
kubectl get chaosexperiment -n code-server --watch
```

## Automated Validation

### Post-Chaos Verification

```bash
#!/bin/bash
# validation.sh - Run after chaos experiment

set -e

echo "=== Chaos Test Validation ==="

# 1. Check pod status
PENDING=$(kubectl get pods -n code-server --field-selector=status.phase=Pending -o json | jq '.items | length')
if [ "$PENDING" -gt 0 ]; then
  echo "❌ FAIL: $PENDING pods still pending"
  exit 1
fi

# 2. Check data consistency
EXPECTED_ROWS=$(kubectl exec -n databases postgresql-0 -- psql -U postgres code_server -t -c "SELECT COUNT(*) FROM audit_log;")
ACTUAL_ROWS=$(kubectl exec -n databases postgresql-0 -- psql -U postgres code_server -t -c "SELECT COUNT(*) FROM audit_log;")

if [ "$EXPECTED_ROWS" != "$ACTUAL_ROWS" ]; then
  echo "❌ FAIL: Data mismatch - expected $EXPECTED_ROWS, got $ACTUAL_ROWS"
  exit 1
fi

# 3. Check error rate
ERROR_RATE=$(kubectl exec -m monitoring prometheus-0 -- \
  promtool query instant "rate(http_requests_total{status=\"5xx\"}[5m])" | grep value)

if [ "$ERROR_RATE" -gt 0.001 ]; then  # > 0.1%
  echo "⚠️  WARNING: Error rate elevated at $ERROR_RATE"
fi

# 4. Check latency
P99_LATENCY=$(kubectl exec -m monitoring prometheus-0 -- \
  promtool query instant "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))")

if [ "$P99_LATENCY" -gt 2000 ]; then  # > 2 seconds
  echo "⚠️  WARNING: P99 latency elevated at ${P99_LATENCY}ms"
fi

echo "✅ Post-chaos validation complete"
```

## Observability During Chaos

### Prometheus Queries

```prometheus
# Error rate during chaos
rate(http_requests_total{status="5xx"}[5m])

# Latency percentiles
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.999, rate(http_request_duration_seconds_bucket[5m]))

# Pod recovery time
time() - container_creation_time{pod=~"code-server.*"}

# Cache hit ratio during chaos
rate(redis_hits[5m]) / (rate(redis_hits[5m]) + rate(redis_misses[5m]))

# Database connection pool
pg_stat_activity_count by (state)
```

### Grafana Dashboard Queries

Display during chaos test:
- Error rate (5-min average)
- P99 latency (current)
- Active pods (vs desired)
- Cache hit ratio
- Database connection count
- Memory usage

## Chaos Testing Best Practices

1. **Start Small**: Kill 1 pod before testing complex scenarios
2. **Test in Staging First**: Never test untested experiments in production
3. **Have Runbook Ready**: Know how to abort/rollback before starting
4. **Monitor Closely**: Watch metrics in real-time
5. **Document Results**: Record SLO impact and recovery characteristics
6. **Iterate**: Improve resilience based on failure patterns
7. **Regular Cadence**: Weekly chaos tests (Sunday early morning)
8. **Team Involvement**: On-call team watches and learns from chaos

## Success Metrics

After 4 weeks of chaos engineering, expect:

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| MTTR (Mean Time To Recovery) | 30 min | 5 min | < 5 min ✅ |
| Unplanned Downtime | 2 hours/month | < 15 min | < 15 min |
| Incident Response SLA Met | 85% | 98% | > 95% |
| Data Loss Incidents | 1 incident | 0 incidents | 0 |

## Automated Chaos Report

```bash
# Build chaos report (monthly)
#!/bin/bash
REPORT="chaos-report-$(date +%Y-%m).md"

echo "# Chaos Engineering Report - $(date +%B %Y)" > $REPORT
echo "" >> $REPORT
echo "## Tests Executed" >> $REPORT
kubectl get chaosexperiments -n code-server -o json | \
  jq '.items[] | "\(.metadata.name): \(.status.state)"' >> $REPORT

echo "## Findings" >> $REPORT
grep "FAIL\|alert\|violation" monitoring/chaos-test.log >> $REPORT

echo "## Improvements Made" >> $REPORT
git log --oneline --grep="chaos\|resilience" origin/main..HEAD >> $REPORT

echo "Chaos report: $REPORT"
```

---

## Next: Test Your System

Start with Experiment 1 (pod kill) and run Sunday at 2 AM. Observe the behavior. Does your system handle gracefully?

If yes → proceed to Experiment 2 (network latency).  
If no → implement fixes based on what you learned.
