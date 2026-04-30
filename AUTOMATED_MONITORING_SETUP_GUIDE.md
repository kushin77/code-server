# AUTOMATED MONITORING & ALERTING SETUP GUIDE

**Date:** April 30, 2026 | **Status:** READY FOR DEPLOYMENT | **Audience:** DevOps/Operations

---

## Overview

This guide sets up automated real-time monitoring and alerting for all 10 SLAs, enabling the Operations team to detect and respond to issues proactively rather than reactively.

---

## Quick Setup (30 minutes)

### 1. Start Background Health Monitor
```bash
# Run in tmux/screen session (never stops)
cd /home/akushnir/code-server
tmux new-session -d -s hermes-monitor
tmux send-keys -t hermes-monitor './monitor-health.sh 10 86400' Enter

# Verify monitoring started
tmux list-sessions | grep hermes-monitor
# Output: hermes-monitor: 1 windows (created...)
```

### 2. Configure Monitoring Alerts
```bash
# Edit monitoring alert thresholds
cat > monitoring-config.env << 'EOF'
# Alert Thresholds
CPU_WARNING=60
CPU_CRITICAL=85
MEMORY_WARNING=70
MEMORY_CRITICAL=90
DISK_WARNING=70
DISK_CRITICAL=85
ERROR_RATE_WARNING=1
ERROR_RATE_CRITICAL=5
RESPONSE_TIME_WARNING=1000
RESPONSE_TIME_CRITICAL=2000
EOF

# Load config
source monitoring-config.env
echo "✅ Monitoring config loaded"
```

### 3. Setup Slack Notifications
```bash
# Configure Slack webhook for alerts
cat > alert-slack.sh << 'EOF'
#!/bin/bash
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
MESSAGE=$1
SEVERITY=$2

curl -X POST "$SLACK_WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d "{
    \"text\": \"[$SEVERITY] $MESSAGE\",
    \"color\": $([ \"$SEVERITY\" = \"CRITICAL\" ] && echo '\"danger\"' || echo '\"warning\"')
  }"
EOF

chmod +x alert-slack.sh
echo "✅ Slack alerting configured"
```

### 4. Create Monitoring Cron Job
```bash
# Add to crontab
crontab -e

# Add these lines:
# Every 5 minutes: Check system health
*/5 * * * * /home/akushnir/code-server/check-health-and-alert.sh

# Every 15 minutes: Check SLAs
*/15 * * * * /home/akushnir/code-server/check-slas-and-alert.sh

# Every hour: Generate metrics report
0 * * * * /home/akushnir/code-server/generate-metrics-report.sh
```

---

## SLA Monitoring Configuration

### SLA 1: System Uptime (Target: 99.9%)

**Measurement:**
```bash
# Calculate uptime from container logs
docker stats --no-stream --format '{{.Container}}\t{{.Status}}' | \
  grep -c "Up"

# Count: Should be 5/5 (100% healthy)
```

**Alert Conditions:**
```
WARNING:  When any container is down
CRITICAL: When >1 container down OR any service not responding
```

**Response:**
```bash
# Check health
docker ps | grep -E "code-server-|appsmith|redis|postgres"

# Restart if needed
docker-compose -f docker-compose.enterprise.yml restart <service>

# If still down, escalate to DevOps
```

### SLA 2: API Response Time (Target: <500ms)

**Measurement:**
```bash
# Test API response time
time curl -k https://kushnir.cloud/api/hermes/health

# Extract time: Look for "real" time output
# Expected: <500ms
```

**Alert Conditions:**
```
WARNING:  When response time 500-1000ms
CRITICAL: When response time >1000ms
```

**Response:**
```bash
# Check service logs
docker logs hermes-integration | tail -50

# Check resource usage
docker stats --no-stream hermes-integration

# If CPU/memory high, escalate to DevOps
```

### SLA 3: Error Rate (Target: <0.1%)

**Measurement:**
```bash
# Check error rate from logs
docker logs hermes-integration --since 1h | \
  grep -i "error\|exception" | wc -l

# Count errors and divide by total requests
# Calculate: (error count) / (total requests) * 100
```

**Alert Conditions:**
```
WARNING:  When error rate 0.1-1%
CRITICAL: When error rate >1%
```

**Response:**
```bash
# Get recent errors
docker logs hermes-integration --since 30m | grep -i "error"

# Analyze pattern
# If systematic: Escalate to development
# If temporary: Monitor and close
```

### SLA 4: Container Health (Target: 100%)

**Measurement:**
```bash
# Count healthy containers
docker ps --filter "health=healthy" | wc -l
# Should equal 5 (or count in docker-compose)

# List unhealthy
docker ps --filter "health=unhealthy"
```

**Alert Conditions:**
```
WARNING:  When any container starting/restarting
CRITICAL: When any container unhealthy or down
```

