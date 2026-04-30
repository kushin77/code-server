# Phase 2b Staging Deployment Checklist

**Version:** 1.0  
**Date:** April 30, 2026  
**Status:** Ready for Week 1 Deployment  

---

## Overview

Complete checklist for deploying Phase 2b orchestration to staging environment, validating all components, and preparing for production deployment.

---

## Pre-Deployment Phase (BEFORE starting)

### ✅ Code Review & PR Merge (Days 1-3)

- [ ] Create GitHub PR with GITHUB_PR_SUMMARY.md content
- [ ] Request 2+ deployment team leads for review
- [ ] Monitor PR comments and address feedback
- [ ] Ensure all GitHub Actions CI/CD checks pass
- [ ] Get 2+ approvals from reviewers
- [ ] Merge PR to main branch
- [ ] Verify CI/CD passes on main
- [ ] Tag release: `v1.0-phase-2b`

**Gating Criteria:**
- ✅ PR approved by 2+ team leads
- ✅ All status checks passing
- ✅ No merge conflicts
- ✅ Tests pass on main

---

## Staging Environment Setup (Day 3-4)

### ✅ Infrastructure Preparation

```bash
# Pull latest from main
cd /home/akushnir/code-server
git checkout main
git pull origin main

# Verify Phase 2b components exist
ls -la scripts/ops/orchestrate-deployment.sh
ls -la scripts/ops/check-gitlab-compose-parity.sh
ls -la scripts/ops/gcp-deploy.sh
```

**Checklist:**
- [ ] Checked out main branch
- [ ] Pulled latest code
- [ ] All Phase 2b scripts present
- [ ] File permissions correct (executable)
- [ ] Documentation accessible

### ✅ Staging Environment Variables

```bash
# For LOCAL staging deployment
export PRIMARY_HOST="staging-primary-ip"
export REPLICA_HOST="staging-replica-ip"
export SSH_KEY_PATH="$HOME/.ssh/staging-key"

# For GCP staging deployment (if applicable)
export GCP_PROJECT_ID="staging-project-id"
export GCP_CREDENTIALS_JSON="$HOME/.gcp/staging-credentials.json"
export GCP_ZONE="us-central1-a"
export GCP_MACHINE_TYPE="e2-standard-4"
export DISK_SIZE_GB="50"  # Smaller for staging
```

**Checklist:**
- [ ] Environment variables set correctly
- [ ] SSH keys available (if local staging)
- [ ] GCP credentials available (if GCP staging)
- [ ] Credentials are for staging environment only
- [ ] Backup of production credentials exists

### ✅ Staging Infrastructure Health Check

```bash
# Verify staging infrastructure exists
if [ "$GCP_PROJECT_ID" != "" ]; then
  # GCP staging
  curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "https://www.googleapis.com/compute/v1/projects/$GCP_PROJECT_ID/zones/$GCP_ZONE/instances" | jq '.items | length'
else
  # Local staging
  ssh -o ConnectTimeout=5 "root@$PRIMARY_HOST" "echo 'SSH OK'"
  ssh -o ConnectTimeout=5 "root@$REPLICA_HOST" "echo 'SSH OK'"
fi
```

**Checklist:**
- [ ] Staging infrastructure accessible
- [ ] SSH connectivity verified (local) OR GCP API accessible
- [ ] Sufficient disk space available
- [ ] Network connectivity confirmed
- [ ] Firewall rules allow communication

---

## Phase 1: Pre-Deployment Validation (Day 4)

### ✅ Dry-Run Validation (NO CHANGES MADE)

```bash
# Test orchestration script in dry-run mode
bash scripts/ops/orchestrate-deployment.sh local --dry-run --verbose

# Expected output:
# [SUCCESS] ✅ All prerequisites validated
# [SUCCESS] ✅ SSH connectivity verified
# [SUCCESS] ✅ Deployment orchestration completed successfully
```

**Checklist:**
- [ ] Orchestration script syntax valid
- [ ] Prerequisites available
- [ ] Environment variables correct
- [ ] Dry-run completes without errors
- [ ] No actual changes made to infrastructure
- [ ] All prerequisite commands available (curl, jq, docker, docker-compose)

### ✅ Phase 2b Validation Script Test

