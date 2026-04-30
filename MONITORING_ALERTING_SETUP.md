# Monitoring & Alerting Automation Setup Guide

**Created:** April 30, 2026  
**Status:** PHASE 3 - Production Operations  
**Audience:** Operations Team, DevOps Engineers

---

## 1. Executive Summary

This guide establishes comprehensive automated monitoring and alerting for the code-server-enterprise production infrastructure. The system provides real-time visibility into all 28 containerized services across primary (192.168.168.31) and replica (192.168.168.42) hosts.

### Key Capabilities
- **Real-time Metrics Collection:** Prometheus scraping at 15-second intervals from all services
- **Multi-tier Alerting:** Critical (9093), Warning (email), Info (Slack)
- **Health Monitoring:** 50+ alert rules for infrastructure, application, and service health
- **Log Aggregation:** Loki log pipeline with automatic label extraction
- **Distributed Tracing:** Tempo trace collection for request path analysis
- **Alert Relay:** Central webhook processor for alert routing and deduplication

---

## 2. Architecture Overview

### Monitoring Stack Components

```
┌─────────────────────────────────────────────────────────────────┐
│                     OBSERVABILITY STACK                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐         ┌──────────────────┐              │
│  │  Prometheus      │         │   Grafana        │              │
│  │  (v2.48.0)       │────────→│   (v10.2.0)      │              │
│  │  - Metrics       │         │   - Dashboards   │              │
│  │  - Rules Engine  │         │   - Visualization│              │
│  │  - Alert Manager │         │                  │              │
│  └──────────────────┘         └──────────────────┘              │
│         │                             │                          │
│         ├─→ Alert Rules (50+)         └─→ HTTPS:Port 3000       │
│         │                                                        │
│  ┌──────────────────┐         ┌──────────────────┐              │
│  │  AlertManager    │         │   Alert Relay    │              │
│  │  (v0.27.0)       │────────→│   (Microservice) │              │
│  │  - Alert Routing │         │   - Deduplication               │
│  │  - Receivers     │         │   - Enrichment   │              │
│  └──────────────────┘         └──────────────────┘              │
│         │                             │                          │
│         ├─→ Email (ops@kushnir.cloud) ├─→ Slack (#incidents)   │
│         ├─→ Webhooks                  └─→ Custom Integrations   │
│         └─→ PagerDuty (future)                                  │
│                                                                  │
│  ┌──────────────────┐         ┌──────────────────┐              │
│  │  Loki            │         │   Tempo          │              │
│  │  (v2.9.4)        │         │   (v2.4.1)       │              │
│  │  - Log Pipeline  │         │   - Trace Collect│              │
│  │  - Labels        │         │   - Request Path │              │
│  └──────────────────┘         └──────────────────┘              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Services (13 primary + 15 replica)
        │
        ├─→ Prometheus Exporters (metrics)
        │   - Node Exporter: System metrics (CPU, Memory, Disk)
        │   - cAdvisor: Container metrics
        │   - Postgres Exporter: Database metrics
        │   - Redis Exporter: Cache metrics
        │   - Custom exporters: Application metrics
        │
        ├─→ Prometheus (scrape every 15s)
        │   - Time-series database
        │   - Rule evaluation (30s intervals)
        │   - Alert generation
        │
        ├─→ AlertManager
        │   - Route by severity
        │   - Group by service
        │   - Deduplicate
        │
        ├─→ Alert Relay (webhook processor)
        │   - Enrich alerts
        │   - Transform formats
        │   - Route to receivers
        │
        └─→ End Receivers
            - Email: ops@kushnir.cloud (warning/info)
            - Slack: #incidents (info/debug)
            - Webhooks: Custom systems
            - Critical: Alert Relay (9093)

        ├─→ Loki (log collection)
        │   - Scrape logs from services
        │   - Index by labels
        │   - Query via Grafana
        │
        └─→ Tempo (trace collection)
            - Collect distributed traces
            - Correlate with logs/metrics
            - Request flow visualization
```

---

## 3. Service Configuration Details

### 3.1 Prometheus Configuration

**File:** `/config/monitoring/prometheus/prometheus.yml`

