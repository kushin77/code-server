# Healthcheck Event Streaming - Operational Guide
**Phase 2.2: Centralized Health Monitoring via Loki**

---

## Overview

The Healthcheck Event Streamer polls container health states at regular intervals and streams state transitions, restarts, and failures to Loki for centralized logging, querying, and alerting.

**Key Features:**
- Real-time health state transition detection (healthy ↔ unhealthy)
- Restart event capture (restart_count increases)
- Loki integration for historical querying
- Stateful tracking (only streams on changes, not duplicate logs)
- Configurable polling intervals and Loki endpoints

---

## Deployment Options

### Option 1: Systemd Service (Recommended)

**Setup:**
```bash
# 1. Copy healthcheck event streamer to both hosts
ssh akushnir@192.168.168.31 "mkdir -p ~/code-server-enterprise/scripts && scp healthcheck-event-streamer.sh ..."
ssh akushnir@192.168.168.42 "mkdir -p ~/code-server-enterprise/scripts && scp healthcheck-event-streamer.sh ..."

# 2. Create systemd unit file (on each host)
cat > /etc/systemd/system/healthcheck-monitor.service << 'EOF'
[Unit]
Description=Healthcheck Event Streamer for Docker Containers
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=akushnir
WorkingDirectory=/home/akushnir/code-server-enterprise
ExecStart=/home/akushnir/code-server-enterprise/scripts/healthcheck-event-streamer.sh --interval 30 --loki-url http://code-server-loki:3100/loki/api/v1/push
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 3. Enable and start
sudo systemctl daemon-reload
sudo systemctl enable healthcheck-monitor.service
sudo systemctl start healthcheck-monitor.service

# 4. Verify running
sudo systemctl status healthcheck-monitor.service
journalctl -u healthcheck-monitor -f
```

**Service Lifecycle:**
```bash
# View service logs
journalctl -u healthcheck-monitor -f

# Restart service
sudo systemctl restart healthcheck-monitor

# Stop service
sudo systemctl stop healthcheck-monitor

# Check status
sudo systemctl status healthcheck-monitor
```

### Option 2: Cron Job (Lightweight Alternative)

**Setup:**
```bash
# Add to crontab on each host
crontab -e

# Add this line to run streamer every minute
* * * * * /home/akushnir/code-server-enterprise/scripts/healthcheck-event-streamer.sh --interval 1 --loki-url http://code-server-loki:3100/loki/api/v1/push >> /var/log/healthcheck-monitor.log 2>&1
```

**Limitations:**
- Polling interval limited to 1 minute (cron minimum)
- Less real-time than systemd service
- Less reliable for rapid state transitions

### Option 3: Manual/Docker Compose

**In docker-compose.enterprise.yml:**
```yaml
healthcheck-monitor:
  image: python:3.11-slim
  command: |
    sh -c "
    apt-get update && apt-get install -y curl jq >/dev/null 2>&1
    while true; do
      /app/healthcheck-event-streamer.sh --interval 30 --loki-url http://loki:3100/loki/api/v1/push
    done
    "
  volumes:
    - ./scripts/healthcheck-event-streamer.sh:/app/healthcheck-event-streamer.sh:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
  depends_on:
    - loki
```

---

## Loki Query Examples

### Basic Queries

**1. View all healthcheck events:**
```
{job="healthcheck-monitor"}
```

**2. Events for a specific service:**
```
{job="healthcheck-monitor", service="code-server-vault"}
```

**3. Only status transitions:**
```
{job="healthcheck-monitor"} | json | pattern `STATUS_TRANSITION`
```

**4. Unhealthy services:**
```
{job="healthcheck-monitor", status="unhealthy"}
```

**5. Restart events:**
```
{job="healthcheck-monitor"} | json | pattern `RESTART_DETECTED`
```

### Advanced Queries

**1. Services that have restarted in the last hour:**
```
{job="healthcheck-monitor"} | json | pattern `RESTART_DETECTED` | __timestamp__ > now - 1h
```

**2. Health transitions (state changes):**
```
{job="healthcheck-monitor"} | json | pattern `STATUS_TRANSITION`
```

**3. Count unhealthy events per service (last 30 minutes):**
```
{job="healthcheck-monitor", status="unhealthy"} | json | __timestamp__ > now - 30m | group by service
```

**4. Rate of health state changes:**
```
rate({job="healthcheck-monitor"} | json | pattern `STATUS_TRANSITION` [5m])
```

**5. Services with recovery events (went from unhealthy to healthy):**
```
{job="healthcheck-monitor"} | json | pattern `RECOVERED`
```

### Dashboard Panels (in Grafana)

**1. Health Timeline**
```
{job="healthcheck-monitor"} | json | service, status
```

**2. Event Log Table**
```
{job="healthcheck-monitor"} | json
```

**3. Service Status Heatmap**
```
{job="healthcheck-monitor", host="primary"} | json | status | group by service
```

---

## Alerting Rules

### Prometheus Rules (save to `prometheus/healthcheck-alerts.yml`)