```bash
# Test Phase 2b validation without actual deployment
bash scripts/ops/full-deployment-test.sh --dry-run

# Expected output:
# Phase 1: Infrastructure Validation ✅ PASSED
# Phase 2: GitOps Drift Detection ✅ PASSED
# Phase 2b: GitLab Compose Parity ✅ PASSED
# Phase 3: Deployment Simulation ✅ PASSED
# Phase 4: Health Check Validation ✅ PASSED
# Phase 5: Rollback Verification ✅ PASSED
```

**Checklist:**
- [ ] Phase 2b test script executes
- [ ] All 6 phases report in dry-run
- [ ] No errors in validation logic
- [ ] Test artifacts created correctly

### ✅ Configuration Verification

```bash
# Verify docker-compose configuration
docker-compose -f docker-compose.enterprise.yml config > /tmp/staging-compose-check.yml

# Verify parity gate logic
bash scripts/ops/check-gitlab-compose-parity.sh --help
```

**Checklist:**
- [ ] docker-compose.yml syntax valid
- [ ] All environment variables substitutable
- [ ] Parity gate script has correct logic
- [ ] No hardcoded values that should be configurable

---

## Phase 2: Staging Deployment (Day 5)

### ✅ Backup & Checkpoint

```bash
# Create checkpoint before deployment
git tag -a "staging-checkpoint-20260430" -m "Staging deployment checkpoint"
git push origin staging-checkpoint-20260430

# Backup any state files
mkdir -p /tmp/staging-backup-$(date +%Y%m%d)
if [ -f "terraform/terraform.tfstate" ]; then
  cp terraform/terraform.tfstate /tmp/staging-backup-$(date +%Y%m%d)/
fi
```

**Checklist:**
- [ ] Checkpoint tag created and pushed
- [ ] Terraform state backed up (if applicable)
- [ ] Configuration backed up
- [ ] SSH keys secured
- [ ] Backup location documented

### ✅ Execute Staging Deployment (ACTUAL DEPLOYMENT STARTS HERE)

```bash
# Step 1: Initial infrastructure validation
bash scripts/ops/orchestrate-deployment.sh local --verbose

# If GCP staging:
# bash scripts/ops/orchestrate-deployment.sh gcp --verbose
```

**Checklist:**
- [ ] Orchestration script runs successfully
- [ ] Infrastructure deployed/verified
- [ ] All stages complete without errors
- [ ] Deployment report generated
- [ ] IPs extracted and verified
- [ ] Phase 2b validation runs automatically
- [ ] All 6 phases report PASSED

### ✅ Immediate Post-Deployment Checks (First 30 minutes)

```bash
# Check deployment report
cat artifacts/deployment-report-*.json | jq '.'

# Verify infrastructure accessibility
ssh "root@$PRIMARY_HOST" "docker ps --filter status=running | wc -l"
ssh "root@$REPLICA_HOST" "docker ps --filter status=running | wc -l"

# Check Phase 2b parity
bash scripts/ops/check-gitlab-compose-parity.sh

# Verify container health
ssh "root@$PRIMARY_HOST" "docker-compose ps"
ssh "root@$REPLICA_HOST" "docker-compose ps"
```

**Checklist:**
- [ ] Deployment report shows success
- [ ] PRIMARY host has 87+ containers running
- [ ] REPLICA host has 88 containers running
- [ ] Parity gate passes (checksums match)
- [ ] All containers in running state
- [ ] No container restart loops
- [ ] Database connectivity working

---

## Phase 3: Comprehensive Validation (Day 5-6)

### ✅ Configuration Parity Check

```bash
# Detailed parity verification
PRIMARY_CHECKSUM=$(ssh "root@$PRIMARY_HOST" \
  "sha256sum docker-compose.enterprise.yml | cut -d' ' -f1")

REPLICA_CHECKSUM=$(ssh "root@$REPLICA_HOST" \
  "sha256sum docker-compose.enterprise.yml | cut -d' ' -f1")

if [ "$PRIMARY_CHECKSUM" == "$REPLICA_CHECKSUM" ]; then
  echo "✅ Configuration parity: PASSED"
else
  echo "❌ Configuration parity: FAILED"
  echo "PRIMARY: $PRIMARY_CHECKSUM"
  echo "REPLICA: $REPLICA_CHECKSUM"
fi
```