**Response:**
```bash
# Check specific container
docker ps -a | grep <container-name>

# Get logs
docker logs <container-name> | tail -100

# If corrupted: Restore from backup
./backup-recovery.sh restore <backup-id>
```

### SLA 5: Database Latency (Target: <1ms)

**Measurement:**
```bash
# Test database latency
docker exec code-server-postgres \
  psql -U purebliss_user -d purebliss_db \
  -c "SELECT pg_sleep(0); SELECT 1;"

# Expected: Query completes in <1ms
```

**Alert Conditions:**
```
WARNING:  When latency 1-5ms
CRITICAL: When latency >5ms
```

**Response:**
```bash
# Check database status
docker exec code-server-postgres \
  psql -U purebliss_user -d purebliss_db \
  -c "SELECT 1;"

# Check replication status
docker exec code-server-postgres \
  psql -U purebliss_user -d purebliss_db \
  -c "SELECT * FROM pg_stat_replication;"

# If lag detected, escalate to DevOps
```

### SLA 6: Memory Utilization (Target: <70%)

**Measurement:**
```bash
# Get memory usage
docker stats --no-stream --format \
  "table {{.Container}}\t{{.MemPerc}}" | \
  awk '{sum+=$2} END {print sum"%"}'

# Expected: <70% of total
```

**Alert Conditions:**
```
WARNING:  When memory 70-80%
CRITICAL: When memory >80%
```

**Response:**
```bash
# Identify high-memory services
docker stats --no-stream | sort -k4 -rn | head -3

# If database high:
docker exec code-server-postgres \
  vacuumdb -U purebliss_user purebliss_db

# If app high:
docker-compose -f docker-compose.enterprise.yml restart appsmith

# Monitor recovery
watch -n 2 'docker stats --no-stream'
```

### SLA 7: CPU Utilization (Target: <60%)

**Measurement:**
```bash
# Get CPU usage
docker stats --no-stream --format \
  "table {{.Container}}\t{{.CPUPerc}}" | \
  awk '{sum+=$2} END {print sum}'

# Expected: <60% of available CPU
```

**Alert Conditions:**
```
WARNING:  When CPU 60-75%
CRITICAL: When CPU >75%
```

**Response:**
```bash
# Identify high-CPU services
docker stats --no-stream | sort -k3 -rn | head -3

# Check for runaway processes
docker top <service> aux

# Restart if needed
docker-compose -f docker-compose.enterprise.yml restart <service>

# If persists, escalate to DevOps
```

### SLA 8: Disk Utilization (Target: <70%)

**Measurement:**
```bash
# Check disk usage
df -h /home | awk 'NR==2 {print $5}'

# Expected: <70% full (>20GB free)
```

**Alert Conditions:**
```
WARNING:  When disk 70-80%
CRITICAL: When disk >80%
```

**Response:**
```bash
# Identify large files
du -sh /* | sort -h | tail -10

# Clean old logs
rm -rf deployment-reports/*.text
docker system prune -a

# Check disk again
df -h /home

# If still high, escalate to DevOps
```

### SLA 9: Backup Freshness (Target: <24 hours)

**Measurement:**
```bash
# Check last backup
ls -lt backup-* | head -1 | awk '{print $6, $7, $8}'

# Expected: Today's date (within last 24 hours)
```

**Alert Conditions:**
```
WARNING:  When last backup >24 hours old
CRITICAL: When last backup >36 hours old
```

**Response:**
```bash
# Run backup if needed
./backup-recovery.sh backup

# Verify backup
./backup-recovery.sh list | head -1

# Expected: Current timestamp, size >100MB
```

### SLA 10: External Connectivity (Target: 100%)

**Measurement:**
```bash
# Test external connectivity
curl -k https://kushnir.cloud/ --max-time 5

# Expected: 200/301/302 response code
```

**Alert Conditions:**
```
WARNING:  When response time >2000ms
CRITICAL: When no response or timeout
```

**Response:**
```bash
# Check if port is open
curl -v -k https://kushnir.cloud/ 2>&1 | head -20

# Check Caddyfile status
docker exec nginx-reverse-proxy \
  nginx -t

# If error, reload:
docker exec nginx-reverse-proxy \
  nginx -s reload

# If still down, escalate to DevOps
```

---

## Automated Alert Script

Create this script to check all SLAs and send alerts:

```bash
#!/bin/bash
# check-slas-and-alert.sh

source monitoring-config.env

# Function to send alert
send_alert() {
  local severity=$1
  local message=$2
  
  # Send to Slack
  ./alert-slack.sh "$message" "$severity"
  
  # Log locally
  echo "[$(date)] $severity: $message" >> sla-alerts.log
}

# SLA 1: Uptime
health_count=$(docker stats --no-stream --format '{{.Container}}\t{{.Status}}' | grep -c "Up")
if [ $health_count -lt 5 ]; then
  send_alert "CRITICAL" "Only $health_count/5 containers healthy"
fi

# SLA 2: Response Time
response_time=$(curl -k https://kushnir.cloud/api/hermes/health --max-time 5 2>&1 | grep "time_total" | cut -d: -f2)
if (( $(echo "$response_time > 1000" | bc -l) )); then
  send_alert "CRITICAL" "API response time: ${response_time}ms (target: <500ms)"
elif (( $(echo "$response_time > 500" | bc -l) )); then
  send_alert "WARNING" "API response time: ${response_time}ms (target: <500ms)"
fi

# SLA 3-10: Add similar checks for each SLA

echo "[$(date)] SLA checks completed"
```

---

## Monitoring Dashboard Setup

### Option 1: Simple Text Dashboard
```bash
#!/bin/bash
# Run in terminal for real-time monitoring

watch -n 5 'echo "=== HERMES AGENT PORTAL MONITORING ===" && \
echo "" && \
echo "CONTAINERS:" && \
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.CPUPerc}}\t{{.MemPerc}}" && \
echo "" && \
echo "DISK:" && \
df -h /home && \
echo "" && \
echo "API:" && \
curl -k --max-time 2 https://kushnir.cloud/api/hermes/health 2>/dev/null'
```

### Option 2: Logging to File
```bash
# Create continuous log
while true; do
  {
    echo "=== $(date) ==="
    echo "Containers: $(docker ps --format 'table {{.Names}}\t{{.Status}}' | wc -l)"
    echo "CPU: $(docker stats --no-stream --format '{{.CPUPerc}}' --all | grep -o '[0-9.]*' | awk '{sum+=$1} END {print sum}')%"
    echo "Memory: $(docker stats --no-stream --format '{{.MemPerc}}' --all | grep -o '[0-9.]*' | awk '{sum+=$1} END {print sum}')%"
    echo "Disk: $(df -h /home | awk 'NR==2 {print $5}')"
    echo ""
  } >> monitoring.log
  
  sleep 300  # Log every 5 minutes
done
```

---

## Manual Monitoring Commands (Quick Reference)

```bash
# Everything at once
docker stats --no-stream && \
docker ps && \
df -h /home && \
curl -k https://kushnir.cloud/api/hermes/health

# Just health check
curl -k https://kushnir.cloud/api/hermes/health

# All container status
docker ps -a

# Specific service logs
docker logs hermes-integration | tail -50

# Database status
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;"

# Memory and CPU
docker stats --no-stream

# Disk space
df -h /home
```

---

## Monitoring Best Practices

1. **Check Often, Act Fast**
   - Monitor every 5-15 minutes during business hours
   - Any warning = investigate immediately
   - Any critical = escalate within 5 minutes

2. **Document Everything**
   - Log all alerts and responses
   - Note time, action taken, outcome
   - Use for trend analysis

3. **Trend Analysis**
   - Review weekly: Is memory growing?
   - Review weekly: Are errors increasing?
   - Review weekly: Is response time degrading?

4. **Proactive Maintenance**
   - Run optimization weekly: `./optimize-performance.sh optimize`
   - Clean logs monthly: `docker system prune -a`
   - Backup daily: `./backup-recovery.sh backup`

5. **Communication**
   - Alert team immediately of any P1 issue
   - Update status page if service down
   - Send daily summary at end of shift

---

## Troubleshooting Monitoring Issues

### Monitoring Script Not Running
```bash
# Check if tmux session still active
tmux list-sessions | grep hermes-monitor

# If not found, restart
tmux new-session -d -s hermes-monitor './monitor-health.sh 10 86400'
```

### Alerts Not Sending
```bash
# Test Slack webhook
curl -X POST "$SLACK_WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test alert"}'

# Check Slack webhook URL is correct in alert-slack.sh
cat alert-slack.sh | grep SLACK_WEBHOOK
```

### High False Positive Rate
```bash
# Adjust thresholds in monitoring-config.env
# Make them more realistic based on baseline

# Check baseline before any alert
docker stats --no-stream
df -h /home
```

---

## Monitoring Checklist (Daily)

- [ ] 09:00 - Start monitoring session
- [ ] 09:15 - Verify all 5 containers healthy
- [ ] 12:00 - Check SLA targets all on track
- [ ] 15:00 - Review error logs for patterns
- [ ] 17:00 - Generate end-of-day report
- [ ] 17:30 - Archive logs for analysis
- [ ] 18:00 - Brief team on any issues

---

**Status:** ✅ READY FOR IMPLEMENTATION

Set up automated monitoring in 30 minutes using this guide to enable proactive issue detection and response.
