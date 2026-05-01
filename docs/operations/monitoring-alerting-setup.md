# Monitoring & Alerting Setup - Code-Server Platform
**Date:** May 1, 2026  
**Status:** Production Monitoring Configuration  
**Audience:** DevOps, SRE, Monitoring Team

---

## Document Purpose

Complete setup guide for monitoring stack and alerting rules. Includes:
- ✅ Monitoring architecture overview
- ✅ Alert configuration procedures
- ✅ Dashboard setup instructions
- ✅ Custom metric creation
- ✅ Alert routing and escalation
- ✅ Monitoring health checks

---

## Part 1: Monitoring Architecture

### Stack Components

| Component | Purpose | Port | Host |
|-----------|---------|------|------|
| **Prometheus** | Metrics collection | 9090 | Primary (192.168.168.31) |
| **Grafana** | Visualization & dashboards | 3000 | Primary |
| **Loki** | Log aggregation | 3100 | Primary |
| **Tempo** | Distributed tracing | 3200 | Primary |
| **Alertmanager** | Alert routing | 9093 | Primary |
| **OTEL Collector** | Telemetry collection | 4317/14250 | Primary |
| **Node Exporter** | System metrics | 9100 | Both hosts |
| **cAdvisor** | Container metrics | 8080 | Both hosts |

### Data Flow

```
┌─ Services (metrics, logs, traces)
├─ OTEL Collector → Prometheus, Loki, Tempo
├─ Node Exporter → Prometheus
├─ cAdvisor → Prometheus
└─ Prometheus → Grafana (visualization)
      → Alertmanager (alerting)
      → Long-term storage
```

---

## Part 2: Prometheus Configuration

### Scrape Targets

Check current Prometheus config:
```bash
ssh akushnir@192.168.168.31
docker exec prometheus_svc cat /etc/prometheus/prometheus.yml
```

### Adding New Scrape Target

1. **Edit Prometheus config** on primary host:
```bash
ssh akushnir@192.168.168.31
sudo vi /etc/prometheus/prometheus.yml
```

2. **Add new scrape job** under `scrape_configs`:
```yaml
  - job_name: 'my-new-service'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 15s
    scrape_timeout: 10s
```

3. **Reload Prometheus** (no downtime):
```bash
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
# If OK, reload:
docker compose exec prometheus kill -HUP 1
```

