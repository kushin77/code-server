# Phase 5 SLA Monitoring Dashboard - Implementation & Deployment Guide
**Prepared:** April 30, 2026 | **Status:** ✅ Ready for May 2 Implementation | **Duration:** 1-2 hours

---

## SLA Dashboard Overview

**Purpose:** Real-time monitoring of 10 operational SLAs with automated alerts and escalation  
**Target Deployment:** May 2, 2026 (09:00-11:00 UTC)  
**Monitoring Interval:** 5-minute checks with 1-minute granularity  
**Alert Response:** 3-level escalation (Log → 15-min response → CTO)  

---

## 10 Operational SLAs - Dashboard Panels

### Panel 1: System Availability
```yaml
SLA: System Availability
Target: 99.9% uptime (≤52 minutes downtime/month)
Current: 100% (52/54 containers operational)
Critical Threshold: <99% (alert immediately)
Warning Threshold: 99-99.5% (monitor and log)
Metrics Source: docker ps, container health check
Frequency: Every 5 minutes
Action: If <99%, page on-call engineer immediately
```

### Panel 2: Response Time (HTTP)
```yaml
SLA: HTTP Response Time
Target: <2 seconds average
Current: <100ms average
Critical Threshold: >5 seconds (alert)
Warning Threshold: 2-5 seconds (warning)
Metrics Source: curl timing, application logs
Frequency: Every 1 minute
Action: If >5s, investigate nginx/appsmith performance
```

### Panel 3: Error Rate
```yaml
SLA: Application Error Rate
Target: <0.1% (less than 1 error per 1000 requests)
Current: 0% observed
Critical Threshold: >1% (alert)
Warning Threshold: 0.5-1% (warning)
Metrics Source: nginx error logs, application metrics
Frequency: Every 5 minutes
Action: If >1%, page application team
```

### Panel 4: Certificate Validity
```yaml
SLA: SSL Certificate Expiration
Target: 90+ days until expiration
Current: 365 days (new cert)
Critical Threshold: <7 days until expiration (alert)
Warning Threshold: 7-30 days (warning)
Metrics Source: openssl x509 enddate, certbot logs
Frequency: Daily at 00:00 UTC
Action: If <7 days, auto-renew and notify team
```

### Panel 5: Database Latency
```yaml
SLA: Primary ↔ Replica Latency
Target: <100ms RTT
Current: 0.190ms (excellent)
Critical Threshold: >500ms (alert)
Warning Threshold: 100-500ms (warning)
Metrics Source: postgres replication lag, network ping
Frequency: Every 30 seconds
Action: If >500ms, check network and database connection
```

### Panel 6: Network Latency
```yaml
SLA: External Network Latency
Target: <1ms RTT to primary host
Current: 0.190ms (excellent)
Critical Threshold: >10ms (alert)
Warning Threshold: 1-10ms (warning)
Metrics Source: ping to primary/secondary, traceroute
Frequency: Every 60 seconds
Action: If >10ms, investigate network routing
```

### Panel 7: Storage Availability
```yaml
SLA: Available Disk Space
Target: >20GB available
Current: 33GB available (66% used)
Critical Threshold: <10GB (alert)
Warning Threshold: 10-20GB (warning)
Metrics Source: df -h, disk usage metrics
Frequency: Every 5 minutes
Action: If <10GB, trigger cleanup and notify ops
```

### Panel 8: Memory Utilization
```yaml
SLA: Memory Utilization
Target: <85% average utilization
Current: 26% (excellent)
Critical Threshold: >90% (alert)
Warning Threshold: 85-90% (warning)
Metrics Source: free -h, docker stats
Frequency: Every 5 minutes
Action: If >90%, investigate memory leaks and scale if needed
```

### Panel 9: Container Health
```yaml
SLA: Container Health Status
Target: 100% of critical containers (8/8)
Current: 8/8 healthy (100%)
Critical Threshold: <100% (any critical container down)
Warning Threshold: <95% (non-critical containers down)
Metrics Source: docker ps, health check status
Frequency: Every 30 seconds
Action: If <100%, auto-restart and page ops team
```

