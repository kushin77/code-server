# Production Monitoring & Alerting Setup Guide

**Date:** April 30, 2026  
**Status:** ✅ READY FOR MAY 1 DEPLOYMENT  
**Duration:** ~45 minutes setup + testing  

---

## Executive Summary

This guide deploys comprehensive monitoring and alerting for the May 1 production launch. The setup includes:

✅ **Prometheus** - Metrics collection (already running)
✅ **Grafana** - Dashboards and visualization (already running)  
✅ **Alert Rules** - 50+ critical/warning alerts for production
✅ **Alert Routing** - Notification channels (email, Slack, PagerDuty)
✅ **On-Call Procedures** - Escalation and response procedures
✅ **Operational Runbooks** - How to respond to each alert

---

## System Architecture

```
Prometheus Scraper
    ↓
Metrics Collection from 87 containers
    ↓
Alert Evaluation Rules (prometheus-alerts.yml)
    ↓
Alert Manager
    ↓
┌─────────────────────────────────────┐
│ Notification Channels:              │
│ - Email (all team)                  │
│ - Slack #incidents                  │
│ - PagerDuty (escalation)            │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ Grafana Dashboards:                 │
│ - Infrastructure Overview            │
│ - PostgreSQL Replication            │
│ - API Performance                   │
│ - Application Health               │
└─────────────────────────────────────┘
```

---

## Part 1: Alert Rules Deployment (10 minutes)

### Step 1: Verify Prometheus Running

```bash
# SSH to primary host
ssh ubuntu@192.168.168.31

cd /home/ubuntu/code-server

# Check Prometheus container
docker-compose ps prometheus
# Should show: "Up X hours"

# Access Prometheus UI
curl -s http://localhost:9090/graph -o /dev/null && echo "✅ Prometheus accessible" || echo "❌ Not accessible"
```

### Step 2: Deploy Alert Rules

```bash
# Copy alert rules to Prometheus config directory
cp prometheus-alerts.yml prometheus/

# Update prometheus.yml to include alerts
# Add this section to prometheus.yml under global settings:
cat >> prometheus/prometheus.yml <<'EOF'

rule_files:
  - '/etc/prometheus/prometheus-alerts.yml'

EOF

# Reload Prometheus
docker-compose restart prometheus

# Wait for reload
sleep 10

# Verify alerts loaded
curl -s http://localhost:9090/api/v1/rules | grep -c "alert"
# Should show number of alerts loaded (50+)
```

### Step 3: Verify Alert Rules

```bash
# Check if alerts are loaded
docker exec code-server-prometheus promtool check rules /etc/prometheus/prometheus-alerts.yml
# Should show: success

# Check active alerts
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts | length'
# Shows count of currently active alerts
```

---

## Part 2: Alert Routing Configuration (15 minutes)

### Option A: Slack Notifications (Recommended)

**Prerequisites:**
- [ ] Slack workspace access
- [ ] Ability to create incoming webhooks

**Setup:**

1. **Create Slack Incoming Webhook**
   ```
   1. Go to: https://api.slack.com/apps
   2. Create New App → "From scratch"
   3. Name: "ProductionAlerts"
   4. Select workspace
   5. Enable "Incoming Webhooks"
   6. Add New Webhook to Workspace
   7. Select channel: #incidents
   8. Copy Webhook URL
   ```

2. **Configure AlertManager**
   ```bash
   # Create alertmanager config
   cat > alertmanager/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m
  slack_api_url: 'YOUR_WEBHOOK_URL_HERE'

route:
  receiver: 'slack-incidents'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h

receivers:
  - name: 'slack-incidents'
    slack_configs:
      - channel: '#incidents'
        title: 'Production Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        send_resolved: true
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
EOF
   ```

3. **Deploy AlertManager**
   ```bash
   docker-compose restart alertmanager
   sleep 5
   
   # Test webhook
   curl -XPOST YOUR_WEBHOOK_URL_HERE \
     -H 'Content-Type: application/json' \
     -d '{"text":"✅ Slack integration test successful"}'
   ```

### Option B: Email Notifications

```bash
# Configure SMTP in alertmanager.yml
cat > alertmanager/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password: 'YOUR_APP_PASSWORD'
  smtp_from: 'alerts@example.com'

route:
  receiver: 'email-ops'
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 6h

receivers:
  - name: 'email-ops'
    email_configs:
      - to: 'ops-team@example.com'
        headers:
          Subject: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
EOF
```

### Option C: PagerDuty Integration (Enterprise)

