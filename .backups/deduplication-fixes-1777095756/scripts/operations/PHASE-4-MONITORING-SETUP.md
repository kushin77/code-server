# Phase 4: Resource Limits Monitoring & Alerting Setup

**Date**: April 26, 2026  
**Phase**: 4 of 4 (FINAL)  
**Duration**: 1-2 hours  
**Effort Level**: Low (configuration-driven)  
**Risk Level**: Minimal (observability only, no production changes)  

---

## Overview

Phase 4 sets up comprehensive monitoring and alerting for resource limits. After completion, the system will:
- Track resource usage in real-time
- Alert on approaching limits
- Generate dashboards for visualization
- Enable proactive capacity planning

---

## Component 1: Prometheus Alert Rules (30 minutes)

### Objective
Define alert rules to trigger notifications when services approach or exceed resource limits.

### Alert Rule Configuration

Create file: `monitoring/prometheus-alerts-resource-limits.yml`

```yaml
groups:
  - name: ResourceLimits
    interval: 30s
    rules:
      # Memory Alerts
      - alert: MemoryUsageHigh
        expr: >
          (container_memory_usage_bytes / container_memory_limit_bytes) > 0.80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.container_name }}"
          description: "{{ $labels.container_name }} memory usage is {{ $value | humanizePercentage }}"

      - alert: MemoryUsageCritical
        expr: >
          (container_memory_usage_bytes / container_memory_limit_bytes) > 0.95
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Critical memory usage on {{ $labels.container_name }}"
          description: "{{ $labels.container_name }} memory usage is {{ $value | humanizePercentage }}"

      # CPU Alerts
      - alert: CPUThrottling
        expr: >
          rate(container_cpu_cfs_throttled_cpu_usage_seconds_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CPU throttling detected on {{ $labels.container_name }}"
          description: "{{ $labels.container_name }} is being throttled by CPU limits"

      - alert: CPUUsageHigh
        expr: >
          (rate(container_cpu_usage_seconds_total[5m]) / 1) > 3.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.container_name }}"
          description: "{{ $labels.container_name }} CPU usage is {{ $value | humanize }}"

      # OOMKilled Prevention
      - alert: OOMKilledRisk
        expr: >
          (container_memory_usage_bytes / container_memory_limit_bytes) > 0.85
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Risk of OOMKilled: {{ $labels.container_name }}"
          description: "Container {{ $labels.container_name }} approaching OOMKilled threshold"

      # Service Restart Alert
      - alert: ServiceRestartDetected
        expr: >
          rate(container_started_count[5m]) > 0
        labels:
          severity: warning
        annotations:
          summary: "Service restart detected: {{ $labels.container_name }}"
          description: "{{ $labels.container_name }} has been restarted"
```

### Implementation Steps

```bash
# 1. Copy alert rules to Prometheus config directory
cp monitoring/prometheus-alerts-resource-limits.yml /etc/prometheus/rules/

# 2. Reload Prometheus
curl -X POST http://prometheus:9090/-/reload

# 3. Verify rules loaded
curl http://prometheus:9090/api/v1/rules | jq '.data.groups[] | select(.name=="ResourceLimits")'

# Expected: 5 alert rules shown
```

---

## Component 2: Grafana Dashboard Configuration (30 minutes)

### Objective
Create Grafana dashboard for real-time visualization of resource usage and limits.

### Dashboard: Resource Limits Overview

Create file: `monitoring/grafana-dashboards-resource-limits.json`

```json
{
  "dashboard": {
    "title": "Resource Limits - Overview",
    "panels": [
      {
        "title": "Memory Usage vs Limits",
        "targets": [
          {
            "expr": "container_memory_usage_bytes / container_memory_limit_bytes",
            "legendFormat": "{{ container_name }} usage"
          }
        ],
        "type": "graph",
        "yaxes": [{"format": "percentunit", "min": 0, "max": 1}]
      },
      {
        "title": "CPU Throttling Time",
        "targets": [
          {
            "expr": "rate(container_cpu_cfs_throttled_cpu_usage_seconds_total[5m])",
            "legendFormat": "{{ container_name }} throttle time"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Memory Limit Utilization",
        "targets": [
          {
            "expr": "container_memory_limit_bytes / node_memory_MemTotal_bytes",
            "legendFormat": "{{ container_name }} limit %"
          }
        ],
        "type": "gauge"
      },
      {
        "title": "Service Restart Count",
        "targets": [
          {
            "expr": "container_started_count",
            "legendFormat": "{{ container_name }} restarts"
          }
        ],
        "type": "stat"
      }
    ]
  }
}
```

