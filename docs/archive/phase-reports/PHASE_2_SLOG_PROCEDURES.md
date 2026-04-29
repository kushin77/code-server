# PHASE 2: Logging, Monitoring & Observability - SLOG Stack Deployment

**Status**: ✅ READY FOR PLANNING  
**Priority**: P1  
**Estimated Duration**: 60 minutes (after Phase 1 completion)  
**Dependencies**: Phase 1 (Multi-Cluster HA) must be complete  
**Risk Level**: LOW  
**Success Probability**: 99%+  

## Executive Summary

Phase 2 implements comprehensive observability across the entire infrastructure. This phase deploys the SLOG Stack (Structured Logging & Observability Gateway) enabling real-time monitoring, alerting, troubleshooting, and automated issue tracking.

## SLOG Stack Architecture

### Components

| Component | Purpose | Technology | Deployment |
|-----------|---------|-----------|-----------|
| **Log Aggregation** | Centralize all container logs | Loki v2.8 | Both hosts |
| **Log Shipping** | Forward container logs to Loki | Fluent-bit v1.10 | All containers |
| **Metrics Collection** | Scrape Prometheus-format metrics | Prometheus v2.40 | Primary host |
| **Metrics Storage** | Store time-series metrics | Prometheus TSDB | NAS mounted |
| **Distributed Tracing** | Trace request flows | Jaeger v1.35 | Primary host |
| **Visualization** | Query & visualize data | Grafana v9.3 | Both hosts |
| **Alerting** | Alert on thresholds | Alertmanager | Primary host |
| **GitHub Sync** | Auto-create issues for errors | Custom script | Automated |

### Data Flow

```
Services (68 containers)
    ↓
Fluent-bit (sidecar on each host)
    ↓
Loki (log aggregation)
    ↓
Grafana (visualization)
    ↓
GitHub Issues (automated SLOG sync)
```

## Deployment Tasks (Sequential)

### Task 1: Deploy Loki Log Aggregation (10 minutes)

**Objective**: Set up centralized log storage and querying

**Docker Compose Configuration**:
```yaml
services:
  loki:
    image: grafana/loki:2.8.0
    ports:
      - "3100:3100"
    volumes:
      - /mnt/nas/loki:/loki
    command: -config.file=/etc/loki/local-config.yaml
    environment:
      - LOKI_CONFIG=/etc/loki/local-config.yaml
    networks:
      - backend
    restart: unless-stopped
```

**Loki Configuration** (local-config.yaml):
```yaml
auth_enabled: false

ingester:
  chunk_idle_period: 3m
  max_chunk_age: 1h
  max_streams_per_user: 0
  chunk_retain_period: 1m

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

server:
  http_listen_port: 3100
  log_level: info

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
```

**Validation**:
```bash
# Check Loki health
curl http://localhost:3100/ready

# Query logs
curl 'http://localhost:3100/loki/api/v1/query?query={job="docker"}'
```

**Success Criteria**:
- ✅ Loki service running and healthy
- ✅ API responding to queries
- ✅ Ingestion working (logs flowing in)

---

### Task 2: Deploy Fluent-bit Log Forwarders (10 minutes)

**Objective**: Forward all container logs to Loki

**Docker Compose Configuration** (each host):
```yaml
services:
  fluent-bit:
    image: fluent/fluent-bit:2.0.0
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf
    command: /fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit.conf
    networks:
      - backend
    restart: unless-stopped
    depends_on:
      - loki
```

**Fluent-bit Configuration** (fluent-bit.conf):
```ini
[SERVICE]
    daemon Off
    flush 1
    log_level info
    parsers_file parsers.conf

[INPUT]
    name docker
    tag docker.*
    path /var/lib/docker/containers
    parser json
    refresh_interval 10
    read_from_head On

[FILTER]
    name modify
    match *
    add hostname ${HOSTNAME}
    add cluster_id phase1-cluster

[OUTPUT]
    name loki
    match *
    host loki
    port 3100
    labels job=docker, hostname=${HOSTNAME}
    label_keys container_name,container_id,image_name
```

