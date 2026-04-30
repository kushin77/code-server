# Phase 5: SLA Monitoring Dashboard Setup Guide
**Date:** May 2, 2026 (Execution) | **Duration:** 1-2 hours | **Owner:** Operations Team

---

## Overview

This guide provides step-by-step procedures to deploy the 10 operational SLAs defined in PHASE_4_EXTERNAL_TESTING_SLA.md. All monitoring rules, alert thresholds, and escalation procedures are included.

---

## Pre-Setup Checklist

- [ ] Operations team assembled
- [ ] Access to monitoring system (Prometheus/Grafana or equivalent)
- [ ] Alert notification channels configured (Slack, email, etc.)
- [ ] Team contact list updated
- [ ] Escalation procedures reviewed
- [ ] All Phase 1-4 infrastructure verified stable

---

## SLA 1: Availability (99.9% Monthly Uptime)

### Target
- Uptime: 99.9% monthly (43.2 minutes max downtime)
- Scope: kushnir.cloud domain + 8 critical services

### Setup

**Metrics to Monitor:**
```
- Domain availability (HTTP status 200)
- Critical service health (8 services)
- nginx reverse proxy response time
- Appsmith OAuth service status
```

**Alert Rule:**
```
IF service_down > 0 FOR 5 minutes
THEN alert Level 2 (15 min on-call response)
```

**Dashboard Panel:**
```
Title: "System Availability"
Type: Gauge
Target: avg(uptime_percentage)
Thresholds: 
  - Green: >99.5%
  - Yellow: 99-99.5%
  - Red: <99%
```

### Escalation
- **Level 1:** Alert to ops team log, monitor for 30 min
- **Level 2:** Page on-call engineer (15 min response)
- **Level 3:** Escalate to CTO (if service down >1 hour)

---

## SLA 2: Response Time (<2s p95 for Homepage)

### Targets
- Homepage: <2 seconds p95
- OAuth Login: <3 seconds p95
- IDE Access: <5 seconds p95

### Setup

**Metrics to Monitor:**
```
- http_request_duration_seconds (p95 percentile)
- nginx response times
- Appsmith page load times
```

**Alert Rule:**
```
IF http_request_duration_seconds{path="/", quantile="0.95"} > 2
THEN alert Level 2
```

**Dashboard Panel:**
```
Title: "Response Time (p95)"
Type: Line Chart
Series:
  - Homepage (target: 2s)
  - OAuth (target: 3s)
  - IDE (target: 5s)
Threshold line: 2000ms (red)
```

### Escalation
- **Level 1:** Log and monitor (alert sent to ops)
- **Level 2:** If sustained >5 min, investigate backend performance

---

## SLA 3: Error Rate (<0.1%, <1 error per 1000 requests)

### Target
- Error rate: <0.1% (HTTP 5xx)
- Scope: All HTTP requests to kushnir.cloud

### Setup

**Metrics to Monitor:**
```
- http_requests_total{status=~"5.."}
- error_rate = errors / total_requests
```

**Alert Rule:**
```
IF error_rate > 0.001 FOR 10 minutes
THEN alert Level 1 (log only)
```

**Dashboard Panel:**
```
Title: "Error Rate (%)"
Type: Gauge
Target: (errors / total_requests) * 100
Thresholds:
  - Green: <0.05%
  - Yellow: 0.05-0.1%
  - Red: >0.1%
```

### Escalation
- **Level 1:** Log to error tracking, monitor for patterns
- **Level 2:** If error rate >0.5%, page on-call engineer

---

## SLA 4: SSL Certificate Validity (Always Valid)

### Target
- Certificate: Always valid and deployed
- Renewal: Automatic, renewed before expiration
- Alert: 30 days before expiration, escalate at 7 days

### Setup

**Metrics to Monitor:**
```
- ssl_certificate_expires_seconds (TTL)
- ssl_certificate_valid (binary: 0=invalid, 1=valid)
```

**Alert Rule:**
```
IF ssl_certificate_valid == 0
THEN alert Level 3 (immediate CTO escalation)

IF (ssl_certificate_expires_seconds / 86400) < 30
THEN alert Level 1 (log and notify)

IF (ssl_certificate_expires_seconds / 86400) < 7
THEN alert Level 2 (on-call response within 15 min)
```

**Dashboard Panel:**
```
Title: "SSL Certificate Status"
Type: Stat
Top Value: "Certificate Valid" (green)
Left Value: "Days Until Expiration"
Thresholds:
  - Green: >30 days
  - Yellow: 7-30 days
  - Red: <7 days
```

### Escalation
- **Level 1 (Info):** 30+ days before expiration
- **Level 2 (Alert):** 7-30 days before expiration
- **Level 3 (Critical):** Certificate invalid or <7 days