**Scrape Targets:**
- Prometheus self (localhost:9090)
- OPA Policy Engine (opa:8181) - 10s interval
- Caddy Gateway (caddy:2019)
- PostgreSQL (localhost:9187 via postgres_exporter)
- Redis (localhost:9121 via redis_exporter)
- Node Exporter (localhost:9100)
- Docker (localhost:9323)
- Redpanda (redpanda:8644)
- Ollama (ollama:11434)
- Qdrant (qdrant:6333)

**Global Settings:**
- Scrape Interval: 15 seconds
- Evaluation Interval: 15 seconds
- External Labels:
  - cluster: kushnir-cloud
  - env: production
  - region: primary

**Alert Routing:**
- AlertManager: localhost:9093
- Alert Rules: `/etc/prometheus/rules/*.yml`

### 3.2 AlertManager Configuration

**File:** `/config/monitoring/alertmanager.yml`

**Alert Routing Hierarchy:**

```
Default Route (30s group_wait, 5m repeat)
├─ Critical Alerts (severity="critical") → webhook:9093
├─ Warning Alerts (severity="warning") → email:ops@kushnir.cloud
├─ Info Alerts (severity="info") → slack:#incidents
└─ System Alerts (DeadMansSwitch, etc.) → webhook:9093
```

**Receivers Configuration:**

| Receiver | Type | Endpoint | Purpose |
|----------|------|----------|---------|
| default-webhook | webhook | alert-relay:8080/api/alerts/default | General alert processing |
| critical-webhook | webhook | alert-relay:8080/api/alerts/critical | Critical incidents |
| warning-email | email | ops@kushnir.cloud | Warning notifications |
| info-slack | slack | #incidents channel | Info/debug alerts |

**Grouping Rules:**
- Group By: alertname, cluster, service, severity
- Group Wait: 30 seconds (batch related alerts)
- Group Interval: 5 minutes (resend grouped alerts)
- Repeat Interval: 4 hours (escalation)

**Inhibition Rules:**
- Critical alerts suppress related warning/info alerts for same service

### 3.3 Prometheus Alert Rules

**File:** `/config/monitoring/alerts/prometheus-rules.yml`

**Alert Categories (50+ rules):**

#### Application Health (10 rules)
- APIHealthCheckFailure - API service down (critical)
- APIHighErrorRate - Error rate >5% (high)
- APIResponseTimeHigh - P95 latency >1s (warning)
- WebUIHealthFailure - Web UI down (critical)
- AuthServiceFailure - Authentication service down (critical)

#### Infrastructure Health (15 rules)
- DatabaseConnectionPoolExhausted - >90% connections (critical)
- DatabaseHighCPUUsage - CPU >80% (high)
- DatabaseReplicationLag - Lag >5min (high)
- ContainerCrashLoop - Service restarting (critical)
- MemoryUsageHigh - RAM >85% (warning)
- DiskSpaceWarning - Disk >80% (warning)
- DiskSpaceExhausted - Disk >95% (critical)

#### Service Availability (12 rules)
- RedisUnavailable - Redis down (critical)
- PostgresUnavailable - PostgreSQL down (critical)
- CadavailableUnavailable - Caddy down (critical)
- PrometheusUnavailable - Prometheus down (critical)
- AlertmanagerUnavailable - AlertManager down (critical)
- LokiUnavailable - Loki down (critical)

#### System-level Rules (8 rules)
- DeadMansSwitch - Heartbeat failure (critical)
- PromtailStopped - Log collector down (high)
- OTelCollectorUnavailable - Trace collector down (high)
- NodeExporterDown - System metrics collector down (warning)

#### Network & Connectivity (5 rules)
- HighNetworkLatency - Latency >100ms (warning)
- HighPacketLoss - >1% packet loss (warning)
- ServiceToServiceLatency - Inter-service latency >500ms (warning)
- ExternalServiceDowntime - External dependency down (critical)

### 3.4 Loki Log Collection

**File:** `/config/monitoring/loki/loki-config.yaml`

**Log Pipeline:**
1. Services emit logs to stdout/stderr
2. Docker driver captures container logs
3. Promtail scrapes logs by label
4. Loki indexes with labels (job, service, instance, level)
5. Grafana queries via LogQL

**Label Strategy:**
- job: Service name (postgres, redis, caddy)
- service: Functional component (database, cache, gateway)
- instance: Container host (primary, replica)
- level: Log severity (info, warning, error)

### 3.5 Tempo Trace Collection

**File:** `/config/monitoring/tempo/tempo-config.yaml`

