# Operations Deployment Procedures & Checklists

**Document**: Step-by-Step Deployment & Change Management  
**Version**: Phase 10  
**Date**: April 30, 2026  
**Audience**: Ops Team, DevOps, Release Engineers

---

## Section 1: Pre-Deployment Validation

### Pre-Deployment Checklist (15 minutes)

**Before ANY deployment, complete this checklist**:

```
ENVIRONMENT CHECK:
☐ Primary host accessible: ssh akushnir@192.168.168.31
☐ Replica host accessible: ssh akushnir@192.168.168.42
☐ VRRP virtual IP accessible: ssh akushnir@192.168.168.50
☐ Docker running on both hosts: docker ps | wc -l (should be ~50)
☐ Network connectivity: ping both hosts from jump host

CURRENT STATE CHECK:
☐ All validation checks pass: bash scripts/ci/validate-pre-apply.sh
☐ No terraform drift: cd terraform/environments/private && terraform plan | grep "resource_drift"
☐ No unhealthy containers: docker ps | grep -i unhealthy
☐ Disk space OK: df /home (should be <70%)
☐ Git state clean: git status (no uncommitted changes)

BACKUP CHECK:
☐ Current state committed: git log --oneline -1
☐ Database backup recent: ls -la backup-postgresql*.sql.gz (within 24h)
☐ Terraform state backed up: git status terraform/environments/private

TEAM CHECK:
☐ Deployment window approved by ops lead
☐ Rollback plan documented
☐ Escalation contact on standby
☐ Alert channels configured and tested
```

### Pre-Deployment Validation Script

```bash
#!/bin/bash
# Run all pre-deployment checks automatically

set -euo pipefail

echo "=== PRE-DEPLOYMENT VALIDATION ==="
echo ""

# 1. SSH connectivity
echo "Checking SSH connectivity..."
for host in 192.168.168.31 192.168.168.42 192.168.168.50; do
  ssh -o ConnectTimeout=5 akushnir@$host "echo OK" || {
    echo "FAIL: Cannot connect to $host"
    exit 1
  }
done
echo "✓ All hosts accessible"

# 2. Docker status
echo "Checking Docker status..."
PRIMARY_COUNT=$(ssh akushnir@192.168.168.31 "docker ps | wc -l")
REPLICA_COUNT=$(ssh akushnir@192.168.168.42 "docker ps | wc -l")
echo "  Primary containers: $PRIMARY_COUNT"
echo "  Replica containers: $REPLICA_COUNT"
[[ $PRIMARY_COUNT -gt 40 ]] || { echo "FAIL: Low container count on primary"; exit 1; }

# 3. Validation checks
echo "Running validation checks..."
bash scripts/ci/validate-pre-apply.sh || {
  echo "FAIL: Validation checks failed"
  exit 1
}
echo "✓ All validation checks passed"

# 4. Git status
echo "Checking git status..."
[[ -z "$(git status --porcelain)" ]] || {
  echo "FAIL: Uncommitted changes in git"
  exit 1
}
echo "✓ Git status clean"

echo ""
echo "=== PRE-DEPLOYMENT VALIDATION PASSED ==="
echo "Ready to proceed with deployment"
```

---

## Section 2: Deployment Procedures

### Procedure 1: Routine Container Update

**Scenario**: Update a single container (e.g., new version)

**Steps**:
```bash
# 1. SSH to primary
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server

# 2. Run validation
bash scripts/ci/validate-pre-apply.sh

# 3. Update terraform or docker-compose
# Option A: Via Terraform
cd terraform/environments/private
# Edit main.tf or variables.tf to change container image
terraform plan

# Option B: Via Docker Compose
cd /home/akushnir/code-server
docker-compose -f docker-compose.enterprise.yml pull
docker-compose -f docker-compose.enterprise.yml up -d <service-name>

# 4. Verify deployment
docker ps | grep <service-name>
docker logs <service-name> --tail=20

# 5. Run validation
bash scripts/ci/validate-pre-apply.sh

# 6. Monitor for 15 minutes
tail -f /tmp/code-server-remediation.log
# Look for any errors

# 7. Commit changes
git add -A
git commit -m "chore: update <service-name> to new version"
```

