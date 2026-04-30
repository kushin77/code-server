# Monitoring & Dashboard Integration Guide for code-server

**Version**: 1.0  
**Date**: April 30, 2026  
**Purpose**: Setup Prometheus metrics collection and Grafana dashboards

---

## Overview

This guide covers integration of Prometheus metrics collection and Grafana visualization for code-server operational monitoring. Provides real-time visibility into infrastructure health, SLO compliance, and system resources.

---

## Architecture

```
┌─────────────────────────────────────┐
│   Metrics Sources                   │
├─────────────────────────────────────┤
│ ✓ Drift Watchdog (drift resources)  │
│ ✓ SLO Tracker (compliance metrics)  │
│ ✓ Node Exporter (system metrics)    │
│ ✓ cAdvisor (container metrics)      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Prometheus (time-series DB)        │
│  Port: 9090                         │
│  Config: monitoring/prometheus.yml  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Grafana (visualization)            │
│  Port: 3000                         │
│  Dashboard: Code-Server Ops         │
└─────────────────────────────────────┘
```

---

## Components

### 1. Prometheus Configuration (`monitoring/prometheus.yml`)

**Scrape Jobs**:
- `prometheus`: Self-monitoring (localhost:9090)
- `node-primary`: System metrics from primary host (192.168.168.31:9100)
- `node-replica`: System metrics from replica host (192.168.168.42:9100)
- `cadvisor-primary`: Container metrics from primary (192.168.168.31:8080)
- `cadvisor-replica`: Container metrics from replica (192.168.168.42:8080)
- `code-server-ops`: Custom metrics from drift/SLO (localhost:9091)

**Scrape Interval**: 5 minutes (matches drift watchdog)

### 2. Metrics Exporter (`scripts/ops/export-prometheus-metrics.sh`)

**Exported Metrics**:
- `code_server_terraform_drift_resources`: Number of drifted resources
- `code_server_healthy_containers`: Healthy container count by host
- `code_server_unhealthy_containers`: Unhealthy container count by host
- `code_server_disk_usage_percent`: Disk usage percentage by host
- `code_server_slo_availability_percent`: Availability SLO compliance
- `code_server_slo_deployment_success_percent`: Deployment success SLO
- `code_server_slo_drift_free_percent`: Drift-free SLO compliance
- `code_server_slo_health_check_percent`: Health check SLO compliance

**Functions**:
- `collect_drift_metrics()`: Export Terraform drift data
- `collect_health_metrics()`: Export container health
- `collect_slo_metrics()`: Export SLO compliance
- `collect_disk_metrics()`: Export disk usage

### 3. Grafana Dashboard (`monitoring/grafana-dashboard.json`)

**Panels**:
1. **Terraform Drift Gauge**: Real-time drifted resource count (0-50)
2. **Unhealthy Containers Gauge**: Current unhealthy container count
3. **Availability SLO Gauge**: Current availability SLO %
4. **Disk Usage Trend**: Historical disk usage with thresholds
5. **Container Health Distribution**: Pie chart of healthy/unhealthy ratio
6. **SLO Compliance Table**: All 4 SLO metrics side-by-side

**Color Coding**:
- Green: Good (drift=0, healthy=all, SLO>=99%)
- Yellow: Warning (drift>0, SLO>95%, disk>70%)
- Red: Critical (unhealthy>1, SLO<95%, disk>85%)

---

## Installation & Deployment

### Prerequisites

```bash
# Required packages
sudo apt-get install -y prometheus grafana-server

# Optional but recommended
sudo apt-get install -y prometheus-node-exporter
docker run -d --name cadvisor --volumes-from /:/rootfs:ro \
  gcr.io/cadvisor/cadvisor:latest
```

### Step 1: Deploy Prometheus

```bash
# Copy Prometheus config
sudo cp monitoring/prometheus.yml /etc/prometheus/prometheus.yml

# Restart Prometheus
sudo systemctl restart prometheus

# Verify
curl http://localhost:9090/api/v1/query?query=up
```

### Step 2: Deploy Metrics Exporter

```bash
# Make script executable
chmod +x scripts/ops/export-prometheus-metrics.sh

# Start metrics server (runs in background)
./scripts/ops/export-prometheus-metrics.sh start

# Verify metrics are available
curl http://localhost:9091/metrics
```

### Step 3: Configure Grafana Data Source

```bash
# Open Grafana at http://localhost:3000
# Default: admin/admin

# Steps:
# 1. Go to Configuration → Data Sources
# 2. Add Prometheus
#    - URL: http://localhost:9090
#    - Access: Server (default)
# 3. Save & Test
```

### Step 4: Import Dashboard

```bash
# Option A: Via UI
# 1. Go to Dashboards → Import
# 2. Upload file: monitoring/grafana-dashboard.json
# 3. Select Prometheus data source
# 4. Save

# Option B: Via API
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @monitoring/grafana-dashboard.json
```

---

## Viewing Metrics

### Prometheus Queries

```promql
# Current drift resources
code_server_terraform_drift_resources

# Unhealthy containers
sum(code_server_unhealthy_containers)

# Disk usage trend
code_server_disk_usage_percent

# SLO compliance
code_server_slo_availability_percent

# Container count by host
sum(code_server_healthy_containers) by (host)

# Disk usage threshold violations
code_server_disk_usage_percent > 80
```

### Grafana Dashboard Access

```
URL: http://localhost:3000/d/code-server-ops
Default: admin/admin (change on first login)
```

---

## Alerts & Thresholds

### Alerting Rules (Optional)

Configure alertmanager for automatic notifications:

