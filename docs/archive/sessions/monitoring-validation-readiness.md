# Monitoring Stack Validation & Operational Readiness
**Date:** May 1, 2026  
**Status:** Monitoring Stack Validation Phase  
**Purpose:** Verify all monitoring components are operational and properly configured

---

## Part 1: Monitoring Stack Inventory

### Core Components

| Component | Container Name | Port | Status | Purpose |
|-----------|----------------|------|--------|---------|
| **Prometheus** | code-server-prometheus | 9090 | Active | Metrics collection & storage |
| **Grafana** | code-server-grafana | 3000 | Active | Metrics visualization & dashboards |
| **Alertmanager** | code-server-alertmanager | 9093 | Active | Alert routing & management |
| **Loki** | code-server-loki | 3100 | Active | Log aggregation |
| **Tempo** | code-server-tempo | 3200 | Active | Distributed tracing |
| **OTEL Collector** | code-server-otel-collector | 4317/14250 | Active | Telemetry collection |

### Init/Setup Containers

| Container | Purpose |
|-----------|---------|
| code-server-prometheus-init | Prometheus config setup |
| code-server-grafana-init | Grafana datasource & dashboard provisioning |
| code-server-alertmanager-init | Alertmanager configuration setup |
| code-server-loki-init | Loki schema & retention setup |

---

## Part 2: Pre-Deployment Validation Checklist

### 2.1 Service Health Check (5 minutes)

```bash
# Run this on the primary host (192.168.168.31)
cd /home/akushnir/code-server

# Check all monitoring services are running
echo "=== Monitoring Services Status ==="
docker compose ps | grep -E "prometheus|grafana|alertmanager|loki|tempo|otel"

# Expected output: All services should show "Up" status
# If any show "Exited" or "Unhealthy", investigate logs
```

**Validation Criteria:**
- ✅ All monitoring containers show "Up"
- ✅ No containers in "Exited" or "Restarting" state
- ✅ Health checks passing (if configured)

### 2.2 Prometheus Health (5 minutes)

```bash
# Test Prometheus connectivity
curl -s http://localhost:9090/-/healthy
# Expected: 200 OK

# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
# Expected: Should show number of active targets (typically 20-30)

# Verify alert rules loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups | length'
# Expected: Should show number of alert rule groups (typically 5-10)
```

**Validation Criteria:**
- ✅ Health endpoint returns 200
- ✅ Active targets >10
- ✅ Alert rule groups >0

### 2.3 Grafana Datasource Check (5 minutes)

```bash
# Test Grafana connectivity
curl -s http://localhost:3000/api/health
# Expected: 200 OK with "ok" status

# List configured datasources
curl -s -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" http://localhost:3000/api/datasources
# Expected: Should show Prometheus, Loki, Tempo datasources

# Test Prometheus datasource
curl -s -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
  http://localhost:3000/api/datasources/proxy/1/api/prom/api/v1/query?query=up
# Expected: Should return query results
```

**Validation Criteria:**
- ✅ Grafana health check returns OK
- ✅ Datasources configured (Prometheus, Loki, Tempo)
- ✅ Datasource queries return results

### 2.4 Alertmanager Configuration (5 minutes)

```bash
# Test Alertmanager connectivity
curl -s http://localhost:9093/-/healthy
# Expected: 200 OK

# Check alert routes
curl -s http://localhost:9093/api/v1/status | jq '.config'
# Expected: Should show Slack webhook URL and routing rules

# Verify no firing alerts (baseline should be clean)
curl -s http://localhost:9093/api/v1/alerts
# Expected: Should return empty array if no alerts
```

**Validation Criteria:**
- ✅ Alertmanager health endpoint returns 200
- ✅ Routes configured correctly
- ✅ No false positive alerts firing

---

## Part 3: Integration Validation Tests

### 3.1 Metric Collection Validation

**Test: Verify metrics are being scraped**

