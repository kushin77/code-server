# Phase 2b Monitoring & Alerting Setup Guide

## Overview
This guide provides operational team with instructions to integrate Phase 2b parity checks into monitoring and alerting systems for continuous validation.

---

## 1. Prometheus Metrics Collection

### Phase 2b Metrics to Export

Create `/etc/prometheus/phase-2b-metrics.sh` on your monitoring host:

```bash
#!/bin/bash
# Phase 2b Parity Metrics Exporter

METRICS_PORT=9901
METRICS_FILE="/tmp/phase_2b_metrics.txt"

cat > $METRICS_FILE << 'EOF'
# HELP phase_2b_parity_check_total Total number of parity checks executed
# TYPE phase_2b_parity_check_total counter
phase_2b_parity_check_total 0

# HELP phase_2b_parity_check_success_total Successful parity checks
# TYPE phase_2b_parity_check_success_total counter
phase_2b_parity_check_success_total 0

# HELP phase_2b_parity_check_failure_total Failed parity checks
# TYPE phase_2b_parity_check_failure_total counter
phase_2b_parity_check_failure_total 0

# HELP phase_2b_parity_check_duration_seconds Duration of parity check in seconds
# TYPE phase_2b_parity_check_duration_seconds gauge
phase_2b_parity_check_duration_seconds 0

# HELP phase_2b_configuration_drift Configuration drift detected (1=drift, 0=no drift)
# TYPE phase_2b_configuration_drift gauge
phase_2b_configuration_drift 0

# HELP phase_2b_gitlab_health_primary Primary GitLab health status (1=healthy, 0=unhealthy)
# TYPE phase_2b_gitlab_health_primary gauge
phase_2b_gitlab_health_primary 1

# HELP phase_2b_gitlab_health_replica Replica GitLab health status (1=healthy, 0=unhealthy)
# TYPE phase_2b_gitlab_health_replica gauge
phase_2b_gitlab_health_replica 1

# HELP phase_2b_checksum_match Configuration checksum match status (1=match, 0=mismatch)
# TYPE phase_2b_checksum_match gauge
phase_2b_checksum_match 1
EOF

python3 << 'PYTHON'
from prometheus_client import start_http_server, Gauge, Counter
import time
import subprocess
import os

# Initialize metrics
parity_check_total = Counter('phase_2b_parity_check_total', 'Total parity checks')
parity_check_success = Counter('phase_2b_parity_check_success_total', 'Successful checks')
parity_check_failure = Counter('phase_2b_parity_check_failure_total', 'Failed checks')
parity_check_duration = Gauge('phase_2b_parity_check_duration_seconds', 'Check duration')
config_drift = Gauge('phase_2b_configuration_drift', 'Drift detected')
gitlab_health_primary = Gauge('phase_2b_gitlab_health_primary', 'Primary health')
gitlab_health_replica = Gauge('phase_2b_gitlab_health_replica', 'Replica health')
checksum_match = Gauge('phase_2b_checksum_match', 'Checksum match')

def run_parity_check():
    """Execute Phase 2b parity check and update metrics"""
    start_time = time.time()
    parity_check_total.inc()
    
    try:
        result = subprocess.run(
            ['/home/akushnir/code-server/scripts/ops/check-gitlab-compose-parity.sh'],
            env={
                **os.environ,
                'PRIMARY_HOST': '192.168.168.31',
                'REPLICA_HOST': '192.168.168.42'
            },
            capture_output=True,
            timeout=60
        )
        
        duration = time.time() - start_time
        parity_check_duration.set(duration)
        
        if result.returncode == 0:
            parity_check_success.inc()
            config_drift.set(0)
            checksum_match.set(1)
            print(f"✅ Parity check passed ({duration:.2f}s)")
        else:
            parity_check_failure.inc()
            config_drift.set(1)
            checksum_match.set(0)
            print(f"❌ Parity check failed ({duration:.2f}s)")
            print(f"Error output: {result.stderr.decode()}")
    
    except subprocess.TimeoutExpired:
        parity_check_failure.inc()
        config_drift.set(1)
        print("❌ Parity check timeout")
    except Exception as e:
        parity_check_failure.inc()
        print(f"❌ Parity check error: {e}")

# Start metrics server
start_http_server(int(os.getenv('METRICS_PORT', 9901)))

# Run checks every 5 minutes
while True:
    run_parity_check()
    time.sleep(300)
PYTHON
```