**Timeline**: 10-15 minutes  
**Risk**: LOW (single container, easy rollback)

---

### Procedure 2: Infrastructure Scaling

**Scenario**: Add new container or increase resources

**Steps**:
```bash
# 1. Pre-deployment checks
bash scripts/ci/validate-pre-apply.sh

# 2. Update Terraform
cd terraform/environments/private
vim main.tf  # Add new container or increase resources

# 3. Dry-run test
terraform plan -json | head -100  # Review changes

# 4. Commit proposed change
git add terraform/
git commit -m "proposal: scale <service-name>"

# 5. Review with team
git log --oneline -1
git show HEAD

# 6. Apply changes
terraform apply

# 7. Verify on both hosts
ssh akushnir@192.168.168.31 "docker ps | grep <new-service>"
ssh akushnir@192.168.168.42 "docker ps | grep <new-service>"

# 8. Validation checks
bash scripts/ci/validate-pre-apply.sh

# 9. SLO check
./scripts/ops/track-slo-metrics.sh
```

**Timeline**: 20-30 minutes  
**Risk**: MEDIUM (infrastructure change, affects all)

---

### Procedure 3: Full Redeployment (Both Hosts)

**Scenario**: Update infrastructure or deploy major changes

**Steps**:

**Phase 1: Preparation**
```bash
# 1. Pre-deployment validation
bash scripts/ci/validate-pre-apply.sh

# 2. Backup current state
git status
git add -A
git commit -m "backup: before full redeployment"

# 3. Review Terraform changes
cd terraform/environments/private
terraform plan -json | jq '.[] | select(.type == "resource_drift")'

# 4. Notify team
# "Starting full redeployment at 14:30 UTC"
```

**Phase 2: Primary Deployment**
```bash
# 1. SSH to primary
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server

# 2. Check VRRP status (should show MASTER)
ip addr show | grep 192.168.168.50

# 3. Apply Terraform
cd terraform/environments/private
terraform apply -auto-approve

# 4. Monitor containers coming up
watch -n 1 'docker ps | wc -l'

# 5. Validation checks
bash scripts/ci/validate-pre-apply.sh

# 6. Verify health
docker ps | grep -v "Up" | wc -l  # Should be 0 unhealthy
```

**Phase 3: Replica Deployment**
```bash
# 1. SSH to replica
ssh akushnir@192.168.168.42
cd /home/akushnir/code-server

# 2. Check VRRP status (should show BACKUP)
ip addr show | grep 192.168.168.50

# 3. Apply Terraform
cd terraform/environments/private
terraform apply -auto-approve

# 4. Monitor containers
watch -n 1 'docker ps | wc -l'

# 5. Validation checks
bash scripts/ci/validate-pre-apply.sh
```

**Phase 4: Verification**
```bash
# Back on primary (or any host)
cd /home/akushnir/code-server

# 1. Run full deployment test
timeout 60 bash scripts/ops/full-deployment-test.sh --dry-run
# Expected: 6/6 PASS

# 2. Check SLO metrics
./scripts/ops/track-slo-metrics.sh

# 3. Review Grafana dashboard
# → http://localhost:3000/d/code-server-ops
# → All panels should be green

# 4. Monitor alerts for 30 minutes
tail -f /tmp/code-server-remediation.log
# Should see: "All checks passed"
```

**Timeline**: 45-90 minutes  
**Risk**: HIGH (affects entire infrastructure)

---

### Procedure 4: Emergency Hotfix

**Scenario**: Critical bug fix needed immediately

