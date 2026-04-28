# Comprehensive Operations Runbook

**Date:** April 28, 2026  
**Version:** 1.0.0  
**Status:** Production-Ready

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Deployment Procedures](#deployment-procedures)
3. [Monitoring & Observability](#monitoring--observability)
4. [Incident Response](#incident-response)
5. [Compliance & Auditing](#compliance--auditing)
6. [Security & Secrets Management](#security--secrets-management)
7. [Troubleshooting](#troubleshooting)
8. [Recovery Procedures](#recovery-procedures)

---

## Quick Start

### Pre-Deployment Checklist

```bash
# 1. Verify deployment readiness
bash scripts/ci/verify-deployment-readiness.sh

# 2. Run pre-flight health checks
bash scripts/ci/quick-health-check.sh

# 3. Generate audit report
bash scripts/compliance/audit-framework.sh summary ./audit.json

# 4. Check deployment state
bash scripts/ops/deployment-state-machine.sh status
```

### Standard Deployment

```bash
# 1. Transition to DEPLOYING state
bash scripts/ops/deployment-state-machine.sh transition DEPLOYING "Standard deployment initiated"

# 2. Run orchestrated deployment (5 phases)
bash scripts/ops/deployment-coordinator.sh

# 3. Monitor deployment progress
bash scripts/observability/infrastructure-monitor.sh --interval 10

# 4. Verify post-deployment
bash scripts/ci/quick-health-check.sh

# 5. Transition to STABLE state
bash scripts/ops/deployment-state-machine.sh transition STABLE "Deployment successful"
```

---

## Deployment Procedures

### Pre-Deployment Validation

**Script:** `scripts/ci/verify-deployment-readiness.sh`

Validates:
- Docker Compose files (all 9 manifests)
- Health check coverage (27/28 services)
- Script syntax (202 scripts)
- SSOT compliance (185/203 scripts)
- Resource limits (services)
- Image pinning (digest enforcement)
- Git status (clean working tree)
- Network configuration
- Volume configuration

**Expected Output:**
```
[2026-04-28T12:52:21Z] [SUCCESS] Passed:           11
[2026-04-28T12:52:21Z] [WARN] Warnings:         3
[2026-04-28T12:52:21Z] [SUCCESS] ✓ DEPLOYMENT READY - all critical checks passed
```

**Action if FAILED:**
```bash
# Review specific check
bash scripts/ci/verify-deployment-readiness.sh 2>&1 | grep -A5 FAILED

# Fix issues and re-run
bash scripts/ci/verify-deployment-readiness.sh
```

### Multi-Phase Deployment

**Script:** `scripts/ops/deployment-coordinator.sh`

Executes 5 coordinated phases:

**Phase 1: Validation**
- Docker Compose validation
- Readiness checks
- Health check coverage

**Phase 2: Pre-Flight**
- Resource verification (disk, memory)
- Git state validation
- Audit generation

**Phase 3: Preparation**
- Image building
- Dependency validation

**Phase 4: Deployment**
- Service startup
- Health check monitoring (30s timeout)

**Phase 5: Validation**
- Service health verification
- Data persistence checks
- Deployment reporting

**Usage:**
```bash
# Full deployment
bash scripts/ops/deployment-coordinator.sh

# Dry-run (test without deployment)
DRY_RUN=true bash scripts/ops/deployment-coordinator.sh

# Resume from specific phase
START_PHASE=3 bash scripts/ops/deployment-coordinator.sh
```

### Rollback Procedures

**Scenario:** Deployment fails during Phase 4

```bash
# 1. Transition to DEPLOYING_ERROR
bash scripts/ops/deployment-state-machine.sh transition DEPLOYING_ERROR "Rollback initiated"

# 2. Execute rollback
docker-compose down
docker volume prune -f  # Optional: clean unused volumes
docker-compose up -d

# 3. Verify recovery
bash scripts/ci/quick-health-check.sh

# 4. Transition to ROLLBACK state
bash scripts/ops/deployment-state-machine.sh transition ROLLBACK "Emergency rollback"

# 5. Transition to INIT
bash scripts/ops/deployment-state-machine.sh transition INIT "Ready for re-deployment"
```

---

## Monitoring & Observability

### Real-Time Infrastructure Monitoring

**Script:** `scripts/observability/infrastructure-monitor.sh`

Monitors:
- CPU usage (threshold: 80%)
- Memory usage (threshold: 80%)
- Disk usage (threshold: 80%)
- Network connections
- Process health (zombie detection)
- Container health

**Usage:**
```bash
# Standard monitoring (30s interval, 80% threshold)
bash scripts/observability/infrastructure-monitor.sh

# Custom parameters
bash scripts/observability/infrastructure-monitor.sh 10 75

# Output analysis
cat ./metrics.json | jq '.alerts'
```

### Grafana Dashboard Snapshots

**Script:** `scripts/observability/generate-grafana-snapshots.sh`

Generates:
- Dashboard snapshots for performance reports
- Configurable retention (default 30 days)
- Automatic cleanup of expired snapshots
- URL logging for audit trail

**Usage:**
```bash
# Generate snapshots
bash scripts/observability/generate-grafana-snapshots.sh

# Monitor output
tail -f /tmp/grafana-snapshots.log
```

### Health Check Verification

**Script:** `scripts/ci/quick-health-check.sh`

Verifies:
- Docker Compose service status
- Critical service connectivity (PostgreSQL, Redis, Redpanda, Grafana, Prometheus)
- System resource availability
- Deployment script validity

**Usage:**
```bash
# Quick health check
bash scripts/ci/quick-health-check.sh

# With custom timeout
bash scripts/ci/quick-health-check.sh 60
```

---

## Incident Response

### Service Outage Response

**Detection:**
```bash
# Automated detection
bash scripts/incident/response-automation.sh outage detect
```

**Automatic Response:**
```bash
# Triggered automatically or manually
bash scripts/incident/response-automation.sh outage respond
```

**Remediation:**
```bash
# Full recovery procedure
bash scripts/incident/response-automation.sh outage remediate
```

**Expected Actions:**
1. Collect diagnostics
2. Attempt service restart
3. Verify recovery
4. Full redeployment if needed

### Performance Degradation Response

**Detection:**
```bash
bash scripts/incident/response-automation.sh degradation detect
```

**Response Includes:**
1. System state capture (CPU, memory, disk)
2. Cache clearing
3. Performance optimization attempts
4. Scaling recommendations

### Security Incident Response

**Detection:**
```bash
bash scripts/incident/response-automation.sh security detect
```

**Manual Escalation Required:**
```bash
bash scripts/incident/response-automation.sh security respond
```

**Remediation Checklist:**
- Review access logs
- Identify attack source
- Update firewall rules
- Force password resets if needed
- Update SSH keys
- Scan for backdoors

---

## Compliance & Auditing

### Pre-Deployment Audit

**Script:** `scripts/ops/pre-deployment-audit.sh`

Generates audit manifest with:
- Git state verification
- Docker Compose validation
- Service health analysis
- Compliance metrics
- Security posture assessment
- Performance readiness

**Usage:**
```bash
# Generate audit
bash scripts/ops/pre-deployment-audit.sh

# With signature
bash scripts/ops/pre-deployment-audit.sh --sign
```

### Comprehensive Compliance Audit

**Script:** `scripts/compliance/audit-framework.sh`

Report Types:
- **Full:** Complete audit with all checks and metrics
- **Summary:** High-level compliance summary
- **Compliance:** Detailed compliance checklist

**Usage:**
```bash
# Full audit report
bash scripts/compliance/audit-framework.sh full ./audit-full.json

# Summary report
bash scripts/compliance/audit-framework.sh summary ./audit-summary.json

# Compliance checklist
bash scripts/compliance/audit-framework.sh compliance ./compliance.json
```

**Audit Coverage:**
- SSOT compliance (187/202 scripts)
- Image security (100% digest pinned)
- Health checks (28/28 services)
- Resource limits (configured)
- Secrets management (centralized)
- Deployment automation (active)

### Compliance Verification

```bash
# Verify SSOT compliance
find scripts -name "*.sh" -exec grep -l "source.*init.sh" {} \; | wc -l

# Verify image pinning
grep -r "@sha256:" docker-compose*.yml | wc -l

# Verify health checks
grep -c "healthcheck:" docker-compose.yml

# Verify resource limits
grep -c "memory:" docker-compose.yml
```

---

## Security & Secrets Management

### Loading Secrets

**Library:** `apps/_shared/bash/secrets-loader.sh`

**Usage:**
```bash
source apps/_shared/bash/secrets-loader.sh

# Load single secret
DB_PASSWORD=$(load_secret "DATABASE_PASSWORD")

# Load from file with permission check
CERT=$(load_secret_file "TLS_CERT" "/etc/certs/server.crt")

# Validate all required secrets
validate_all_secrets "DB_USER" "DB_PASS" "API_KEY"
```

**Validation Functions:**
```bash
# Check secret configured
validate_secret_configured "API_KEY"

# Check not empty
validate_secret_not_empty "DB_PASSWORD"

# Check format (regex)
validate_secret_format "EMAIL" '^[a-zA-Z0-9+_.-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

# Check minimum length
validate_secret_length "PASSWORD" 12
```

### Audit Trail

All secret access logged to `.secrets-audit.log`:
```
2026-04-28T12:00:00Z [load] DATABASE_PASSWORD (user: deploy@prod)
2026-04-28T12:00:05Z [clear] DATABASE_PASSWORD (user: deploy@prod)
```

### Secrets Cleanup

```bash
# Clear specific secret
clear_secret "API_KEY"

# Clear all loaded secrets
clear_all_secrets
```

---

## Troubleshooting

### Service Won't Start

**Diagnostics:**
```bash
# Check container logs
docker logs <container_name> -f

# Check health status
docker inspect <container_name> --format='{{.State.Health}}'

# Check resource constraints
docker inspect <container_name> --format='{{.HostConfig.Memory}}'
```

**Common Issues:**

1. **Port already in use**
   ```bash
   lsof -i :<port>
   # Kill process or change port mapping
   ```

2. **Out of memory**
   ```bash
   free -h
   docker ps --format 'table {{.Names}}\t{{.MemoryLimit}}'
   # Scale down or add resources
   ```

3. **Disk full**
   ```bash
   df -h
   docker system prune -a  # Clean unused images/volumes
   ```

### Deployment Stuck in State

**Recovery:**
```bash
# Check current state
bash scripts/ops/deployment-state-machine.sh status

# View state history
bash scripts/ops/deployment-state-machine.sh history

# Force recovery
bash scripts/ops/deployment-state-machine.sh recover
```

### Health Check Failures

**Investigation:**
```bash
# Check service endpoint
curl -v http://service-name:port/health

# Check container logs
docker logs service-name

# Validate configuration
docker-compose config | grep -A 10 "service-name:"
```

---

## Recovery Procedures

### Complete System Recovery

```bash
# 1. Stop all services
docker-compose down

# 2. Clean orphaned resources
docker system prune -a --volumes

# 3. Verify git state
git status

# 4. Re-initialize state
bash scripts/ops/deployment-state-machine.sh transition INIT "System recovery"

# 5. Run pre-deployment validation
bash scripts/ci/verify-deployment-readiness.sh

# 6. Full deployment
bash scripts/ops/deployment-coordinator.sh

# 7. Verify health
bash scripts/ci/quick-health-check.sh
```

### Database Recovery

```bash
# 1. Stop dependent services
docker-compose stop app-service

# 2. Check database health
docker exec postgres psql -U postgres -c "SELECT version();"

# 3. Restore from backup if needed
# Custom restoration procedure per backup strategy

# 4. Restart services
docker-compose up -d
```

### State Machine Reset

```bash
# If state machine is corrupted
rm -rf ./.deployment-state

# Reinitialize
bash scripts/ops/deployment-state-machine.sh status

# This will create fresh state directory
```

---

## Operational Metrics

**Production Deployment Status:**
- 11/14 checks passing
- 3 non-critical warnings only
- 0 blocking failures
- Average deployment time: 5-10 minutes
- Service startup time: 30-60 seconds per service
- Health check validation: 30 second interval

**Monitoring Thresholds:**
- CPU Alert: > 80%
- Memory Alert: > 80%
- Disk Alert: > 80%
- Service Restart Attempts: 3
- Container Health Timeout: 30 seconds

---

## Support & Escalation

**For Deployment Issues:**
- Review logs: `docker logs <service>`
- Check deployment readiness: `scripts/ci/verify-deployment-readiness.sh`
- Generate audit: `scripts/compliance/audit-framework.sh`

**For Incident Response:**
- Detect incident: `scripts/incident/response-automation.sh <type> detect`
- Respond: `scripts/incident/response-automation.sh <type> respond`
- Remediate: `scripts/incident/response-automation.sh <type> remediate`

**For Security Issues:**
- Emergency escalation required
- Run incident response: `scripts/incident/response-automation.sh security respond`

---

## Summary

This runbook provides complete operational procedures for:
- Deployment automation with safety checks
- Real-time infrastructure monitoring
- Incident detection and response
- Compliance verification and auditing
- Secrets management with audit trails
- Troubleshooting and recovery

All procedures are automated where possible with clear manual escalation paths.

**Status: PRODUCTION READY**
