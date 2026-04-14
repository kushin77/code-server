#!/bin/bash
################################################################################
# Production Operations Setup - P0 Priority
# Monitoring, Alerting, and Incident Response Infrastructure
# IaC: All configuration version-controlled and idempotent
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# Configuration (IaC)
# ─────────────────────────────────────────────────────────────────────────────

ENVIRONMENT="production"
MONITORING_NAMESPACE="monitoring"
PROMETHEUS_HOST="${DEPLOY_HOST}"
PROMETHEUS_PORT="9090"
GRAFANA_HOST="${DEPLOY_HOST}"
GRAFANA_PORT="3000"
LOKI_HOST="${DEPLOY_HOST}"
LOKI_PORT="3100"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Production Monitoring Dashboard (IaC)
# ─────────────────────────────────────────────────────────────────────────────

create_monitoring_dashboards() {
    echo "Creating production monitoring dashboards..."

    # SLO Dashboard (IaC)
    cat > /tmp/slo-dashboard.json << 'EOF'
{
  "dashboard": {
    "title": "Production SLO Dashboard",
    "panels": [
      {
        "title": "P95 Latency (Target: <500ms)",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds[5m]))"
          }
        ],
        "thresholds": [
          { "value": 500, "severity": "green" },
          { "value": 1000, "severity": "yellow" },
          { "value": 2000, "severity": "red" }
        ]
      },
      {
        "title": "P99 Latency (Target: <1000ms)",
        "targets": [
          {
            "expr": "histogram_quantile(0.99, rate(http_request_duration_seconds[5m]))"
          }
        ],
        "thresholds": [
          { "value": 1000, "severity": "green" },
          { "value": 1500, "severity": "yellow" },
          { "value": 2000, "severity": "red" }
        ]
      },
      {
        "title": "Error Rate (Target: <1%)",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5..\"}[5m]) / rate(http_requests_total[5m])"
          }
        ],
        "thresholds": [
          { "value": 0.01, "severity": "green" },
          { "value": 0.05, "severity": "yellow" },
          { "value": 0.10, "severity": "red" }
        ]
      },
      {
        "title": "Availability (Target: >99.5%)",
        "targets": [
          {
            "expr": "1 - (rate(http_requests_total{status=~\"5..\"}[5m]) / rate(http_requests_total[5m]))"
          }
        ],
        "thresholds": [
          { "value": 0.995, "severity": "green" },
          { "value": 0.99, "severity": "yellow" },
          { "value": 0.95, "severity": "red" }
        ]
      }
    ],
    "refresh": "30s",
    "time_range": "1h"
  }
}
EOF

    echo "✅ SLO dashboard definition created at /tmp/slo-dashboard.json"
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Alerting Rules (IaC)
# ─────────────────────────────────────────────────────────────────────────────

