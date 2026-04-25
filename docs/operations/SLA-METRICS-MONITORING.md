# SLA Metrics & Monitoring Configuration

**Version**: 1.0  
**Date**: April 25, 2026  
**Scope**: Production infrastructure monitoring and SLA compliance  

---

## Table of Contents

1. [SLA Definitions](#sla-definitions)
2. [Prometheus Metrics Configuration](#prometheus-metrics-configuration)
3. [Grafana Dashboards](#grafana-dashboards)
4. [Alerting Rules](#alerting-rules)
5. [SLA Dashboard Queries](#sla-dashboard-queries)

---

## SLA Definitions

### Service Availability

| Service Tier | Availability Target | Monthly Downtime Budget | Response Time P95 |
|--------------|-------------------|------------------------|-------------------|
| Platinum (Critical) | 99.99% | 4m 32s | 50ms |
| Gold (High) | 99.9% | 43m 12s | 100ms |
| Silver (Standard) | 99% | 7h 18m | 200ms |

### Critical Services (Platinum - 99.99%)

- `postgres-db` - Primary database
- `redis-cache` - Session cache
- `api` - Primary API service
- `frontend` - Web UI
- `qdrant` - Vector database

### High-Priority Services (Gold - 99.9%)

- `reputation-engine`
- `execution-scheduler`
- `agent-runtime`
- `paperclip`
- `prometheus`

### Standard Services (Silver - 99%)

- All other services and infrastructure components

---

## Prometheus Metrics Configuration

### Custom Metrics to Track

```yaml
# Custom SLA Metrics Group
sla_metrics:
  - name: "service_uptime"
    description: "Service availability over time"
    type: "gauge"
    labels:
      - service
      - tier

  - name: "service_response_time_ms"
    description: "API response time in milliseconds"
    type: "histogram"
    buckets: [10, 50, 100, 250, 500, 1000]
    labels:
      - service
      - endpoint
      - method

  - name: "service_error_rate"
    description: "Percentage of requests resulting in errors"
    type: "gauge"
    labels:
      - service
      - error_type

  - name: "deployment_success_rate"
    description: "Percentage of successful deployments"
    type: "gauge"

  - name: "database_replication_lag_seconds"
    description: "PostgreSQL replication lag in seconds"
    type: "gauge"
    labels:
      - replica_host

  - name: "cache_hit_ratio"
    description: "Redis cache hit rate"
    type: "gauge"

  - name: "queue_depth"
    description: "Task queue depth"
    type: "gauge"
    labels:
      - queue_name

  - name: "incident_response_time_seconds"
    description: "Time to respond to incidents"
    type: "histogram"
    buckets: [10, 30, 60, 300, 900]
    labels:
      - severity
```

### Alert Evaluation Intervals

```yaml
global:
  scrape_interval: 15s       # Prometheus scrapes metrics every 15 seconds
  evaluation_interval: 30s   # Alert rules evaluated every 30 seconds
  external_labels:
    cluster: "production"
    environment: "prod"

rule_files:
  - "/etc/prometheus/alert-rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "alertmanager:9093"
```

---

## Grafana Dashboards

### Dashboard 1: Service Availability Overview

**Panels**:
1. Service uptime gauge (99.99%, 99.9%, 99%)
2. Availability trend (last 24 hours)
3. Current error rate by service
4. Service status table (green/yellow/red)

**Queries**:

```promql
# Service uptime percentage
(count(up{job="prometheus"} == 1) / count(up{job="prometheus"})) * 100

# Error rate by service
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100

# Response time P95
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### Dashboard 2: Database Performance

**Panels**:
1. Database query latency (P50, P95, P99)
2. Connection pool status
3. Replication lag (primary → replicas)
4. Disk I/O utilization
5. Cache hit ratio

**Queries**:

```promql
# Database latency P95
histogram_quantile(0.95, rate(db_query_duration_seconds_bucket[5m]))

# Replication lag
pg_replication_lag_seconds

# Connection pool utilization
pg_stat_activity_count / pg_max_connections * 100
```

### Dashboard 3: Deployment & Release

**Panels**:
1. Deployment frequency (deploys per week)
2. Deployment success rate
3. Mean time to recovery (MTTR)
4. Lead time for changes
5. Change failure rate

**Queries**:

```promql
# Deployment success rate
increase(deployments_total{status="success"}[1d]) / increase(deployments_total[1d]) * 100

# Mean time to recovery
avg(incident_resolution_time_seconds)

# Lead time for changes
avg(git_commit_to_deploy_seconds)
```

### Dashboard 4: Infrastructure Health

**Panels**:
1. CPU utilization by host
2. Memory usage by container
3. Disk space remaining
4. Network I/O by service
5. Container restart rate

**Queries**:

```promql
# CPU utilization
rate(container_cpu_usage_seconds_total[5m]) * 100

# Memory utilization
container_memory_usage_bytes / container_spec_memory_limit_bytes * 100

# Disk space available
node_filesystem_avail_bytes / node_filesystem_size_bytes * 100
```

---

## Alerting Rules

### Critical Alerts (Page Operations Team Immediately)

```yaml
groups:
  - name: "critical_alerts"
    interval: 30s
    rules:
      # API service down
      - alert: "APIServiceDown"
        expr: "up{job='api'} == 0"
        for: "1m"
        annotations:
          severity: "critical"
          summary: "API service is down"
          description: "API service has been unavailable for >1 minute"

      # Database replication lag
      - alert: "DatabaseReplicationLag"
        expr: "pg_replication_lag_seconds > 60"
        for: "5m"
        annotations:
          severity: "critical"
          summary: "Database replication lag exceeds 60 seconds"

      # Error rate > 5%
      - alert: "HighErrorRate"
        expr: |
          (rate(http_requests_total{status=~"5.."}[5m]) / 
           rate(http_requests_total[5m])) * 100 > 5
        for: "5m"
        annotations:
          severity: "critical"
          summary: "High error rate detected"
```

### High Priority Alerts (Page SRE Team)

```yaml
  - name: "high_priority_alerts"
    interval: 30s
    rules:
      # Response time P95 > 500ms
      - alert: "HighResponseTime"
        expr: |
          histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.5
        for: "10m"
        annotations:
          severity: "high"
          summary: "Response time P95 exceeds 500ms"

      # Disk space < 20%
      - alert: "LowDiskSpace"
        expr: |
          (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 20
        for: "10m"
        annotations:
          severity: "high"
          summary: "Disk space below 20%"

      # Memory usage > 85%
      - alert: "HighMemoryUsage"
        expr: |
          (container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 85
        for: "5m"
        annotations:
          severity: "high"
          summary: "Memory usage exceeds 85%"
```

### Medium Priority Alerts (Create Issues)

```yaml
  - name: "medium_priority_alerts"
    interval: 30s
    rules:
      # Deployment failure
      - alert: "DeploymentFailure"
        expr: |
          increase(deployments_total{status="failure"}[1h]) > 0
        annotations:
          severity: "medium"
          summary: "Deployment failure detected"

      # High queue depth
      - alert: "HighQueueDepth"
        expr: "task_queue_depth > 10000"
        for: "15m"
        annotations:
          severity: "medium"
          summary: "Task queue depth exceeds 10,000 items"
```

---

## SLA Dashboard Queries

### Monthly Availability Calculation

```promql
# Calculate uptime percentage for current month
(1 - (
  increase(up{job="api"}==0[30d]) / 
  (increase(up{job="api"}[30d]) + increase(up{job="api"}==0[30d]))
)) * 100
```

### Service Performance Summary

```promql
# Combined view: availability, response time, error rate
{
  availability: (1 - (increase(errors_total[30d]) / increase(requests_total[30d]))) * 100,
  response_time_p95: histogram_quantile(0.95, rate(request_duration_seconds_bucket[30d])),
  error_rate: (increase(errors_total[30d]) / increase(requests_total[30d])) * 100
}
```

### SLA Compliance Status

```promql
# Green (>99.99%):  >= 99.99%
# Yellow (99.9%):   99% - 99.98%
# Red (<99%):       < 99%

CASE
  WHEN availability >= 99.99 THEN "SLA: Platinum (Green)"
  WHEN availability >= 99.9  THEN "SLA: Gold (Yellow)"
  WHEN availability >= 99    THEN "SLA: Silver (Yellow)"
  ELSE "SLA: Violated (Red)"
END
```

---

## Monitoring Stack Architecture

### Components

1. **Prometheus** (192.168.168.31:9090)
   - Metrics collection and storage
   - Alert rule evaluation
   - 15-day retention by default

2. **Grafana** (192.168.168.31:3000)
   - Visualization and dashboarding
   - SLA tracking
   - Custom alerting UI

3. **AlertManager** (192.168.168.31:9093)
   - Alert routing and deduplication
   - Integration with PagerDuty/Slack
   - Incident escalation

4. **Loki** (192.168.168.31:3100)
   - Log aggregation
   - Log-to-metrics conversion
   - Long-term log retention (30 days)

### Data Retention Policy

| Component | Retention | Sampling | Purpose |
|-----------|-----------|----------|---------|
| Prometheus | 15 days | Real-time | Metrics and alerting |
| Prometheus Archive | 1 year | Daily | Historical analysis |
| Loki | 30 days | All logs | Debugging and auditing |
| Grafana Snapshots | 30 days | N/A | Dashboard history |

---

## Integration with CI/CD

### Deployment Metrics Injection

```bash
# In deployment scripts, export metrics:
curl -X POST http://prometheus:9091/metrics/job/deployment/instance/primary \
  -d "deployment_duration_seconds $DEPLOY_TIME"

curl -X POST http://prometheus:9091/metrics/job/deployment/instance/primary \
  -d "deployment_status{result=\"success\"} 1"
```

### Release Notes Integration

Each deployment should include:
- Deployment timestamp
- Services deployed
- Configuration changes
- Performance impact (if any)

---

## SLA Review Process

### Weekly SLA Review (Every Monday)

1. Check if any alerts were triggered
2. Calculate weekly availability percentage
3. Review error rate trends
4. Identify capacity concerns
5. Document incidents and root causes

### Monthly SLA Review (First Monday of month)

1. Calculate monthly availability percentage
2. Compare against SLA targets
3. Review deployment frequency and success rate
4. Analyze MTTR (mean time to recovery)
5. Create action items for missed targets

### Quarterly SLA Review (Every 13 weeks)

1. Trend analysis (3-month view)
2. SLA target adjustments if needed
3. Infrastructure capacity planning
4. Team performance metrics
5. Stakeholder reporting

---

## Commands for Operations

### View Real-Time Metrics

```bash
# Get current service status
curl http://localhost:9090/api/v1/query?query=up

# Get current error rate
curl http://localhost:9090/api/v1/query?query='rate(errors_total[5m])'

# Get response time P95
curl http://localhost:9090/api/v1/query?query='histogram_quantile(0.95, rate(request_duration_seconds_bucket[5m]))'
```

### Trigger Manual SLA Checks

```bash
# Run Prometheus alerting rules immediately
curl -X POST http://localhost:9090/-/reload

# Export all metrics for analysis
curl http://localhost:9090/api/v1/series?match[]='up' > metrics_export.json
```

---

## Success Criteria

- ✅ All critical services maintain 99.99% uptime
- ✅ P95 response time < 100ms for API endpoints
- ✅ Error rate < 0.1% under normal conditions
- ✅ Mean time to recovery < 15 minutes
- ✅ Deployment success rate > 98%
- ✅ SLA dashboard updated real-time

---

**Status**: READY FOR DEPLOYMENT  
**Last Updated**: April 25, 2026
