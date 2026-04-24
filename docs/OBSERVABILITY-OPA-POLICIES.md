# OPA Policy Monitoring & Alerting Documentation

**Last Updated:** 2026-04-25T00:00:00Z
**Status:** Production Ready
**P0-1552 Phase 5 Deliverable**

## OPA Observability Stack

All OPA policy decisions are logged, exported to Prometheus, and visualized in Grafana for real-time policy enforcement monitoring.

### Decision Log Metrics

- **opa_decisions_total**: Counter of all OPA policy decisions (allow/deny)
- **opa_policy_violations_total**: Counter of policy violations by policy name
- **opa_decision_evaluation_seconds**: Histogram of policy evaluation latency

### Grafana Dashboards

1. **OPA Policy Monitoring**
   - Policy allow/deny rate (5-minute windows)
   - Decision evaluation latency (95th percentile)
   - Policy violations by type (table)
   - Top policy violators (by user/service)

2. **OPA System Health**
   - Service uptime
   - Bundle load success/failure rates
   - Decision log throughput

### Alert Rules

| Alert | Threshold | Severity | Action |
|-------|-----------|----------|--------|
| OPAPolicyViolationRateHigh | >2% violations/sec for 5m | Warning | Review policy logs |
| OPADecisionLatencyHigh | p95 >100ms for 10m | Warning | Check OPA resource usage |
| OPAServiceDown | Up metric == 0 for 1m | Critical | Restart OPA service, escalate |

### Sample Metrics Query

```promql
# Allow rate per policy (last 5 minutes)
rate(opa_decisions_total{decision="allow"}[5m])

# Top 10 denied policies
topk(10, increase(opa_decisions_total{decision="deny"}[1h]))

# Policy evaluation latency p99
histogram_quantile(0.99, opa_decision_evaluation_seconds)
```

### Access

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (dashboard: "OPA Policy Monitoring")
- **OPA Metrics Endpoint**: http://localhost:8181/metrics
- **OPA Decision Logs**: http://localhost:8181/v1/data/system/opa/decisions

### Troubleshooting

**OPA not exporting metrics:**
```bash
curl http://localhost:8181/health  # Verify OPA is running
```

**Policy violations spiking:**
1. Check alert: `OPAPolicyViolationRateHigh`
2. Query violated policy: `rate(opa_decisions_total{decision="deny", policy="<name>"}[5m])`
3. Review policy logs in Loki: `{job="opa"} | json | decision="deny"`
4. Investigate root cause and update policy or service behavior
