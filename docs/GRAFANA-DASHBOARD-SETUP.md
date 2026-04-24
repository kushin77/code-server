# Grafana Cluster Health Dashboard

**Dashboard Type**: Real-time cluster monitoring  
**Target Audience**: Operations Team, SRE, On-call Engineers  
**Refresh Rate**: 5 seconds (real-time updates)  
**Time Window**: Last 1 hour  
**Setup Time**: < 5 minutes  
**Health Check Time**: < 10 seconds (SUCCESS CRITERIA MET)

---

## Dashboard Overview

**Unified Grafana dashboard** for real-time cluster health monitoring with instant health assessment (< 10 seconds to determine cluster status).

### Success Metrics
✅ **Health determination time**: < 10 seconds (ops team looks at dashboard, immediately knows cluster state)  
✅ **Real-time updates**: 5-second refresh rate (reflects actual cluster state)  
✅ **Visual clarity**: Color-coded status, easy-to-scan layout  
✅ **Comprehensive coverage**: All critical metrics included  
✅ **Actionable information**: Links to troubleshooting and runbooks  

---

## Installation & Setup

### Step 1: Import Dashboard JSON

```bash
# Option A: Via Grafana UI
1. Go to: http://grafana.kushnir.cloud:3000 (or localhost:3000)
2. Navigate: Dashboards → New → Import
3. Upload: monitoring/grafana-cluster-health-dashboard.json
4. Configure:
   - Prometheus datasource: "prometheus"
   - Dashboard name: "Cluster Health"
   - Folder: "Production"

# Option B: Via API
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -d @monitoring/grafana-cluster-health-dashboard.json
```

### Step 2: Configure Prometheus Datasource

```yaml
# In Grafana: Configuration → Data Sources → Add Prometheus
Name: prometheus
URL: http://prometheus:9090
Access: Server (default)
Scrape interval: 15s
Evaluation interval: 15s
```

### Step 3: Verify Metrics Are Available

```bash
# From Prometheus UI (http://localhost:9090):
# Test these queries to ensure metrics exist:

up{job=~"replica.*"}                    # Should show 2 results (replica 1 & 2)
pg_replication_lag{replica=~"replica.*"}  # Should show replication lag
redis_connected_slaves{replica=~"replica.*"}  # Should show sentinel state
container_last_seen{replica=~"replica.*"}    # Should show running services
ALERTS{alertstate="firing"}             # Should show active alerts
```

### Step 4: Star Dashboard (Make Default)

```
In Grafana UI:
1. Open: Cluster Health Dashboard
2. Click: Star icon (top right)
3. Select: "Mark as default dashboard"
```

---

## Dashboard Panels

### Row 1: Cluster Status Overview

#### Panel 1: Replica Availability (1=Up, 0=Down)
- **Type**: Time series graph
- **Metric**: `up{job=~"replica.*"}`
- **Shows**: Real-time availability timeline for both replicas
- **Green line (1)**: Replica is up
- **Red gap**: Replica is down
- **Use case**: Identify outage windows and duration
- **Refresh**: Every 5 seconds

#### Panel 2: Cluster Status (AT A GLANCE)
- **Type**: Stat card with color coding
- **Shows**: Replica 1 (192.168.168.31) and Replica 2 (192.168.168.42)
- **Green**: UP (status = 1)
- **Red**: DOWN (status = 0)
- **Use case**: Instant health check (< 5 seconds to see cluster state)
- **SUCCESS CRITERIA**: ✅ Ops team determines health in < 10 seconds

---

### Row 2: Core Infrastructure Metrics

#### Panel 3: Database Replication Lag (seconds)
- **Type**: Time series graph with thresholds
- **Metric**: `pg_replication_lag{replica=~"replica.*"}`
- **Green zone**: < 10 seconds
- **Yellow zone**: 10-30 seconds (acceptable but watch)
- **Red zone**: > 30 seconds (investigate)
- **Critical threshold**: 30 seconds (alert trigger)
- **Use case**: Monitor data consistency between replicas
- **Healthy state**: Lag < 1 second (near real-time replication)

#### Panel 4: Service Distribution (Running/Stopped)
- **Type**: Donut chart
- **Shows**: Ratio of running vs stopped services
- **Healthy state**: All services running (100%)
- **Warning**: Any stopped services should trigger investigation
- **Use case**: Quick visual check: are all services operational?

---

### Row 3: Service & Performance Metrics

#### Panel 5: Running Services per Replica
- **Type**: Stacked bar chart
- **Shows**: Service count per replica over time
- **Healthy state**: Consistent count across replicas
- **Deviation**: If counts differ between replicas, investigate
- **Expected**: 10+ services running on each replica
- **Use case**: Detect partial service failures

#### Panel 6: Redis Sentinel State
- **Type**: Stat card
- **Shows**: Redis Sentinel connectivity status
- **States**:
  - 0 (DOWN): Red - Redis down or unreachable
  - 1 (UP): Green - Redis primary operational
  - 2 (SYNC): Green - Redis replicating (standby synced)