4. **Verify** in Prometheus UI (http://localhost:9090):
   - Status → Targets
   - Look for your new job with "UP" status

---

## Part 3: Grafana Dashboard Setup

### Accessing Grafana

```
URL: http://192.168.168.250:3000 (or your external endpoint)
Username: admin
Password: [In Vault or team secret manager]
```

### Pre-Built Dashboards (Already Installed)

| Dashboard | Purpose | Link |
|-----------|---------|------|
| **Code-Server Overview** | Service health overview | Dashboards → Code-Server Overview |
| **Container Metrics** | CPU, memory, disk by container | Dashboards → Docker Containers |
| **Database Performance** | PostgreSQL query performance | Dashboards → PostgreSQL |
| **Network Traffic** | Network I/O by service | Dashboards → Network Traffic |
| **SLO Dashboard** | Service Level Objective tracking | Dashboards → SLO Dashboard |

### Creating a Custom Dashboard

**Example: Create "API Response Time" Dashboard**

1. **Click "+" → "Dashboard" → "Add new panel"**

2. **Configure the panel:**
   - **Title:** "API Response Time (p99)"
   - **Data source:** Prometheus
   - **Metrics query:**
     ```promql
     histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
     ```
   - **Legend:** `{{handler}}`
   - **Unit:** "seconds"
   - **Alert threshold:** >0.2s (yellow), >0.5s (red)

3. **Click "Apply" → "Save"**

4. **Set up alert** (see Alerting section below)

---

## Part 4: Alert Configuration

### Alert Channels Setup

#### Slack Integration (Recommended)

1. **Create Slack incoming webhook:**
   - Slack workspace → Settings → Apps & Integrations
   - Search "Incoming Webhooks"
   - Click "Add New"
   - Choose channel: #code-server-alerts
   - Copy webhook URL

2. **Configure Alertmanager** on primary host:
```bash
ssh akushnir@192.168.168.31
docker compose exec alertmanager vi /etc/alertmanager/alertmanager.yml
```

3. **Add Slack receiver:**
```yaml
receivers:
  - name: 'slack-alerts'
    slack_configs:
      - api_url: '<YOUR_SLACK_WEBHOOK_URL>'
        channel: '#code-server-alerts'
        title: '{{ .Status }} - {{ .GroupLabels.alertname }}'
        text: 'Service: {{ .GroupLabels.instance }} - {{ .CommonAnnotations.description }}'
        send_resolved: true
```

4. **Reload Alertmanager:**
```bash
docker compose exec alertmanager kill -HUP 1
```

#### Email Integration (Alternative)

```yaml
receivers:
  - name: 'email-alerts'
    email_configs:
      - to: 'ops-team@company.com'
        from: 'alertmanager@code-server'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alerts@company.com'
        auth_password: '<EMAIL_PASSWORD>'
        headers:
          Subject: '{{ .Status }} - {{ .GroupLabels.alertname }}'
```

### Pre-Configured Alert Rules

Check existing alerts:
```bash
ssh akushnir@192.168.168.31
docker exec prometheus cat /etc/prometheus/alert_rules.yml | head -50
```

### Creating New Alert Rules

**Example: Alert if API Response Time > 500ms**

1. **Create alert rule file:**
```bash
cat > /tmp/my_alerts.yml << 'EOF'
groups:
  - name: api_performance
    interval: 30s
    rules:
      - alert: APIHighResponseTime
        expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 0.5
        for: 2m
        labels:
          severity: warning
          team: backend
        annotations:
          summary: "API response time too high"
          description: "{{ $value }}s on {{ $labels.instance }}"
          runbook_url: "https://wiki.company.com/runbooks/api-high-latency"
EOF
```

2. **Update Prometheus config** to include this file:
```yaml
rule_files:
  - '/etc/prometheus/alert_rules.yml'
  - '/etc/prometheus/my_alerts.yml'  # Add this
```

3. **Validate and reload:**
```bash
docker compose exec prometheus promtool check rules /etc/prometheus/my_alerts.yml
docker compose exec prometheus kill -HUP 1
```

4. **Verify** in Prometheus UI:
   - Alerts tab → Should see your new alert

---

## Part 5: Critical Alerts (Must Configure)

### Database Health

**Alert: PostgreSQL Down**
```yaml
- alert: PostgreSQLDown
  expr: pg_up == 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "PostgreSQL is down"
    description: "PostgreSQL on {{ $labels.instance }} is not responding"
```

**Alert: Replication Lag > 5s**
```yaml
- alert: PostgreSQLReplicationLag
  expr: pg_replication_lag_seconds > 5
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "PostgreSQL replication lag detected"
    description: "Replication lag: {{ $value }}s on {{ $labels.instance }}"
```

### Service Health

**Alert: Service Down**
```yaml
- alert: ServiceDown
  expr: up == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "{{ $labels.job }} is down"
    description: "{{ $labels.instance }} has been unavailable for 2 minutes"
```

**Alert: High Error Rate**
```yaml
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.01
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High error rate detected"
    description: "Error rate on {{ $labels.instance }}: {{ $value }}%"
```

### Infrastructure Health

**Alert: Disk Space > 80%**
```yaml
- alert: DiskSpaceLow
  expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 20
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Low disk space"
    description: "Available disk on {{ $labels.instance }}: {{ $value }}%"
```

**Alert: Memory Pressure > 85%**
```yaml
- alert: MemoryPressure
  expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High memory usage"
    description: "Memory pressure on {{ $labels.instance }}: {{ $value }}%"
```

---

## Part 6: Custom Metrics

### Adding Application Metrics

Applications can expose metrics at `/metrics` endpoint in Prometheus format.

**Example: Custom metric from Code-Server IDE**
```
# HELP code_server_active_sessions Total active user sessions
# TYPE code_server_active_sessions gauge
code_server_active_sessions 42

# HELP code_server_requests_total Total requests processed
# TYPE code_server_requests_total counter
code_server_requests_total{handler="/api/v1/execute",status="200"} 15923
code_server_requests_total{handler="/api/v1/execute",status="500"} 127
```

### Prometheus Query Examples

```promql
# Current value
code_server_active_sessions

# Rate of increase (per second)
rate(code_server_requests_total[5m])

# Percentage of 5xx errors
sum(rate(code_server_requests_total{status=~"5.."}[5m])) /
sum(rate(code_server_requests_total[5m])) * 100

# Top 5 slowest endpoints (p99)
topk(5, histogram_quantile(0.99, 
  rate(http_request_duration_seconds_bucket[5m])))
```

---

## Part 7: Log Aggregation (Loki)

### Accessing Logs

**In Grafana:**
1. Explore → Data Source: Loki
2. Select log stream: `{job="docker"}`
3. Filter by container: `{container_name="api-gateway"}`
4. View logs

**Via Command Line:**
```bash
ssh akushnir@192.168.168.31
docker compose logs api-gateway --tail 100
```

### Log Query Examples

```logql
# All logs from specific container
{container_name="postgres"}

# Logs with errors
{container_name="api-gateway"} | "error" | "ERROR"

# Logs with specific pattern
{container_name="auth-server"} | "failed login"

# Count logs by level
sum by (level) (rate({job="docker"} [5m]))
```

---

## Part 8: Distributed Tracing (Tempo)

### Accessing Traces

**In Grafana:**
1. Explore → Data Source: Tempo
2. Search for traces by:
   - Service name
   - Trace ID
   - Duration (slow traces)
   - Error status

**Example: Find slow requests**
1. Service name: "api-gateway"
2. Span name: "http.request"
3. Min duration: 0.5s
4. Click "Search"

### Interpreting Traces

Each trace shows:
- Request path through services
- Duration in each service
- Errors or warnings
- Database query times

Use traces to debug:
- Slow transactions
- Service-to-service failures
- Database query bottlenecks
- External API timeouts

---

## Part 9: SLO Tracking

### Service Level Objectives

```yaml
Code-Server Platform SLOs:
  Availability: 99.5% (22h 20m downtime/month)
  Response Time: <200ms p99
  Error Rate: <0.1%
  Database Replication: <1s lag
```

### Tracking SLOs in Grafana

**Dashboard: SLO Dashboard**
Shows:
- Availability status (% uptime)
- Response time distribution
- Error rate trend
- Replication lag
- Burn rate (how fast you're using your error budget)

### Checking SLO Status

```bash
# Command-line check
ssh akushnir@192.168.168.31
bash scripts/ops/track-slo-metrics.sh
```

---

## Part 10: Alerting Rules Best Practices

### Rule Design

**❌ Bad alert:** Too many false positives
```yaml
- alert: HighCPU
  expr: node_cpu_usage_percent > 50
  for: 1m  # Too sensitive
```

**✅ Good alert:** Specific, actionable
```yaml
- alert: PersistentHighCPU
  expr: avg(rate(node_cpu_usage_percent[1m])) > 80
  for: 10m  # Allow temporary spikes
  labels:
    severity: warning
  annotations:
    summary: "High sustained CPU usage"
    runbook_url: "https://wiki/high-cpu-investigation"
```

### Alert Severity Levels

| Severity | Response Time | Action |
|----------|---------------|--------|
| **Critical** | 5 min | Page on-call immediately |
| **Warning** | 15 min | Email to team, investigate |
| **Info** | 1 hour | Log for analysis |

---

## Part 11: Health Checks

### Service Health Endpoint

Each service should expose `/health`:
```bash
curl http://localhost:8080/health
# Response:
{
  "status": "healthy",
  "timestamp": "2026-05-01T10:00:00Z",
  "dependencies": {
    "database": "connected",
    "cache": "connected",
    "messaging": "connected"
  }
}
```

### Liveness & Readiness Probes (K8s)

For Kubernetes deployments (Phase 4+):
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

---

## Part 12: Monitoring Team Responsibilities

### Daily Monitoring Tasks

- [ ] Review alert history for patterns
- [ ] Check SLO status (availability, latency, errors)
- [ ] Verify all data sources connected (Prometheus, Loki, Tempo)
- [ ] Update dashboard with weekly trends

### Weekly Monitoring Tasks

- [ ] Review alert rule accuracy (false positives/negatives)
- [ ] Analyze burned SLO budget
- [ ] Check backup status of metrics
- [ ] Review and update runbook links in alerts

### Monthly Monitoring Tasks

- [ ] Capacity planning (storage, CPU, memory trends)
- [ ] SLO review and adjustment if needed
- [ ] Clean up old dashboards
- [ ] Training review for team members

---

## Part 13: Monitoring Troubleshooting

### "Prometheus is slow"

```bash
# Check disk usage
docker exec prometheus du -sh /prometheus

# Check query load
docker exec prometheus ps aux | grep prometheus

# Increase retention if needed (in prometheus.yml)
# --storage.tsdb.retention.time=90d
```

### "No data in Grafana"

1. Check Prometheus targets: http://localhost:9090/targets
   - All should be "UP"
   - If "DOWN", check service is running: `docker compose ps`
2. Check data is being scraped
   - In Prometheus UI, type metric name, should return data
3. Check Grafana data source connection
   - Configuration → Data Sources → Prometheus
   - Click "Test"

### "Alerts not firing"

```bash
# Check Alertmanager is running
docker compose ps | grep alertmanager

# Check alert rules syntax
docker exec prometheus promtool check rules /etc/prometheus/alert_rules.yml

# Check alert routing config
docker exec alertmanager amtool config routes

# Test alert receiver (Slack, Email, etc.)
# Send test via Alertmanager UI: http://localhost:9093
```

---

## Part 14: Integration Examples

### Alert to Incident Tracker

Example: Create JIRA ticket automatically on critical alert

```yaml
receivers:
  - name: 'jira-incidents'
    webhook_configs:
      - url: 'http://jira.company.com/api/2/issue'
        send_resolved: true
        headers:
          Authorization: 'Bearer <TOKEN>'
        # Custom JSON payload
```

### Alert to On-Call Rotation

Integration with PagerDuty, Opsgenie, etc.

```yaml
receivers:
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<YOUR_SERVICE_KEY>'
        severity: '{{ .GroupLabels.severity }}'
```

---

## Monitoring Success Criteria

✅ All critical services being monitored  
✅ Alerts routing to correct channels (Slack, email, pager)  
✅ Alert rules tested and validated  
✅ SLO dashboard accurate and up-to-date  
✅ Historical data retention sufficient (30+ days)  
✅ Team trained on alert investigation  
✅ Monitoring stack itself monitored (recursive monitoring)  

---

**Next Steps:**
1. Test all alert channels
2. Validate alert rules in staging first
3. Train team on dashboard usage
4. Set up alert runbook links
5. Configure SLO tracking

**Questions?** Refer to Prometheus and Grafana official docs for advanced configurations.
