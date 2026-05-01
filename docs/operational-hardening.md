# Operational Hardening: Continuous Validation & Monitoring

**Document**: Operational Hardening Phase (April 30, 2026)  
**Scope**: code-server deployment validation and monitoring  
**Status**: Complete - Ready for Integration

---

## Overview

This document describes the **continuation hardening phase** that adds proactive operational safeguards to the code-server deployment pipeline:

1. **Pre-apply Validation** - Catch configuration and connectivity issues before deployment
2. **Policy Enforcement** - Prevent drift-masking anti-patterns in Terraform code  
3. **Drift Monitoring Watchdog** - Continuous detection of configuration drift and health degradation

---

## 1. Pre-Apply Validation (`scripts/ci/validate-pre-apply.sh`)

### Purpose
Runs **critical checks before `terraform apply`** to prevent bad deployments.

### Features
- ✅ Terraform syntax and format validation
- ✅ SSH connectivity to both hosts (primary + replica)
- ✅ Docker daemon availability and image pull capability
- ✅ PostgreSQL database connectivity (primary + replica)
- ✅ Redis availability check
- ✅ Disk space validation (recommend >10GB)
- ✅ Network connectivity between hosts
- ✅ Keepalived service status
- ✅ Terraform variables validation

### Usage

```bash
# Run before any terraform apply
./scripts/ci/validate-pre-apply.sh

# Expected output (success)
============================================
Pre-Apply Validation for code-server
============================================
[Terraform]
Checking Terraform syntax... ✓
Checking Terraform code formatting... ✓
[Connectivity]
SSH connectivity to hosts... ✓
Network connectivity between hosts... ✓
[Docker & Services]
Docker daemon on PRIMARY (192.168.168.31)... ✓
Docker daemon on REPLICA (192.168.168.42)... ✓
Docker images accessible (sample pull test)... ✓
Keepalived services... ✓
[Databases]
PostgreSQL connectivity on PRIMARY... ✓
PostgreSQL connectivity on REPLICA... ⚠
(replica may not have PostgreSQL running yet)
Redis connectivity on PRIMARY... ✓
[System Resources]
Disk space on PRIMARY... ✓
Disk space on REPLICA... ✓

============================================
Validation Summary
============================================
Passed: 12
Failed: 0

All critical checks passed ✓
Safe to proceed with: terraform apply
```

### Integration

Recommended to add to pre-deployment pipeline:

```bash
# In CI/CD workflow:
./scripts/ci/validate-pre-apply.sh || exit 1
terraform apply -auto-approve
```

---

## 2. Policy Enforcement (`scripts/ci/enforce-terraform-policies.sh`)

### Purpose
Enforce **anti-drift-masking policies** to prevent configuration drift from being hidden in Terraform code.

### Policies Enforced

1. **Forbidden Pattern**: `ignore_changes = [all]` (never allowed)
   - Rationale: Masks all resource changes, preventing drift detection

2. **Forbidden Pattern**: `env in ignore_changes` (removed in Phase 4)
   - Rationale: Environment variable drift must be visible, not hidden

3. **Required**: All containers must have lifecycle rules
   - Rationale: Prevents accidental state changes from resetting resources

4. **Documentation**: `ignore_changes` entries should have justification
   - Rationale: Makes intent explicit for future reviewers

### Usage

```bash
# Check policy compliance
./scripts/ci/enforce-terraform-policies.sh

# Expected output (compliant)
============================================
Terraform Policy Enforcement
============================================
Checking for drift masking patterns...
Checking for documented ignore_changes patterns...
Checking container lifecycle policies...
Containers defined: 50
ignore_changes entries found: 51

============================================
Policy Check Summary
============================================
✓ All policies compliant
```

### Exit Codes
- `0` - All policies compliant
- `1` - Policy violations found

---

## 3. Drift Monitoring Watchdog (`scripts/ops/drift-monitoring-watchdog.sh`)

### Purpose
Continuous detection of **configuration drift** and **health degradation** suitable for running as a scheduled job.

### Checks Performed

1. **Terraform Drift Detection** (jq-based parsing)
   - Counts `resource_drift` events from `terraform plan -json`
   - Alerts if drift increases > 5 resources in one cycle
   - Tracks improvement when drift decreases

2. **Container Health Check**
   - Queries Docker on both hosts for unhealthy containers
   - Identifies containers not in "healthy" or "Up" state
   - Alerts if unhealthy containers > 0

3. **Container Count Parity**
   - Compares container count between primary and replica
   - Alerts if difference > 2 containers
   - Useful for detecting replica sync failures

4. **Disk Space Monitoring**
   - Checks disk usage on both hosts
   - Warning if >80% used
   - Alert if <5GB available

5. **Keepalived VRRP Status**
   - Verifies keepalived containers running on both hosts
   - Ensures VRRP election mechanism is operational

### Usage

```bash
# Run once
./scripts/ops/drift-monitoring-watchdog.sh

# Setup as cron job (every 5 minutes)
*/5 * * * * /home/akushnir/code-server/scripts/ops/drift-monitoring-watchdog.sh

# Or use systemd timer:
# /etc/systemd/system/drift-monitor.service
# /etc/systemd/system/drift-monitor.timer

# Check alerts
cat /tmp/code-server-watchdog/alerts.log
```

### Output Example