**Trace Collection:**
- Endpoint: localhost:4317 (OpenTelemetry Protocol)
- Services: Instrument API, UI, backend services
- Trace Retention: 72 hours (configurable)
- Span Sampling: 100% for production
- Backend: S3/local storage

---

## 4. Deployment & Activation

### 4.1 Deploy Monitoring Stack

**Step 1: Verify Compose Configuration**

```bash
docker-compose config | grep -A 5 "prometheus:\|alertmanager:\|grafana:\|loki:\|tempo:"
```

**Step 2: Start Monitoring Services**

```bash
# Deploy monitoring tier
docker-compose up -d prometheus alertmanager grafana loki tempo

# Wait for health checks
sleep 30
docker-compose ps | grep -E "prometheus|alertmanager|grafana|loki|tempo"
```

**Step 3: Deploy Alert Relay Service**

```bash
# Alert Relay startup
docker-compose up -d alert-relay

# Verify webhook endpoint
curl -s http://localhost:8080/health | jq .
```

**Step 4: Verify Prometheus Scrape Targets**

```bash
# Access Prometheus UI on internal port 9090
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels'

# Expected scraped targets: 10+
# All should show state: "up"
```

**Step 5: Initialize Grafana Dashboards**

```bash
# Access Grafana at localhost:3000 (external: kushnir.cloud:443/grafana)
# Default credentials: admin/admin (CHANGE IMMEDIATELY)

# API: Provision Datasources
curl -X POST http://localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
    "access": "proxy",
    "isDefault": true
  }'

# API: Provision Loki Datasource
curl -X POST http://localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Loki",
    "type": "loki",
    "url": "http://loki:3100",
    "access": "proxy"
  }'

# API: Provision Tempo Datasource
curl -X POST http://localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Tempo",
    "type": "tempo",
    "url": "http://tempo:3100",
    "access": "proxy"
  }'
```

### 4.2 Configure Alert Receivers

**Email Configuration (AlertManager):**

```yaml
# Add SMTP credentials to environment
SMTP_HOST: smtp.kushnir.cloud
SMTP_PORT: 587
SMTP_USER: alertmanager@kushnir.cloud
SMTP_PASSWORD: (from secure store)
SMTP_FROM: alertmanager@kushnir.cloud
```

**Slack Integration:**

```yaml
# Add Slack webhook to environment
SLACK_WEBHOOK: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
SLACK_CHANNEL: #incidents
```

**Custom Webhook:**

```bash
# Alert Relay accepts webhooks at:
# POST http://alert-relay:8080/api/alerts/{receiver_name}

# Example webhook payload transformation:
curl -X POST http://localhost:8080/api/alerts/critical \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [
      {
        "status": "firing",
        "labels": {
          "alertname": "DatabaseUnavailable",
          "severity": "critical",
          "service": "postgres"
        },
        "annotations": {
          "summary": "PostgreSQL database is unreachable",
          "description": "Database on primary host (192.168.168.31) not responding"
        }
      }
    ]
  }'
```

---

## 5. Monitoring Dashboards

### 5.1 Pre-configured Dashboard Templates

Create the following Grafana dashboards for comprehensive monitoring:

**Dashboard 1: Infrastructure Overview**
- CPU usage (all hosts)
- Memory usage (all hosts)
- Disk I/O
- Network throughput
- Container count by service

**Dashboard 2: Database Monitoring**
- Connection pool status
- Query performance (p50, p95, p99)
- Transaction rate
- Cache hit ratio
- Replication lag

**Dashboard 3: Service Health**
- Service uptime (each of 28 services)
- Request rate (req/s)
- Error rate (%)
- Response time distribution
- Health check status

**Dashboard 4: Alert Status**
- Active alerts (by severity)
- Alert firing rate (trends)
- Silenced alerts
- Alert frequency (top 10)
- Mean time to resolution (MTTR)

**Dashboard 5: Log Analysis**
- Error log volume (by service)
- Warning log volume
- Application trace correlation
- Log pattern anomalies

### 5.2 Custom Metric Queries

**Service Availability (99.9% SLA):**
```promql
count(up{job!="node"} == 1) / count(up{job!="node"}) * 100
```

**Error Rate (target <0.1%):**
```promql
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100
```

**P95 Latency (target <500ms):**
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