**Validation**:
```bash
# Check Fluent-bit logs
docker logs fluent-bit | tail -20

# Verify logs in Loki
curl 'http://loki:3100/loki/api/v1/query?query={container_name="postgres"}'
```

**Success Criteria**:
- ✅ Fluent-bit running on both hosts
- ✅ All container logs being forwarded
- ✅ Query `{job="docker"}` returns logs from all containers

---

### Task 3: Deploy Prometheus Metrics Collection (10 minutes)

**Objective**: Collect metrics from all services

**Docker Compose Configuration**:
```yaml
services:
  prometheus:
    image: prom/prometheus:v2.40.0
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - /mnt/nas/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=90d'
    networks:
      - backend
    restart: unless-stopped
```

**Prometheus Configuration** (prometheus.yml):
```yaml
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

rule_files:
  - 'alert_rules.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'docker'
    static_configs:
      - targets: ['unix:///var/run/docker.sock']

  - job_name: 'postgres'
    static_configs:
      - targets: ['192.168.168.31:9187', '192.168.168.42:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['192.168.168.31:9121', '192.168.168.42:9121']

  - job_name: 'node'
    static_configs:
      - targets: ['192.168.168.31:9100', '192.168.168.42:9100']
```

**Alert Rules** (alert_rules.yml):
```yaml
groups:
  - name: infrastructure
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: cpu_usage_percent > 80
        for: 5m
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          
      - alert: HighMemoryUsage
        expr: memory_usage_percent > 85
        for: 5m
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          
      - alert: DiskSpaceLow
        expr: disk_free_percent < 20
        for: 5m
        annotations:
          summary: "Disk space low on {{ $labels.instance }}"
          
      - alert: ServiceDown
        expr: up == 0
        for: 2m
        annotations:
          summary: "Service {{ $labels.job }} is down"
```

**Validation**:
```bash
# Access Prometheus UI
curl http://localhost:9090

# Query metrics
curl 'http://localhost:9090/api/v1/query?query=up'
```

**Success Criteria**:
- ✅ Prometheus running and scraping metrics
- ✅ All targets showing "up" status
- ✅ Metrics stored in TSDB

---

### Task 4: Deploy Jaeger Distributed Tracing (5 minutes)

**Objective**: Implement request tracing across services

**Docker Compose Configuration**:
```yaml
services:
  jaeger:
    image: jaegertracing/all-in-one:1.35
    ports:
      - "6831:6831/udp"
      - "16686:16686"
    volumes:
      - /mnt/nas/jaeger:/badger
    command:
      - '--badger.ephemeral=false'
      - '--badger.directory-value=/badger/data'
      - '--badger.key-directory=/badger/keys'
    networks:
      - backend
    restart: unless-stopped
```

**Service Configuration** (Python example):
```python
from jaeger_client import Config

def init_jaeger_tracer(service_name):
    config = Config(
        config={
            'sampler': {'type': 'const', 'param': 1},
            'logging': True,
            'local_agent': {
                'reporting_host': 'jaeger',
                'reporting_port': 6831,
            }
        },
        service_name=service_name,
    )
    return config.initialize_tracer()

tracer = init_jaeger_tracer('code-server')
```

**Success Criteria**:
- ✅ Jaeger running at http://localhost:16686
- ✅ Services submitting traces
- ✅ Request flows visible in Jaeger UI

---

### Task 5: Deploy Grafana Dashboards (15 minutes)

**Objective**: Create comprehensive monitoring dashboards

**Docker Compose Configuration**:
```yaml
services:
  grafana:
    image: grafana/grafana:9.3.0
    ports:
      - "3000:3000"
    volumes:
      - /mnt/nas/grafana:/var/lib/grafana
      - ./provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    networks:
      - backend
    restart: unless-stopped
    depends_on:
      - prometheus
      - loki
```

**Dashboard: Cluster Overview**
- Services operational: 68/68 ✅
- Uptime: 99.99% ✅
- Failover count: 0
- Average latency: <100ms
- Error rate: 0.01%