```yaml
# Example: Alert on high drift
alert: HighDrift
expr: code_server_terraform_drift_resources > 5
for: 5m
annotations:
  summary: "High terraform drift: {{ $value }} resources"
```

### Dashboard Thresholds

**Terraform Drift**:
- Green: 0 resources
- Yellow: 1-4 resources
- Red: 5+ resources

**Unhealthy Containers**:
- Green: 0 containers
- Yellow: 1-2 containers
- Red: 3+ containers

**SLO Compliance**:
- Green: ≥99%
- Yellow: 95-98%
- Red: <95%

**Disk Usage**:
- Green: <70%
- Yellow: 70-85%
- Red: >85%

---

## Troubleshooting

### Prometheus Not Scraping Metrics

**Problem**: "No metrics found" in Prometheus UI

**Solutions**:
1. Check Prometheus is running:
   ```bash
   systemctl status prometheus
   systemctl restart prometheus
   ```

2. Verify config syntax:
   ```bash
   promtool check config /etc/prometheus/prometheus.yml
   ```

3. Check targets:
   ```
   http://localhost:9090/targets
   ```

4. Enable debug logging:
   ```bash
   # Add to prometheus.yml
   global:
     log_level: debug
   ```

### Metrics Exporter Not Running

**Problem**: Port 9091 unreachable

**Solutions**:
1. Check if server is running:
   ```bash
   netstat -tuln | grep 9091
   ```

2. Start metrics exporter:
   ```bash
   ./scripts/ops/export-prometheus-metrics.sh start
   ```

3. Test metrics collection:
   ```bash
   ./scripts/ops/export-prometheus-metrics.sh metrics
   ```

4. Check for errors:
   ```bash
   tail -f /var/log/syslog | grep code-server
   ```

### Dashboard Not Displaying Data

**Problem**: Panels show "No data"

**Solutions**:
1. Verify Prometheus data source:
   - Go to Grafana → Configuration → Data Sources
   - Click Prometheus
   - "Test Connection" should pass

2. Check time range:
   - Dashboard defaults to 6 hours
   - Extend if needed for historical data

3. Verify metrics exist:
   ```bash
   # In Prometheus UI:
   # Search for: code_server_terraform_drift_resources
   ```

### SSH Connection Failures in Metrics

**Problem**: Metrics collection hangs or fails for replica metrics

**Solutions**:
1. Verify SSH connectivity:
   ```bash
   ssh akushnir@192.168.168.42 "echo OK"
   ```

2. Add SSH key if needed:
   ```bash
   ssh-copy-id akushnir@192.168.168.42
   ```

3. Check SSH timeout settings in export script:
   ```bash
   # Modify timeout: ssh -o ConnectTimeout=5 ...
   ```

---

## Performance Considerations

### Storage Requirements

Prometheus time-series database retention:
- Default: 15GB disk space for 15 days retention
- Adjust with `--storage.tsdb.retention.time=30d`

### CPU Usage

- Prometheus: ~2-5% CPU for 50 containers
- Grafana: ~1-2% CPU for dashboards
- Metrics exporter: <1% CPU

### Network Impact

- Scrape interval: Every 5 minutes
- Data per scrape: ~5-10 KB
- Monthly: ~4-8 MB per metric

---

## Integration with Existing Systems

### With Alert Router

Combine Prometheus alerts with alert-router.sh:

```bash
# In alertmanager config:
receivers:
  - name: 'code-server'
    webhook_configs:
      - url: 'http://localhost:9091/alert'
        send_resolved: true
```

### With Drift Watchdog

Metrics automatically exported from watchdog state:
- Drift counts from `/tmp/code-server-watchdog/last-drift-state`
- Container health from SSH queries
- Health status from Docker API

### With SLO Tracker

SLO metrics exported from daily JSON reports:
- Availability compliance
- Deployment success rate
- Drift-free status
- Health check pass rate

---

## Maintenance

### Regular Tasks

**Daily**:
- Monitor dashboard for anomalies
- Check SLO compliance
- Review disk usage trend

**Weekly**:
- Review Prometheus retention needs
- Verify metric collection (no gaps)
- Update dashboard if needed

**Monthly**:
- Archive old Prometheus data
- Review and adjust thresholds
- Generate compliance report

### Backup & Recovery

```bash
# Backup Prometheus data
tar -czf prometheus-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/prometheus/

# Backup Grafana configuration
tar -czf grafana-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/grafana/

# Restore if needed
tar -xzf prometheus-backup-20260430.tar.gz -C /
systemctl restart prometheus
```

---

## Advanced Customization

### Adding Custom Metrics

1. Add metric collection function to `export-prometheus-metrics.sh`
2. Format as Prometheus text format:
   ```
   # HELP metric_name Description
   # TYPE metric_name gauge
   metric_name{label="value"} 42
   ```
3. Update Prometheus scrape config
4. Add panels to Grafana dashboard

### Creating Alert Rules

```yaml
# alerts.yml
groups:
  - name: code-server
    rules:
      - alert: HighDrift
        expr: code_server_terraform_drift_resources > 5
        for: 5m
        annotations:
          summary: "High drift: {{ $value }} resources"
```

Load with:
```bash
# Append to prometheus.yml:
rule_files:
  - "alerts.yml"

# Restart Prometheus
sudo systemctl restart prometheus
```

---

## Support & Documentation

For issues or questions:
1. Check Prometheus status: `systemctl status prometheus`
2. Review logs: `journalctl -u prometheus -f`
3. Check Grafana UI for data source errors
4. Verify network connectivity between components