### Panel 10: Backup Coverage
```yaml
SLA: Backup Completion
Target: 100% of databases backed up weekly
Current: Active (100% coverage)
Critical Threshold: Backup >7 days old (alert)
Warning Threshold: Backup >3 days old (warning)
Metrics Source: backup job logs, S3 backup verification
Frequency: Daily after backup run
Action: If failed, page database team immediately
```

---

## Grafana Dashboard Setup (1 hour)

### Step 1: Access Grafana Interface
```bash
# Access via: https://kushnir.cloud/grafana (or designated monitoring URL)
# Login: admin / (password from vault)
# Navigate to: Dashboards → New Dashboard
```

### Step 2: Add Data Sources (10 min)
```yaml
Data Sources:
  1. Prometheus
     - URL: http://prometheus:9090
     - Access: Browser
     - Scrape Interval: 5s
     
  2. Docker
     - URL: unix:///var/run/docker.sock
     - Access: Server
```

### Step 3: Create Dashboard Panels (40 min)

Each panel follows this structure:
```yaml
Panel Configuration:
  - Title: [SLA Name]
  - Data Source: Prometheus
  - Query: [PromQL query for metric]
  - Visualization: Graph/Gauge/Stat
  - Thresholds: Green/Yellow/Red (target/warning/critical)
  - Refresh: Every 5 minutes
```

### Panel Setup Details

**Panel 1: Availability - Stat Panel**
```prometheus
Query: (count(container_up{name=~"appsmith|nginx|postgres|gitlab|vault|redis"}) / 6) * 100
Thresholds: Green >99, Yellow 99-95, Red <95
Format: percentage
```

**Panel 2: Response Time - Graph Panel**
```prometheus
Query: histogram_quantile(0.95, http_request_duration_seconds)
Thresholds: Green <2s, Yellow 2-5s, Red >5s
Label: milliseconds
```

**Panel 3: Error Rate - Stat Panel**
```prometheus
Query: (increase(http_requests_total{status=~"5.."}[5m]) / increase(http_requests_total[5m])) * 100
Thresholds: Green 0-0.1%, Yellow 0.1-1%, Red >1%
Format: percent
```

**Panel 4: Certificate Expiry - Gauge Panel**
```bash
Query: (ssl_certificate_not_after_seconds - time()) / (24 * 3600)
Thresholds: Green >90, Yellow 30-90, Red <30
Units: days
```

**Panel 5: DB Latency - Graph Panel**
```prometheus
Query: pg_replication_lag_seconds
Thresholds: Green <0.1, Yellow 0.1-0.5, Red >0.5
Units: seconds
```

**Panel 6: Network Latency - Graph Panel**
```bash
Query: probe_duration_seconds (from blackbox exporter)
Thresholds: Green <0.001, Yellow 0.001-0.01, Red >0.01
Units: seconds
```

**Panel 7: Storage - Gauge Panel**
```prometheus
Query: (node_filesystem_avail_bytes{mountpoint="/"} / 1024 / 1024 / 1024)
Thresholds: Green >20GB, Yellow 10-20GB, Red <10GB
Units: GB
```

**Panel 8: Memory - Gauge Panel**
```prometheus
Query: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
Thresholds: Green <85%, Yellow 85-90%, Red >90%
Units: percent
```

**Panel 9: Containers - Stat Panel**
```prometheus
Query: count(container_up)
Thresholds: Green 52-54, Yellow 50-51, Red <50
Format: short
```

**Panel 10: Backups - Stat Panel**
```bash
Query: (now() - backup_last_run_timestamp) / 3600
Thresholds: Green <24h, Yellow 24-72h, Red >72h
Units: hours
```

---

## Alert Rules Configuration (20 min)