**Database Connection Pool Usage:**
```promql
pg_stat_activity_count / pg_settings_max_connections * 100
```

---

## 6. Alert Response Procedures

### 6.1 Critical Alert Handling (SLA: 5 minutes)

**Step 1: Alert Reception**
- Alert received via webhook
- Alert Relay enriches with context
- Escalation chain notified (email + Slack + PagerDuty)

**Step 2: Initial Assessment**
1. Check alert details in AlertManager UI
2. Verify service status: `docker ps | grep <service>`
3. Review recent logs: Loki query for service
4. Check infrastructure metrics: Grafana dashboard

**Step 3: Incident Response**
1. Page on-call engineer (if not already notified)
2. Create incident ticket (ServiceNow/Jira)
3. Document timeline
4. Begin remediation (see runbook)

**Step 4: Remediation**
- For service restart: `docker-compose restart <service>`
- For resource exhaustion: Scale up, investigate root cause
- For connectivity: Check network, firewall rules
- For data: Verify backups, run integrity checks

**Step 5: Post-Incident**
- Root cause analysis (RCA)
- Preventive measures implementation
- Documentation update
- Team debrief

### 6.2 Warning Alert Handling (SLA: 30 minutes)

**Step 1:** Receive via email (ops@kushnir.cloud)  
**Step 2:** Assess urgency  
**Step 3:** Schedule remediation (within 24 hours)  
**Step 4:** Document trend (for capacity planning)  
**Step 5:** Implement fix proactively

### 6.3 Alert Tuning

**Threshold Adjustments:**

| Alert | Current Threshold | Adjustment Reason |
|-------|-------------------|-------------------|
| HighMemoryUsage | 85% | Lower to 80% if false positives |
| DiskSpace | 80% | Increase to 75% for tighter control |
| APIResponseTime | 1s p95 | Lower to 500ms if capacity allows |
| DatabaseConnections | 90% of max | Lower to 75% for earlier warning |

**Suppression Rules:**

```yaml
# Suppress during maintenance windows
inhibit_rules:
  - source_matchers:
      - alertname = "MaintenanceWindow"
    target_matchers:
      - severity =~ "warning|info"
    equal:
      - cluster
```

---

## 7. Automated Remediation

### 7.1 Self-healing Capabilities

**Automatic Service Restart:**
```bash
# Prometheus rule triggers alert
# Alert Router detects pattern
# Execute remediation action:

docker-compose restart <failing_service>

# Verify recovery:
docker-compose exec <service> healthcheck_command
```

**Automatic Resource Scaling:**
```bash
# Memory threshold exceeded
# Scale replica services to secondary host:

docker-compose up -d --scale <service>=2 <service>
```

**Automatic Failover:**
```bash
# Primary host unreachable
# Activate replica host:

ssh replica-host "docker-compose up -d"
# VIP (192.168.168.30) automatically switches via Keepalived
```

### 7.2 Alert Suppression During Maintenance

```bash
# Create silence in AlertManager
curl -X POST http://localhost:9093/api/v1/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {
        "name": "service",
        "value": "postgres",
        "isRegex": false
      }
    ],
    "startsAt": "2026-04-30T10:00:00Z",
    "endsAt": "2026-04-30T12:00:00Z",
    "createdBy": "ops-team",
    "comment": "Scheduled maintenance window"
  }'
```

---

## 8. Monitoring SLOs & Targets

### 8.1 Service Level Objectives

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Service Availability | 99.9% | <99.5% (4h window) |
| Error Rate | <0.1% | >0.5% (5m window) |
| P95 Latency | <500ms | >1000ms (10m window) |
| MTTR (Mean Time To Resolve) | <30 min | Track trend |
| Mean Time Between Failures | >720 hours | <168 hours (warning) |

### 8.2 Weekly Monitoring Checklist

**Monday-Friday:**
- [ ] Review AlertManager dashboard (active/silenced)
- [ ] Check Prometheus target health (all up)
- [ ] Verify log ingestion rate (no gaps)
- [ ] Monitor SLO achievement (dashboard)

**Weekly (Friday):**
- [ ] Review alert patterns and trends
- [ ] Identify false positives and adjust thresholds
- [ ] Verify backup of Prometheus data
- [ ] Rotation verification for on-call team

**Monthly:**
- [ ] Full alert rule review and update
- [ ] Capacity planning analysis (trends)
- [ ] Disaster recovery drill (failover simulation)
- [ ] Documentation update