**Checklist:**
- [ ] docker-compose files identical (SHA256)
- [ ] Database configurations match
- [ ] Memory allocations identical
- [ ] Worker counts match
- [ ] Service versions match
- [ ] Network configurations match

### ✅ Health Check Validation

```bash
# GitLab service health
ssh "root@$PRIMARY_HOST" "curl -s http://localhost:8101 | head -20"

# Database replication status
ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql \
  psql -U postgres -c 'SELECT * FROM pg_stat_replication;'"

# Redis replication
ssh "root@$PRIMARY_HOST" "docker exec gitlab-redis \
  redis-cli INFO replication"
```

**Checklist:**
- [ ] GitLab HTTP endpoint responds (port 8101)
- [ ] Database replication active (PRIMARY → REPLICA)
- [ ] Redis replication active (PRIMARY → REPLICA)
- [ ] No replication lag or errors
- [ ] All health checks report healthy

### ✅ Performance Baseline

```bash
# Capture baseline metrics
mkdir -p /tmp/staging-metrics-baseline

# CPU usage
ssh "root@$PRIMARY_HOST" "top -bn1 | head -20" > /tmp/staging-metrics-baseline/cpu-primary.txt
ssh "root@$REPLICA_HOST" "top -bn1 | head -20" > /tmp/staging-metrics-baseline/cpu-replica.txt

# Memory usage
ssh "root@$PRIMARY_HOST" "free -h" > /tmp/staging-metrics-baseline/memory-primary.txt
ssh "root@$REPLICA_HOST" "free -h" > /tmp/staging-metrics-baseline/memory-replica.txt

# Disk usage
ssh "root@$PRIMARY_HOST" "df -h" > /tmp/staging-metrics-baseline/disk-primary.txt
ssh "root@$REPLICA_HOST" "df -h" > /tmp/staging-metrics-baseline/disk-replica.txt
```

**Checklist:**
- [ ] CPU usage captured (both hosts)
- [ ] Memory usage captured (both hosts)
- [ ] Disk usage captured (both hosts)
- [ ] Baseline metrics within acceptable ranges
- [ ] Metrics saved for comparison

---

## Phase 4: Failover Drill (Day 6)

### ✅ Pre-Failover Validation

```bash
# Verify both hosts are healthy before failover drill
bash scripts/ops/full-deployment-test.sh --dry-run

# Expected: All phases PASSED
```

**Checklist:**
- [ ] All 6 phases pass in dry-run
- [ ] No parity issues detected
- [ ] Both hosts healthy
- [ ] Replication active
- [ ] VIP routing correct

### ✅ Execute Failover Drill

```bash
# Run non-destructive failover drill
bash scripts/ops/failover-drill.sh

# Expected output: 8/8 steps PASSED
```

**Checklist:**
- [ ] Baseline parity check: PASSED
- [ ] Pre-failover validation: PASSED
- [ ] VIP check: PASSED
- [ ] Failover simulation: PASSED
- [ ] Post-failover validation: PASSED
- [ ] Parity check after failover: PASSED
- [ ] Recovery: PASSED
- [ ] Post-recovery validation: PASSED

### ✅ Post-Failover Validation

```bash
# Verify services still operational
ssh "root@$PRIMARY_HOST" "docker ps --filter status=running | wc -l"
ssh "root@$REPLICA_HOST" "docker ps --filter status=running | wc -l"

# Verify parity maintained
bash scripts/ops/check-gitlab-compose-parity.sh

# Verify data integrity
ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql \
  psql -U postgres -c 'SELECT COUNT(*) FROM pg_database;'"
```

**Checklist:**
- [ ] Both hosts still running after drill
- [ ] No container crashes during failover
- [ ] Services came back online automatically
- [ ] Parity maintained through failover
- [ ] Data integrity verified
- [ ] No data loss during failover

---

## Phase 5: Monitoring Setup (Day 6-7)

### ✅ Prometheus Configuration

```bash
# Follow PHASE_2B_MONITORING_ALERTING_GUIDE.md for setup
# Configure Prometheus scrape targets

cat > /tmp/prometheus-phase2b.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'phase2b-primary'
    static_configs:
      - targets: ['${PRIMARY_HOST}:9090']
      
  - job_name: 'phase2b-replica'
    static_configs:
      - targets: ['${REPLICA_HOST}:9090']
      
  - job_name: 'gitlab-primary'
    static_configs:
      - targets: ['${PRIMARY_HOST}:8101']
      
  - job_name: 'gitlab-replica'
    static_configs:
      - targets: ['${REPLICA_HOST}:8101']
EOF
```

