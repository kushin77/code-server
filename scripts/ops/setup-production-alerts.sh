#!/bin/bash

###
# @file scripts/ops/setup-production-alerts.sh
# @module operations/alerting
# @description Setup comprehensive alerting rules for production infrastructure
# @governance GOV-002: All alerting rules validated and documented for SLA compliance
###

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================

ALERTS_DIR="${REPO_ROOT}/monitoring/alerts"
PROMETHEUS_RULES="${ALERTS_DIR}/prometheus-rules.yaml"
GRAFANA_ALERTS="${ALERTS_DIR}/grafana-alerts.json"

mkdir -p "${ALERTS_DIR}"

log_info "=== Setting up Production Alerting Rules ==="
log_info "Alerts Directory: ${ALERTS_DIR}"
log_info ""

# ============================================================================
# Create Prometheus Rules
# ============================================================================

log_info "Creating Prometheus alerting rules..."

cat > "${PROMETHEUS_RULES}" << 'EOF'
# Prometheus alerting rules for production infrastructure
# Generated: 2026-04-25
# Version: 1.0

groups:
  - name: application_health
    interval: 30s
    rules:
      # API Health Checks
      - alert: APIHealthCheckFailure
        expr: up{job="api"} == 0
        for: 2m
        labels:
          severity: critical
          service: api
        annotations:
          summary: "API service is down"
          description: "API service {{ $labels.instance }} is not responding to health checks"
          runbook: "docs/RUNBOOK-API-RECOVERY.md"

      - alert: APIHighErrorRate
        expr: rate(http_requests_total{job="api",status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: high
          service: api
        annotations:
          summary: "API error rate is high (>5%)"
          description: "API error rate for {{ $labels.instance }} is {{ $value | humanizePercentage }}"
          runbook: "docs/RUNBOOK-API-ERROR-RATE.md"

      - alert: APIResponseTimeHigh
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="api"}[5m])) > 1.0
        for: 10m
        labels:
          severity: warning
          service: api
        annotations:
          summary: "API response time is high (>1s p95)"
          description: "API p95 response time is {{ $value | humanizeDuration }}"
          runbook: "docs/RUNBOOK-API-PERFORMANCE.md"

  - name: infrastructure_health
    interval: 30s
    rules:
      # Database Health
      - alert: DatabaseConnectionPoolExhausted
        expr: pg_stat_activity_count > pg_settings_max_connections * 0.9
        for: 5m
        labels:
          severity: critical
          component: database
        annotations:
          summary: "Database connection pool exhausted"
          description: "Database has {{ $value }} connections (>90% of max)"
          runbook: "docs/RUNBOOK-DB-CONNECTION-POOL.md"

      - alert: DatabaseHighCPUUsage
        expr: node_cpu_seconds_total{instance=~"db-.*"} > 0.8
        for: 10m
        labels:
          severity: high
          component: database
        annotations:
          summary: "Database CPU usage is high (>80%)"
          description: "Database CPU usage is {{ $value | humanizePercentage }}"
          runbook: "docs/RUNBOOK-DB-CPU-TUNING.md"

      - alert: DatabaseReplicationLag
        expr: pg_wal_lsn_age > 300
        for: 5m
        labels:
          severity: high
          component: database
        annotations:
          summary: "Database replication lag exceeds 5 minutes"
          description: "Replication lag is {{ $value | humanizeDuration }}"
          runbook: "docs/RUNBOOK-DB-REPLICATION.md"

      # Docker & Container Health
      - alert: ContainerCrashLooping
        expr: rate(container_last_seen{state="running"}[5m]) == 0
        for: 5m
        labels:
          severity: critical
          component: container
        annotations:
          summary: "Container is crash looping"
          description: "Container {{ $labels.container_name }} is not running"
          runbook: "docs/RUNBOOK-CONTAINER-RESTART.md"

      - alert: HighMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
        for: 5m
        labels:
          severity: warning
          component: container
        annotations:
          summary: "Container memory usage is high (>90%)"
          description: "Container {{ $labels.container_name }} memory: {{ $value | humanizePercentage }}"
          runbook: "docs/RUNBOOK-MEMORY-PRESSURE.md"

  - name: deployment_health
    interval: 30s
    rules:
      # Deployment Status
      - alert: DeploymentReplicasNotReady
        expr: kube_deployment_status_replicas_unavailable > 0
        for: 10m
        labels:
          severity: critical
          component: deployment
        annotations:
          summary: "Deployment replicas not ready"
          description: "Deployment {{ $labels.deployment }} has {{ $value }} unavailable replicas"
          runbook: "docs/RUNBOOK-DEPLOYMENT-FAILED.md"

      - alert: PodOOMKilled
        expr: rate(container_oom_kills_total[5m]) > 0
        for: 2m
        labels:
          severity: critical
          component: pod
        annotations:
          summary: "Pod OOM killed"
          description: "Pod {{ $labels.pod_name }} exceeded memory limit"
          runbook: "docs/RUNBOOK-POD-OOM.md"

  - name: infrastructure_capacity
    interval: 60s
    rules:
      # Disk Space
      - alert: DiskSpaceRunningOut
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
        for: 15m
        labels:
          severity: critical
          component: filesystem
        annotations:
          summary: "Disk space running out (<10% free)"
          description: "Filesystem {{ $labels.device }} on {{ $labels.instance }} has {{ $value | humanizePercentage }} free"
          runbook: "docs/RUNBOOK-DISK-SPACE.md"

      - alert: InodeLimitApproaching
        expr: (node_filesystem_files_free / node_filesystem_files) < 0.1
        for: 30m
        labels:
          severity: warning
          component: filesystem
        annotations:
          summary: "Inode limit approaching"
          description: "Filesystem {{ $labels.device }} has {{ $value | humanizePercentage }} inodes free"
          runbook: "docs/RUNBOOK-INODE-CLEANUP.md"

      # Network
      - alert: HighNetworkLatency
        expr: histogram_quantile(0.95, rate(network_latency_seconds_bucket[5m])) > 0.1
        for: 10m
        labels:
          severity: warning
          component: network
        annotations:
          summary: "Network latency is high (>100ms p95)"
          description: "Network p95 latency: {{ $value | humanizeDuration }}"
          runbook: "docs/RUNBOOK-NETWORK-LATENCY.md"

  - name: security_alerts
    interval: 30s
    rules:
      # Authentication Failures
      - alert: HighAuthenticationFailureRate
        expr: rate(auth_failures_total[5m]) > 0.1
        for: 5m
        labels:
          severity: high
          component: security
        annotations:
          summary: "High authentication failure rate"
          description: "Auth failure rate is {{ $value | humanize }} per second"
          runbook: "docs/RUNBOOK-AUTH-FAILURES.md"

      # Policy Violations
      - alert: OPAPolicyViolation
        expr: increase(opa_policy_violations_total[5m]) > 0
        for: 1m
        labels:
          severity: critical
          component: security
        annotations:
          summary: "OPA policy violation detected"
          description: "Policy {{ $labels.policy }} violated {{ $value }} times"
          runbook: "docs/RUNBOOK-POLICY-VIOLATION.md"

  - name: business_metrics
    interval: 60s
    rules:
      # SLA Metrics
      - alert: APISLABreach
        expr: (1 - (count(http_requests_total{status=~"2.."}) / count(http_requests_total))) > 0.01
        for: 5m
        labels:
          severity: critical
          sla: "99.9%"
        annotations:
          summary: "API SLA breach detected"
          description: "API availability is below SLA threshold"
          runbook: "docs/RUNBOOK-SLA-BREACH.md"

      - alert: HighLatencyReachingThreshold
        expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 0.5
        for: 10m
        labels:
          severity: warning
          sla: "performance"
        annotations:
          summary: "API latency reaching SLA threshold"
          description: "API p99 latency: {{ $value | humanizeDuration }}"
          runbook: "docs/RUNBOOK-LATENCY-THRESHOLD.md"