---

## 9. Troubleshooting

### 9.1 Prometheus Issues

**Problem:** Targets showing "down"

```bash
# Check service connectivity
docker-compose exec prometheus \
  curl -v http://<service>:<port>/metrics

# Check scrape configuration syntax
docker-compose exec prometheus \
  promtool check config /etc/prometheus/prometheus.yml

# View recent scrape errors
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down")'
```

**Problem:** Alert rules not evaluating

```bash
# Verify rules are loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules'

# Check rule syntax
docker-compose exec prometheus \
  promtool check rules /etc/prometheus/rules/prometheus-rules.yml
```

### 9.2 AlertManager Issues

**Problem:** Alerts not routing to receivers

```bash
# Check AlertManager configuration
docker-compose exec alertmanager \
  amtool config routes

# Test webhook connectivity
curl -X POST http://alert-relay:8080/api/alerts/critical \
  -H "Content-Type: application/json" \
  -d '{"alerts": [{"status": "firing"}]}'

# View recent alerts in AlertManager UI
# Access: http://localhost:9093
```

**Problem:** Email alerts not sending

```bash
# Verify SMTP configuration
echo "SMTP_HOST: $SMTP_HOST, SMTP_PORT: $SMTP_PORT"

# Test SMTP connectivity
docker run --rm \
  -e SMTP_HOST=$SMTP_HOST \
  -e SMTP_PORT=$SMTP_PORT \
  alpine:latest \
  nc -zv $SMTP_HOST $SMTP_PORT
```

### 9.3 Loki Log Issues

**Problem:** Logs not appearing in Loki

```bash
# Check Loki ingestion metrics
curl -s http://localhost:3100/loki/api/v1/query_range \
  -G --data-urlencode 'query={job="prometheus"}' | jq '.data.result'

# Verify Promtail scrape config
docker-compose exec loki \
  curl -s http://localhost:3100/loki/api/v1/services

# Check container logs are being captured
docker logs <container_name> | head -20
```

---

## 10. Next Steps & Future Enhancements

### Phase 3.1 (Complete Now)
- ✅ Deploy monitoring stack (Prometheus, Grafana, Loki, Tempo)
- ✅ Configure alert routing (email, Slack, webhooks)
- ✅ Create initial dashboards
- ✅ Document alert response procedures

### Phase 3.2 (Week 1)
- [ ] Implement PagerDuty integration for critical alerts
- [ ] Set up automated backup of Prometheus data (daily snapshots)
- [ ] Configure custom metrics instrumentation in applications
- [ ] Create alert playbooks for each critical rule

### Phase 3.3 (Week 2)
- [ ] Deploy Alert Relay service (custom webhook processor)
- [ ] Implement alert aggregation and deduplication
- [ ] Set up anomaly detection (ML-based threshold optimization)
- [ ] Create SLO burn-down dashboards

### Phase 3.4 (Week 3+)
- [ ] Implement Jaeger integration (distributed tracing UI)
- [ ] Set up trace-to-logs correlation
- [ ] Configure custom Grafana dashboard templating
- [ ] Establish 24/7 monitoring rotation schedule

---

## 11. Reference Material

### Configuration Files Location
- Prometheus: `config/monitoring/prometheus/prometheus.yml`
- AlertManager: `config/monitoring/alertmanager.yml`
- Alert Rules: `config/monitoring/alerts/prometheus-rules.yml`
- Loki: `config/monitoring/loki/loki-config.yaml`
- Tempo: `config/monitoring/tempo/tempo-config.yaml`

### Service Ports (Internal)
- Prometheus: 9090
- Grafana: 3000
- AlertManager: 9093
- Loki: 3100
- Tempo: 3100
- Alert Relay: 8080

### External Access (via Caddy/HTTPS)
- Grafana: https://kushnir.cloud/grafana
- Prometheus: https://kushnir.cloud/prometheus
- AlertManager: https://kushnir.cloud/alertmanager

### Contact Information
- On-call Team: ops@kushnir.cloud
- Critical Incidents: alerting-critical@kushnir.cloud
- Slack: #incidents channel
- PagerDuty: (future integration)

---

**Document Version:** 1.0  
**Last Updated:** April 30, 2026  
**Next Review:** May 7, 2026  
**Owner:** Operations Team