**Steps**:
```bash
# 1. Minimal validation (skip long checks)
docker ps | wc -l
df /home

# 2. Make minimal change
# Option A: Quick restart (if issue is transient)
docker restart <container>

# Option B: Update and restart
docker pull <new-image>
docker restart <container>

# 3. Verify fix
docker logs <container> | tail -20

# 4. Run quick validation
bash scripts/ci/validate-pre-apply.sh

# 5. Commit for records
git add -A
git commit -m "hotfix: urgent fix for <issue>"

# 6. Schedule proper fix for later
# "Created ticket #XYZ for permanent fix"
```

**Timeline**: 5-10 minutes  
**Risk**: CRITICAL (minimal testing)

---

## Section 3: Rollback Procedures

### When to Rollback

**Criteria**:
- ✗ Validation checks failing after deployment
- ✗ Critical service not starting
- ✗ Performance degradation (>30% increase in response time)
- ✗ Data corruption suspected
- ✗ Unexpected container restarts (>10 in 5 minutes)

### Rollback Procedure

**Step 1: Stop the Damage**
```bash
# Immediately stop any automated processes
kill $(pgrep terraform)
kill $(pgrep docker-compose)

# Prevent auto-remediation from interfering
systemctl stop code-server-remediation.timer || true
```

**Step 2: Identify Last Good State**
```bash
# Check git history
git log --oneline | head -10

# Identify last good commit
git log --grep="deployment\|release" --oneline | head -5

# Example: commit abc123 was last successful deployment
```

**Step 3: Rollback on Primary**
```bash
# SSH to primary
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server

# Revert to last good state
git reset --hard abc123

# Reapply Terraform with old state
cd terraform/environments/private
terraform apply -auto-approve

# Verify
docker ps | wc -l
bash scripts/ci/validate-pre-apply.sh
```

**Step 4: Rollback on Replica**
```bash
# SSH to replica
ssh akushnir@192.168.168.42
cd /home/akushnir/code-server

# Same rollback steps
git reset --hard abc123
cd terraform/environments/private
terraform apply -auto-approve

# Verify
bash scripts/ci/validate-pre-apply.sh
```

**Step 5: Verify Recovery**
```bash
# Check both hosts
ssh akushnir@192.168.168.31 "docker ps | wc -l"
ssh akushnir@192.168.168.42 "docker ps | wc -l"

# Run full validation
bash scripts/ci/validate-pre-apply.sh

# Check dashboards
# → Grafana should return to green

# Post-mortem
# Commit rollback: git commit -m "rollback: revert deployment due to <issue>"
# Document what failed
# Create bug fix ticket
```

**Timeline**: 10-20 minutes  
**Post-Action**: Root cause analysis, implement fix, re-deploy

---

## Section 4: Change Management Process

### Change Request Template

```
Title: [DEPLOY] Brief description

Environment: Production / Staging
Risk Level: LOW / MEDIUM / HIGH
Timeline: <date/time>, ~<duration>

WHAT:
- What is being changed?
- Why is it needed?
- What files/components affected?

VALIDATION:
- Pre-deployment checks: PASS/FAIL
- Rollback plan: [Describe rollback steps]
- Testing completed: YES/NO

APPROVAL:
- Requested by: [Name]
- Approved by: [Name]
- Date: [Date]

COMMUNICATION:
- Team notified: YES/NO
- Stakeholders alerted: YES/NO
- On-call backup on standby: YES/NO
```

### Change Log Template

```
=== DEPLOYMENT LOG ===
Date: 2026-04-30T14:30:00Z
Deployer: [Name]
Change: [Brief description]

TIMELINE:
14:30 - Pre-deployment checks: PASS
14:32 - Terraform apply started
14:35 - Containers updated on primary
14:36 - Validation checks: PASS
14:38 - Containers updated on replica
14:40 - Full validation: PASS
14:45 - Monitoring checks: Green
14:50 - DEPLOYMENT COMPLETE

RESULTS:
✓ All validations passed
✓ All containers healthy
✓ SLO metrics normal
✓ No alerts triggered

ISSUES:
[None, or list any minor issues]

NEXT STEPS:
- Monitor for 24 hours
- [Any follow-up items]
```