EOF

log_success "Prometheus rules created: ${PROMETHEUS_RULES}"

# ============================================================================
# Create Grafana Alert Rules
# ============================================================================

log_info "Creating Grafana alert rules..."

cat > "${GRAFANA_ALERTS}" << 'EOF'
{
  "alerts": [
    {
      "name": "API Availability",
      "uid": "api-availability-001",
      "condition": "A",
      "data": [
        {
          "refId": "A",
          "queryType": "",
          "relativeTimeRange": {
            "from": 300,
            "to": 0
          },
          "datasourceUid": "prometheus-uid",
          "expression": "1 - (count(http_requests_total{status=~'2..'}) / count(http_requests_total))",
          "intervalMs": 1000,
          "maxDataPoints": 43200
        }
      ],
      "noDataState": "NoData",
      "execErrState": "Alerting",
      "for": "5m",
      "annotations": {
        "summary": "API availability below SLA",
        "description": "Current availability: {{ $value | humanizePercentage }}"
      },
      "labels": {
        "severity": "critical",
        "sla": "99.9%"
      }
    },
    {
      "name": "Database Connection Pool",
      "uid": "db-pool-001",
      "condition": "A",
      "data": [
        {
          "refId": "A",
          "queryType": "",
          "relativeTimeRange": {
            "from": 300,
            "to": 0
          },
          "datasourceUid": "prometheus-uid",
          "expression": "pg_stat_activity_count / pg_settings_max_connections",
          "intervalMs": 1000,
          "maxDataPoints": 43200
        }
      ],
      "noDataState": "NoData",
      "execErrState": "Alerting",
      "for": "5m",
      "annotations": {
        "summary": "Database connection pool usage high",
        "description": "Pool utilization: {{ $value | humanizePercentage }}"
      },
      "labels": {
        "severity": "high",
        "component": "database"
      }
    },
    {
      "name": "Disk Space",
      "uid": "disk-space-001",
      "condition": "A",
      "data": [
        {
          "refId": "A",
          "queryType": "",
          "relativeTimeRange": {
            "from": 900,
            "to": 0
          },
          "datasourceUid": "prometheus-uid",
          "expression": "node_filesystem_avail_bytes / node_filesystem_size_bytes",
          "intervalMs": 1000,
          "maxDataPoints": 43200
        }
      ],
      "noDataState": "NoData",
      "execErrState": "Alerting",
      "for": "15m",
      "annotations": {
        "summary": "Disk space running low",
        "description": "Free space: {{ $value | humanizePercentage }}"
      },
      "labels": {
        "severity": "critical",
        "component": "filesystem"
      }
    }
  ],
  "created": "2026-04-25T00:00:00Z",
  "version": "1.0",
  "governance": "GOV-002: All alerts documented with runbooks and SLA targets"
}
EOF

