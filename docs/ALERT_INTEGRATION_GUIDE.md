# Alert Integration Guide for code-server Operational Monitoring

**Version**: 1.0  
**Date**: April 30, 2026  
**Status**: Production Ready

---

## Overview

The alert integration system provides automated notifications when operational issues are detected:
- **Drift monitoring alerts**: Terraform drift, health degradation, resource parity issues
- **SLO breach alerts**: Availability, deployment success, drift-free, and health check SLO violations
- **System alerts**: Disk space, SSH failures, Docker unavailability, Keepalived issues

Alerts can be routed to:
- **Slack**: Real-time notifications in your workspace
- **Email**: For formal records and alerts to distribution lists
- **Syslog**: Local system logging (always available)

---

## Architecture

### Alert Router Module

The alert router (`scripts/lib/alert-router.sh`) provides:
- Centralized alert routing to multiple channels
- Alert history logging
- Duplicate suppression (prevent alert fatigue)
- Alert level management (INFO, WARNING, ERROR, CRITICAL)
- Slack message formatting with colors and fields
- Email formatting with structured content

### Integration Points

1. **Drift Monitoring Watchdog** (`scripts/ops/drift-monitoring-watchdog.sh`)
   - Sends alerts for: drift increases, unhealthy containers, parity mismatches, disk space, Keepalived status

2. **SLO Metrics Tracker** (`scripts/ops/track-slo-metrics.sh`)
   - Sends alerts for: availability, deployment success, drift-free, and health check SLO breaches

3. **Systemd Timer** (`systemd/drift-monitor.timer`)
   - Automatically triggers alerting every 5 minutes

---

## Configuration

### Enable Alert Channels

Edit `.alerts/config.env` to enable desired channels:

```bash
# Enable Slack alerts
ALERT_SLACK_ENABLED=true
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Enable Email alerts
ALERT_EMAIL_ENABLED=true
EMAIL_TO="ops-team@example.com"

# Syslog alerts (always enabled by default)
ALERT_SYSLOG_ENABLED=true
```

### Set Alert Thresholds

```bash
# Drift detection
DRIFT_ALERT_THRESHOLD=5              # Alert if >5 resources drift
ALERT_ON_DRIFT_DETECTED=true

# Health monitoring
HEALTH_ALERT_THRESHOLD=1             # Alert if >1 container unhealthy
ALERT_ON_CONTAINER_UNHEALTHY=true

# Container parity
PARITY_ALERT_THRESHOLD=2             # Alert if primary/replica differ >2 containers
ALERT_ON_PARITY_MISMATCH=true

# Disk space
DISK_ALERT_THRESHOLD=80              # Alert if >80% disk used
ALERT_ON_DISK_HIGH=true

# SLO breaches
ALERT_ON_AVAILABILITY_BREACH=true
ALERT_ON_DEPLOYMENT_BREACH=true
ALERT_ON_DRIFT_FREE_BREACH=true
ALERT_ON_HEALTH_BREACH=true
```

### Prevent Alert Fatigue

Configure duplicate suppression:

```bash
# Don't re-alert for same source/title within 5 minutes
ALERT_SUPPRESS_WINDOW=300
```

---

## Setup Instructions

### 1. Slack Integration

#### Create Slack Webhook