### Prometheus Configuration

Add to `/etc/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'phase-2b-parity'
    static_configs:
      - targets: ['localhost:9901']
    scrape_interval: 5m
    scrape_timeout: 60s
```

---

## 2. Alert Rules

Create `/etc/prometheus/phase-2b-alerts.yml`:

```yaml
groups:
  - name: phase_2b_parity_alerts
    interval: 1m
    rules:
      # Alert: Configuration Drift Detected
      - alert: Phase2BConfigurationDrift
        expr: phase_2b_configuration_drift == 1
        for: 5m
        labels:
          severity: critical
          component: phase_2b_parity
        annotations:
          summary: "Phase 2b: Configuration drift detected"
          description: "GitLab Compose parity check failed - configuration divergence between PRIMARY and REPLICA"
          runbook_url: "https://github.com/kushin77/code-server/blob/main/FAILOVER_DRILL_RESULTS.md#troubleshooting"
          action: "Execute: scripts/ops/check-gitlab-compose-parity.sh to diagnose"

      # Alert: Checksum Mismatch
      - alert: Phase2BChecksumMismatch
        expr: phase_2b_checksum_match == 0
        for: 5m
        labels:
          severity: critical
          component: phase_2b_parity
        annotations:
          summary: "Phase 2b: Docker Compose checksum mismatch"
          description: "docker-compose.enterprise.yml checksums differ between PRIMARY and REPLICA"
          resolution: "Sync docker-compose.enterprise.yml from PRIMARY to REPLICA"

      # Alert: Primary GitLab Unhealthy
      - alert: Phase2BPrimaryGitLabUnhealthy
        expr: phase_2b_gitlab_health_primary == 0
        for: 2m
        labels:
          severity: warning
          component: phase_2b_parity
        annotations:
          summary: "Phase 2b: Primary GitLab container unhealthy"
          description: "GitLab container on PRIMARY (192.168.168.31) failed health checks"

      # Alert: Replica GitLab Unhealthy
      - alert: Phase2BReplicaGitLabUnhealthy
        expr: phase_2b_gitlab_health_replica == 0
        for: 2m
        labels:
          severity: warning
          component: phase_2b_parity
        annotations:
          summary: "Phase 2b: Replica GitLab container unhealthy"
          description: "GitLab container on REPLICA (192.168.168.42) failed health checks"

      # Alert: Parity Check Failing
      - alert: Phase2BParityCheckFailing
        expr: rate(phase_2b_parity_check_failure_total[5m]) > 0
        for: 10m
        labels:
          severity: high
          component: phase_2b_parity
        annotations:
          summary: "Phase 2b: Parity checks consistently failing"
          description: "Phase 2b parity validation has failed {{ $value | humanizePercentage }} of checks in last 5 minutes"

      # Alert: Parity Check Timeout
      - alert: Phase2BParityCheckTimeout
        expr: phase_2b_parity_check_duration_seconds > 60
        for: 1m
        labels:
          severity: high
          component: phase_2b_parity
        annotations:
          summary: "Phase 2b: Parity check taking too long"
          description: "Parity check exceeded 60 second timeout (current: {{ $value }}s)"
```

---

## 3. Grafana Dashboard

### Dashboard Configuration (JSON)