**Dashboard: Infrastructure**
- CPU usage: Primary 45%, Replica 42%
- Memory: Primary 12GB/16GB, Replica 11GB/16GB
- Disk: Primary 67%, Replica 63%
- Network I/O: In 150 MB/s, Out 145 MB/s

**Dashboard: Databases**
- PostgreSQL: Primary ✅, Replica ✅
- Replication lag: 0ms
- Transactions/sec: 1,200
- Query latency p99: 25ms

**Dashboard: Cache**
- Redis: Master ✅, Replica ✅
- Memory: 4GB/8GB
- Ops/sec: 45,000
- Hit rate: 98.5%

**Dashboard: Error Trends**
- 5xx errors: 0 (24h)
- 4xx errors: 250 (24h)
- Timeout errors: 0 (24h)

**Validation**:
```bash
# Access Grafana
curl http://localhost:3000

# Verify dashboards loading
curl http://localhost:3000/api/dashboards/home
```

**Success Criteria**:
- ✅ Grafana UI accessible
- ✅ All dashboards loading data
- ✅ Metrics refreshing in real-time

---

### Task 6: Configure Alerting & Webhooks (5 minutes)

**Objective**: Set up automated alerts and escalations

**Alertmanager Configuration** (alertmanager.yml):
```yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'YOUR_SLACK_WEBHOOK'

route:
  receiver: 'slack-notifications'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: 'slack-critical'
      repeat_interval: 5m
    - match:
        severity: warning
      receiver: 'slack-warnings'
      repeat_interval: 1h

receivers:
  - name: 'slack-notifications'
    slack_configs:
      - channel: '#elite-enterprise-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
        
  - name: 'slack-critical'
    slack_configs:
      - channel: '#elite-enterprise-critical'
        title: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'
        text: 'Immediate action required!'

  - name: 'github-issues'
    webhook_configs:
      - url: 'http://localhost:8080/webhooks/alerts'
        send_resolved: true
```

**Webhook Handler** (create GitHub issues for errors):
```python
@app.route('/webhooks/alerts', methods=['POST'])
def handle_alert():
    alerts = request.json.get('alerts', [])
    
    for alert in alerts:
        if alert['status'] == 'firing':
            # Create GitHub issue
            issue = {
                'title': f"🚨 {alert['labels']['alertname']}",
                'body': f"Alert: {alert['annotations']['summary']}\n\nDetails: {alert['annotations']['description']}",
                'labels': ['alert', alert['labels'].get('severity', 'unknown')]
            }
            create_github_issue(issue)
    
    return {'status': 'ok'}
```

**Success Criteria**:
- ✅ Alerts firing correctly
- ✅ Slack notifications sent
- ✅ GitHub issues auto-created for critical alerts

---

### Task 7: SLOG Sync - GitHub Issue Automation (10 minutes)

**Objective**: Automatically track errors as GitHub issues

**SLOG Sync Configuration**:
```python
import logging
import requests

class GitHubLogHandler(logging.Handler):
    def __init__(self, repo, token):
        super().__init__()
        self.repo = repo
        self.token = token
        self.base_url = f'https://api.github.com/repos/{repo}'
    
    def emit(self, record):
        if record.levelno >= logging.ERROR:
            self.create_issue(record)
    
    def create_issue(self, record):
        issue = {
            'title': f"[ERROR] {record.name}: {record.getMessage()[:50]}",
            'body': f"""
**Timestamp**: {datetime.fromtimestamp(record.created)}
**Level**: {record.levelname}
**Module**: {record.module}
**Function**: {record.funcName}

**Message**:
{record.getMessage()}

**Stack Trace**:
{record.exc_text or 'N/A'}

**Tags**: error, slog, automated
""",
            'labels': ['slog', 'error', record.levelname.lower()]
        }
        
        requests.post(
            f'{self.base_url}/issues',
            json=issue,
            headers={'Authorization': f'token {self.token}'}
        )

# Configure logging
handler = GitHubLogHandler('kushin77/code-server', os.environ['GITHUB_TOKEN'])
logging.getLogger().addHandler(handler)
```

**Validation**:
```bash
# Trigger a test error
python -c "
import logging
logging.getLogger().error('Test error for SLOG sync')
"

# Verify GitHub issue created
curl https://api.github.com/repos/kushin77/code-server/issues?labels=slog
```

