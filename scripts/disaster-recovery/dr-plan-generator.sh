#!/usr/bin/env bash
# @file scripts/disaster-recovery/dr-plan-generator.sh
# @module disaster-recovery/planning
# @description Comprehensive disaster recovery plan generation and validation
# @governance GOV-004: Maintain operational continuity and data protection
# @usage dr-plan-generator.sh [--scenario outage|data-loss|security] [--output ./dr-plan.md]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "DR plan generation failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
SCENARIO="${1:-comprehensive}"
OUTPUT_FILE="${2:-.}/disaster-recovery-plan.md"
PLAN_ID="DRP-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "DISASTER RECOVERY PLAN GENERATOR"
log_info "═══════════════════════════════════════════════════════"
log_info "Plan ID: ${PLAN_ID}"
log_info "Scenario: ${SCENARIO}"
echo

# Initialize DR plan document
init_dr_plan() {
  cat > "${OUTPUT_FILE}" <<'EOF'
# Disaster Recovery Plan

## Document Information

**Plan ID:** [PLAN_ID]
**Generated:** [GENERATION_TIME]
**Version:** 1.0
**Status:** ACTIVE

**Last Updated:** [GENERATION_TIME]
**Next Review:** [NEXT_REVIEW]

---

## Executive Summary

This Disaster Recovery (DR) Plan outlines procedures for detecting,
responding to, and recovering from disasters affecting Code Server
Enterprise platform infrastructure, services, or data.

**Key Objectives:**
- Minimize service downtime (RTO)
- Prevent data loss (RPO)
- Maintain operational continuity
- Ensure stakeholder communication
- Document recovery procedures

---

## Table of Contents

1. [Disaster Classification](#disaster-classification)
2. [Recovery Objectives](#recovery-objectives)
3. [Disaster Detection](#disaster-detection)
4. [Response Procedures](#response-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Communication Plan](#communication-plan)
7. [Testing Schedule](#testing-schedule)
8. [Appendices](#appendices)

---

## Disaster Classification

### Severity Levels

| Level | Impact | RTO | RPO | Examples |
|-------|--------|-----|-----|----------|
| **Level 1 (Critical)** | Complete service outage | 15 min | 5 min | Core database failure, all services down |
| **Level 2 (High)** | Partial service degradation | 1 hour | 15 min | One critical service down |
| **Level 3 (Medium)** | Limited impact | 4 hours | 1 hour | Non-critical service down |
| **Level 4 (Low)** | Minimal impact | 24 hours | 4 hours | Monitoring or reporting issues |

### Disaster Types

#### 1. Infrastructure Failures
- **Data Center Outage**: Complete loss of physical infrastructure
- **Network Failure**: Loss of external connectivity
- **Storage Failure**: Database or persistent storage loss
- **Host Failure**: Compute node unavailable

#### 2. Application Failures
- **Service Crash**: Application process terminated
- **Memory Leak**: Service resource exhaustion
- **Configuration Error**: Invalid deployment configuration
- **Dependency Failure**: Required service unavailable

#### 3. Data Loss Events
- **Accidental Deletion**: User or process error
- **Database Corruption**: Data integrity compromise
- **Backup Failure**: No available recovery point
- **Encryption Key Loss**: Encrypted data inaccessible

#### 4. Security Incidents
- **Data Breach**: Unauthorized access to data
- **Malware Infection**: Compromised system
- **Account Compromise**: Unauthorized credential usage
- **DDoS Attack**: Service degradation from volumetric attack

---

## Recovery Objectives

### RTO (Recovery Time Objective)

**Target Recovery Times by Service:**

| Service | RTO | Justification |
|---------|-----|---------------|
| PostgreSQL Database | 15 min | Critical for all operations |
| Redis Cache | 5 min | Performance-critical |
| Redpanda Streams | 30 min | Message queue, non-blocking |
| Web UI | 30 min | User-facing, not data-critical |
| Monitoring Stack | 1 hour | Observability not blocking |

### RPO (Recovery Point Objective)

**Target Recovery Points by Data Type:**

| Data Type | RPO | Backup Frequency |
|-----------|-----|-----------------|
| Production Database | 5 minutes | Every 1 minute (continuous WAL) |
| Configuration Data | 15 minutes | Every 5 minutes |
| User Data | 1 hour | Hourly snapshots |
| Logs & Metrics | 6 hours | Daily retention |

---

## Disaster Detection

### Automated Monitoring

**Detection Mechanisms:**

1. **Health Checks**
   - Docker Compose health checks (10s interval, 3 retries)
   - Application-level heartbeats
   - Database connectivity probes
   - Network connectivity tests

2. **Metrics Monitoring**
   - CPU usage exceeding 90%
   - Memory usage exceeding 85%
   - Disk usage exceeding 90%
   - Network latency exceeding 500ms

3. **Log Aggregation**
   - Error rate anomalies
   - Exception flood detection
   - Security event alerts
   - Service restart triggers

### Manual Detection Triggers

- Escalated user support tickets
- Direct stakeholder reports
- Third-party service notifications
- Security alert notifications

### Alert Escalation

**Level 1 Critical (≤ 5 min response):**
- Automated SMS to on-call engineer
- PagerDuty critical alert
- Slack #incidents channel notification
- Automatic incident creation

**Level 2 High (≤ 15 min response):**
- Slack notification with @on-call mention
- Email to engineering lead
- Incident tracking creation

**Level 3 Medium (≤ 1 hour response):**
- Slack notification to #ops channel
- Email notification
- Add to daily standup agenda

---

## Response Procedures

### Incident Commander Activation

**When to activate:** Any Level 1 or 2 disaster

**Incident Commander Responsibilities:**
1. Declare incident severity
2. Gather incident response team
3. Maintain incident timeline
4. Communicate with stakeholders
5. Authorize recovery actions
6. Document all decisions

### Response Workflow

```
1. Detection (0 min)
   ↓
2. Acknowledgment (0-5 min)
   ↓
3. Initial Assessment (5-15 min)
   ↓
4. Action Authorization (15-30 min)
   ↓
5. Recovery Initiation (30+ min)
   ↓
6. Verification (Ongoing)
   ↓
7. Post-Incident Review (24 hours)
```

### First Response Checklist

**Immediate Actions (First 5 minutes):**

- [ ] Acknowledge alert
- [ ] Create incident ticket
- [ ] Gather incident response team
- [ ] Open command center chat
- [ ] Begin documentation/timeline
- [ ] Assess service impact
- [ ] Identify recovery approach

**Assessment (5-15 minutes):**

- [ ] Collect current metrics/logs
- [ ] Determine root cause
- [ ] Estimate recovery time
- [ ] Identify dependencies
- [ ] Plan communication
- [ ] Authorize recovery actions

---

## Recovery Procedures

### Service Recovery Playbooks

#### PostgreSQL Database Recovery

**Symptom:** Database connection failures

**Immediate Actions:**
1. Verify Docker container status: `docker ps | grep postgres`
2. Check database logs: `docker logs <postgres-container>`
3. Verify disk space: `docker exec <postgres> df -h`

**Recovery Steps:**

```bash
# Option 1: Restart service
docker-compose restart postgres

# Option 2: Restore from backup
docker exec postgres pg_restore -d myapp /backups/latest.dump

# Option 3: Full recovery
bash scripts/ops/rollback-manager.sh --restore-database
```

**Verification:**
- [ ] Database responding to queries
- [ ] All tables accessible
- [ ] Data integrity verified
- [ ] Replication status OK

#### Redis Cache Recovery

**Symptom:** Cache unavailable or corrupted

**Immediate Actions:**
1. Check Redis status: `redis-cli ping`
2. Verify memory: `redis-cli info memory`
3. Check connections: `redis-cli info clients`

**Recovery Steps:**

```bash
# Option 1: Clear and restart
docker-compose exec redis redis-cli FLUSHALL
docker-compose restart redis

# Option 2: Restore from AOF
docker exec redis redis-cli BGREWRITEAOF
```

#### Complete Service Stack Recovery

**Symptom:** Multiple services down or corrupt

**Recovery Steps:**

```bash
# Execute full recovery
bash scripts/ops/deployment-coordinator.sh --recover --phase 5

# Monitor recovery
bash scripts/observability/infrastructure-monitor.sh

# Verify health
bash scripts/ci/health-check.sh
```

---

## Communication Plan

### Stakeholder Notification Template

**Subject:** [SEVERITY] Service Incident Report - [Service Name]

```
Incident ID: [ID]
Start Time: [START]
Current Status: [STATUS]
Estimated Resolution: [ETA]

Impact:
[Description of affected services/users]

Root Cause:
[If determined]

Mitigation Steps:
[Actions being taken]

Updates:
[Timeline of updates]

Next Update: [TIME]
```

### Status Page Updates

**Incident Declared:**
- Set status to "Investigating"
- Post initial impact description
- Provide ETA for next update

**Active Recovery:**
- Update ETA every 15 minutes
- Post major milestone achievements
- Increase detail as investigation progresses

**Recovery Complete:**
- Set status to "Resolved"
- Post final timeline and impact
- Schedule post-incident review

---

## Testing Schedule

### Monthly DR Tests

**First Tuesday of each month (10:00 AM UTC)**

**Scenarios Rotated:**

1. **Month 1:** Database failover
2. **Month 2:** Service crash recovery
3. **Month 3:** Network partition
4. **Month 4:** Backup restoration

### Annual Full DR Exercise

**Scheduled:** Q1 (January-March)

**Duration:** 4 hours
**Scope:** Complete stack recovery
**Participants:** Full ops and engineering team
**Validation:** Independent verification

---

## Appendices

### A. Contact Information

**On-Call Engineer:**
- Primary: [NAME/EMAIL]
- Backup: [NAME/EMAIL]
- Escalation: [MANAGER/EMAIL]

**External Contacts:**
- Cloud Provider Support: [CONTACT]
- ISP Support: [CONTACT]
- Database Vendor Support: [CONTACT]

### B. Recovery Scripts Location

```
scripts/ops/
├── deployment-coordinator.sh       # Multi-phase recovery
├── rollback-manager.sh             # Rollback to known state
└── deployment-state-machine.sh     # State recovery

scripts/disaster-recovery/
├── dr-plan-generator.sh            # This document
└── recovery-automation.sh           # Automated recovery

scripts/compliance/
└── audit-framework.sh              # Post-incident audit
```

### C. Backup Locations

**Database Backups:**
- Primary: `/var/lib/postgresql/backups/`
- Secondary: Cloud storage (encrypted)
- Frequency: Continuous WAL archiving + hourly snapshots

**Configuration Backups:**
- Primary: Git repository (version controlled)
- Secondary: `/etc/codeserver/backups/`
- Frequency: On every deployment

### D. Documentation References

- OPERATIONS_RUNBOOK.md
- DEPLOYMENT_EXECUTION_PLAN.md
- docs/testing/validation-libraries.md
- docs/architecture/docker-compose-architecture.md

---

## Document History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | [GENERATION_TIME] | Initial creation | Automation |

---

**Approval:**

- [ ] Engineering Lead: _________________ Date: _______
- [ ] Operations Manager: _________________ Date: _______
- [ ] Security Officer: _________________ Date: _______

**Next Review Date:** [NEXT_REVIEW]

EOF

  # Substitute placeholders
  sed -i "s/\[PLAN_ID\]/${PLAN_ID}/g" "${OUTPUT_FILE}"
  sed -i "s/\[GENERATION_TIME\]/${GENERATION_TIME}/g" "${OUTPUT_FILE}"
  sed -i "s/\[NEXT_REVIEW\]/$(date -u -d '+90 days' +%Y-%m-%d)/g" "${OUTPUT_FILE}"
}

# Main execution
main() {
  init_dr_plan
  log_success "✓ Disaster Recovery Plan generated: ${OUTPUT_FILE}"
  log_info "Plan ID: ${PLAN_ID}"
  log_info "Total lines: $(wc -l < "${OUTPUT_FILE}")"
  return 0
}

main