1. Go to https://api.slack.com/apps
2. Click "Create New App"
3. Choose "From scratch"
4. Enter name (e.g., "code-server ops")
5. Select your workspace
6. In the left menu, go to "Incoming Webhooks"
7. Toggle "Activate Incoming Webhooks" to ON
8. Click "Add New Webhook to Workspace"
9. Select the channel (e.g., #ops or #alerts)
10. Authorize the app
11. Copy the Webhook URL

#### Configure Slack

```bash
# Edit .alerts/config.env
ALERT_SLACK_ENABLED=true
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX"

# Source the config
source .alerts/config.env

# Test
source scripts/lib/alert-router.sh
send_alert WARNING test-source "Test Alert" "This is a test alert"
```

### 2. Email Integration

#### Prerequisites

Your system must have a mail service installed:

```bash
# Check if mail is available
which mail

# If not, install postfix or similar
sudo apt-get update && sudo apt-get install -y postfix

# When prompted, select "Internet Site"
```

#### Configure Email

```bash
# Edit .alerts/config.env
ALERT_EMAIL_ENABLED=true
EMAIL_TO="ops@example.com"

# Or comma-separated for multiple recipients
EMAIL_TO="ops@example.com,security@example.com"

# Test
echo "test" | mail -s "test" ops@example.com

# Configure in .alerts/config.env and test
source .alerts/config.env
source scripts/lib/alert-router.sh
send_alert WARNING test-source "Test Email Alert" "This is a test email"
```

### 3. Syslog Integration

Syslog alerts are always available and logged automatically:

```bash
# View real-time alerts
journalctl -u code-server-ops -f

# View alerts from last hour
journalctl -u code-server-ops --since "1 hour ago"

# View specific severity
journalctl -u code-server-ops PRIORITY=warning

# Search for specific alert
journalctl -u code-server-ops -g "drift"
```

---

## Alert Types & Examples

### Drift Monitoring Alerts

```
[WARNING] Terraform drift increased significantly: +5 resources (2 → 7)
[WARNING] Unhealthy containers detected: 2
[WARNING] Container count mismatch: primary=50, replica=48
[WARNING] High disk usage on primary: 85%
[ERROR] Keepalived not running on primary
```

### SLO Breach Alerts

```
[WARNING] SLO Breach: Availability target=99% actual=98.5%
[WARNING] SLO Breach: Deployment Success target=95% actual=90%
[WARNING] SLO Breach: Drift-Free target=100% actual=99.8%
[WARNING] SLO Breach: Health Check target=98% actual=97%
```

### Slack Notification Example

```
code-server ops
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔶 WARNING: Terraform Drift Detected

Drift detected: 5 resources showing configuration drift

Level:    WARNING
Source:   drift-watchdog
Time:     2026-04-30 23:30:00 UTC

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Testing Alerts

### Test Individual Channels

```bash
# Source alert module
source scripts/lib/alert-router.sh

# Test WARNING alert
send_alert WARNING test-source "Test Alert" "Testing alert system"

# Test ERROR alert
send_alert ERROR test-source "Test Error" "This is a test error"

# Test with custom details
send_alert CRITICAL test-source "System Issue" "CPU high" '{"cpu": 95, "memory": 87}'
```

### Test via Drift Watchdog

```bash
# Manually trigger watchdog with alerts enabled
source .alerts/config.env
./scripts/ops/drift-monitoring-watchdog.sh

# Check alert history
tail -20 .alerts/history.log
```

### Test via SLO Tracker

```bash
# Run SLO tracker (will trigger alerts if SLOs are breached)
source .alerts/config.env
./scripts/ops/track-slo-metrics.sh
```

### Verify Syslog Recording

```bash
# Check syslog in real-time
journalctl -u code-server-ops -f &

# Trigger a test alert
source scripts/lib/alert-router.sh
send_alert WARNING test "Verify Syslog" "Testing syslog recording"

# Should appear in journalctl immediately
```

---

## Systemd Integration

Once alerts are configured, the systemd timer will automatically send alerts:

```bash
# Check timer status
systemctl status drift-monitor.timer

# View recent watchdog execution with alerts
journalctl -u drift-monitor.service -n 50

# Follow real-time output
journalctl -u drift-monitor.service -f
```

---

## Alert History & Querying

### View Alert History

```bash
# View all alerts from last hour
./scripts/lib/alert-router.sh
source .alerts/config.env
source scripts/lib/alert-router.sh
query_alerts 60      # Last 60 minutes

# View only WARNING alerts from last 24 hours
query_alerts 1440 WARNING

# View only CRITICAL alerts
query_alerts 1440 CRITICAL
```

### Alert Statistics

```bash
# Get alert count summary for last 24 hours
source scripts/lib/alert-router.sh
alert_stats 1440

# Example output:
# {"info": 24, "warning": 3, "error": 0, "critical": 0}
```

---

## Troubleshooting

### Alerts Not Sending to Slack

**Problem**: Webhook configured but alerts not appearing in Slack

**Solutions**:
1. Verify webhook URL is correct
   ```bash
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"test"}' "$SLACK_WEBHOOK_URL"
   ```

2. Check alert routing is enabled
   ```bash
   source .alerts/config.env
   echo $ALERT_SLACK_ENABLED  # Should print: true
   ```

3. Verify webhook is still valid (regenerate if needed):
   - Check in Slack workspace app settings
   - Delete and recreate if expired

### Emails Not Sending

**Problem**: EMAIL_TO configured but emails not arriving

**Solutions**:
1. Test mail command directly
   ```bash
   echo "test" | mail -s "test subject" your-email@example.com
   ```

2. Check mail service is running
   ```bash
   systemctl status postfix
   sudo systemctl start postfix  # if not running
   ```

3. Check mail logs for errors
   ```bash
   tail -f /var/log/mail.log
   tail -f /var/log/syslog | grep postfix
   ```

4. Verify bounce handling (some email systems reject)
   - Check spam folder
   - Ask email admin to whitelist sender

### Too Many Duplicate Alerts

**Problem**: Same alert appearing multiple times

**Solutions**:
1. Increase suppression window
   ```bash
   ALERT_SUPPRESS_WINDOW=600  # 10 minutes instead of 5
   ```

2. Disable certain alert types
   ```bash
   ALERT_ON_DRIFT_DETECTED=false      # Only alert on increases
   ALERT_ON_CONTAINER_HEALTHY=false   # Only alert on failures
   ```

3. Increase thresholds
   ```bash
   DRIFT_ALERT_THRESHOLD=10           # Only alert if >10 resources
   HEALTH_ALERT_THRESHOLD=3           # Only alert if >3 unhealthy
   ```

### Syslog Alerts Not Appearing

**Problem**: Alerts not appearing in `journalctl`

**Solutions**:
1. Verify syslog is enabled
   ```bash
   source .alerts/config.env
   echo $ALERT_SYSLOG_ENABLED  # Should print: true
   ```

2. Check journalctl can see logs
   ```bash
   journalctl -u code-server-ops
   ```

3. Check `systemd-journald` is running
   ```bash
   systemctl status systemd-journald
   ```

---

## Alert Response Procedures

When you receive an alert, follow these steps:

### Upon Receiving a Drift Alert

1. Log into primary host
   ```bash
   ssh akushnir@192.168.168.31
   ```

2. Check current drift status
   ```bash
   cd ~/code-server/terraform/environments/private
   terraform plan -json | jq 'select(.type == "resource_drift")'
   ```

3. Identify drifted resources and remediate:
   - Manual drift: Update Terraform to match actual state
   - Configuration issue: Fix the resource configuration
   - Unknown drift: Review resource logs

4. Re-apply if needed
   ```bash
   terraform apply
   ```

### Upon Receiving a Health Alert

1. Check container status
   ```bash
   ssh akushnir@192.168.168.31
   docker ps --format "table {{.Names}}\t{{.Status}}"
   ```

2. Identify unhealthy containers
   ```bash
   docker inspect <container_id> | jq '.[].State.Health'
   ```

3. Review logs
   ```bash
   docker logs <container_id>
   ```

4. Restart if needed
   ```bash
   docker restart <container_id>
   ```

### Upon Receiving an SLO Breach Alert

1. Check SLO metrics
   ```bash
   ./scripts/ops/track-slo-metrics.sh
   ```

2. Review specific SLO data
   ```bash
   cat .metrics/slo-report-$(date +%Y%m%d).json | jq '.metrics'
   ```

3. Take corrective action based on SLO type:
   - Availability: Check host uptime and container restarts
   - Deployment Success: Review failed deployments
   - Drift-Free: Run drift detection and remediate
   - Health Check: Check container health logs

---

## Integration Checklist

- [ ] Load `.alerts/config.env` configuration
- [ ] Set `ALERT_SLACK_ENABLED=true` if using Slack
- [ ] Configure `SLACK_WEBHOOK_URL` with valid webhook
- [ ] Set `ALERT_EMAIL_ENABLED=true` if using email
- [ ] Configure `EMAIL_TO` with recipient email(s)
- [ ] Test Slack alerts: `send_alert WARNING test "Test" "message"`
- [ ] Test email alerts: `echo "test" | mail -s "test" $EMAIL_TO`
- [ ] Test syslog alerts: verify `journalctl -u code-server-ops` shows alerts
- [ ] Deploy systemd timer: `sudo ./scripts/ops/setup-drift-monitoring.sh`
- [ ] Verify timer is active: `systemctl status drift-monitor.timer`
- [ ] Review alert history: `source scripts/lib/alert-router.sh && query_alerts 60`
- [ ] Document alert response procedures for ops team
- [ ] Train team on alert types and responses
- [ ] Set up on-call rotation for alerts

---

## Next Steps

1. **Configure your preferred alert channel** (Slack or Email)
2. **Test alerts** using the test procedures
3. **Deploy systemd timer** to enable 24/7 monitoring
4. **Monitor for 7 days** to verify alert quality
5. **Adjust thresholds** based on alert volume
6. **Document team procedures** for responding to each alert type
7. **Schedule team training** on alert system and procedures

---

## Support & Maintenance

For alert system issues:

1. Check alert history
   ```bash
   source scripts/lib/alert-router.sh
   tail -50 "$ALERT_HISTORY"
   ```

2. Review alert module
   ```bash
   cat scripts/lib/alert-router.sh
   ```

3. Test alert routing directly
   ```bash
   source scripts/lib/alert-router.sh
   send_alert CRITICAL test "Direct Test" "Testing alert routing"
   ```

4. Check systemd service logs
   ```bash
   journalctl -u drift-monitor.service -n 50
   ```

