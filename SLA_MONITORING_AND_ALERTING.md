# SLA Monitoring & Alerting Implementation Guide

**Date:** April 30, 2026  
**Version:** 1.0  
**Purpose:** Complete implementation of 10-point SLA monitoring for production operations  
**Timeline:** Implementation on May 2, 2026 | First 24-hour monitoring May 1-3

---

## SLA Framework Overview

### The 10 SLAs

| # | SLA | Target | Warning | Critical | Metric Unit |
|---|-----|--------|---------|----------|-------------|
| 1 | System Uptime | 99.9% | 99.5% | 99.0% | Percentage (%) |
| 2 | API Response Time | <500ms | 1000ms | 2000ms | Milliseconds |
| 3 | Memory Utilization | <70% | 80% | 90% | Percentage (%) |
| 4 | CPU Utilization | <60% | 75% | 85% | Percentage (%) |
| 5 | Disk Utilization | <70% | 80% | 90% | Percentage (%) |
| 6 | Error Rate | <0.1% | 1% | 5% | Percentage (%) |
| 7 | Database Latency | <1ms | 5ms | 10ms | Milliseconds |
| 8 | Container Health | 100% critical | 95% | 85% | Percentage (%) |
| 9 | Backup Freshness | <24h | 36h | 48h | Hours |
| 10 | External Connectivity | 100% | 95% | 90% | Percentage (%) |

---

## Monitoring Infrastructure Setup

### Option 1: Manual Monitoring (Recommended for May 2-3)

**Implementation:** Use existing automation scripts

```bash
# Real-time monitoring
./monitor-health.sh 30 3600  # Every 30 seconds for 1 hour

# Daily validation
./validate-deployment.sh     # Generate daily report

# Metrics collection
./optimize-performance.sh analyze  # Performance baseline

# Weekly reporting
./optimize-performance.sh report   # Weekly summary
```

### Option 2: Docker-Based Prometheus (Post-deployment Option)

**For future enhancement: Automated metrics collection**

```yaml
# docker-compose-monitoring.yml
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - prometheus-data:/prometheus
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
    depends_on:
      - prometheus
```

### Option 3: Cloud-Based Monitoring

**For future: Datadog, New Relic, or CloudWatch**

---

## SLA 1: System Uptime (Target: 99.9%)

### Definition
Percentage of time all 8 critical services are operational and responding to health checks.

### Measurement
```bash
# Automated tracking
./monitor-health.sh 60 86400  # 24-hour monitoring

# Manual calculation
UPTIME_PERCENT = (Healthy_Intervals / Total_Intervals) * 100
```

### Success Criteria
- Uptime > 99.9% (acceptable downtime: 43 seconds/day)
- All 8 critical services: Healthy
- Services responding within 5 seconds

### Alert Triggers
- ⚠️ Warning: Uptime < 99.5%
- 🚨 Critical: Uptime < 99.0%

### Response Procedure
```bash
# If service down:
1. Check logs: docker logs <service> | tail -50
2. Restart: docker-compose restart <service>
3. Verify: curl -k https://kushnir.cloud/api/hermes/health
4. Monitor: ./monitor-health.sh 10 300
5. Document: Log incident and resolution time
```

---

## SLA 2: API Response Time (Target: <500ms)

### Definition
99th percentile of API request response times across all endpoints.

### Measurement
```bash
# Automated tracking
curl -s -w "@-" -o /dev/null https://kushnir.cloud/api/hermes/health <<EOF
Response-Time: %{time_total}s
HTTP-Code: %{http_code}
EOF

# Script collection
#!/bin/bash
for i in {1..100}; do
    RESPONSE_TIME=$(curl -s -w "%{time_total}" -o /dev/null https://kushnir.cloud/api/hermes/health)
    echo "$RESPONSE_TIME" >> response-times.txt
done
# Calculate 99th percentile
sort -n response-times.txt | tail -1
```

### Success Criteria
- 99th percentile response: < 500ms
- Average response: < 300ms
- P95 response: < 400ms