- **Healthy state**: 1 or 2 (at least one replica connected to sentinel)
- **Use case**: Verify session store is available

---

### Row 4: Traffic & Alerting

#### Panel 7: Loadbalancer Traffic (Requests/sec)
- **Type**: Time series graph
- **Metric**: `rate(caddy_http_requests_total[1m])`
- **Shows**: Request throughput from each replica
- **Healthy state**: Traffic distributed across both replicas
- **Anomaly**: Sudden drop = replica down, sudden spike = traffic spike
- **Use case**: Monitor traffic patterns and detect anomalies

#### Panel 8: Active Alerts by Severity
- **Type**: Donut chart
- **Shows**: Active alert count segmented by severity
  - Critical (red): Production breaking
  - Warning (yellow): Should be resolved soon
  - Info (blue): Informational only
- **Healthy state**: No critical or warning alerts
- **Use case**: Instant alert status overview

---

### Row 5: Resource Utilization

#### Panel 9: Memory Usage % per Replica
- **Type**: Time series with thresholds
- **Metric**: `(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100`
- **Green zone**: < 75%
- **Yellow zone**: 75-90% (watch for growth)
- **Red zone**: > 90% (risk of OOM)
- **Healthy state**: Stable, usually 40-60%
- **Use case**: Detect memory leaks or over-allocation

#### Panel 10: Disk Usage % per Replica
- **Type**: Time series with thresholds
- **Metric**: `(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100` for root filesystem
- **Green zone**: < 70%
- **Yellow zone**: 70-85% (investigate growth)
- **Red zone**: > 85% (may impact performance)
- **Healthy state**: Stable, usually 20-40%
- **Use case**: Monitor disk growth, trigger cleanup if needed

---

### Row 6: Alert History

#### Panel 11: Active Alerts Table
- **Type**: Table
- **Shows**: All currently firing alerts sorted by time (newest first)
- **Columns**: Alert name, Instance, Replica, Severity
- **Color coded**: Critical (red), Warning (yellow), Info (blue)
- **Healthy state**: Empty table (no active alerts)
- **Use case**: Drill down into specific alerts, see alert details

---

## Health Assessment Workflow

### Quick Health Check (< 10 seconds)

1. **Open dashboard**: http://grafana.kushnir.cloud:3000/d/cluster-health
2. **Glance at Panel 2** (Cluster Status): Both replicas green? ✅ Healthy
3. **Glance at Panel 3** (Replication Lag): < 5 seconds? ✅ Good
4. **Glance at Panel 8** (Alerts): No red critical alerts? ✅ OK

**Result**: If all 3 glances are green, cluster is healthy. If any is red, proceed to detailed investigation.

### Detailed Health Investigation (2-5 minutes)

**If Panel 2 shows DOWN (red)**:
- Check Panel 1 (Availability): When did it go down?
- Check Panel 5 (Services): Are services still running?
- Action: SSH to down replica, check docker-compose ps

**If Panel 3 shows RED (> 30 seconds lag)**:
- Check Panel 7 (Traffic): Is there a traffic spike?
- Check Panel 9 (Memory): Is replica running out of memory?
- Check Panel 10 (Disk): Is disk full?
- Action: Check database replication status, investigate lag root cause

**If Panel 8 shows CRITICAL alerts**:
- Click on alert in Panel 11 (Alerts Table)
- See alert details: which replica? which service?
- Action: Navigate to relevant runbook (deployment, failover, troubleshooting)

---

## Typical Cluster States

### State 1: All Green (Healthy)

```
Panel 2 (Status): Replica 1: UP, Replica 2: UP
Panel 3 (Lag): ~0.5 seconds
Panel 5 (Services): Both showing ~10 services
Panel 6 (Redis): 2 (SYNC)
Panel 7 (Traffic): Distributed across both
Panel 8 (Alerts): 0 Critical, 0 Warning
Panel 9 (Memory): ~50% on both
Panel 10 (Disk): ~30% on both
→ Action: No action needed, cluster operational
```

### State 2: Replica 2 Down (Failover in Progress)

```
Panel 2 (Status): Replica 1: UP, Replica 2: DOWN (red)
Panel 3 (Lag): ~0 seconds (only one master, no replication)
Panel 5 (Services): Replica 1: ~10, Replica 2: ~0
Panel 6 (Redis): 1 (UP, one replica only)
Panel 7 (Traffic): All traffic on Replica 1
Panel 8 (Alerts): 1 Critical "Replica2 Down"
→ Action: Check failover status, verify services on R1, prepare recovery
```

### State 3: High Replication Lag (Performance Issue)