```bash
# Query recent metrics from Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result | length'
# Expected: Should return >10 metrics (all services should report "up" status)

# Check specific service metrics
for service in postgres redis grafana ollama; do
  echo "Checking $service metrics:"
  curl -s "http://localhost:9090/api/v1/query?query=up{job=\"$service\"}" | jq '.data.result[0].value'
done
# Expected: Each should return [timestamp, "1"] indicating service is up
```

**Success Criteria:**
- ✅ Metrics being collected for all configured services
- ✅ Service up/down status metrics present
- ✅ No scrape errors in Prometheus targets page

### 3.2 Alert Rule Validation

**Test: Verify alert rules are loaded and evaluating**

```bash
# Check alert rules are loaded
ALERTS=$(curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules | length')
echo "Total alert rules loaded: $ALERTS"
# Expected: Should be >20 alert rules

# Check for alert evaluation errors
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.state=="error")'
# Expected: Should return empty (no errors)

# Test a specific alert rule (e.g., ServiceDown)
curl -s 'http://localhost:9090/api/v1/query?query=ALERTS{alertname="ServiceDown"}' | jq '.data.result'
# Expected: Should evaluate without error
```

**Success Criteria:**
- ✅ Alert rules loaded successfully
- ✅ No evaluation errors
- ✅ Rules are actively evaluating

### 3.3 Alert Notification Test

**Test: Send test alert to verify notification routing**

```bash
# Method 1: Send test alert via Alertmanager API
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "critical",
      "service": "monitoring"
    },
    "annotations": {
      "summary": "This is a test alert",
      "description": "Monitoring validation test alert"
    }
  }]'

# Expected: Alert should be routed to configured receiver (Slack)
# Check Slack channel for notification within 30 seconds

# Method 2: Verify alert is visible in Alertmanager UI
curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | select(.labels.alertname=="TestAlert")'
# Expected: Should show the test alert
```

**Success Criteria:**
- ✅ Test alert appears in Alertmanager
- ✅ Notification received in configured channel (Slack)
- ✅ Alert transitions to "resolved" after TTL

### 3.4 Dashboard Validation

**Test: Verify dashboards load and display metrics**

```bash
# Get list of dashboards
curl -s -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
  http://localhost:3000/api/search?type=dash-db | jq '.[].title'
# Expected: Should show dashboards like "Overview", "Services", "Database", etc.

# Test loading a dashboard
curl -s -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
  http://localhost:3000/api/dashboards/db/overview | jq '.dashboard.title'
# Expected: Should return dashboard title
```

**Success Criteria:**
- ✅ Dashboards exist and are accessible
- ✅ Dashboard panels load without errors
- ✅ Panels display metrics and graphs

---

## Part 4: Performance & Capacity Testing

### 4.1 Prometheus Storage & Performance

```bash
# Check Prometheus disk usage
docker exec code-server-prometheus \
  sh -c 'du -sh /prometheus && ls -lh /prometheus/wal/'
# Expected: WAL size should be reasonable (<5GB for typical deployments)

# Check Prometheus memory usage
docker stats code-server-prometheus --no-stream | awk '{print $6}'
# Expected: Should be <2GB for typical workload

# Query performance (should return quickly)
time curl -s 'http://localhost:9090/api/v1/query_range?query=rate(http_requests_total[5m])&start=1&end=2&step=1' > /dev/null
# Expected: Query should complete in <1 second
```

**Success Criteria:**
- ✅ Prometheus disk usage reasonable (<10% of available)
- ✅ Memory usage <2GB
- ✅ Query latency <1 second for typical queries

### 4.2 Loki Log Performance

```bash
# Check Loki disk usage
docker exec code-server-loki \
  sh -c 'du -sh /loki && du -sh /loki/chunks'
# Expected: Should be proportional to log volume (typically 100MB-500MB per day)

# Test Loki query
curl -s 'http://localhost:3100/loki/api/v1/query?query={job="docker"}&limit=100' | jq '.data.result | length'
# Expected: Should return logs within reasonable time (<2 seconds)
```