```bash
# For critical alerts, integrate with PagerDuty
cat > alertmanager/alertmanager.yml <<'EOF'
route:
  receiver: 'pagerduty-critical'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
      continue: true
    - match:
        severity: warning
      receiver: 'email-ops'

receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
        description: '{{ .GroupLabels.alertname }}'
        details:
          firing: '{{ template "pagerduty.default.instances" .Alerts.Firing }}'
  
  - name: 'email-ops'
    email_configs:
      - to: 'ops-team@example.com'
EOF
```

---

## Part 3: Grafana Dashboards Setup (15 minutes)

### Pre-built Dashboard 1: Infrastructure Overview

```bash
# Import dashboard via Grafana UI:
# 1. Go to: http://192.168.168.31:3000/dashboards
# 2. Click "New" → "Import"
# 3. Upload: grafana/dashboards/infrastructure-overview.json
# 4. Select Prometheus data source
# 5. Click "Import"
```

**Metrics Displayed:**
- Host CPU, Memory, Disk usage (both hosts)
- Network latency and errors
- Container count and resource usage
- Service availability percentage

### Pre-built Dashboard 2: PostgreSQL Replication

```bash
# This dashboard monitors the replication fix deployment
# Import: grafana/dashboards/postgresql-replication.json
# Metrics:
# - Replication lag (should be < 1s)
# - WAL sender/receiver status
# - Replication slot status
# - Primary/replica CPU and memory
# - Query performance comparison
```

### Pre-built Dashboard 3: API Performance

```bash
# Import: grafana/dashboards/api-performance.json
# Metrics:
# - Request rate (req/sec)
# - Response time (P50/P95/P99)
# - Error rate by endpoint
# - Throughput by service
# - Latency distribution
```

### Pre-built Dashboard 4: Application Health

```bash
# Import: grafana/dashboards/application-health.json
# Metrics:
# - Container status (green/red indicator)
# - Service health checks
# - Error logs by service
# - Custom application metrics
```

---

## Part 4: On-Call & Escalation Procedures (10 minutes)

### Alert Severity Levels

| Severity | Impact | Response Time | Escalation |
|----------|--------|----------------|------------|
| **Critical** | Complete service outage | 5 minutes | Immediate page to on-call |
| **High** | Partial degradation | 15 minutes | Page if not resolved in 15m |
| **Warning** | Early warning | 30 minutes | Email to ops team |
| **Info** | Informational only | No SLA | Log and monitor |

### On-Call Escalation Chain

**Level 1 (First Responder)** - 5 minute response
- DevOps on-call engineer
- Assess severity
- Take initial action if clear resolution path

**Level 2 (Backup)** - 15 minute response  
- Senior DevOps engineer
- Handle escalations from Level 1
- Complex troubleshooting

**Level 3 (Escalation)** - 30 minute response
- Infrastructure lead
- CTO
- Major incident coordination

### Response Procedures by Alert

```bash
# Create on-call runbook
cat > operations/on-call-runbook.md <<'EOF'

## Critical Alerts - Response Procedures

### PostgreSQL Replication Not Active
**Severity:** CRITICAL  
**SLA:** 5 minutes to acknowledge
**Response:**
1. SSH to replica (192.168.168.42)
2. Run: docker exec code-server-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
3. If false, execute: bash /home/ubuntu/code-server/orchestrate-postgresql-replication-fix.sh
4. Monitor recovery mode for 5 minutes
5. Verify data sync with test insert
6. If still not working, escalate to Level 2

### API Server Down
**Severity:** CRITICAL
**SLA:** 5 minutes to resolve
**Response:**
1. Check: docker-compose ps api-server
2. If exited: docker-compose up -d api-server
3. Wait 30 seconds
4. Check health: curl http://localhost:8000/health
5. If still down, check logs: docker logs api-server
6. If OOM: restart with increased memory and escalate

### PostgreSQL Down
**Severity:** CRITICAL
**SLA:** 5 minutes to restore
**Response:**
1. Check: docker-compose ps postgres
2. If exited: docker-compose up -d postgres
3. Wait 60 seconds for database to initialize
4. Verify: docker exec code-server-postgres psql -U postgres -c "SELECT 1"
5. If corruption suspected, restore from backup
6. Escalate immediately

EOF
```

---

## Part 5: Testing Alerts (5 minutes)

### Test 1: CPU High Alert

```bash
# Trigger high CPU alert
ssh ubuntu@192.168.168.31
docker run --cpus=1.9 --rm -it alpine stress-ng --cpu 2 --timeout 2m

# Check Prometheus for alert
# Visit: http://192.168.168.31:9090/alerts
# Should see: "HostCPUUsageHigh" in FIRING state

# Should receive notification (Slack/Email/PagerDuty)
```