```yaml
groups:
  - name: healthcheck_alerts
    interval: 30s
    rules:
      # Alert if service unhealthy for 2+ minutes
      - alert: ContainerUnhealthy
        expr: |
          count({job="healthcheck-monitor", status="unhealthy"}) by (service) > 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.service }} is unhealthy"
          description: "Service {{ $labels.service }} has been unhealthy for over 2 minutes"

      # Alert on rapid restarts (>5 in 10 minutes)
      - alert: RapidRestarts
        expr: |
          increase({job="healthcheck-monitor"} | json | pattern `RESTART_DETECTED` [10m]) > 5
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.service }} restarting rapidly"
          description: "{{ $labels.service }} has restarted 5+ times in 10 minutes"
```

---

## Performance Considerations

### Impact on System

- **CPU:** Minimal (1-2% per polling cycle)
- **Memory:** ~50MB for streamer process
- **Network:** ~1-2KB per poll cycle to Loki
- **Disk:** Loki storage depends on retention policy

### Optimization

**Increase poll interval if resources constrained:**
```bash
./scripts/healthcheck-event-streamer.sh --interval 60  # Every 60 seconds instead of 30
```

**Filter containers to reduce volume:**
```bash
# Modify script to only monitor critical services:
get_containers_with_healthchecks() {
  for svc in vault postgres redis loki appsmith; do
    docker ps --format '{{.Names}}' | grep "code-server-$svc"
  done
}
```

**Adjust Loki retention:**
```yaml
# In loki-config.yml
limits_config:
  retention_period: 168h  # Keep 7 days of logs
```

---

## Troubleshooting

### Events Not Appearing in Loki

**Check 1: Service is running**
```bash
sudo systemctl status healthcheck-monitor
journalctl -u healthcheck-monitor -n 20
```

**Check 2: Loki connectivity**
```bash
docker exec code-server-loki curl -v http://localhost:3100/loki/api/v1/push
# Should return 204 No Content
```

**Check 3: Run with debug enabled**
```bash
./scripts/healthcheck-event-streamer.sh --debug --interval 10
```

**Check 4: Verify containers exist**
```bash
docker ps --format '{{.Names}}' | grep code-server- | wc -l
# Should be > 0
```

### High Volume of Events

**Symptom:** Too many health state transitions in logs

**Solution:** Increase health check start_period in docker-compose (let containers stabilize before polling)
```yaml
healthcheck:
  start_period: 60s  # Give more time before first check
  interval: 30s
  timeout: 10s
  retries: 3
```

### Loki Connection Refused

**Symptom:** "Connection refused" errors

**Check:** Loki is accessible from host
```bash
curl -v http://code-server-loki:3100/loki/api/v1/push

# If DNS fails, use IP:
curl -v http://172.20.0.9:3100/loki/api/v1/push  # Adjust IP as needed
```

---

## Testing

### Dry-Run Mode

Test without sending to Loki:
```bash
./scripts/healthcheck-event-streamer.sh --dry-run --debug --interval 5
```

Expected output:
```
[09:27:21] Healthcheck Event Streamer started
[09:27:21] Configuration:
[09:27:21]   Loki URL: http://localhost:3100/loki/api/v1/push
[09:27:21]   Poll interval: 5s
[DEBUG] Poll cycle at 09:27:26
[OK] [code-server-vault] Healthy (no change)
[DRY-RUN] Would send to Loki: {...}
```

### Trigger a Health Transition

Manually restart a container to verify event capture:
```bash
# Terminal 1: Watch events
./scripts/healthcheck-event-streamer.sh --debug --interval 5

# Terminal 2: Restart a container
docker restart code-server-vault

# Should see in Terminal 1:
# [STATUS_TRANSITION] starting → healthy
```

---

## Integration with CI/CD

### GitHub Actions Example

```yaml
# .github/workflows/health-check.yml
name: Verify Container Health

on: [push, pull_request]

jobs:
  health-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run healthcheck monitor (dry-run)
        run: |
          chmod +x scripts/healthcheck-event-streamer.sh
          timeout 30 ./scripts/healthcheck-event-streamer.sh --dry-run --debug || true
      
      - name: Query Loki for anomalies
        run: |
          # After deployment, verify no unhealthy events in last 5 minutes
          curl "http://loki:3100/loki/api/v1/query" \
            -G --data-urlencode 'query={job="healthcheck-monitor",status="unhealthy"}' \
            | jq '.data.result | length' | grep -q "^0$"
```

---

## Maintenance

### Update Loki URL

If Loki moves to different host/port:
```bash
# Update systemd unit
sudo systemctl edit healthcheck-monitor

# Change ExecStart line to new URL, then:
sudo systemctl daemon-reload
sudo systemctl restart healthcheck-monitor
```

### Rotate Logs

Loki automatically manages retention. To adjust:
```yaml
# In loki-config.yml under limits_config:
retention_period: 168h  # 7 days
retention_stream:
  - selector: '{job="healthcheck-monitor"}'
    period: 30d  # Keep healthcheck logs longer
```

---

## Next Steps (Phase 2.3)

Once healthcheck event streaming is operational, Phase 2.3 will implement **Staged Rollout Procedures**:
- Canary → Replica → Primary deployment gates
- Automated health checks between stages
- Rollback procedures

---

## References

- [Loki Documentation](https://grafana.com/docs/loki/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Docker Healthchecks](https://docs.docker.com/compose/compose-file/compose-file-v3/#healthcheck)
- [Healthcheck Patterns](../docs/operations/HEALTHCHECK-PATTERNS.md)

---