### Alert Triggers
- ⚠️ Warning: Average > 1000ms
- 🚨 Critical: Average > 2000ms

### Response Procedure
```bash
# If response time high:
1. Check API logs: docker logs hermes-integration | tail -50
2. Check database: docker logs code-server-postgres | tail -50
3. Monitor resources: docker stats --no-stream
4. If high CPU: Restart services
5. If high memory: Run ./optimize-performance.sh optimize
6. Verify: Re-run response time tests
7. Document: Log performance issue and fix
```

---

## SLA 3: Memory Utilization (Target: <70%)

### Definition
Percentage of total available memory currently in use.

### Measurement
```bash
# Real-time monitoring
docker stats --no-stream --format "{{.Container}}\t{{.MemPerc}}"

# Parse percentage
MEMORY_PERCENT=$(docker stats --no-stream appsmith | awk '{print $NF}' | sed 's/%//')

# Threshold check
if [ "$MEMORY_PERCENT" -gt 70 ]; then
    echo "ALERT: Memory > 70%"
fi
```

### Success Criteria
- Overall memory usage: < 70%
- Per-service: < 85%
- Trend: Stable (not growing)

### Alert Triggers
- ⚠️ Warning: Memory > 80%
- 🚨 Critical: Memory > 90%

### Response Procedure
```bash
# If memory high:
1. Check which services: docker stats --no-stream
2. For Appsmith: Usually needs restart
   docker-compose restart appsmith
3. For API: Check for memory leaks
   docker logs hermes-integration | grep -i "memory\|gc"
4. For Database: Optimize queries
   docker exec code-server-postgres vacuumdb -U purebliss_user
5. Clear cache: docker exec code-server-redis redis-cli FLUSHALL
6. Monitor: Watch for 10 minutes
7. If not resolved: Escalate to architecture team
```

---

## SLA 4: CPU Utilization (Target: <60%)

### Definition
Percentage of CPU capacity currently in use.

### Measurement
```bash
# Real-time monitoring
docker stats --no-stream --format "{{.Container}}\t{{.CPUPerc}}"

# Average over time
#!/bin/bash
for i in {1..60}; do
    docker stats --no-stream --format "{{.CPUPerc}}" | sed 's/%//' | \
    awk '{sum+=$1} END {print "CPU Average: " sum/NR "%"}'
    sleep 1
done
```

### Success Criteria
- Overall CPU: < 60%
- Peak CPU: < 75%
- No services sustaining > 80%

### Alert Triggers
- ⚠️ Warning: CPU > 75%
- 🚨 Critical: CPU > 85%

### Response Procedure
```bash
# If CPU high:
1. Identify high CPU process: docker stats --no-stream (sort by CPU)
2. If API: May be high traffic - scale or optimize
3. If Database: Check for slow queries
   docker exec code-server-postgres pg_stat_statements
4. If Appsmith: Restart it
   docker-compose restart appsmith
5. Run optimization: ./optimize-performance.sh optimize
6. Monitor: Verify CPU returns to normal
7. Investigate: Root cause analysis if pattern continues
```

---

## SLA 5: Disk Utilization (Target: <70%)

### Definition
Percentage of disk space currently used on primary server.

### Measurement
```bash
# Check disk usage
df -h /home

# Parse percentage
DISK_PERCENT=$(df -h /home | tail -1 | awk '{print $(NF-1)}' | sed 's/%//')

# Threshold check
if [ "$DISK_PERCENT" -gt 70 ]; then
    echo "ALERT: Disk > 70%"
fi
```

### Success Criteria
- Disk usage: < 70%
- Free space: > 20GB
- Growth rate: Acceptable for workload

### Alert Triggers
- ⚠️ Warning: Disk > 80%
- 🚨 Critical: Disk > 90%

### Response Procedure
```bash
# If disk high:
1. Identify space usage: du -sh /* | sort -h | tail -10
2. Check Docker images: docker images | awk '{print $7}' | tail -n +2
3. Clean Docker: docker system prune -a
4. Archive old logs:
   tar -czf logs_archive_$(date +%Y%m%d).tar.gz deployment-reports/
   rm -rf deployment-reports/*.text
5. Check Docker volumes: docker volume ls
6. If still high: Escalate to infrastructure team
7. Long-term: Plan storage expansion
```