---

## SLA 5: Database Query Latency (<100ms)

### Target
- Query response time: <100ms (p95)
- Database replication lag: <1 second

### Setup

**Metrics to Monitor:**
```
- postgresql_query_duration_seconds (p95)
- pg_replication_lag_seconds
```

**Alert Rule:**
```
IF postgresql_query_duration_seconds{quantile="0.95"} > 0.1
THEN alert Level 1

IF pg_replication_lag_seconds > 1
THEN alert Level 2 (on-call)
```

**Dashboard Panel:**
```
Title: "Database Latency"
Type: Line Chart
Series:
  - Query Latency (target: 100ms)
  - Replication Lag (target: <1s)
Threshold: 100ms (yellow), 500ms (red)
```

### Escalation
- **Level 1:** Log query slowness, check logs for patterns
- **Level 2:** If replication lag >5s, page DBA

---

## SLA 6: Network Latency (<1ms Primary ↔ Replica)

### Target
- Latency: <1ms (currently 0.190ms - excellent)
- No packet loss
- Network stable

### Setup

**Metrics to Monitor:**
```
- network_latency_milliseconds (primary to replica)
- network_packet_loss_percent
```

**Alert Rule:**
```
IF network_latency_milliseconds > 1
THEN alert Level 1 (monitoring only)

IF network_packet_loss_percent > 0.1
THEN alert Level 2 (network team)
```

**Dashboard Panel:**
```
Title: "Network Health"
Type: Gauge (dual)
Left: Latency (target: <1ms, current: 0.19ms)
Right: Packet Loss (target: 0%, current: 0%)
```

### Escalation
- **Level 1:** Monitor for degradation
- **Level 2:** If latency >5ms, investigate network

---

## SLA 7: Storage Capacity (>20GB Free)

### Target
- Free space: >20GB
- Alert: 10GB free
- Critical: 5GB free

### Setup

**Metrics to Monitor:**
```
- disk_free_bytes
- disk_used_percent
```

**Alert Rule:**
```
IF disk_free_bytes / 1000000000 < 10
THEN alert Level 1 (log and notify)

IF disk_free_bytes / 1000000000 < 5
THEN alert Level 2 (on-call response)

IF disk_free_bytes / 1000000000 < 2
THEN alert Level 3 (emergency - CTO escalation)
```

**Dashboard Panel:**
```
Title: "Storage Usage"
Type: Gauge + Sparkline
Value: Free GB
Thresholds:
  - Green: >20GB
  - Yellow: 10-20GB
  - Red: <10GB
  - Critical: <5GB
```

### Escalation
- **Level 1 (Info):** 10-20GB free, start cleanup planning
- **Level 2 (Alert):** 5-10GB free, execute cleanup
- **Level 3 (Critical):** <5GB free, emergency cleanup needed

---

## SLA 8: Memory Utilization (<85%)

### Target
- Memory: <85% utilized
- Available: >15Gi (from 31Gi total)
- Current: 67% (21Gi available)

### Setup

**Metrics to Monitor:**
```
- memory_usage_percent
- memory_available_bytes
```

**Alert Rule:**
```
IF memory_usage_percent > 85
THEN alert Level 1 (log and monitor)

IF memory_usage_percent > 95
THEN alert Level 2 (on-call, may require restart)
```

**Dashboard Panel:**
```
Title: "Memory Utilization"
Type: Gauge
Value: Percent Used
Thresholds:
  - Green: <70%
  - Yellow: 70-85%
  - Red: >85%
  - Critical: >95%
Sub-text: Available Memory (Gi)
```

### Escalation
- **Level 1:** Monitor for memory leaks
- **Level 2:** If >95%, investigate container memory usage

---

## SLA 9: Container Health (100% of 8 Critical Services)

### Target
- All 8 critical services: healthy
- No critical containers down
- Docker health checks passing

### Setup

**Metrics to Monitor:**
```
- container_health_status (per critical service)
- containers_unhealthy_count
```

**Alert Rule:**
```
IF containers_unhealthy_count >= 1
THEN alert Level 1 (log, ops team review)

IF containers_unhealthy_count >= 2
THEN alert Level 2 (on-call restart investigation)

IF containers_unhealthy_count >= 3 OR critical_service_down
THEN alert Level 3 (CTO escalation)
```

**Dashboard Panel:**
```
Title: "Container Health Status"
Type: Table
Columns: Container Name | Status | Health | Uptime
Services:
  - Appsmith
  - nginx
  - PostgreSQL
  - GitLab
  - Code Server
  - Vault
  - Minio
  - Keepalived
Indicators: Green (healthy), Red (unhealthy)
```

### Escalation
- **Level 1:** Check logs for restart cause
- **Level 2:** If service down >5 min, manual restart
- **Level 3:** If multiple critical services down, escalate to CTO