---

## Section 5: Maintenance Windows

### Scheduled Maintenance

**When to Schedule**:
- ✓ Database backups (daily)
- ✓ Log rotation (daily)
- ✓ Disk cleanup (weekly)
- ✓ Metrics retention (monthly)

### Maintenance Checklist

```bash
# Monthly maintenance window

# 1. Backup databases
docker exec postgresql pg_dump -U postgres | gzip > monthly-backup-$(date +%Y%m%d).sql.gz

# 2. Verify backups
ls -lah monthly-backup-*.sql.gz

# 3. Review logs for issues
tail -500 /tmp/code-server-remediation.log | grep "ERROR\|CRITICAL"

# 4. Update metrics retention
# Currently: 15 days in Prometheus
# Adjust if needed in monitoring/prometheus.yml

# 5. Archive old logs
find /home/akushnir/code-server -name "*.log" -mtime +30 -exec gzip {} \;

# 6. Health check
bash scripts/ci/validate-pre-apply.sh

# 7. Document maintenance
git add -A
git commit -m "maint: monthly maintenance - backups, log rotation, cleanup"
```

---

## Section 6: Disaster Recovery Testing

### Quarterly DR Drill

**Schedule**: First Friday of every quarter (4 times/year)

**Scenario 1: Primary Host Failure**
```bash
# Simulate primary going down
ssh akushnir@192.168.168.31
sudo shutdown -h now

# Monitor failover
ssh akushnir@192.168.168.42
watch -n 1 'ip addr show | grep 192.168.168.50'

# Verify service continues
# → Check that traffic goes to replica
# → Verify VRRP failover occurred
# → Monitor until primary comes back

# Timeline: Failover should happen in <30 seconds
```

**Scenario 2: Terraform State Corruption**
```bash
# Simulate state corruption
cd terraform/environments/private
cp terraform.tfstate terraform.tfstate.backup
echo "{}" > terraform.tfstate

# Test recovery
terraform refresh
# Should fail with state mismatch

# Restore from backup
cp terraform.tfstate.backup terraform.tfstate
terraform refresh
# Should succeed

# Verify
terraform plan
```

**Scenario 3: Database Crash**
```bash
# Simulate database failure
docker stop postgresql

# Verify auto-restart (if enabled)
watch -n 1 'docker ps | grep postgresql'
# Should restart within 5 minutes

# If not auto-restarting
docker start postgresql
docker logs postgresql | tail -20
# Should recover

# Verify
docker exec postgresql psql -U postgres -c "SELECT 1"
```

**Document Results**:
```
DR DRILL REPORT - Q2 2026
Date: 2026-04-30
Duration: 45 minutes
Scenarios Tested: 3

RESULTS:
✓ Primary failover: 15 seconds (target <30s)
✓ State recovery: Successful
✓ Database recovery: 8 seconds (auto-restart)

ISSUES FOUND:
[None this quarter, or list issues]

ACTION ITEMS:
[Any follow-up improvements]

SIGN-OFF:
Approved by: [Name], Ops Lead
Date: [Date]
```

---

## Section 7: Change Calendar

### Sample Change Calendar

```
APRIL 2026
---------
04/30 - Deploy Phase 8-9 (Monitoring & Remediation)
        Risk: MEDIUM, Window: 2hrs, Lead: [Name]

MAY 2026
-------
05/07 - Q2 DR Drill (Quarterly)
        Risk: TEST, Window: 1hr, Lead: [Name]

05/10 - Upgrade PostgreSQL (Major)
        Risk: HIGH, Window: 4hrs, Lead: [Name]

05/17 - Scale to 75 containers
        Risk: MEDIUM, Window: 2hrs, Lead: [Name]

05/24 - System maintenance (Backups, logs)
        Risk: LOW, Window: 1hr, Lead: [Name]
```

---

**Status**: ✅ **DEPLOYMENT READY**

All procedures, checklists, and escalation paths documented for operations team.