---

## SLA 6: Error Rate (Target: <0.1%)

### Definition
Percentage of API requests that return error responses (4xx, 5xx).

### Measurement
```bash
# Collect from logs
#!/bin/bash
TOTAL_REQUESTS=$(docker logs --since 1h hermes-integration | grep "GET\|POST\|PUT\|DELETE" | wc -l)
ERROR_REQUESTS=$(docker logs --since 1h hermes-integration | grep " [45][0-9][0-9] " | wc -l)

if [ $TOTAL_REQUESTS -gt 0 ]; then
    ERROR_RATE=$((ERROR_REQUESTS * 100 / TOTAL_REQUESTS))
    echo "Error Rate: ${ERROR_RATE}%"
fi
```

### Success Criteria
- Error rate: < 0.1%
- No cascading errors
- 99.9% request success

### Alert Triggers
- ⚠️ Warning: Error rate > 1%
- 🚨 Critical: Error rate > 5%

### Response Procedure
```bash
# If error rate high:
1. Check error logs: docker logs hermes-integration | grep "ERROR\|EXCEPTION"
2. Identify error pattern: 4xx (client) or 5xx (server)?
3. If client errors: Likely normal (bad requests)
4. If server errors: Investigate root cause
   - Check database connection: Can API reach DB?
   - Check API logs for exceptions
   - Check for resource exhaustion
5. Fix and restart:
   - Database restart if needed
   - API restart
6. Monitor error rate recovery
7. Root cause analysis: Why did errors occur?
```

---

## SLA 7: Database Latency (Target: <1ms)

### Definition
Network latency between primary and secondary database (replication lag).

### Measurement
```bash
# Check replication status
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db \
  -c "SELECT * FROM pg_stat_replication;"

# Extract latency
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db \
  -c "SELECT write_lag FROM pg_stat_replication;" | grep -oP '\d+\.\d+(?=ms)'
```

### Success Criteria
- Replication latency: < 1ms
- No data loss risk
- HA failover ready

### Alert Triggers
- ⚠️ Warning: Latency > 5ms
- 🚨 Critical: Latency > 10ms or replication broken

### Response Procedure
```bash
# If latency high:
1. Check replication status (see measurement above)
2. If broken, run remediation:
   ./remediate_secondary.sh
3. Verify: Re-check replication latency
4. If still broken: Manual investigation needed
   - Check network connectivity to secondary
   - Check secondary disk space
   - Check secondary database logs

# Manual recovery steps:
ssh akushnir@192.168.168.42
docker ps | grep postgres
docker logs <postgres-container> | tail -50
```

---

## SLA 8: Container Health (Target: 100%)

### Definition
Percentage of critical containers (8 total) that are healthy and responding.

### Measurement
```bash
# Check all containers
docker-compose -f docker-compose.enterprise.yml ps

# Count healthy
HEALTHY=$(docker-compose -f docker-compose.enterprise.yml ps | grep "Up (healthy)" | wc -l)
TOTAL=8
HEALTH_PERCENT=$((HEALTHY * 100 / TOTAL))
```

### Success Criteria
- All 8 critical containers: Healthy
- Health checks passing: 100%
- Restart frequency: < 1 per day

### Alert Triggers
- ⚠️ Warning: Healthy < 95% (< 7.6 containers)
- 🚨 Critical: Healthy < 85% (< 6.8 containers)

### Response Procedure
```bash
# If container unhealthy:
1. Identify: docker-compose ps | grep -v "Up (healthy)"
2. Check logs: docker logs <container-name> | tail -50
3. Restart:
   docker-compose restart <container-name>
4. Wait 30 seconds for health check
5. Verify: docker-compose ps
6. If still unhealthy: Escalate to DevOps team
```

---

## SLA 9: Backup Freshness (Target: <24h)

### Definition
Time since last successful full backup.