### Test 2: Service Down Alert

```bash
# Temporarily stop a non-critical service
ssh ubuntu@192.168.168.31
docker-compose stop redis

# Wait 1-2 minutes
sleep 90

# Check alert
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts | map(select(.labels.alertname | contains("Redis")))'

# Restart service
docker-compose up -d redis
```

### Test 3: PostgreSQL Replication Alert

```bash
# Stop replication on replica
ssh ubuntu@192.168.168.42
docker-compose stop postgres
sleep 30

# Check alert (should show "PostgreSQLReplicationNotActive")
curl http://192.168.168.31:9090/api/v1/alerts

# Restart
docker-compose up -d postgres
```

---

## Part 6: Operational Validation Checklist

### Pre-Production Verification

- [ ] Prometheus collecting metrics from all 87 containers
- [ ] Alert rules file loaded (50+ alerts active)
- [ ] AlertManager routing configured and tested
- [ ] Slack/Email/PagerDuty notifications confirmed working
- [ ] Grafana dashboards imported and displaying metrics
- [ ] On-call procedures documented and team trained
- [ ] Alert routing rules tested for each severity level
- [ ] Runbooks created for all critical alerts
- [ ] Team has tested responding to 3+ alert scenarios
- [ ] Monitoring can run independently (Prometheus/Grafana/AlertManager resilient)

### Performance Baselines Captured

- [ ] API response time baseline (P95 < 1s)
- [ ] PostgreSQL query time baseline
- [ ] Container resource usage baseline
- [ ] Network latency baseline
- [ ] Service availability baseline (target: > 99%)

### Operational Ready

- [ ] On-call team notified and standing by
- [ ] Contact procedures updated in runbooks
- [ ] Escalation procedures tested
- [ ] Team knows how to access dashboards
- [ ] Team knows how to silence/snooze alerts if needed
- [ ] Team knows how to update alert thresholds

---

## Monitoring During May 1 Go-Live

### 06:00-08:30 UTC: PostgreSQL Replication Fix

**Monitor:**
- [ ] Prometheus collecting from both primary and replica
- [ ] PostgreSQL replication lag alert should CLEAR after fix
- [ ] WAL sender/receiver metrics showing healthy values

### 09:00-10:00 UTC: Initial Deployment

**Critical Watches:**
- [ ] API error rate stays below 0.1%
- [ ] Response time P95 stays below 1s
- [ ] Database connection count stays below 50
- [ ] Container restart rate = 0
- [ ] Network errors = 0

### 10:00-24:00 UTC: Monitoring Window

**Daily Checks:**
- [ ] No critical alerts in last 12 hours
- [ ] All services showing green in dashboards
- [ ] Replication lag < 100ms
- [ ] API availability > 99.9%
- [ ] No memory leaks detected

---

## Alert Tuning After Deployment

### Week 1: Establish Baselines
- Monitor actual production behavior
- Adjust alert thresholds based on real data
- Reduce false positive rate
- Document observed patterns

### Week 2: Optimize Alerts
- Fine-tune thresholds based on baselines
- Adjust alert grouping rules
- Test escalation procedures
- Train team on new patterns

### Week 3+: Continuous Improvement
- Regular review of alert effectiveness
- Update runbooks based on incidents
- Add new alerts for identified gaps
- Monitor alert fatigue

---

## Key Contacts & Resources

### Alert Dashboards
- **Prometheus:** http://192.168.168.31:9090
- **Grafana:** http://192.168.168.31:3000
- **AlertManager:** http://192.168.168.31:9093

### Documentation
- Alert Rules: `prometheus-alerts.yml`
- Runbooks: `operations/runbooks/`
- On-Call Guide: `operations/on-call-runbook.md`

### Team
- **DevOps Lead:** [CONTACT]
- **On-Call Engineer:** [ROTATING]
- **Escalation:** [CTO/INFRA_LEAD]

---

## Success Criteria

✅ **Monitoring Setup Complete:**
- [ ] Prometheus collecting all metrics
- [ ] 50+ alerts configured and active
- [ ] Notifications routing to 2+ channels
- [ ] Grafana dashboards displaying in real-time
- [ ] Team trained on response procedures
- [ ] Alert testing verified

✅ **Ready for Production:**
- [ ] Can detect and alert on all critical failures
- [ ] Notification delivery confirmed working
- [ ] On-call team ready to respond
- [ ] Operational runbooks prepared
- [ ] No monitoring gaps identified