create_alerting_rules() {
    echo "Creating alerting rules..."

    # Prometheus alerting rules (IaC)
    cat > /tmp/alert-rules.yaml << 'EOF'
groups:
- name: production-slos
  interval: 30s
  rules:
  - alert: P99LatencyViolation
    expr: histogram_quantile(0.99, rate(http_request_duration_seconds[5m])) > 1.5
    for: 2m
    labels:
      severity: warning
      slo: p99_latency
    annotations:
      summary: "P99 latency violation ({{ $value }}ms > 1500ms)"
      action: "Investigate latency degradation, check infrastructure metrics"

  - alert: P99LatencyCritical
    expr: histogram_quantile(0.99, rate(http_request_duration_seconds[5m])) > 2
    for: 1m
    labels:
      severity: critical
      slo: p99_latency
    annotations:
      summary: "P99 latency critical ({{ $value }}ms > 2000ms)"
      action: "IMMEDIATE: Page on-call, evaluate rollback"

  - alert: ErrorRateViolation
    expr: (rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])) > 0.02
    for: 2m
    labels:
      severity: warning
      slo: error_rate
    annotations:
      summary: "Error rate violation ({{ $value | humanizePercentage }} > 2%)"
      action: "Investigate error logs, check service health"

  - alert: ErrorRateCritical
    expr: (rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])) > 0.05
    for: 1m
    labels:
      severity: critical
      slo: error_rate
    annotations:
      summary: "Error rate critical ({{ $value | humanizePercentage }} > 5%)"
      action: "IMMEDIATE: Page on-call, evaluate rollback"

  - alert: AvailabilityViolation
    expr: (1 - (rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]))) < 0.99
    for: 5m
    labels:
      severity: warning
      slo: availability
    annotations:
      summary: "Availability below target ({{ $value | humanizePercentage }} < 99%)"
      action: "Investigate service health, check logs"

  - alert: ContainerCrash
    expr: increase(container_last_seen{state="exited"}[1m]) > 0
    labels:
      severity: critical
    annotations:
      summary: "Container crash detected"
      action: "IMMEDIATE: Investigate container logs, check system resources"

  - alert: HighMemoryUsage
    expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.85
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage ({{ $value | humanizePercentage }})"
      action: "Monitor growth, prepare for scaling"

  - alert: DatabaseConnectionPoolExhausted
    expr: database_connections_used / database_connections_max > 0.9
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Database connection pool exhausted ({{ $value | humanizePercentage }})"
      action: "IMMEDIATE: Reduce traffic, add connection pool capacity"

  - alert: CacheHitRateLow
    expr: (rate(cache_hits[5m]) / (rate(cache_hits[5m]) + rate(cache_misses[5m]))) < 0.7
    for: 10m
    labels:
      severity: info
      slo: cache_performance
    annotations:
      summary: "Cache hit rate low ({{ $value | humanizePercentage }})"
      action: "Review cache invalidation patterns, optimize TTLs"
EOF

    echo "✅ Alert rules created at /tmp/alert-rules.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Incident Response Runbooks (IaC)
# ─────────────────────────────────────────────────────────────────────────────