### Alert Rule 1: Availability Critical
```yaml
Alert: AvailabilityCritical
Condition: (container_up_count / 8) < 0.99
Duration: 5 minutes
Severity: CRITICAL
Notification: Slack #alerts, PagerDuty, CTO email
Action: Auto-restart failed container, page ops
```

### Alert Rule 2: Response Time Warning
```yaml
Alert: ResponseTimeWarning
Condition: histogram_quantile(0.95, http_duration) > 2s
Duration: 10 minutes
Severity: WARNING
Notification: Slack #alerts, monitoring dashboard
Action: Log event, investigate performance
```

### Alert Rule 3: Error Rate Critical
```yaml
Alert: ErrorRateCritical
Condition: (error_count / total_requests) > 0.01
Duration: 5 minutes
Severity: CRITICAL
Notification: Slack #alerts, PagerDuty, Application team
Action: Page app team, check error logs
```

### Alert Rule 4: Certificate Expiry Warning
```yaml
Alert: CertificateExpirySoon
Condition: (cert_expiry_time - now()) < 7 days
Duration: 1 hour
Severity: WARNING
Notification: Slack #alerts, Security team, CTO
Action: Auto-renew certificate, send notification
```

### Alert Rule 5: Database Latency High
```yaml
Alert: DatabaseLatencyHigh
Condition: pg_replication_lag > 0.5s
Duration: 5 minutes
Severity: WARNING
Notification: Slack #alerts, Database team
Action: Investigate replication, check network
```

### Alert Rule 6: Network Latency High
```yaml
Alert: NetworkLatencyHigh
Condition: ping_response_time > 10ms
Duration: 10 minutes
Severity: WARNING
Notification: Slack #alerts, Infrastructure team
Action: Check network routing, investigate ISP issues
```

### Alert Rule 7: Disk Space Low
```yaml
Alert: DiskSpaceCritical
Condition: available_disk < 10GB
Duration: 5 minutes
Severity: CRITICAL
Notification: Slack #alerts, PagerDuty, Ops team
Action: Trigger cleanup, expand disk if needed
```

### Alert Rule 8: Memory Utilization High
```yaml
Alert: MemoryUtilizationHigh
Condition: memory_used_percent > 90
Duration: 15 minutes
Severity: WARNING
Notification: Slack #alerts, Ops team
Action: Investigate memory leaks, consider scaling
```

### Alert Rule 9: Container Down
```yaml
Alert: ContainerCritical
Condition: container_status == "stopped" for critical service
Duration: 1 minute
Severity: CRITICAL
Notification: Slack #alerts, PagerDuty, Ops team, CTO
Action: Auto-restart, escalate if restart fails
```

### Alert Rule 10: Backup Failed
```yaml
Alert: BackupFailed
Condition: last_backup_age > 24 hours
Duration: 1 hour
Severity: CRITICAL
Notification: Slack #alerts, PagerDuty, Database team, CTO
Action: Investigate backup process, manual backup if needed
```

---

## Notification Channels - Setup (10 min)

### Slack Integration
```yaml
Channel: #alerts
Webhook: https://hooks.slack.com/services/[YOUR_TOKEN]
Notifications:
  - CRITICAL: Red color, mentions @ops-team
  - WARNING: Yellow color, mentions @team
  - INFO: Blue color, regular notification
```

### PagerDuty Integration
```yaml
Service Key: [Generate from PagerDuty]
Severity Mapping:
  - CRITICAL → Trigger PagerDuty incident
  - WARNING → Log to PagerDuty timeline
Integration: Grafana → PagerDuty → On-call rotation
```

### Email Notifications
```yaml
Recipients:
  - ops-team@company.com
  - cto@company.com
  - database-team@company.com
  - security-team@company.com
Trigger: CRITICAL alerts only
```

### SMS/Phone (Critical Only)
```yaml
Recipients:
  - CTO phone: [Number]
  - On-call engineer: [Number]
Trigger: CRITICAL + P1 incidents only
Escalation: If not acknowledged within 5 minutes
```

---

## Testing Procedures (30 min)