---

## SLA 10: Backup Success Rate (100% Weekly)

### Target
- Backup: 100% success rate weekly
- Last backup: <7 days old
- Backup size: >1GB (adequate)

### Setup

**Metrics to Monitor:**
```
- backup_success_count (weekly)
- last_backup_timestamp
- backup_size_bytes
```

**Alert Rule:**
```
IF backup_success_count < 1 AND day_of_week == "Monday"
THEN alert Level 1 (log, verify backup runs)

IF (now - last_backup_timestamp) > 604800 (7 days)
THEN alert Level 2 (on-call, manual backup needed)

IF backup_size_bytes < 1000000000
THEN alert Level 1 (log, verify backup size)
```

**Dashboard Panel:**
```
Title: "Backup Status"
Type: Stat + Timeline
Top Value: "Last Backup"
Left: "Success Rate This Week"
Timeline: Last 4 weeks backup schedule
Indicator:
  - Green: Last <3 days
  - Yellow: Last 3-7 days
  - Red: Last >7 days
```

### Escalation
- **Level 1:** Manual verification of backup schedule
- **Level 2:** If no backup >7 days, manual backup and investigation

---

## Dashboard Implementation

### Step 1: Create Dashboard
```
Dashboard Name: "Phase 5: Operational SLAs"
Refresh Rate: 30 seconds
Layout: 2-column grid
```

### Step 2: Add Panels (One per SLA)
```
For each SLA 1-10:
1. Create new panel
2. Configure metrics (see above)
3. Set thresholds and colors
4. Add description
5. Link to runbook documentation
```

### Step 3: Configure Alerts
```
For each alert rule:
1. Define condition
2. Set duration threshold
3. Configure notification channel
4. Test alert delivery
5. Verify escalation path
```

### Step 4: Setup Notification Channels
```
Channels to configure:
- Slack: #ops-alerts, #devops-alerts
- Email: ops-team@company.com, devops@company.com
- PagerDuty: On-call engineer assignment
- Jira: Auto-create tickets for Level 2+ alerts
```

### Step 5: Team Training
```
Topics:
1. How to read each SLA panel
2. When alerts are triggered
3. How to respond to each level
4. How to verify alert resolution
5. How to update thresholds
```

---

## Testing SLA Alerts

### Test Plan
```
For each SLA:
1. Test Level 1 alert (log only)
2. Test Level 2 alert (on-call)
3. Test Level 3 alert (escalation)
4. Verify notification delivery
5. Verify escalation path
6. Clear alert and verify resolution
```

### Example Test (SLA 1: Availability)
```
Step 1: Stop nginx container
  docker stop hermes-nginx

Step 2: Verify Level 2 alert fires within 5 minutes
  Check Slack channel for alert
  Verify on-call engineer paged

Step 3: Restart nginx
  docker start hermes-nginx

Step 4: Verify alert clears
  Check alert status changes to "resolved"
```

---

## Documentation & Runbooks

### Documentation Links
- SLA Definitions: PHASE_4_EXTERNAL_TESTING_SLA.md
- Escalation Procedures: PHASE_3_CONTINUOUS_OPERATIONS.md
- Team Contacts: FINAL_OPERATIONAL_HANDOFF_CHECKLIST.md

### Runbook Templates
```
Create runbooks for each alert:
1. SLA X Triggered - Investigation Steps
2. How to Resolve [Issue]
3. When to Escalate to Level 2/3
4. Verification Steps
```

---

## Post-Setup Verification

- [ ] All 10 SLA panels visible on dashboard
- [ ] All alerts testing successfully
- [ ] Notification channels verified
- [ ] Escalation paths confirmed
- [ ] Team trained on procedures
- [ ] Runbooks linked to alerts
- [ ] 24-hour monitoring period begins (May 3)
- [ ] Daily SLA reports generated
- [ ] Weekly SLA compliance report scheduled (May 10)
- [ ] Monthly SLA report documented (May 31)

---

## Success Criteria

✅ All 10 SLAs deployed and monitoring  
✅ Alert thresholds verified correct  
✅ Notification channels working  
✅ Escalation paths tested  
✅ Team trained  
✅ Runbooks available  
✅ Dashboard accessible to all ops team  

---

## Handoff to Operations

**Owner:** Operations Team  
**Support Contact:** Infrastructure Lead  
**Escalation:** CTO for critical issues  
**Review Schedule:** Daily during Week 1, Weekly thereafter  
**Monthly Report:** May 31, 2026  

---

**Setup Guide Prepared By:** DevOps Agent  
**Date:** April 30, 2026  
**Target Execution:** May 2, 2026  
**Status:** ✅ Ready for Team Implementation
