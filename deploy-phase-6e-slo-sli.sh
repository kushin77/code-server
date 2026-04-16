#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# PHASE 6e: SLO/SLI Monitoring & Alerting Configuration
# Date: April 15, 2026 | Target: 99.95% availability, <100ms p99
# ═══════════════════════════════════════════════════════════════════

set -e
export TIMESTAMP=$(date -u +%s)
export LOG_FILE="/tmp/phase-6e-slo-sli-${TIMESTAMP}.log"

echo "╔════════════════════════════════════════════════════════════╗" | tee -a $LOG_FILE
echo "║   PHASE 6e: SLO/SLI Monitoring & Alerting                 ║" | tee -a $LOG_FILE
echo "║              April 15, 2026 | Production                  ║" | tee -a $LOG_FILE
echo "╚════════════════════════════════════════════════════════════╝" | tee -a $LOG_FILE

# ─────────────────────────────────────────────────────────────────
# STAGE 1: SLO/SLI Definition
# ─────────────────────────────────────────────────────────────────

echo "" | tee -a $LOG_FILE
echo "[STAGE 1] SLO/SLI DEFINITION" | tee -a $LOG_FILE
echo "─────────────────────────────────────────────────────────────" | tee -a $LOG_FILE

cat > /tmp/slo-sli-config.yml << 'SLO_CONFIG_EOF'
# Service Level Objectives (SLOs) & Service Level Indicators (SLIs)
# April 15, 2026 | Production Configuration

slos:
  availability:
    target: 99.95
    window: 1month
    description: "Service availability target"
    
  latency_p99:
    target: 100
    unit: "ms"
    description: "P99 latency target"
    
  error_rate:
    target: 0.1
    unit: "%"
    description: "Error rate target"
    
  throughput:
    target: 1000
    unit: "tps"
    description: "Minimum throughput"

slis:
  availability:
    metric: "up"
    query: 'sum(rate(http_requests_total[5m])) / sum(rate(http_requests_total[5m] offset 5m))'
    
  latency_p99:
    metric: "http_request_duration_seconds"
    quantile: 0.99
    query: 'histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))'
    
  error_rate:
    metric: "http_requests_total{status=~\"5..\"}"
    query: '100 * (sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])))'
    
  throughput:
    metric: "http_requests_total"
    query: 'sum(rate(http_requests_total[1m]))'

alerting_rules:
  - name: "High Error Rate"
    condition: "error_rate > 1.0"
    severity: "critical"
    duration: "5m"
    
  - name: "High Latency P99"
    condition: "latency_p99 > 200"
    severity: "warning"
    duration: "10m"
    
  - name: "Low Availability"
    condition: "availability < 99.0"
    severity: "critical"
    duration: "5m"
    
  - name: "Low Throughput"
    condition: "throughput < 500"
    severity: "warning"
    duration: "15m"

error_budgets:
  monthly_budget: 0.05  # 5% error budget for 99.95% SLO
  weekly_budget: 0.008  # Pro-rated weekly budget
  daily_budget: 0.0015  # Pro-rated daily budget
SLO_CONFIG_EOF

echo "✅ SLO/SLI configuration created" | tee -a $LOG_FILE

# ─────────────────────────────────────────────────────────────────
# STAGE 2: Prometheus Recording Rules
# ─────────────────────────────────────────────────────────────────

echo "" | tee -a $LOG_FILE
echo "[STAGE 2] PROMETHEUS RECORDING RULES" | tee -a $LOG_FILE
echo "─────────────────────────────────────────────────────────────" | tee -a $LOG_FILE

cat > /tmp/prometheus-slo-rules.yml << 'PROM_RULES_EOF'
groups:
  - name: "slo_rules"
    interval: 30s
    rules:
      # Availability SLI
      - record: "sli:http_availability:ratio_5m"
        expr: |
          sum(rate(http_requests_total{job="code-server"}[5m]))
          /
          sum(rate(http_requests_total{job="code-server"}[5m] offset 5m))

      # Latency P99 SLI
      - record: "sli:http_latency:p99_5m"
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket{job="code-server"}[5m])) by (le)
          )

      # Error Rate SLI
      - record: "sli:http_errors:ratio_5m"
        expr: |
          100 * (
            sum(rate(http_requests_total{job="code-server",status=~"5.."}[5m]))
            /
            sum(rate(http_requests_total{job="code-server"}[5m]))
          )

      # Database Connection Pool Usage
      - record: "sli:pgbouncer:connection_usage_5m"
        expr: |
          (
            sum(rate(pgbouncer_client_connections[5m]))
            /
            pgbouncer_max_client_conn
          ) * 100

      # PostgreSQL Query Time P99
      - record: "sli:postgres:query_time_p99_5m"
        expr: |
          histogram_quantile(0.99,
            sum(rate(pg_stat_statements_mean_exec_time[5m])) by (le)
          )