### Test 1: Alert Trigger Test
```bash
# Simulate each alert to verify notification delivery
# Stop a critical container:
docker stop code-server-appsmith

# Verify:
# ✅ Slack notification received
# ✅ PagerDuty incident created
# ✅ Email notification sent
# ✅ Dashboard shows red alert

# Restart container:
docker start code-server-appsmith

# Verify alert clears
```

### Test 2: Threshold Testing
```bash
# Generate load to test response time alert
ab -n 1000 -c 100 https://kushnir.cloud/

# Monitor dashboard for:
# ✅ Response time metric updated
# ✅ Warning threshold triggered if >2s
# ✅ Alert notifications sent
```

### Test 3: All Alerts Verification
```bash
# Run comprehensive test:
bash scripts/ci/test-sla-alerts.sh

# Expected results:
# ✅ 10/10 alerts tested
# ✅ All notification channels verified
# ✅ Alert escalation paths confirmed
# ✅ Dashboard accuracy validated
```

---

## Dashboard Verification Checklist

- [ ] All 10 panels loaded and displaying data
- [ ] Response times: <100ms confirmed
- [ ] Container count: 52-54 showing
- [ ] Memory utilization: 26% showing
- [ ] Storage: 33GB available showing
- [ ] Certificate: Expiry date showing
- [ ] Database latency: 0.190ms showing
- [ ] Network latency: 0.190ms showing
- [ ] Error rate: 0% showing
- [ ] Availability: 100% showing
- [ ] All alerts: Enabled and tested
- [ ] Slack notifications: Working
- [ ] PagerDuty integration: Active
- [ ] Email notifications: Confirmed
- [ ] Alert escalation: Tested
- [ ] Dashboard refresh: 5-minute cycle
- [ ] Historical data: Retention set
- [ ] Export/reporting: Configured

---

## May 2 Execution Timeline

### 09:00 UTC - Dashboard Setup (30 min)
- Access Grafana interface
- Configure data sources
- Create all 10 panels
- Verify data sources connected

### 09:30 UTC - Alert Configuration (20 min)
- Create alert rules for all 10 SLAs
- Configure notification channels
- Set thresholds and escalation paths
- Verify alert system ready

### 09:50 UTC - Testing (20 min)
- Test each alert trigger
- Verify notifications delivered
- Confirm escalation paths working
- Validate dashboard accuracy

### 10:10 UTC - Team Training (30 min)
- Dashboard walkthrough
- Alert response procedures
- Escalation path training
- Q&A and final verification

### 11:00 UTC - Handoff & Sign-Off (30 min)
- Operations team sign-off
- Documentation transfer
- Operational procedures review
- Go-live authorization

---

## Post-Deployment Maintenance

### Daily Tasks
- Review alert logs for any triggered alerts
- Verify all containers healthy (8/8)
- Check storage availability
- Monitor response times

### Weekly Tasks
- Review SLA compliance metrics
- Update alert thresholds if needed
- Test alert escalation paths
- Review backup completion status
- Generate compliance report

### Monthly Tasks
- Full SLA compliance audit
- Certificate renewal verification
- Performance trend analysis
- Team training update
- Risk assessment review

---

## Success Criteria - All Must Pass ✅

- [ ] All 10 SLA panels created and displaying
- [ ] All alert rules configured and tested
- [ ] All notification channels working
- [ ] All thresholds validated
- [ ] Team training completed
- [ ] Dashboard accuracy verified
- [ ] Response time <5 min to alert
- [ ] Escalation paths tested
- [ ] Historical data retention active
- [ ] Team sign-off obtained

---

## Status: ✅ READY FOR MAY 2 DEPLOYMENT

**Prepared:** April 30, 2026  
**Target:** May 2, 2026 09:00 UTC  
**Duration:** 1-2 hours  
**Team:** Operations (6-person team)  
**Follow-up:** Daily monitoring + weekly compliance review  

**Next Action:** Execute dashboard setup on May 2 morning