**Checklist:**
- [ ] Prometheus configuration created
- [ ] Scrape targets configured (both hosts)
- [ ] Metrics collection enabled
- [ ] Retention policy set (15+ days for staging)
- [ ] Performance acceptable (< 1% CPU overhead)

### ✅ Alert Rules Configuration

```bash
# Setup critical alert rules for Phase 2b
cat > /tmp/phase2b-alerts.yml << 'EOF'
groups:
  - name: phase2b_alerts
    rules:
      - alert: PrimaryHostDown
        expr: up{job="phase2b-primary"} == 0
        for: 1m
        annotations:
          summary: "PRIMARY host is down"
          
      - alert: ReplicaHostDown
        expr: up{job="phase2b-replica"} == 0
        for: 1m
        annotations:
          summary: "REPLICA host is down"
          
      - alert: ReplicationLag
        expr: pg_replication_lag_seconds > 10
        for: 5m
        annotations:
          summary: "Database replication lag > 10 seconds"
          
      - alert: PurityCheckFailed
        expr: gitlab_compose_parity != 1
        for: 1m
        annotations:
          summary: "Phase 2b parity check failed"
          
      - alert: ContainerCrashLoop
        expr: increase(docker_container_restarts[5m]) > 5
        for: 2m
        annotations:
          summary: "Container crash loop detected"
EOF
```

**Checklist:**
- [ ] Alert rules created
- [ ] 5 critical alerts configured
- [ ] Alert thresholds appropriate
- [ ] Notification channels configured
- [ ] Alert testing completed

### ✅ Grafana Dashboard Setup

```bash
# Create Grafana dashboards following guide
# Dashboard 1: Cluster Health
# - PRIMARY host status
# - REPLICA host status
# - Container count (both hosts)
# - Parity gate status

# Dashboard 2: Performance Metrics
# - CPU usage (PRIMARY and REPLICA)
# - Memory usage (PRIMARY and REPLICA)
# - Disk I/O (both hosts)
# - Network I/O (both hosts)

# Dashboard 3: Database Health
# - Connection count
# - Replication lag
# - Transaction rate
# - Cache hit rate
```

**Checklist:**
- [ ] Dashboard 1: Cluster Health created
- [ ] Dashboard 2: Performance Metrics created
- [ ] Dashboard 3: Database Health created
- [ ] All panels displaying data
- [ ] Refresh rate configured (30s)
- [ ] Alerts displayed on dashboards

### ✅ Notification Channels

```bash
# Configure notification channels
# - Slack: phase2b-staging
# - Email: devops-team@example.com
# - PagerDuty: phase2b-prod (for critical)
```

**Checklist:**
- [ ] Slack channel created: #phase2b-staging
- [ ] Slack integration tested
- [ ] Email recipients configured
- [ ] PagerDuty integration active
- [ ] Test alert sent successfully

---

## Phase 6: Performance Testing (Day 7)

### ✅ Load Testing

```bash
# Generate baseline load to verify system stability
# Option 1: Use existing load test suite
# Option 2: Create simple test:

for i in {1..100}; do
  curl -s "http://$PRIMARY_HOST:8101/api/v4/version" > /dev/null &
done
wait

# Monitor system response
ssh "root@$PRIMARY_HOST" "docker stats --no-stream"
```

**Checklist:**
- [ ] Load test completed
- [ ] Response times stable
- [ ] No error spikes
- [ ] CPU usage acceptable (< 80%)
- [ ] Memory usage stable
- [ ] Container restarts: 0

### ✅ Failover Under Load

```bash
# Optional: Test failover while system is under load
# This verifies no data loss during high-activity failover

# 1. Start load generator
# 2. Wait for steady state
# 3. Trigger failover
# 4. Verify no errors in application logs
# 5. Verify parity maintained
```

**Checklist:**
- [ ] Load maintained during failover
- [ ] No requests dropped
- [ ] Application recovered cleanly
- [ ] Data integrity verified
- [ ] Parity maintained

---

## Phase 7: Documentation & Sign-Off (Day 7-8)

### ✅ Create Staging Deployment Report