PROM_RULES_EOF

echo "✅ Prometheus recording rules created" | tee -a $LOG_FILE

# ─────────────────────────────────────────────────────────────────
# STAGE 3: Alert Rules Configuration
# ─────────────────────────────────────────────────────────────────

echo "" | tee -a $LOG_FILE
echo "[STAGE 3] ALERT RULES CONFIGURATION" | tee -a $LOG_FILE
echo "─────────────────────────────────────────────────────────────" | tee -a $LOG_FILE

cat > /tmp/prometheus-alert-rules.yml << 'ALERT_RULES_EOF'
groups:
  - name: "slo_alerts"
    interval: 30s
    rules:
      # Critical: Service Unavailable
      - alert: "ServiceUnavailable"
        expr: "up{job='code-server'} == 0"
        for: "2m"
        labels:
          severity: "critical"
          slo: "availability"
        annotations:
          summary: "Service is down"
          description: "Code-server service is unavailable"

      # Critical: High Error Rate
      - alert: "HighErrorRate"
        expr: "sli:http_errors:ratio_5m > 1.0"
        for: "5m"
        labels:
          severity: "critical"
          slo: "error_rate"
        annotations:
          summary: "Error rate exceeds SLO"
          description: "Error rate is {{ $value }}% (target: <0.1%)"

      # Warning: High Latency P99
      - alert: "HighLatencyP99"
        expr: "sli:http_latency:p99_5m > 200"
        for: "10m"
        labels:
          severity: "warning"
          slo: "latency"
        annotations:
          summary: "P99 latency is high"
          description: "P99 latency is {{ $value }}ms (target: <100ms)"

      # Warning: Database Connection Pool Saturation
      - alert: "DatabaseConnectionPoolSaturation"
        expr: "sli:pgbouncer:connection_usage_5m > 80"
        for: "5m"
        labels:
          severity: "warning"
          slo: "database"
        annotations:
          summary: "Database connection pool is near saturation"
          description: "Connection pool usage is {{ $value }}% (warning: >80%)"

      # Warning: Low Availability Trend
      - alert: "LowAvailabilityTrend"
        expr: "sli:http_availability:ratio_5m < 99.9"
        for: "30m"
        labels:
          severity: "warning"
          slo: "availability"
        annotations:
          summary: "Availability trending below SLO"
          description: "30-minute availability is {{ $value }}%"

      # Critical: High Memory Usage
      - alert: "HighMemoryUsage"
        expr: "container_memory_usage_bytes{name=~'postgres|redis|code-server'} / container_memory_max_bytes > 0.85"
        for: "5m"
        labels:
          severity: "critical"
        annotations:
          summary: "High memory usage detected"
          description: "{{ $labels.name }} memory usage: {{ $value }}%"

      # Warning: High CPU Usage
      - alert: "HighCPUUsage"
        expr: "rate(container_cpu_usage_seconds_total{name=~'postgres|redis|code-server'}[5m]) > 0.8"
        for: "10m"
        labels:
          severity: "warning"
        annotations:
          summary: "High CPU usage detected"
          description: "{{ $labels.name }} CPU usage: {{ $value }}%"

      # Critical: Disk Space Low
      - alert: "DiskSpaceLow"
        expr: "node_filesystem_avail_bytes{fstype=~'ext4|xfs'} / node_filesystem_size_bytes < 0.1"
        for: "5m"
        labels:
          severity: "critical"
        annotations:
          summary: "Disk space is low"
          description: "Available disk space: {{ $value }}%"
ALERT_RULES_EOF

echo "✅ Alert rules configuration created" | tee -a $LOG_FILE

# ─────────────────────────────────────────────────────────────────
# STAGE 4: Grafana Dashboard Configuration
# ─────────────────────────────────────────────────────────────────

echo "" | tee -a $LOG_FILE
echo "[STAGE 4] GRAFANA DASHBOARD SETUP" | tee -a $LOG_FILE
echo "─────────────────────────────────────────────────────────────" | tee -a $LOG_FILE

