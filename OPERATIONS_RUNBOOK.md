# Production Operations Runbook
## Complete System Operations Manual

**Last Updated**: April 13, 2026  
**System**: Production Platform (Phases 4A-15)  
**Target Audience**: Operations, DevOps, SRE teams  

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Deployment Procedures](#deployment-procedures)
3. [Monitoring & Alerting](#monitoring--alerting)
4. [Incident Response](#incident-response)
5. [Disaster Recovery](#disaster-recovery)
6. [Troubleshooting](#troubleshooting)
7. [Maintenance](#maintenance)
8. [Emergency Procedures](#emergency-procedures)

---

## Quick Start

### Verify System Health

```bash
# Check all components healthy
curl https://api.production.local/health
# Expected: { "status": "healthy", "components": { ... } }

# Check SLO compliance
curl https://api.production.local/metrics/slo
# Expected: p99_latency < 100ms, error_rate < 1%, availability > 99.95%

# View system status dashboard
open https://dashboard.production.local/system-status
```

### System Access Points

| Component | Endpoint | Port | Auth |
|-----------|----------|------|------|
| API | api.production.local | 443 | OAuth2 |
| Dashboard | dashboard.production.local | 443 | OAuth2 |
| Health Check | api.production.local/health | 443 | Public |
| Metrics | api.production.local/metrics | 443 | OAuth2 |
| Logs | logs.production.local | 443 | OAuth2 |

---

## Deployment Procedures

### Standard Canary Deployment (Recommended)

**Duration**: ~45 minutes  
**Risk Level**: Low  
**Success Rate**: > 99%

#### Phase 1: Pre-Deployment Validation (5 min)

```bash
# 1. Verify staging environment passing tests
cd /opt/platform && ./scripts/verify-staging.sh

# 2. Check SLO baseline
./scripts/check-slo-baseline.sh v2.0.0

# 3. Verify all dependencies available
./scripts/validate-dependencies.sh

# Expected output:
# ✅ Code verification: PASSED
# ✅ Security scan: PASSED (0 vulnerabilities)
# ✅ Dependency check: PASSED
# ✅ SLO baseline: ESTABLISHED
```

#### Phase 2: Canary Deployment (10 min)

```bash
# 1. Start canary deployment (5% traffic)
./scripts/deploy-canary.sh \
  --version v2.0.0 \
  --canary-percentage 5 \
  --monitor-duration 10

# 2. Monitor canary health (runs automatically)
# - Collects metrics every 30 seconds
# - Validates health score >= 75
# - Checks P99 latency change < 10%
# - Monitors error rate increase < 5%

# 3. View canary dashboard
open https://dashboard.production.local/canary-status

# Expected output after 10 min:
# ✅ Health score: 85/100
# ✅ Latency delta: +2% (< 10% threshold)
# ✅ Error rate delta: -0.2% (improvement)
# 🟢 READY TO PROGRESS
```

#### Phase 3: Progressive Rollout (20 min)

```bash
# 1. Progress to 25% traffic
./scripts/progress-canary.sh \
  --deployment-id <canary-id> \
  --new-percentage 25

# 2. Monitor for 10 minutes
sleep 600

# 3. Progress to 50% traffic
./scripts/progress-canary.sh \
  --deployment-id <canary-id> \
  --new-percentage 50

# 4. Monitor for 10 minutes
sleep 600

# Expected output at each stage:
# ✅ Traffic shifted (X% → Y%)
# ✅ Health score maintained > 75
# ✅ SLO metrics within target
# 🟢 AUTO-PROGRESSING
```

#### Phase 4: Production Promotion (10 min)

```bash
# 1. Complete traffic switch to 100%
./scripts/promote-canary.sh \
  --deployment-id <canary-id>

# 2. Blue-green switch (instantaneous)
# - Green environment becomes active
# - Blue environment drains connections
# - Instant rollback available < 30 seconds

# 3. Validate promotion
./scripts/validate-promotion.sh

# Expected output:
# ✅ Green environment: ACTIVE (100% traffic)
# ✅ Blue environment: DRAINING (connections < 10)
# ✅ Disaster recovery test: PASSED
# ✅ Deployment complete: 45 minutes total
```

#### Phase 5: Post-Deployment (5 min)

```bash
# 1. Generate deployment report
./scripts/deployment-report.sh v2.0.0

# 2. Archive artifacts
./scripts/archive-deployment.sh v2.0.0

# 3. Update monitoring baselines
./scripts/update-slo-baselines.sh v2.0.0

# Expected output:
# ✅ Performance: 12% improvement
# ✅ Cost: 3% reduction
# ✅ SLO compliance: 100%
# ✅ Incident rate: < 0.1%
```

### Emergency Quick Rollback (< 30 seconds)

```bash
# IMMEDIATE ROLLBACK
./scripts/rollback-immediate.sh \
  --reason "Critical incident detected" \
  --target-version v1.9.0

# Output:
# ⏱️ Rollback started: 12:34:56 UTC
# ⏱️ Shifting traffic: 100% → 0%
# ⏱️ Draining connections: 1000 → 0
# ✅ Rollback complete: 12:35:22 UTC (26 seconds)
# ✅ Services healthy: API, Cache, Database
```

---

## Monitoring & Alerting

### Critical Metrics to Monitor

```bash
# View real-time metrics dashboard
open https://dashboard.production.local/metrics

# Key metrics:
# - P99 Latency (target: < 100ms)
# - Error Rate (target: < 1%)
# - Throughput (target: > 5,000 ops/sec)
# - CPU Usage (alert: > 85%)
# - Memory Usage (alert: > 80%)
# - Disk Usage (alert: > 85%)
```

### SLO Compliance Check

```bash
# Check current SLO compliance
curl https://api.production.local/metrics/slo

# Expected response:
{
  "compliance": "PASS",
  "metrics": {
    "auth_latency_p99": { "target": 100, "actual": 85, "met": true },
    "policy_eval_p99": { "target": 50, "actual": 42, "met": true },
    "threat_detection": { "target": 5000, "actual": 5200, "met": true },
    "error_rate": { "target": 1, "actual": 0.5, "met": true },
    "availability": { "target": 99.95, "actual": 99.97, "met": true }
  }
}
```

### Alert Configuration

```yaml
# Critical Alerts (page on-call)
- name: p99_latency_critical
  condition: p99_latency > 150  # 50% over target
  action: page_oncall_engineer

- name: error_rate_critical
  condition: error_rate > 2     # 2x over target
  action: page_oncall_engineer

- name: health_check_failure
  condition: health_score < 60
  action: page_oncall_engineer

# Warning Alerts (create ticket)
- name: p99_latency_warning
  condition: p99_latency > 120
  action: create_ticket

- name: error_rate_warning
  condition: error_rate > 1.5
  action: create_ticket

- name: resource_usage_high
  condition: cpu_usage > 80 OR memory_usage > 80
  action: create_ticket
```

---

## Incident Response

### Auto-Response Flow

```
Metric Anomaly Detected
    ↓
Incident Created
    ↓
Severity Assessed
    ↓
├─ CRITICAL (score > 80)
│  ├─ Automatic Rollback
│  ├─ Page On-Call Engineer
│  └─ Create War Room
│
├─ HIGH (score 60-80)
│  ├─ Auto-Recovery Runbook
│  ├─ Page On-Call Engineer
│  └─ Create Incident Ticket
│
└─ MEDIUM (score < 60)
   ├─ Auto-Recovery Runbook
   ├─ Create Support Ticket
   └─ Monitor Resolution
```

### Manual Incident Response

```bash
# 1. Check active incidents
./scripts/check-incidents.sh  # Shows all active incidents
```

**If High Error Rate (> 5%)**:

```bash
# 1. Check error logs
tail -100 /var/log/platform/errors.log | grep -i "ERROR" | head -20

# 2. Check affected service
./scripts/check-service.sh api

# 3. Scale service if needed
./scripts/scale-service.sh api --instances 15

# 4. Monitor recovery
watch -n 5 'curl https://api.production.local/metrics | grep error_rate'

# 5. Investigate root cause
tail -200 /var/log/platform/errors.log | grep -A 5 "root cause"
```

**If High Latency (> 120ms P99)**:

```bash
# 1. Check database performance
./scripts/check-database.sh

# 2. Check slow queries
mysql -h db.production.local -u admin -p -e \
  "SELECT query_time, query FROM slow_log ORDER BY query_time DESC LIMIT 10;"

# 3. Check cache hit rate
./scripts/check-cache.sh
# Expected: hit_rate > 95%

# 4. Scale database if needed
./scripts/scale-database.sh --read-replicas 5

# 5. Monitor latency recovery
watch -n 5 'curl https://api.production.local/metrics | grep p99_latency'
```

**If Health Degradation**:

```bash
# 1. Run full health check
./scripts/health-check.sh --verbose

# 2. Check component health
./scripts/check-component-health.sh api
./scripts/check-component-health.sh database
./scripts/check-component-health.sh cache
./scripts/check-component-health.sh storage

# 3. Execute recovery runbook
./scripts/execute-recovery.sh --component <component> --runbook auto

# 4. Validate recovery
./scripts/validate-recovery.sh
```

### Creating Incident Report

```bash
# Generate incident report
./scripts/incident-report.sh \
  --incident-id <incident-id> \
  --format pdf

# Report includes:
# - Timeline of events
# - Root cause analysis
# - Impact assessment
# - Resolution actions taken
# - Lessons learned
# - Recommendations for prevention
```

---

## Disaster Recovery

### Test DR (Scheduled Monthly)

```bash
# 1. Notify team
./scripts/notify-team.sh --message "Starting DR test"

# 2. Trigger failover to secondary region
./scripts/failover-to-region.sh \
  --target-region eu-west-1 \
  --test-mode true

# 3. Validate service availability
./scripts/validate-dr.sh \
  --region eu-west-1 \
  --timeout 300

# 4. Failover back to primary
./scripts/failover-to-region.sh \
  --target-region us-east-1

# 5. Generate DR test report
./scripts/dr-test-report.sh

# Expected output:
# ✅ Primary → Secondary failover: 45s
# ✅ All services available in 90s
# ✅ Data consistency verified
# ✅ Secondary → Primary failover: 30s
# ✅ RTO target: 5 minutes ✅ MET
# ✅ RPO target: 1 minute ✅ MET
```

### Emergency Failover (Production Down)

```bash
# 1. Declare disaster
./scripts/declare-disaster.sh

# 2. Immediate failover to secondary region
./scripts/failover-to-region.sh \
  --target-region eu-west-1 \
  --emergency true

# 3. Verify all services
./scripts/verify-services.sh

# 4. DNS update (automatic)
# Points traffic to secondary region

# 5. Escalate to incident commander
./scripts/escalate-to-commander.sh

# Expected timeline:
# T+0s   - Disaster detected
# T+10s  - Failover initiated
# T+60s  - Secondary region ready
# T+90s  - Services verified
# T+120s - Traffic fully switched
```

### Data Recovery

```bash
# 1. Check backup status
./scripts/check-backups.sh

# 2. Restore from scheduled backup
./scripts/restore-backup.sh \
  --timestamp "2026-04-13 12:00:00" \
  --target-region eu-west-1

# 3. Validate data integrity
./scripts/validate-data-integrity.sh

# 4. Point services to restored data
./scripts/point-to-backup.sh \
  --region eu-west-1

# Expected output:
# ✅ Backup found: 2026-04-13 12:00:00
# ✅ Restore started: 12:30:45 UTC
# ✅ Restore complete: 12:45:30 UTC (15 minutes)
# ✅ Data integrity: VERIFIED
# ✅ Services switched
```

---

## Troubleshooting

### High Error Rate

```bash
# 1. Check error logs
tail -n 1000 /var/log/platform/errors.log | grep -i "ERROR"

# 2. Sample errors by type
grep "ERROR" /var/log/platform/errors.log | \
  awk -F']: ' '{print $2}' | \
  sort | uniq -c | sort -rn

# 3. Check specific service
./scripts/check-service-logs.sh api

# 4. Check database connections
mysql -h db.production.local -u admin -p -e \
  "SHOW PROCESSLIST; SHOW STATUS WHERE variable_name = 'Threads_connected';"

# 5. Check cache connections
redis-cli INFO stats | grep -i connected
```

### High Latency

```bash
# 1. Check database query performance
./scripts/check-slow-queries.sh --limit 20

# 2. Check cache hit rate
redis-cli INFO stats | grep hit_rate

# 3. Check network latency
./scripts/check-network-latency.sh --hops 10

# 4. Check CPU/memory usage
./scripts/check-resource-usage.sh

# 5. Check active connections
netstat -an | grep ESTABLISHED | wc -l
```

### Service Not Responding

```bash
# 1. Check service status
./scripts/check-service.sh api

# 2. Check logs
tail -n 100 /var/log/platform/api.log

# 3. Restart service
./scripts/restart-service.sh api

# 4. Verify startup
./scripts/verify-service.sh api --timeout 60

# 5. Check health endpoint
curl https://api.production.local/health -v
```

### Database Issues

```bash
# 1. Check database status
mysql -h db.production.local -u admin -p -e "STATUS;"

# 2. Check replication status
mysql -h db.production.local -u admin -p -e "SHOW SLAVE STATUS\G"

# 3. Check table integrity
mysqlcheck -h db.production.local -u admin -p --all-databases

# 4. Check slow queries
mysql -h db.production.local -u admin -p -e \
  "SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 20;"

# 5. Optimize if needed
mysql -h db.production.local -u admin -p -e \
  "OPTIMIZE TABLE important_table;"
```

---

## Maintenance

### Daily Maintenance (5 min)

```bash
# Every day at 06:00 UTC
0 6 * * * /opt/platform/scripts/daily-maintenance.sh

# Runs:
# ✅ Health check
# ✅ SLO compliance verification
# ✅ Backup verification
# ✅ Log rotation
# ✅ Cache cleanup
```

### Weekly Maintenance (30 min)

```bash
# Every Sunday at 02:00 UTC
0 2 * * 0 /opt/platform/scripts/weekly-maintenance.sh

# Runs:
# ✅ Database optimization
# ✅ Index analysis
# ✅ Backup integrity test
# ✅ Security audit
# ✅ Performance baseline update
```

### Monthly Maintenance (1 hour)

```bash
# First Sunday of month at 02:00 UTC
0 2 1-7 * 0 /opt/platform/scripts/monthly-maintenance.sh

# Runs:
# ✅ Full disaster recovery test
# ✅ Security penetration test
# ✅ Compliance audit
# ✅ Documentation update
# ✅ Capacity planning review
```

### Backup Management

```bash
# View scheduled backups
./scripts/list-backups.sh

# Backup schedule:
# - Hourly: Last 24 hours (kept for 24 hours)
# - Daily: Last 7 days (kept for 7 days)
# - Weekly: Last 4 weeks (kept for 12 weeks)
# - Monthly: Last 12 months (kept for 5 years)

# Manual backup
./scripts/create-backup.sh --target all

# Test backup recovery
./scripts/test-backup-recovery.sh --backup-id <backup-id>

# Delete old backups
./scripts/cleanup-backups.sh --older-than 365  # days
```

---

## Emergency Procedures

### CRITICAL: Immediate System Shutdown

**Use only if system is under attack or severely compromised**

```bash
# 1. Declare emergency
./scripts/emergency-shutdown.sh

# 2. All services stop (30 seconds grace period)
# 3. Connections drained
# 4. Team notified
# 5. Investigation mode enabled

# To restore:
./scripts/emergency-restore.sh
```

### CRITICAL: Network Isolation

**Disconnect system from network in case of attack**

```bash
# 1. Isolate from network
./scripts/network-isolate.sh

# 2. Impact: System fully disconnected from external networks
# 3. Internal health checks continue
# 4. Diagnostic mode enabled
# 5. Team can SSH directly to instances

# To reconnect:
./scripts/network-restore.sh
```

### CRITICAL: Reset Security Context

**Clear compromised authentication tokens**

```bash
# 1. Revoke all active tokens
./scripts/revoke-all-tokens.sh

# 2. Impact: All users must re-authenticate
# 3. All API access requires new token
# 4. No interruption to existing connections

# 2. Force re-authentication
./scripts/force-reauthentication.sh
```

### Contact On-Call Engineer

```bash
# Immediate page
./scripts/page-oncall.sh \
  --severity CRITICAL \
  --message "System critical incident"

# Expected response: < 5 minutes
```

---

## Checklists

### Pre-Deployment Checklist

- [ ] All tests passing (unit, integration, performance)
- [ ] Security scan completed, 0 vulnerabilities
- [ ] Staging environment fully tested
- [ ] SLO baseline established
- [ ] Team briefed on deployment plan
- [ ] Rollback procedure verified
- [ ] On-call engineer available
- [ ] Incident commander available
- [ ] War room setup (if large deployment)

### Post-Deployment Checklist

- [ ] All metrics within SLO targets
- [ ] No elevated error rates
- [ ] Health checks all passing
- [ ] Audit logs complete
- [ ] Compliance verified
- [ ] Performance baseline exceeded or matched
- [ ] Team debriefing completed
- [ ] Lessons learned documented
- [ ] Artifacts archived

### Monthly Review Checklist

- [ ] SLO compliance report reviewed
- [ ] Incident retrospectives completed
- [ ] Capacity planning reviewed
- [ ] Security audit completed
- [ ] Backup recovery test passed
- [ ] Disaster recovery test passed
- [ ] Documentation updated
- [ ] Team training completed
- [ ] Budget vs. actual reviewed

---

## Escalation Procedures

### Level 1: Automated Response
- Automatic incident detection and initial response
- No human intervention unless failure
- **Response time**: < 1 minute

### Level 2: On-Call Engineer
- Paged if automatic response fails
- Manual investigation and execution
- **Response time**: < 5 minutes

### Level 3: Team Lead
- Paged if issue persists > 10 minutes
- Escalation and decision authority
- **Response time**: < 10 minutes

### Level 4: Incident Commander
- Engaged for SEVx events (> 5,000 users affected
- War room coordination
- **Response time**: < 15 minutes

### Level 5: CTO/Director
- Engaged for P1 incidents (business critical)
- Executive communication
- **Response time**: < 30 minutes

---

## Contact Information

| Role | On-Call | Phone | Slack |
|------|---------|-------|-------|
| Platform Engineer | @on-call-eng | +1-555-0100 | #incidents-platform |
| Team Lead | @team-lead | +1-555-0101 | #incidents-team |
| Incident Commander | @incident-commander | +1-555-0102 | #incidents-command |
| CTO | @cto | +1-555-0103 | #cto |

---

**Document Version**: 1.0  
**Last Updated**: April 13, 2026  
**Next Review**: May 13, 2026