```
Panel 2 (Status): Replica 1: UP, Replica 2: UP
Panel 3 (Lag): 45 seconds (RED threshold exceeded)
Panel 5 (Services): Both ~10 services (running)
Panel 7 (Traffic): Replica 1 getting spike in requests
Panel 9 (Memory): Replica 2 showing 85% (high)
Panel 8 (Alerts): 1 Warning "Replication Lag"
→ Action: Check network latency, check replica 2 disk I/O, restart postgres if needed
```

---

## Alerting Integration

### Recommended Alert Rules

Create these in Prometheus for integration with dashboard Panel 8:

```yaml
# Critical: Replica down for > 30 seconds
- alert: ReplicaDown
  expr: up{job=~"replica.*"} == 0
  for: 30s
  annotations:
    severity: critical
    summary: "Replica {{ $labels.instance }} is DOWN"

# Warning: Replication lag > 30 seconds
- alert: ReplicationLagHigh
  expr: pg_replication_lag{replica=~"replica.*"} > 30
  for: 1m
  annotations:
    severity: warning
    summary: "Replication lag on {{ $labels.replica }} is {{ $value }}s"

# Warning: Memory usage > 85%
- alert: MemoryUsageHigh
  expr: |
    (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) 
    / node_memory_MemTotal_bytes * 100 > 85
  for: 5m
  annotations:
    severity: warning
    summary: "Memory usage on {{ $labels.replica }} is {{ $value }}%"

# Warning: Disk usage > 80%
- alert: DiskUsageHigh
  expr: |
    (1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100 > 80
  for: 5m
  annotations:
    severity: warning
    summary: "Disk usage on {{ $labels.replica }} is {{ $value }}%"
```

### Alert Notification Routing

```yaml
# In AlertManager config:
- match:
    severity: critical
  receiver: 'on-call-pager'        # PagerDuty
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 30m

- match:
    severity: warning
  receiver: 'slack-ops'             # Slack #ops channel
  group_wait: 5m
  group_interval: 30m
  repeat_interval: 4h
```

---

## Dashboard Customization

### Add Custom Panels

**Example: Add TLS Certificate Expiry**

```json
{
  "title": "TLS Certificate Expiry (days)",
  "targets": [
    {
      "expr": "(ssl_certificate_expiry_timestamp - time()) / 86400"
    }
  ],
  "fieldConfig": {
    "thresholds": {
      "steps": [
        {"color": "red", "value": 0},
        {"color": "yellow", "value": 7},
        {"color": "green", "value": 30}
      ]
    }
  }
}
```

### Add Custom Variables

```json
{
  "templating": {
    "list": [
      {
        "name": "replica",
        "type": "query",
        "datasource": "prometheus",
        "query": "label_values(up, replica)",
        "multi": true
      }
    ]
  }
}
```

---

## Troubleshooting Dashboard Issues

### Issue: Panels show "No Data"

**Problem**: Metrics not appearing in Prometheus

**Solution**:
1. Check Prometheus is scraping: http://localhost:9090/targets
2. Verify metric names: http://localhost:9090/graph
3. Test query manually: `up{job=~"replica.*"}`
4. If empty: Update job_name in prometheus.yml to match replica labels

### Issue: Dashboard Slow (> 10s refresh)

**Problem**: Too many metrics or slow Prometheus

**Solution**:
1. Reduce refresh rate: Edit dashboard → Refresh: 10s (was 5s)
2. Reduce time window: Edit dashboard → Time range: Last 30m (was 1h)
3. Optimize Prometheus: Add `--query.max-samples=10000000` flag

### Issue: Alerts not appearing in Panel 11

**Problem**: AlertManager not connected to Prometheus

**Solution**:
1. Check AlertManager: http://localhost:9093
2. Verify alerts are firing: http://localhost:9090/alerts
3. Configure AlertManager in Grafana: Configuration → Notification channels

---

## Quick Reference

| Panel | Success State | Warning State | Critical State |
|-------|---|---|---|
| Cluster Status | Both UP | 1 UP | Both DOWN |
| Replication Lag | < 5s | 5-30s | > 30s |
| Service Count | All 10+ each | 1-2 missing | > 2 missing |
| Redis Sentinel | 1 or 2 | Degraded | 0 (DOWN) |
| Traffic | Balanced | Skewed | All one replica |
| Alerts | 0 Critical | 1+ Warning | 1+ Critical |
| Memory | < 70% | 70-85% | > 85% |
| Disk | < 70% | 70-85% | > 85% |

---

## Related Documentation

- [Deployment Runbook](DEPLOYMENT-RUNBOOK-SIMPLIFIED.md) — Deployment procedures
- [Failover Runbook](FAILOVER-RUNBOOK-SIMPLIFIED.md) — Manual failover procedures
- [Production Cluster Architecture](../docs/production-cluster-architecture-v2.md) — Architecture overview
- [Alert Rules](alert-rules.yml) — Complete alert rule set

---

**Dashboard Status**: ✅ Production Ready  
**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Owner**: Operations Team