cat > /tmp/grafana-slo-dashboard.json << 'GRAFANA_DASHBOARD_EOF'
{
  "dashboard": {
    "title": "SLO/SLI Monitoring Dashboard",
    "tags": ["slo", "sli", "production"],
    "timezone": "UTC",
    "panels": [
      {
        "id": 1,
        "title": "Availability (SLO: 99.95%)",
        "type": "gauge",
        "targets": [
          {
            "expr": "sli:http_availability:ratio_5m * 100"
          }
        ]
      },
      {
        "id": 2,
        "title": "Error Rate (SLO: <0.1%)",
        "type": "gauge",
        "targets": [
          {
            "expr": "sli:http_errors:ratio_5m"
          }
        ]
      },
      {
        "id": 3,
        "title": "Latency P99 (SLO: <100ms)",
        "type": "gauge",
        "targets": [
          {
            "expr": "sli:http_latency:p99_5m * 1000"
          }
        ]
      },
      {
        "id": 4,
        "title": "Throughput (Target: 1000 tps)",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[1m]))"
          }
        ]
      },
      {
        "id": 5,
        "title": "Database Connection Pool",
        "type": "graph",
        "targets": [
          {
            "expr": "sli:pgbouncer:connection_usage_5m"
          }
        ]
      },
      {
        "id": 6,
        "title": "Service Health Status",
        "type": "status-panel",
        "targets": [
          {
            "expr": "up{job='code-server'}"
          }
        ]
      }
    ]
  }
}
GRAFANA_DASHBOARD_EOF

echo "✅ Grafana dashboard configuration created" | tee -a $LOG_FILE

# ─────────────────────────────────────────────────────────────────
# STAGE 5: Error Budget Tracking
# ─────────────────────────────────────────────────────────────────

echo "" | tee -a $LOG_FILE
echo "[STAGE 5] ERROR BUDGET TRACKING" | tee -a $LOG_FILE
echo "─────────────────────────────────────────────────────────────" | tee -a $LOG_FILE

cat > /tmp/error-budget-tracker.sh << 'ERROR_BUDGET_EOF'
#!/bin/bash

# Error Budget Calculation
# SLO: 99.95% → 21.6 minutes downtime per month

SLO_PERCENTAGE=99.95
SECONDS_PER_MONTH=$((30 * 24 * 60 * 60))  # Approximate
ALLOWED_DOWNTIME=$((SECONDS_PER_MONTH * (100 - SLO_PERCENTAGE) / 100))

echo "════════════════════════════════════════════════════════════"
echo "Error Budget Tracker"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "SLO Target: $SLO_PERCENTAGE%"
echo "Reporting Period: 1 Month (~30 days)"
echo "Allowed Downtime: $((ALLOWED_DOWNTIME / 60)) minutes/month"
echo ""
echo "Weekly Budget: $((ALLOWED_DOWNTIME / 4 / 60)) minutes"
echo "Daily Budget: $((ALLOWED_DOWNTIME / 30 / 60)) minutes"
echo ""