```
============================================
Drift Monitoring Watchdog
============================================
Time: 2026-04-30 19:19:52

Checking Terraform drift...
  Drift check: OK (39 resources, change: 2)
Checking container health...
  Health check: OK (0 unhealthy)
Checking container count parity...
  Parity check: OK (primary=50, replica=50)
Checking disk space...
  Disk space: OK (primary=45%, replica=42%)
Checking Keepalived VRRP...
  VRRP status: OK

============================================
Watchdog Summary
============================================
Checks passed: 5
Checks failed: 0

All checks passed ✓
```

### Configuration Environment Variables

```bash
# Host addresses (default to production IPs)
PRIMARY_HOST=192.168.168.31
REPLICA_HOST=192.168.168.42

# Alert thresholds
ALERT_THRESHOLD_DRIFT_INCREASE=5    # Resources
ALERT_THRESHOLD_HEALTH=1             # Containers

# Alert channels (future enhancements)
ALERT_ENABLED=1
ALERT_EMAIL=""
ALERT_WEBHOOK=""
```

### State Files

The watchdog maintains state in `/tmp/code-server-watchdog/`:
- `alerts.log` - All alerts with timestamps
- `last-drift-state` - Previous drift count
- `last-health-state` - Previous unhealthy count

These files are used to detect increases/decreases in drift and health status.

---

## Integration into Deployment Pipeline

### Recommended Workflow

```bash
# 1. Pre-deployment validation (before apply)
./scripts/ci/validate-pre-apply.sh

# 2. Policy check (optional, but recommended)
./scripts/ci/enforce-terraform-policies.sh

# 3. Apply changes
terraform apply -auto-approve

# 4. Verify deployment
./scripts/ops/full-deployment-test.sh --dry-run

# 5. Start continuous monitoring
./scripts/ops/drift-monitoring-watchdog.sh

# 6. Schedule watchdog for continuous operation
(crontab -l 2>/dev/null; echo "*/5 * * * * ${REPO_ROOT}/scripts/ops/drift-monitoring-watchdog.sh") | crontab -
```

### CI/CD Integration (GitHub Actions)

```yaml
- name: Pre-apply validation
  run: ./scripts/ci/validate-pre-apply.sh

- name: Policy enforcement
  run: ./scripts/ci/enforce-terraform-policies.sh

- name: Apply Terraform
  run: terraform apply -auto-approve

- name: Post-deployment tests
  run: ./scripts/ops/full-deployment-test.sh --dry-run
```

---

## Troubleshooting

### Pre-Apply Validator

**Problem**: SSH connectivity checks fail  
**Solution**: Verify SSH keys are authorized on both hosts
```bash
ssh akushnir@192.168.168.31 'echo OK'
```

**Problem**: Docker images can't be pulled  
**Solution**: Check network connectivity and Docker Hub access
```bash
ssh akushnir@192.168.168.31 'docker pull alpine:latest'
```

### Policy Enforcement

**Problem**: Policy violations detected  
**Solution**: Review Terraform code for `ignore_changes` patterns
```bash
grep -rn 'ignore_changes = \[all\]' terraform/
grep -rn 'ignore_changes.*env' terraform/
```

### Drift Watchdog

**Problem**: Drift detected but deployment appears healthy  
**Solution**: Run full deployment test
```bash
./scripts/ops/full-deployment-test.sh --dry-run
terraform plan
```

**Problem**: Watchdog times out on Terraform plan  
**Solution**: Run Terraform plan directly to diagnose
```bash
cd terraform/environments/private
timeout 120 terraform plan -json | jq . > /tmp/plan.json
```

---

## Known Limitations

1. **Pre-apply validator** requires SSH access to both hosts
2. **Drift watchdog** alert thresholds are fixed (could be made configurable)
3. **Policy checker** doesn't validate all Terraform best practices (future enhancement)
4. **Watchdog state** is in `/tmp/` (ephemeral on reboot)

---

## Future Enhancements

1. **Remote State Backend**: Move Terraform state to MinIO S3 backend for shared access
2. **Vault Integration**: Manage secrets with automatic rotation
3. **Alert Routing**: Email/Slack/webhook integration for watchdog alerts
4. **SLO Tracking**: Error budget enforcement in test suite
5. **Scheduled Watchdog**: SystemD timer or K8s CronJob for continuous monitoring
6. **Custom Policy Rules**: User-defined policy checks in HCL

---

## Testing

All three scripts have been tested and validated:

```bash
# Syntax validation
bash -n scripts/ci/validate-pre-apply.sh
bash -n scripts/ci/enforce-terraform-policies.sh
bash -n scripts/ops/drift-monitoring-watchdog.sh

# Functional testing
./scripts/ci/validate-pre-apply.sh           # ✓ All checks pass
./scripts/ci/enforce-terraform-policies.sh  # ✓ All policies compliant
./scripts/ops/drift-monitoring-watchdog.sh  # ✓ 5/5 checks pass
```

---

## Commit Information

**Phase**: Continuation - Operational Hardening  
**Commit Date**: April 30, 2026  
**Files Added**:
- `scripts/ci/validate-pre-apply.sh`
- `scripts/ci/enforce-terraform-policies.sh`
- `scripts/ops/drift-monitoring-watchdog.sh`
- `docs/OPERATIONAL_HARDENING.md` (this file)

**Total Changes**: 3 new scripts + 1 documentation file  
**Code Size**: ~650 lines of operational automation

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-30 | Initial release with 3 operational hardening scripts |