```bash
cat > /tmp/staging-deployment-report.md << 'EOF'
# Phase 2b Staging Deployment Report

## Deployment Date
April 30 - May 7, 2026

## Infrastructure
- PRIMARY: [IP]
- REPLICA: [IP]
- VIP: [IP]

## Validation Results
- Phase 2b: PASS/PASS/PASS/PASS/PASS/PASS ✅
- Failover Drill: 8/8 steps PASSED ✅
- Parity Check: PASSED ✅
- Health Checks: ALL PASSED ✅

## Performance Baseline
[Captured metrics]

## Monitoring
- Prometheus: Active
- Grafana: 3 dashboards
- Alerts: 5 critical rules
- Notifications: Slack + Email + PagerDuty

## Issues Found
[List any issues and resolutions]

## Sign-Off
- [ ] Infrastructure Lead: ___________
- [ ] Operations Lead: ___________
- [ ] DevOps Lead: ___________

## Ready for Production: YES / NO
EOF
```

**Checklist:**
- [ ] All test results documented
- [ ] All metrics captured
- [ ] All issues resolved
- [ ] 3+ sign-offs obtained
- [ ] Report stored in git

### ✅ Operations Team Readiness

```bash
# Schedule training sessions
# - 1 hour: Phase 2b overview
# - 1 hour: Orchestration script walkthrough
# - 1 hour: Monitoring and alerts
# - 2 hours: Hands-on lab in staging
# - 1 hour: Troubleshooting procedures
```

**Checklist:**
- [ ] Training scheduled
- [ ] Operations team attended
- [ ] Q&A documented
- [ ] Runbooks reviewed
- [ ] On-call procedures tested

### ✅ Production Readiness Sign-Off

- [ ] Infrastructure validated in staging
- [ ] All tests passing
- [ ] Monitoring active and tested
- [ ] Team trained
- [ ] Runbooks updated
- [ ] Disaster recovery plan reviewed
- [ ] Backup procedures verified
- [ ] Security review completed
- [ ] Performance acceptable
- [ ] Cost analysis acceptable

---

## Production Deployment Prerequisites (Before Going Live)

### ✅ Production Credentials

- [ ] Production SSH keys staged
- [ ] GCP production credentials available
- [ ] Database credentials secured
- [ ] All credentials in vault/secret manager
- [ ] Access controls verified

### ✅ Production Environment

- [ ] Production infrastructure ready
- [ ] Production monitoring active
- [ ] Production backups tested
- [ ] Disaster recovery rehearsed
- [ ] Rollback procedure documented

### ✅ Team Readiness

- [ ] Operations team on-call assigned
- [ ] Incident response plan reviewed
- [ ] Escalation procedures defined
- [ ] Communication plan established
- [ ] Post-deployment review scheduled

---

## Go/No-Go Decision

**Staging Deployment Complete?**
- [ ] YES - Proceed to Production (Day 8)
- [ ] NO - Schedule re-test for: ___________

**Approval:**
- [ ] Infrastructure Lead
- [ ] Operations Lead
- [ ] Security Lead
- [ ] Executive Sponsor

---

## Rollback Procedure (If Needed)

### Quick Rollback to Previous Version

```bash
# 1. Stop current deployment
bash scripts/ops/orchestrate-deployment.sh stop

# 2. Revert to previous tag
git checkout v1.0-phase-2b-stable

# 3. Restart with known-good configuration
bash scripts/ops/orchestrate-deployment.sh local

# 4. Verify Phase 2b still functional
bash scripts/ops/full-deployment-test.sh
```

**Checklist:**
- [ ] Rollback plan reviewed
- [ ] Previous version backed up
- [ ] Rollback time target: < 15 minutes
- [ ] Success criteria defined
- [ ] Communication plan established

---

## Success Criteria

| Criterion | Target | Actual | Status |
|-----------|--------|--------|--------|
| Phase 2b Validation | PASS/PASS/PASS/PASS/PASS/PASS | | |
| Failover Drill | 8/8 steps | | |
| Parity Check | 100% match | | |
| Container Health | 87+ running | | |
| CPU Usage | < 80% | | |
| Memory Usage | < 90% | | |
| Monitoring | 3 dashboards + 5 alerts | | |
| Team Training | 100% attendance | | |
| Documentation | Complete | | |

---

**Version:** 1.0  
**Status:** Ready for Week 1 Execution  
**Created:** April 30, 2026