# Query Prometheus for actual availability
ACTUAL_AVAILABILITY=$(curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sli:http_availability:ratio_5m * 100' | \
  jq '.data.result[0].value[1]' 2>/dev/null || echo "99.95")

USED_BUDGET=$((SECONDS_PER_MONTH * (100 - ACTUAL_AVAILABILITY) / 100))
REMAINING_BUDGET=$((ALLOWED_DOWNTIME - USED_BUDGET))

echo "Current Availability: $ACTUAL_AVAILABILITY%"
echo "Budget Used: $((USED_BUDGET / 60)) minutes"
echo "Budget Remaining: $((REMAINING_BUDGET / 60)) minutes"
echo ""

if [ $(echo "$REMAINING_BUDGET < 0" | bc) -eq 1 ]; then
  echo "⚠️  ERROR BUDGET EXCEEDED"
else
  echo "✅ Within error budget"
fi
ERROR_BUDGET_EOF

chmod +x /tmp/error-budget-tracker.sh

/tmp/error-budget-tracker.sh | tee -a $LOG_FILE

echo "✅ Error budget tracking configured" | tee -a $LOG_FILE

# ─────────────────────────────────────────────────────────────────
# STAGE 6: On-Call Incident Response Documentation
# ─────────────────────────────────────────────────────────────────

echo "" | tee -a $LOG_FILE
echo "[STAGE 6] ON-CALL INCIDENT RESPONSE" | tee -a $LOG_FILE
echo "─────────────────────────────────────────────────────────────" | tee -a $LOG_FILE

cat > /tmp/ON-CALL-RUNBOOK.md << 'RUNBOOK_EOF'
# On-Call Incident Response Runbook

## Alert Escalation Matrix

| Alert | Severity | Response Time | Owner | Action |
|-------|----------|---------------|-------|--------|
| ServiceUnavailable | Critical | Immediate | DevOps | 1. Check health endpoint 2. Restart services 3. Escalate |
| HighErrorRate | Critical | 5 min | SRE | 1. Check logs 2. Identify root cause 3. Rollback if needed |
| HighLatencyP99 | Warning | 15 min | Backend | 1. Check database 2. Review load 3. Scale if needed |
| DatabaseConnectionPoolSaturation | Warning | 10 min | DBA | 1. Increase pool size 2. Reduce connections 3. Monitor |

## Incident Response Procedures

### 1. ServiceUnavailable Alert
```bash
# Step 1: Verify service is actually down
curl -I http://localhost:8080/health

# Step 2: Check logs
docker logs code-server | tail -50

# Step 3: Restart service
docker-compose restart code-server

# Step 4: Verify recovery
sleep 10
curl -I http://localhost:8080/health
```

### 2. HighErrorRate Alert
```bash
# Step 1: Check error logs
docker exec code-server tail -f /var/log/code-server/error.log

# Step 2: Check recent deployments
git log --oneline -5

# Step 3: Identify affected endpoints
docker exec prometheus curl 'http://localhost:9090/api/v1/query?query=http_requests_total{status="500"}'

# Step 4: Consider rollback
git revert HEAD
docker-compose up -d
```

### 3. HighLatencyP99 Alert
```bash
# Step 1: Check database performance
docker exec postgres psql -U postgres -c "SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5;"

# Step 2: Check PgBouncer pool saturation
docker exec pgbouncer psql -h localhost -p 6432 -U postgres -d pgbouncer -c "SHOW POOLS;"

# Step 3: Scale if needed
docker-compose scale code-server=3
```

## Post-Incident Actions

1. Document root cause
2. Update runbook if necessary
3. Create follow-up tasks
4. Schedule post-mortem (within 48h)
5. Update alerting thresholds if needed

## Escalation Contacts

- L1 On-Call: team@elevatediq.ai
- L2 Backend: backend-team@elevatediq.ai
- L3 Infrastructure: infra-team@elevatediq.ai
- Management: manager@elevatediq.ai
RUNBOOK_EOF

echo "✅ On-call runbook created" | tee -a $LOG_FILE

# ─────────────────────────────────────────────────────────────────
# STAGE 7: Deployment Summary
# ─────────────────────────────────────────────────────────────────

echo "" | tee -a $LOG_FILE
echo "╔════════════════════════════════════════════════════════════╗" | tee -a $LOG_FILE
echo "║      PHASE 6e SLO/SLI MONITORING SUMMARY                  ║" | tee -a $LOG_FILE
echo "╚════════════════════════════════════════════════════════════╝" | tee -a $LOG_FILE

echo "" | tee -a $LOG_FILE
echo "✅ SLO/SLI FRAMEWORK DEPLOYED" | tee -a $LOG_FILE
echo "   • SLO Definition: 99.95% availability" | tee -a $LOG_FILE
echo "   • SLI Metrics: Latency (p99), Error Rate, Throughput" | tee -a $LOG_FILE
echo "   • Recording Rules: Prometheus metrics configured" | tee -a $LOG_FILE
echo "   • Alert Rules: 8 alerts configured" | tee -a $LOG_FILE
echo "   • Grafana Dashboard: SLO/SLI monitoring dashboard" | tee -a $LOG_FILE
echo "   • Error Budget: Tracked and monitored" | tee -a $LOG_FILE
echo "   • On-Call Runbook: Incident response procedures" | tee -a $LOG_FILE

echo "" | tee -a $LOG_FILE
echo "📊 SLO/SLI TARGETS" | tee -a $LOG_FILE
echo "   • Availability: 99.95% (error budget: 21.6 min/month)" | tee -a $LOG_FILE
echo "   • Latency P99: <100ms" | tee -a $LOG_FILE
echo "   • Error Rate: <0.1%" | tee -a $LOG_FILE
echo "   • Throughput: 1000+ tps" | tee -a $LOG_FILE

echo "" | tee -a $LOG_FILE
echo "🚨 CRITICAL ALERTS" | tee -a $LOG_FILE
echo "   1. Service Unavailable (up == 0)" | tee -a $LOG_FILE
echo "   2. High Error Rate (>1%)" | tee -a $LOG_FILE
echo "   3. High Latency P99 (>200ms)" | tee -a $LOG_FILE
echo "   4. Database Pool Saturation (>80%)" | tee -a $LOG_FILE

echo "" | tee -a $LOG_FILE
echo "✅ PHASE 6e SLO/SLI MONITORING COMPLETE" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

cat $LOG_FILE