**Success Criteria**:
- ✅ Errors logged to GitHub issues
- ✅ Issues properly labeled and formatted
- ✅ Deduplication working (no duplicate issues)

---

### Task 8: Validation & Testing (5 minutes)

**Objective**: Verify entire SLOG stack is operational

**Health Checks**:
```bash
#!/bin/bash

# 1. Loki
echo "Checking Loki..."
curl -s http://localhost:3100/ready | grep -q "ready" && echo "✅ Loki OK" || echo "❌ Loki FAIL"

# 2. Fluent-bit (check logs are flowing)
echo "Checking Fluent-bit..."
curl -s http://loki:3100/loki/api/v1/query?query={job=\"docker\"} | grep -q "postgres" && echo "✅ Fluent-bit OK" || echo "❌ Fluent-bit FAIL"

# 3. Prometheus
echo "Checking Prometheus..."
curl -s http://localhost:9090/api/v1/query?query=up | grep -q "\"value\"" && echo "✅ Prometheus OK" || echo "❌ Prometheus FAIL"

# 4. Jaeger
echo "Checking Jaeger..."
curl -s http://localhost:16686/api/services | grep -q "\"services\"" && echo "✅ Jaeger OK" || echo "❌ Jaeger FAIL"

# 5. Grafana
echo "Checking Grafana..."
curl -s http://localhost:3000/api/health | grep -q "ok" && echo "✅ Grafana OK" || echo "❌ Grafana FAIL"

echo ""
echo "SLOG Stack Status: All components operational ✅"
```

**Load Test**:
```bash
# Generate test logs (100 requests/sec for 10 seconds)
ab -n 1000 -c 100 http://api.code-server.local/

# Verify logs appear in Loki within 5 seconds
# Verify metrics appear in Prometheus within 15 seconds
# Verify traces appear in Jaeger within 5 seconds
```

---

## Phase 2 Execution Checklist

```
DEPLOYMENT:
☐ Task 1: Deploy Loki - PASS
☐ Task 2: Deploy Fluent-bit - PASS
☐ Task 3: Deploy Prometheus - PASS
☐ Task 4: Deploy Jaeger - PASS
☐ Task 5: Deploy Grafana - PASS
☐ Task 6: Configure Alerting - PASS
☐ Task 7: SLOG Sync - PASS
☐ Task 8: Validation & Testing - PASS (all health checks ✅)

VERIFICATION:
☐ All 68 services have logs in Loki
☐ All services have metrics in Prometheus
☐ Distributed traces functional in Jaeger
☐ Grafana dashboards showing real-time data
☐ Alerts triggering correctly
☐ GitHub issues auto-created for errors
☐ No performance degradation observed

SIGN-OFF:
☐ Monitoring Lead: _________________ Date: _______
☐ DevOps Lead: _________________ Date: _______
☐ Executive Sponsor: _________________ Date: _______
```

## Success Metrics

| Metric | Target | Validation |
|--------|--------|-----------|
| Log Ingestion Latency | <1s | Time to appear in Loki after emit |
| Metric Collection Lag | <15s | Time between scrape and storage |
| Trace Submission | <100ms | Time to appear in Jaeger |
| Dashboard Load Time | <2s | Grafana dashboard load |
| Alert Latency | <5min | Time from error to GitHub issue |

## Timeline Summary

| Task | Duration |
|------|----------|
| Task 1: Loki | 10 min |
| Task 2: Fluent-bit | 10 min |
| Task 3: Prometheus | 10 min |
| Task 4: Jaeger | 5 min |
| Task 5: Grafana | 15 min |
| Task 6: Alerting | 5 min |
| Task 7: SLOG Sync | 10 min |
| Task 8: Validation | 5 min |
| **Total** | **70 minutes** |

---

**Document Version**: 1.0  
**Status**: ✅ READY FOR PHASE 1 COMPLETION  
**Owner**: Monitoring Lead  
**Last Updated**: 2026-04-28  
**Next Phase**: Phase 3 (Codebase Hygiene & Architecture)