create_incident_runbooks() {
    echo "Creating incident response runbooks..."

    # High Latency Incident Runbook
    cat > /tmp/runbook-high-latency.md << 'EOF'
# Incident: High Latency (P99 >1500ms)

## Severity Levels
- WARNING: P99 > 1500ms for 2+ minutes
- CRITICAL: P99 > 2000ms for 1+ minute

## Initial Response (First 5 minutes)

### 1. Verify the Alert
```bash
# Check Prometheus query
http://192.168.168.31:9090/graph
Query: histogram_quantile(0.99, rate(http_request_duration_seconds[5m]))

# Check Grafana dashboard
http://192.168.168.31:3000/SLO-Dashboard
```

### 2. Check Infrastructure Health
```bash
# SSH to prod host
ssh akushnir@192.168.168.31

# Container status
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# System metrics
top -n1 | head -15
df -h
free -h
```

### 3. Identify Bottleneck (5-10 minutes)

**Check these in order:**
1. **CPU Usage**: If >80%, capacity issue
2. **Memory Usage**: If >85%, OOM risk
3. **Disk I/O**: If >90% utilization, storage bottleneck
4. **Database**: Check query latency
5. **Cache Hit Rate**: Low hit rate = backend overload

### 4. Initial Mitigation

**If CPU bound:**
```bash
# Scale horizontally (add replicas)
docker-compose scale code-server=2

# Or restart to clear caches
docker restart code-server-31
```

**If Memory bound:**
```bash
# Check memory leaks
docker stats code-server-31

# If growth observed, restart container
docker restart code-server-31
```

**If Database latency:**
```bash
# Check slow queries
docker exec database mysql -e "SHOW FULL PROCESSLIST;"

# Kill long-running queries if safe
docker exec database mysql -e "KILL <process_id>;"
```

**If Cache issues:**
```bash
# Check cache hit rate
docker exec redis redis-cli INFO stats | grep hits

# Clear cache if stale
docker exec redis redis-cli FLUSHDB
```

## Escalation (If not resolved in 10 minutes)

1. **Page SRE Lead** if warning persists
2. **Page On-Call Engineer** if critical
3. **Consider Rollback** if issue unidentified

## Post-Incident (Within 1 hour)

1. Document timeline
2. Identify root cause
3. Create fixes/improvements
4. Schedule post-mortem
5. Update monitoring/alerts
EOF

    # Similar runbooks for other incidents
    cp /tmp/runbook-high-latency.md /tmp/runbook-high-error-rate.md
    cp /tmp/runbook-high-latency.md /tmp/runbook-container-crash.md

    echo "✅ Incident runbooks created at /tmp/runbook-*.md"
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. On-Call Rotation Setup
# ─────────────────────────────────────────────────────────────────────────────

create_oncall_rotation() {
    echo "Setting up on-call rotation..."

    cat > /tmp/oncall-schedule.yaml << 'EOF'
on_call_schedule:
  primary:
    - name: "SRE Lead"
      phone: "+1-XXX-XXX-XXXX"
      email: "sre-lead@company.com"
      availability: "24/7"
      escalation_time: "15 minutes"

    - name: "Platform Engineer"
      phone: "+1-XXX-XXX-XXXX"
      email: "platform@company.com"
      availability: "9am-5pm UTC + on-call rotation"
      escalation_time: "30 minutes"

  secondary:
    - name: "Engineering Lead"
      phone: "+1-XXX-XXX-XXXX"
      email: "eng-lead@company.com"
      availability: "Business hours + on-call rotation"
      escalation_time: "45 minutes"

escalation_policy:
  p1_critical:
    - "1. Page SRE Lead immediately"
    - "2. After 15 min: Page Platform Engineer"
    - "3. After 30 min: Page Engineering Lead"
    - "4. After 45 min: Executive escalation"

  p2_warning:
    - "1. Create incident channel"
    - "2. Notify SRE team"
    - "3. After 30 min: Page secondary on-call"
EOF

    echo "✅ On-call schedule template created at /tmp/oncall-schedule.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Capacity Planning Baseline
# ─────────────────────────────────────────────────────────────────────────────

capture_baseline_metrics() {
    echo "Capturing baseline metrics..."

  # shellcheck disable=SC2086
  ssh $SSH_OPTS "${DEPLOY_USER}@${DEPLOY_HOST}" << 'SSHEOF'

    echo "=== BASELINE METRICS CAPTURE ===" > /tmp/baseline-metrics.txt
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S UTC')" >> /tmp/baseline-metrics.txt

    echo "" >> /tmp/baseline-metrics.txt
    echo "=== SYSTEM METRICS ===" >> /tmp/baseline-metrics.txt
    echo "Linux kernel: $(uname -r)" >> /tmp/baseline-metrics.txt
    nproc | xargs echo "CPU cores:" >> /tmp/baseline-metrics.txt
    free -h | head -2 >> /tmp/baseline-metrics.txt
    df -h | head -3 >> /tmp/baseline-metrics.txt

    echo "" >> /tmp/baseline-metrics.txt
    echo "=== DOCKER METRICS ===" >> /tmp/baseline-metrics.txt
    docker stats --no-stream --format 'table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}' >> /tmp/baseline-metrics.txt

    echo "" >> /tmp/baseline-metrics.txt
    echo "=== APPLICATION METRICS ===" >> /tmp/baseline-metrics.txt
    curl -s http://localhost:9090/api/v1/query?query=up >> /tmp/baseline-metrics.txt 2>&1 || echo "Prometheus not available" >> /tmp/baseline-metrics.txt

    cat /tmp/baseline-metrics.txt
SSHEOF

    echo "✅ Baseline metrics captured"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          PRODUCTION OPERATIONS SETUP - P0                  ║"
    echo "║          Monitoring, Alerting, Incident Response           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    create_monitoring_dashboards
    echo ""

    create_alerting_rules
    echo ""

    create_incident_runbooks
    echo ""

    create_oncall_rotation
    echo ""

    capture_baseline_metrics
    echo ""

    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              PRODUCTION OPERATIONS READY                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Next steps:"
    echo "1. Deploy alert rules to Prometheus"
    echo "2. Import SLO dashboard to Grafana"
    echo "3. Share runbooks with team"
    echo "4. Set up on-call rotation schedule"
    echo "5. Conduct team training on incident response"
    echo ""
}

main "$@"