### Implementation Steps

```bash
# 1. Create dashboard via Grafana API
curl -X POST http://grafana:3000/api/dashboards/db \
  -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @monitoring/grafana-dashboards-resource-limits.json

# 2. Verify dashboard created
curl http://grafana:3000/api/dashboards/uid/resource-limits-overview

# Expected: Dashboard accessible at http://grafana:3000/d/resource-limits-overview
```

### Dashboard Panels

**Panel 1: Memory Pressure Indicator**
- Query: `(container_memory_usage_bytes / container_memory_limit_bytes) * 100`
- Visualization: Gauge with thresholds (green <70%, yellow 70-90%, red >90%)
- Services: All 20

**Panel 2: CPU Throttle Activity**
- Query: `rate(container_cpu_cfs_throttled_cpu_usage_seconds_total[5m])`
- Visualization: Time series graph
- Threshold line at 0.05 (5%)

**Panel 3: Memory Limit Utilization Over Time**
- Query: `container_memory_usage_bytes`
- Visualization: Time series, stacked
- Range: Last 24 hours

**Panel 4: Service Stability (Restart Count)**
- Query: `container_started_count`
- Visualization: Stat panel
- Alert: Red if > 0 restarts

---

## Component 3: Alertmanager Configuration (20 minutes)

### Objective
Route alerts to appropriate notification channels (email, Slack, PagerDuty, etc.)

### Alertmanager Config

Create file: `monitoring/alertmanager-config.yml`

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: 'critical-alerts'
      continue: true

    - match:
        severity: warning
      receiver: 'warning-alerts'

receivers:
  - name: 'default'
    slack_configs:
      - channel: '#alerts-monitoring'
        title: 'Resource Limit Alert'
        text: '{{ .GroupLabels.alertname }}: {{ .GroupLabels.service }}'

  - name: 'critical-alerts'
    slack_configs:
      - channel: '#critical-alerts'
        title: '🚨 CRITICAL: Resource Limit'
        text: 'Service: {{ .GroupLabels.service }}\nAlerts: {{ .Alerts.Firing | len }} firing'
    email_configs:
      - to: 'ops-team@company.com'
        from: 'alertmanager@company.com'
        smarthost: 'smtp.gmail.com:587'

  - name: 'warning-alerts'
    slack_configs:
      - channel: '#alerts-monitoring'
        title: '⚠️ WARNING: Resource Limit'
        text: 'Service: {{ .GroupLabels.service }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'service']
```

### Implementation Steps

```bash
# 1. Update alertmanager config
cp monitoring/alertmanager-config.yml /etc/alertmanager/config.yml

# 2. Reload alertmanager
curl -X POST http://alertmanager:9093/-/reload

# 3. Verify configuration
curl http://alertmanager:9093/api/v1/status

# Expected: 2 receivers configured (default + critical)
```

---

## Component 4: Loki Log Collection (10 minutes)

### Objective
Aggregate and query resource-related logs for troubleshooting.

### Loki Query Examples

```bash
# Query OOMKilled events
{container_name=~".*"} |= "OOMKilled"

# Query CPU throttle warnings
{container_name=~".*"} |= "throttle"

# Query memory pressure logs
{container_name=~".*"} |= "memory"

# Recent service startup logs
{container_name=~".*"} |= "started" | first_over_time(5m)
```

### Implementation Steps

```bash
# 1. Verify Loki is receiving logs from Promtail
curl -X GET http://loki:3100/loki/api/v1/label/__name__/values

# 2. Test log query
curl -X GET 'http://loki:3100/loki/api/v1/query_range?query={container_name=~".*"}&start=1h ago&end=now'

# 3. Create saved queries in Grafana
# Via GUI: Explore → Loki → Save
```

---

## Component 5: Monitoring Validation (10 minutes)

### Objective
Verify all monitoring components are working correctly.

### Validation Checklist

```bash
# 1. Verify Prometheus alert rules loaded
curl -s http://prometheus:9090/api/v1/rules | jq '.data.groups[] | .name' | grep -i resource

# Expected: "ResourceLimits" group shown

# 2. Verify Alertmanager receivers
curl -s http://alertmanager:9093/api/v1/status | jq '.config.receivers[]?.name'

# Expected: "default", "critical-alerts", "warning-alerts"

# 3. Verify Grafana dashboard accessible
curl -s http://grafana:3000/api/dashboards/uid/resource-limits-overview | jq '.dashboard.title'