```json
{
  "dashboard": {
    "title": "Phase 2b - GitLab Compose Parity",
    "tags": ["phase-2b", "gitlab", "monitoring"],
    "timezone": "UTC",
    "panels": [
      {
        "title": "Parity Check Status",
        "targets": [
          {
            "expr": "phase_2b_checksum_match",
            "legendFormat": "Checksum Match"
          }
        ],
        "type": "stat",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {"color": "red", "value": 0},
            {"color": "yellow", "value": 0.5},
            {"color": "green", "value": 1}
          ]
        }
      },
      {
        "title": "Configuration Drift Status",
        "targets": [
          {
            "expr": "phase_2b_configuration_drift",
            "legendFormat": "Drift Detected"
          }
        ],
        "type": "stat",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {"color": "green", "value": 0},
            {"color": "red", "value": 1}
          ]
        }
      },
      {
        "title": "GitLab Container Health",
        "targets": [
          {
            "expr": "phase_2b_gitlab_health_primary",
            "legendFormat": "PRIMARY"
          },
          {
            "expr": "phase_2b_gitlab_health_replica",
            "legendFormat": "REPLICA"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Parity Check Execution Time",
        "targets": [
          {
            "expr": "phase_2b_parity_check_duration_seconds",
            "legendFormat": "Duration (seconds)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Success vs Failure Rate",
        "targets": [
          {
            "expr": "rate(phase_2b_parity_check_success_total[5m])",
            "legendFormat": "Success Rate"
          },
          {
            "expr": "rate(phase_2b_parity_check_failure_total[5m])",
            "legendFormat": "Failure Rate"
          }
        ],
        "type": "graph"
      }
    ]
  }
}
```

---

## 4. Slack/Email Notifications

### Alertmanager Configuration

Add to `/etc/alertmanager/alertmanager.yml`:

```yaml
route:
  receiver: 'phase-2b-team'
  group_by: ['alertname', 'component']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

receivers:
  - name: 'phase-2b-team'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#infrastructure-alerts'
        title: 'Phase 2b Alert'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\nDescription: {{ .Annotations.description }}\n{{ end }}'
        send_resolved: true
    email_configs:
      - to: 'ops-team@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.example.com:587'
        auth_username: 'alertmanager@example.com'
        auth_password: 'YOUR_EMAIL_PASSWORD'
        headers:
          Subject: 'Phase 2b Alert: {{ .Alerts.Firing | len }} firing'
        text: |
          {{ range .Alerts }}
          Alert: {{ .Labels.alertname }}
          Severity: {{ .Labels.severity }}
          Summary: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          {{ end }}
```

---

## 5. Log Aggregation

### Elasticsearch Configuration

Index Phase 2b logs in Elasticsearch:

```json
PUT /phase-2b-logs-*/_template/phase-2b-template
{
  "index_patterns": ["phase-2b-logs-*"],
  "mappings": {
    "properties": {
      "timestamp": {"type": "date"},
      "component": {"type": "keyword"},
      "status": {"type": "keyword"},
      "checksum_primary": {"type": "keyword"},
      "checksum_replica": {"type": "keyword"},
      "gitlab_health_primary": {"type": "keyword"},
      "gitlab_health_replica": {"type": "keyword"},
      "message": {"type": "text"}
    }
  }
}
```

### Log Forwarding (Filebeat)

Configure `/etc/filebeat/filebeat.yml`:

```yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/phase-2b/*.log
    fields:
      component: phase_2b_parity
    processors:
      - add_kubernetes_metadata: ~

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "phase-2b-logs-%{+yyyy.MM.dd}"
```

---

## 6. Deployment Health Dashboard

### Key Metrics to Monitor

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Checksum Match | 1 (match) | < 0.95 success rate |
| Configuration Drift | 0 (no drift) | Any drift detected |
| Parity Check Duration | < 30s | > 60s |
| GitLab Health (Primary) | 1 (healthy) | = 0 for 2+ min |
| GitLab Health (Replica) | 1 (healthy) | = 0 for 2+ min |
| Check Success Rate | 99%+ | < 95% |

---

## 7. Runbook: Responding to Phase 2b Alerts

### Configuration Drift Alert

**Alert:** `Phase2BConfigurationDrift`

**Symptoms:**
- Alert fires when checksums differ between PRIMARY and REPLICA
- Deployment test suite Phase 2b fails

**Steps to Resolve:**
1. Run parity check: `bash scripts/ops/check-gitlab-compose-parity.sh`
2. Identify diverged settings in output
3. Compare `docker-compose.enterprise.yml` on both hosts
4. Copy canonical version from PRIMARY to REPLICA:
   ```bash
   scp -o BatchMode=yes /path/to/docker-compose.enterprise.yml \
     akushnir@REPLICA_IP:~/code-server-enterprise/
   ```