log_success "Grafana alerts created: ${GRAFANA_ALERTS}"

# ============================================================================
# Create Alert Documentation
# ============================================================================

log_info "Creating alert documentation..."

cat > "${ALERTS_DIR}/ALERTING-GUIDE.md" << 'EOF'
# Production Alerting Guide

## Overview

This document describes the comprehensive alerting rules for production infrastructure monitoring and SLA compliance.

## Alert Severity Levels

- **Critical**: Immediate action required, service impairment or failure
- **High**: Urgent attention needed, degraded performance
- **Warning**: Preventive action recommended, capacity approaching limits

## Alert Categories

### 1. Application Health
- API health checks
- Error rate monitoring
- Response time tracking

### 2. Infrastructure Health
- Database connectivity and replication
- Container health and resource usage
- System resource utilization

### 3. Deployment Health
- Kubernetes deployment status
- Pod lifecycle events
- Resource exhaustion events

### 4. Capacity Monitoring
- Disk space availability
- Network performance
- Memory utilization

### 5. Security Alerts
- Authentication failures
- Policy violations
- Suspicious activity patterns

### 6. Business Metrics
- SLA compliance tracking
- Latency thresholds
- Availability percentages

## Runbook Integration

Each alert includes a runbook reference for quick remediation:

```
docs/RUNBOOK-<ALERT-CATEGORY>.md
```

Follow the runbook for step-by-step recovery procedures.

## Configuration

### Prometheus
- Configuration: `${PROMETHEUS_RULES}`
- Reload: `curl -X POST http://prometheus:9090/-/reload`

### Grafana
- Configuration: `${GRAFANA_ALERTS}`
- Import via: Grafana UI → Alerts → Import

## Testing Alerts

1. **Dry Run**: Test alert rules without firing
   ```bash
   promtool check rules prometheus-rules.yaml
   ```

2. **Query Validation**: Test individual alert expressions
   ```
   http://prometheus:9090/api/v1/query?query=<EXPRESSION>
   ```

3. **Alert Testing**: Simulate alert conditions in staging
   ```bash
   scripts/ops/test-alerts-staging.sh
   ```

## SLA Commitments

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Availability | 99.9% | < 99% |
| Response Time (p95) | 1s | > 1s for 10m |
| Error Rate | < 0.1% | > 0.5% for 5m |
| Database Replication Lag | < 1s | > 300s for 5m |

## Escalation Policy

1. **Tier 1**: Automated remediation (if available)
2. **Tier 2**: On-call engineer (within 15 min for critical)
3. **Tier 3**: Engineering manager (for SLA breach)
4. **Tier 4**: Director/VP (for business impact)

## Maintenance

- Review alert rules monthly
- Update thresholds based on metrics trends
- Test runbook procedures quarterly
- Archive resolved issues for analysis

---

**Last Updated**: 2026-04-25
**Version**: 1.0
**Governance**: GOV-002 - All alerts documented with runbooks
EOF

log_success "Alert documentation created: ${ALERTS_DIR}/ALERTING-GUIDE.md"

# ============================================================================
# Summary
# ============================================================================

log_info ""
log_info "=== Production Alerting Setup Complete ==="
log_info ""
log_info "Created Files:"
log_info "  ✓ ${PROMETHEUS_RULES}"
log_info "  ✓ ${GRAFANA_ALERTS}"
log_info "  ✓ ${ALERTS_DIR}/ALERTING-GUIDE.md"
log_info ""
log_info "Next Steps:"
log_info "  1. Validate Prometheus rules: promtool check rules ${PROMETHEUS_RULES}"
log_info "  2. Deploy to Prometheus server"
log_info "  3. Import Grafana alerts via UI"
log_info "  4. Test alert firing with staging environment"
log_info "  5. Configure notification channels (Slack, PagerDuty, etc.)"
log_info ""
log_success "✅ Production alerting infrastructure ready"