### Measurement
```bash
# List backups
./backup-recovery.sh list

# Get most recent backup time
LATEST_BACKUP=$(ls -lt backups/ | head -2 | tail -1 | awk '{print $6, $7, $8}')
BACKUP_AGE=$(( ($(date +%s) - $(date -d "$LATEST_BACKUP" +%s)) / 3600 ))
echo "Latest backup: ${BACKUP_AGE} hours ago"
```

### Success Criteria
- Daily backups: Automated
- Backup age: < 24 hours
- Backup tested: Weekly restore test
- Retention: 7-day rolling backup

### Alert Triggers
- ⚠️ Warning: Backup > 36 hours old
- 🚨 Critical: Backup > 48 hours old

### Response Procedure
```bash
# If backup not current:
1. Check backup history: ./backup-recovery.sh list
2. Run manual backup: ./backup-recovery.sh backup
3. Verify backup completed successfully
4. Log backup completion: Document in incident log
5. For automation: Check cron job on server
   ssh akushnir@192.168.168.31 'crontab -l | grep backup'
```

---

## SLA 10: External Connectivity (Target: 100%)

### Definition
Percentage of time external users can connect to kushnir.cloud (DNS + TLS + HTTP).

### Measurement
```bash
# Test external connectivity
#!/bin/bash
TESTS=0
PASS=0

# Test 1: DNS Resolution
if nslookup kushnir.cloud &>/dev/null; then
    PASS=$((PASS+1))
fi
TESTS=$((TESTS+1))

# Test 2: Port 443 Open
if timeout 5 bash -c "echo > /dev/tcp/173.77.179.148/443" 2>/dev/null; then
    PASS=$((PASS+1))
fi
TESTS=$((TESTS+1))

# Test 3: TLS Connection
if echo "Q" | timeout 5 openssl s_client -connect kushnir.cloud:443 &>/dev/null; then
    PASS=$((PASS+1))
fi
TESTS=$((TESTS+1))

# Test 4: HTTP Response
if curl -s -k -o /dev/null -w "%{http_code}" https://kushnir.cloud | grep -q "[23].."; then
    PASS=$((PASS+1))
fi
TESTS=$((TESTS+1))

CONNECTIVITY_PERCENT=$((PASS * 100 / TESTS))
echo "External Connectivity: ${CONNECTIVITY_PERCENT}%"
```

### Success Criteria
- DNS resolution: Working
- Port 443: Open and responding
- TLS: Valid certificate (after May 1 upgrade)
- HTTP: Status 200/301/302

### Alert Triggers
- ⚠️ Warning: Any test failing
- 🚨 Critical: Multiple tests failing

### Response Procedure
```bash
# If external connectivity broken:
1. Test from external machine: ping kushnir.cloud
2. Check DNS: nslookup kushnir.cloud
3. Check firewall: Verify port 443 open
4. Check nginx: docker logs nginx-reverse-proxy
5. Check TLS certificate: echo | openssl s_client -connect kushnir.cloud:443
6. Restart services: docker-compose restart
7. Escalate: If still broken, escalate to infrastructure team
```

---

## Alerting Channels Setup

### Channel 1: Slack Notifications

```bash
# Setup Slack webhook
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Send alert
send_slack_alert() {
    local message="$1"
    local severity="$2"  # warning, critical
    
    curl -X POST "$SLACK_WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"[$severity] $message\"}"
}

# Example usage
send_slack_alert "Uptime dropped to 98.5%" "warning"
```

### Channel 2: Email Notifications

```bash
#!/bin/bash
# Send email alert
send_email_alert() {
    local recipient="$1"
    local subject="$2"
    local body="$3"
    
    echo "$body" | mail -s "$subject" "$recipient"
}

# Example usage
send_email_alert "ops-team@company.com" "SLA Alert" "Memory usage above 80%"
```

### Channel 3: PagerDuty Integration