5. Restart GitLab container on REPLICA:
   ```bash
   ssh -o BatchMode=yes akushnir@REPLICA_IP \
     "docker-compose -f docker-compose.enterprise.yml up -d gitlab"
   ```
6. Verify parity is restored: `bash scripts/ops/check-gitlab-compose-parity.sh`

### Checksum Mismatch Alert

**Alert:** `Phase2BChecksumMismatch`

**Steps to Resolve:**
1. Identify which settings differ
2. Review recent changes to `docker-compose.enterprise.yml`
3. If accidental change, revert to known-good version
4. Ensure both hosts have identical configuration
5. Verify checksums match after sync

### GitLab Unhealthy Alert

**Alert:** `Phase2BPrimaryGitLabUnhealthy` or `Phase2BReplicaGitLabUnhealthy`

**Steps to Resolve:**
1. Check container status:
   ```bash
   docker ps --filter name=code-server-gitlab --format "{{.Names}}\t{{.Status}}"
   ```
2. View logs: `docker logs code-server-gitlab | tail -50`
3. If unhealthy for > 5 min, restart:
   ```bash
   docker restart code-server-gitlab
   ```
4. Wait 60 seconds for health check to stabilize
5. Verify health status returned to "healthy"

---

## 8. Continuous Integration

### Pre-Deployment Validation

Ensure Phase 2b passes in CI/CD before allowing deployments:

```yaml
# In your CI/CD pipeline
- name: Validate Phase 2b
  run: |
    PRIMARY_HOST=192.168.168.31 REPLICA_HOST=192.168.168.42 \
      bash scripts/ops/full-deployment-test.sh --dry-run
    
    # Extract result
    RESULT=$(grep "Test Suite Result:" deployment-test-report.json | grep PASS)
    if [[ $RESULT == *"PASS/PASS/PASS/PASS/PASS/PASS"* ]]; then
      echo "✅ Phase 2b validation passed"
      exit 0
    else
      echo "❌ Phase 2b validation failed"
      exit 1
    fi
```

---

## 9. Scheduled Validation

### Nightly Parity Drill

Create cron job on monitoring host:

```bash
# /etc/cron.d/phase-2b-nightly
0 2 * * * akushnir /home/akushnir/code-server/scripts/ops/check-gitlab-compose-parity.sh >> /var/log/phase-2b/nightly-check.log 2>&1
```

### Weekly Failover Simulation

Create `/usr/local/bin/phase-2b-weekly-drill.sh`:

```bash
#!/bin/bash
set -e

echo "[$(date)] Starting weekly Phase 2b failover drill..."

cd /home/akushnir/code-server

# Run failover drill
bash scripts/ops/failover-drill.sh

if [ $? -eq 0 ]; then
  echo "[$(date)] ✅ Weekly drill passed"
  # Send success notification
  curl -X POST $SLACK_WEBHOOK -H 'Content-Type: application/json' \
    -d '{"text":"✅ Phase 2b Weekly Failover Drill: PASSED"}'
else
  echo "[$(date)] ❌ Weekly drill failed"
  # Send failure notification
  curl -X POST $SLACK_WEBHOOK -H 'Content-Type: application/json' \
    -d '{"text":"❌ Phase 2b Weekly Failover Drill: FAILED - requires investigation"}'
  exit 1
fi
```

Schedule:
```bash
# /etc/cron.d/phase-2b-weekly
0 3 * * 0 akushnir /usr/local/bin/phase-2b-weekly-drill.sh
```

---

## 10. Verification Checklist

- [ ] Prometheus scrape config added and validated
- [ ] Alert rules loaded and tested
- [ ] Alertmanager receiving alerts
- [ ] Slack notifications configured and tested
- [ ] Grafana dashboard created and accessible
- [ ] Elasticsearch index template created
- [ ] Filebeat forwarding logs successfully
- [ ] Runbooks reviewed by ops team
- [ ] Weekly drill automated and scheduled
- [ ] Team trained on Phase 2b monitoring

---

**Status:** ✅ Ready for Deployment  
**Next Steps:** Deploy monitoring infrastructure and test end-to-end alerting