# Expected: "Resource Limits - Overview"

# 4. Verify Loki receiving logs
curl -s http://loki:3100/loki/api/v1/label/__name__/values | jq '.data | length'

# Expected: >0 (metric names collected)

# 5. Test alert firing
# Trigger memory pressure alert
docker-compose exec postgres psql -U postgres << 'EOF'
CREATE TEMP TABLE stress AS SELECT generate_series(1, 100000000);
EOF

# Check for alert in Prometheus
curl -s http://prometheus:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="MemoryUsageHigh")'

# Expected: Alert shown with warning/critical status
```

---

## Component 6: Documentation & Knowledge Transfer (10 minutes)

### Runbooks Created

**1. Resource Limit Alert Response Runbook**

```markdown
## Alert: MemoryUsageHigh

### Description
Container memory usage is >80% of allocated limit.

### Action Items
1. Check service logs: `docker-compose logs <service> --tail 50`
2. Identify memory leak or increased load
3. Options:
   a) If temporary spike: Monitor and allow to resolve
   b) If sustained: Increase memory limit in Phase 2
   c) If code issue: Create bug ticket and prioritize fix

### Escalation
- If >95% for >5 minutes: CRITICAL alert fires
- Page on-call engineer immediately
```

**2. Resource Limit Tuning Runbook**

```markdown
## Procedure: Adjust Resource Limits

### Pre-check
1. Verify current limits: `docker inspect <container> | jq '.HostConfig.Memory'`
2. Check historical usage: Query Grafana dashboard

### Update Limits
1. Edit docker-compose.yml
2. Update resources.limits.memory or resources.limits.cpus
3. Restart service: `docker-compose up -d <service>`
4. Monitor for 30 minutes

### Validation
1. Verify service healthy: `docker-compose ps <service>`
2. Check no OOMKilled events: `docker events --filter 'status=oom'`
3. Performance acceptable: Run baseline tests
```

---

## Phase 4 Completion Checklist

- [ ] Prometheus alert rules created (5+ rules)
- [ ] Alert rules loaded and active
- [ ] Grafana dashboard created with 4 panels
- [ ] Dashboard accessible and displaying metrics
- [ ] Alertmanager routes configured
- [ ] Slack/email notification tested
- [ ] Loki log collection verified
- [ ] Test alert successfully fired and notified
- [ ] Runbooks created and documented
- [ ] Monitoring team trained
- [ ] Compliance score: 90/100 (maximum)
- [ ] Ready for Q3 Phase 4 (Kubernetes migration)

---

## Expected Outcomes

✅ **After Phase 4** (FINAL):
- Comprehensive monitoring system in place
- Real-time dashboards for all 20 services
- Automated alerts for resource issues
- Notification channels configured (Slack, email)
- Runbooks for common issues
- Compliance Score: 90/100 (+30 points from start)
- Q3 Readiness: 100% ✅ COMPLETE

---

## Verification Commands

```bash
# Verify all components running
docker-compose ps | grep -E 'prometheus|alertmanager|grafana|loki|promtail'

# Verify metrics data flowing
curl -s http://prometheus:9090/api/v1/query?query=container_memory_limit_bytes | jq '.data.result | length'

# Test dashboard
curl -s http://grafana:3000/api/dashboards/uid/resource-limits-overview | jq '.dashboard.title'

# List active alerts
curl -s http://prometheus:9090/api/v1/alerts | jq '.data.alerts | length'

# Verify logs being collected
curl -s http://loki:3100/loki/api/v1/label/__name__/values | jq '.data | length'
```

---

## Execution Timeline

**Phase 4 Start**: After Phase 3 completion  
**Prometheus Rules**: 30 minutes  
**Grafana Dashboard**: 30 minutes  
**Alertmanager Config**: 20 minutes  
**Loki Validation**: 10 minutes  
**Documentation**: 10 minutes  
**Total**: 1-2 hours  

**Expected Completion**: +1-2 hours from start

---

## Post-Phase 4 Steps

✅ **Resource Limits Implementation COMPLETE**

### Next Work (Q3 Phase 4):
- Kubernetes Migration (60-80 hours, now unblocked)
- Scale to multi-region deployment
- Horizontal pod autoscaling configuration

### Compliance Achievement:
- **Before Resource Limits**: 60/100
- **After Resource Limits**: 90/100 (+30 points)
- **Target for Q3**: 95%+

---

**Phase 4 Status**: Ready to Execute (after Phase 3)
**Overall Program**: ✅ READY FOR COMPLETION