**Success Criteria:**
- ✅ Loki disk usage appropriate for log volume
- ✅ Log queries return within 2 seconds
- ✅ No query errors in logs

---

## Part 5: Alerting Integration Tests

### 5.1 Critical Alert Flow

**Test: Verify critical alerts trigger escalation**

```bash
# Simulate a critical alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "CriticalTest",
      "severity": "critical",
      "service": "test"
    },
    "annotations": {
      "summary": "Critical test alert",
      "description": "This alert should trigger immediate notification"
    }
  }]'

# Verify notification sent to critical receiver (PagerDuty, if configured)
# Check PagerDuty/Slack for immediate notification (group_wait: 0s)
sleep 2
curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | select(.labels.severity=="critical")'

# Expected: Alert should be visible within 2 seconds and notification sent immediately
```

**Success Criteria:**
- ✅ Critical alerts trigger immediately (no grouping delay)
- ✅ Notifications sent to primary receiver
- ✅ Alert remains active until resolved

### 5.2 Warning Alert Flow

**Test: Verify warning alerts are grouped and sent**

```bash
# Simulate multiple warning alerts
for i in {1..3}; do
  curl -X POST http://localhost:9093/api/v1/alerts \
    -H "Content-Type: application/json" \
    -d '[{
      "labels": {
        "alertname": "WarningTest'$i'",
        "severity": "warning",
        "service": "test"
      },
      "annotations": {
        "summary": "Warning test alert #'$i'",
        "description": "Test warning alert"
      }
    }]'
  sleep 1
done

# Check if alerts are grouped
sleep 35  # Wait for group_interval (30s) + buffer
curl -s http://localhost:9093/api/v1/alerts?group_by=alertname | jq '.data | length'
# Expected: Should show grouped alerts notification
```

**Success Criteria:**
- ✅ Multiple warning alerts are grouped together
- ✅ Single notification sent for group (not 3 separate)
- ✅ Grouping respects group_wait (30s)

---

## Part 6: Data Persistence & Recovery

### 6.1 Prometheus Data Persistence

```bash
# Check Prometheus TSDB version
docker exec code-server-prometheus \
  ls -la /prometheus | grep -E "wal|chunks|meta"
# Expected: Should show TSDB directory structure

# Verify metrics are persisted
docker exec code-server-prometheus \
  prometheus-tsutil dump /prometheus | head -20
# Expected: Should show metric samples from recent time period
```

**Success Criteria:**
- ✅ TSDB structure intact
- ✅ Metrics persist across container restarts
- ✅ Data retention matches configuration (typically 15-30 days)

### 6.2 Alert History

```bash
# Check if Alertmanager preserves alert history
docker exec code-server-alertmanager \
  ls -la /alertmanager/data/
# Expected: Should show alert state files

# Verify alerts persist across restarts
curl -s http://localhost:9093/api/v1/alerts?filter=all | jq '.data | length'
# Expected: Should show previous alerts even after restart
```

**Success Criteria:**
- ✅ Alert history preserved
- ✅ Alerts recoverable after restart
- ✅ Silences maintained

---

## Part 7: Operations Monitoring Dashboard

### 7.1 Create Monitoring Health Dashboard

**Dashboard panels to create (via Grafana UI):**

1. **Monitoring Stack Health**
   - Panel 1: Container Status (up/down for each monitoring service)
   - Panel 2: Metrics Scraped (rate of new metrics)
   - Panel 3: Alerts Firing (current firing alerts)

2. **Data Quality Metrics**
   - Panel 4: Scrape Success Rate (% of successful scrapes)
   - Panel 5: Evaluation Latency (alert evaluation time)
   - Panel 6: Query Latency (p50, p95, p99)

3. **System Performance**
   - Panel 7: Prometheus Memory Usage
   - Panel 8: Prometheus Disk Usage
   - Panel 9: Loki Disk Usage