```bash
# For critical incidents
PAGERDUTY_KEY="YOUR_SERVICE_KEY"

send_pagerduty_alert() {
    local message="$1"
    
    curl -X POST https://events.pagerduty.com/trigger/v2_enqueue \
      -H "Content-Type: application/json" \
      -d "{
        \"routing_key\": \"$PAGERDUTY_KEY\",
        \"event_action\": \"trigger\",
        \"dedup_key\": \"sla-alert-$(date +%s)\",
        \"payload\": {
          \"summary\": \"$message\",
          \"severity\": \"critical\",
          \"source\": \"SLA Monitoring\"
        }
      }"
}
```

---

## Monitoring Schedule

### Real-Time Monitoring (May 1-3)
```
09:00-17:00 (Business hours): Active monitoring every 5 minutes
17:00-09:00 (Off-hours): Monitoring every 30 minutes
Alerts: Immediate notification for critical issues
```

### Daily Monitoring (After May 3)
```
09:00: Morning health check
12:00: Midday performance review
17:00: End-of-day summary
Alerts: Immediate for critical, daily digest for warnings
```

### Weekly Monitoring (After go-live)
```
Monday 09:00: Weekly review of all metrics
Thursday 14:00: Midweek trend analysis
Friday 15:00: Weekly performance report
Scheduled: Maintenance window planning
```

---

## Escalation Procedures

### Alert Escalation Matrix

```
Severity Level  Response Time  Action
────────────────────────────────────────
INFO            No action      Log only
WARNING         15 minutes     Investigate, may auto-remediate
CRITICAL        5 minutes      Immediate page, escalate
EMERGENCY       Immediate      Executive escalation
```

### Escalation Chain

```
Alert Triggered
    ↓
[1] Operations Team (5 min)
    - Acknowledge alert
    - Begin investigation
    - Execute standard procedures
    ↓
[2] DevOps Lead (10 min if unresolved)
    - Higher-level diagnosis
    - Potential service restart
    - Infrastructure changes
    ↓
[3] Architecture Lead (20 min if unresolved)
    - System-level diagnosis
    - Potential temporary workarounds
    ↓
[4] CTO (30 min if unresolved)
    - Executive decision making
    - Potential rollback decision
    - Customer communication
```

---

## Dashboard Setup

**For Grafana (if implemented):**

```yaml
# Dashboard: Hermes Platform SLA Monitoring
# Panels:
# 1. System Uptime (Gauge: 0-100%)
# 2. API Response Time (Graph: ms over time)
# 3. Memory Utilization (Gauge: 0-100%)
# 4. CPU Utilization (Gauge: 0-100%)
# 5. Disk Utilization (Gauge: 0-100%)
# 6. Error Rate (Gauge: 0-100%)
# 7. Database Latency (Gauge: 0-20ms)
# 8. Container Health (Gauge: 0-100%)
# 9. Backup Freshness (Gauge: 0-48h)
# 10. External Connectivity (Gauge: 0-100%)

# Alerts on dashboard:
# - Green: All metrics normal
# - Yellow: Warning threshold exceeded
# - Red: Critical threshold exceeded
```

---

## Testing the Monitoring

### Test 1: Warning Alert

```bash
# Simulate high memory
docker run -it --rm --memory=2g --cpus=1 \
  progrium/stress --vm 1 --vm-bytes 250m --vm-hang 60 &

# Verify warning triggered within 1 minute
# Manually resolve
kill %1
```

### Test 2: Critical Alert

```bash
# Simulate service down
docker-compose stop hermes-integration

# Verify critical alert triggered
# Check logs and recovery procedure
docker-compose start hermes-integration
```

### Test 3: Backup Notification

```bash
# Manual backup
./backup-recovery.sh backup

# Verify alert clears
./backup-recovery.sh list
```

---

## Monitoring Success Criteria

By end of May 2:

- [x] All 10 SLAs defined and measurable
- [x] Alerting channels configured (Slack + Email)
- [x] Monitoring scripts running continuously
- [x] Team trained on alert response
- [x] Escalation procedures documented
- [x] Dashboard configured (or Prometheus setup)
- [x] Test alerts verified working
- [x] 24-hour baseline metrics collected

---

**This guide ensures comprehensive production monitoring and rapid incident response.**