4. **Alert Status**
   - Panel 10: Alerts by Severity (critical, warning, info)
   - Panel 11: Notification Success Rate
   - Panel 12: Mean Time to Detect (MTTD)

---

## Part 8: Operational Checklists

### Daily Monitoring Check (5 minutes)

```
☐ Prometheus healthy: curl http://localhost:9090/-/healthy
☐ Grafana accessible: curl http://localhost:3000/api/health
☐ Alertmanager functional: curl http://localhost:9093/-/healthy
☐ No critical alerts: curl http://localhost:9093/api/v1/alerts | grep critical
☐ Metrics flowing: curl http://localhost:9090/api/v1/targets (all green)
☐ Storage healthy: Docker disk usage <70%
```

### Weekly Monitoring Audit (15 minutes)

```
☐ Review alert rule accuracy (false positives/negatives)
☐ Check data retention (Prometheus: 30 days, Loki: appropriate for log volume)
☐ Verify all dashboards loading correctly
☐ Review Alertmanager routes and receivers
☐ Test notification channels (Slack, PagerDuty, email)
☐ Capacity planning (disk/memory trending)
```

### Monthly Maintenance (30 minutes)

```
☐ Update alert thresholds based on baseline metrics
☐ Add new dashboards for new services
☐ Review and update Prometheus scrape configs
☐ Verify backup of Grafana dashboards
☐ Test disaster recovery (restart all monitoring services)
☐ Performance optimization review
```

---

## Part 9: Troubleshooting Guide

### Problem: Prometheus not scraping metrics

**Diagnosis:**
```bash
# Check Prometheus targets page
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down")'

# Check target health
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {labels, health}'
```

**Solutions:**
1. Verify target service is running: `docker compose ps <service_name>`
2. Check network connectivity: `docker exec code-server-prometheus ping <target>`
3. Verify metrics endpoint: `curl http://<target>:port/metrics`
4. Check Prometheus logs: `docker compose logs prometheus | tail -50`

### Problem: Alerts not firing

**Diagnosis:**
```bash
# Check if alert rules are loaded
curl http://localhost:9090/api/v1/rules | jq '.data.groups[] | .rules[] | select(.name=="AlertName")'

# Check if evaluation has errors
curl http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.rules[].state=="error")'

# Manually evaluate alert expression
curl 'http://localhost:9090/api/v1/query?query=<alert_expression>'
```

**Solutions:**
1. Verify alert rule syntax: `docker exec code-server-prometheus promtool check rules /etc/prometheus/rules`
2. Check if metrics exist for alert: `curl http://localhost:9090/api/v1/query?query=metric_name`
3. Review Prometheus logs: `docker compose logs prometheus | grep -i alert`

### Problem: Notifications not received

**Diagnosis:**
```bash
# Check Alertmanager configuration
docker exec code-server-alertmanager cat /etc/alertmanager/alertmanager.yml

# Test Slack webhook
curl -X POST $SLACK_WEBHOOK_URL \
  -H 'Content-type: application/json' \
  -d '{"text":"Test message"}'

# Check Alertmanager logs
docker compose logs alertmanager | tail -50
```

**Solutions:**
1. Verify Slack webhook URL set: `echo $SLACK_WEBHOOK_URL`
2. Test webhook manually
3. Check Alertmanager receiver configuration
4. Verify route matching: `curl http://localhost:9093/api/v1/status | jq '.config.routes'`

---

## Success Criteria - Full Validation

✅ All monitoring services running and healthy  
✅ Metrics being collected from all configured services  
✅ Alert rules loaded and evaluating without errors  
✅ Test alerts routing to configured receivers  
✅ Grafana dashboards loading and displaying metrics  
✅ Prometheus queries responding within SLA  
✅ Data persistence verified  
✅ Monitoring health dashboards operational  
✅ Operations team trained on monitoring system  
✅ Troubleshooting procedures documented  

**Platform is ready for full operational monitoring.**
