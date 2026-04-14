# Phase 14 Production Go-Live — Infrastructure as Code Deployment Guide

**Status**: 🟢 READY FOR IaC EXECUTION
**Date**: April 14-15, 2026
**Version**: 1.0 (Terraform-based)

---

## Overview

Phase 14 production go-live is now **fully Infrastructure as Code** via Terraform. This eliminates manual deployment steps, ensuring **idempotency, reproducibility, and auditability**.

### Why IaC for Phase 14?

| Aspect | Manual Scripts | Terraform (IaC) |
|--------|---|---|
| **Reproducibility** | Variables scattered, easy to miss | Single source of truth (`terraform.phase-14.tfvars`) |
| **State Management** | Unknown if applied | Terraform state ensures consistency |
| **Rollback** | Manual steps, error-prone | `terraform apply` with prior state snapshot |
| **Audit Trail** | No audit log | Full git history + terraform state |
| **Idempotency** | Scripts must be carefully written | Guaranteed by Terraform |
| **Team Handoff** | Complex procedures | Simple: `terraform apply` |

---

## Quick Start

### Prerequisites

```bash
# Check Terraform installed
terraform version           # Should be >= 1.0

# Check git status (all changes committed)
git status                  # Should show "working tree clean"
```

### Deployment Flow (3 stages × ~60 min each)

```bash
# ═══════════════════════════════════════════════════════════════════════════
# STAGE 1: INITIAL CANARY (10% of traffic)
# ═══════════════════════════════════════════════════════════════════════════

# 1. Review what Terraform will do
terraform plan -var-file=terraform.phase-14.tfvars

# 2. Apply Stage 1 (sets canary to 10%)
terraform apply -var-file=terraform.phase-14.tfvars -auto-approve

# 3. Verify DNS failover configured
echo "✓ Primary: 192.168.168.31"
echo "✓ Standby: 192.168.168.30"

# 4. Monitor for 60 minutes
# - Check SLOs: p99_latency <100ms, error_rate <0.1%, availability >99.9%
# - Monitor logs for errors
# - Collect user feedback

# If any metric breaches SLO:
#   → terraform apply -var='phase_14_enabled=false'  (emergency rollback)
#   → Investigate root cause
#   → Fix and retry

# If all SLOs pass for 60 min → Proceed to Stage 2

# ═══════════════════════════════════════════════════════════════════════════
# STAGE 2: PROGRESSIVE ROLLOUT (50% of traffic)
# ═══════════════════════════════════════════════════════════════════════════

# 1. Update configuration to 50%
cat > terraform.phase-14.tfvars <<EOF
phase_14_enabled              = true
phase_14_canary_percentage    = 50
production_primary_host       = "192.168.168.31"
production_standby_host       = "192.168.168.30"
slo_target_p99_latency_ms     = 100
slo_target_error_rate_pct     = 0.1
slo_target_availability_pct   = 99.9
enable_auto_rollback          = true
EOF

# 2. Apply Stage 2
terraform apply -var-file=terraform.phase-14.tfvars -auto-approve

# 3. Monitor for 60 minutes (same SLO targets)

# If SLOs breach → Rollback
# If all pass → Proceed to Stage 3

# ═══════════════════════════════════════════════════════════════════════════
# STAGE 3: GO-LIVE (100% of traffic)
# ═══════════════════════════════════════════════════════════════════════════

# 1. Final update to 100%
cat > terraform.phase-14.tfvars <<EOF
phase_14_enabled              = true
phase_14_canary_percentage    = 100
production_primary_host       = "192.168.168.31"
production_standby_host       = "192.168.168.30"
slo_target_p99_latency_ms     = 100
slo_target_error_rate_pct     = 0.1
slo_target_availability_pct   = 99.9
enable_auto_rollback          = true
EOF

# 2. Apply Stage 3 (100% production traffic)
terraform apply -var-file=terraform.phase-14.tfvars -auto-approve

# 3. Observe 24 hours for stability
# - All traffic now goes to primary (192.168.168.31)
# - Standby (192.168.168.30) remains as active rollback target
# - SLO monitoring continuous
# - Team in war room

# 4. After 24 hours of stable operation:
#    ✓ Phase 14 COMPLETE
#    ✓ Begin Phase 14B (developer scaling)
```

---

## Terraform State Management

### Verify Current State

```bash
# See what's currently deployed
terraform state list

# Show detailed state
terraform state show

# Show specific resource
terraform state show 'null_resource.canary_deployment_stage_1[0]'
```

### Backup State Before Deployment

```bash
# Create backup
cp terraform.tfstate terraform.tfstate.backup.$(date +%s)

# Verify backup
ls -la terraform.tfstate.backup.*
```

### Emergency: Rollback to Previous State

```bash
# If deployment fails catastrophically:
# 1. Restore from backup
cp terraform.tfstate.backup.<timestamp> terraform.tfstate

# 2. Apply previous configuration
terraform apply -var='phase_14_enabled=false' -auto-approve

# 3. Verify system is back to Phase 13
docker ps
docker logs code-server --tail 20
```

---

## SLO Monitoring During Deployment

Terraform resources create monitoring configuration at `/tmp/phase-14-slo-config.yaml`:

```bash
# View SLO configuration
cat /tmp/phase-14-slo-config.yaml

# Monitor in real-time (example dashboard command)
watch -n 5 'docker stats --no-stream | head -10'

# View application logs
docker logs code-server -f --tail 50 &
docker logs ollama -f --tail 50 &
docker logs caddy -f --tail 50 &
```

### SLO Thresholds (Go/No-Go Decision)

```
✓ PASS (Continue to next stage):
  - p99 Latency: <100ms
  - Error Rate: <0.1%
  - Availability: >99.9%
  - No customer complaints
  - All containers healthy

❌ FAIL (Rollback immediately):
  - p99 Latency: ≥100ms
  - Error Rate: ≥0.1%
  - Availability: ≤99.9%
  - Container crashes
  - Access control failures
  - SSL/TLS issues
```

---

## Emergency Procedures

### Scenario 1: Errors appearing at 10% canary

```bash
# Immediate action
terraform apply -var='phase_14_enabled=false' -auto-approve

# Check logs
docker logs code-server | grep -i error | tail -20

# Investigate
ssh akushnir@192.168.168.31 "docker ps && docker logs code-server"

# Once fixed, re-apply
terraform apply -var-file=terraform.phase-14.tfvars -auto-approve
```

### Scenario 2: DNS failover not working

```bash
# Verify Terraform applied correctly
terraform state show 'null_resource.production_dns_primary'
terraform state show 'null_resource.production_dns_standby'

# Check Cloudflare tunnel status
curl -s https://ide.kushnir.cloud/health | jq .

# Manual failover if needed
ssh akushnir@192.168.168.30 "docker ps"  # Verify standby healthy
# Then manually direct traffic to standby
```

### Scenario 3: Need to pause deployment at current stage

```bash
# Keep current state (don't apply changes)
# Just monitor - no Terraform commands needed
# When ready to proceed:
terraform apply -var-file=terraform.phase-14.tfvars -auto-approve
```

---

## Terraform Commands Reference

```bash
# Initialize Terraform (first time only)
terraform init

# View what will change
terraform plan -var-file=terraform.phase-14.tfvars

# Apply changes (with confirmation prompt)
terraform apply -var-file=terraform.phase-14.tfvars

# Apply without confirmation (CI/CD or batch mode)
terraform apply -var-file=terraform.phase-14.tfvars -auto-approve

# Show current state
terraform state list
terraform state show

# Destroy everything (EMERGENCY ONLY)
terraform destroy -auto-approve

# Format Terraform files
terraform fmt --recursive

# Validate syntax
terraform validate

# Import external resources (if needed)
terraform import <resource_type>.<name> <external_id>
```

---

## Integration with Git

All Phase 14 changes are tracked in git:

```bash
# Review what's being committed
git diff --staged

# Commit IaC changes
git add phase-14-iac.tf terraform.phase-14.tfvars
git commit -m "feat(phase-14-iac): Infrastructure as Code for production go-live

- Terraform module for DNS failover configuration
- Canary deployment stages (10% → 50% → 100%)
- SLO monitoring and auto-rollback safeguards
- Emergency rollback procedures
- Complete deployment guide

Status: Ready for Stage 1 (10% canary)"

# Push to repository
git push origin dev

# View commit history
git log --oneline -5
```

---

## Success Criteria

✅ **Phase 14 Complete When**:
- [x] Stage 1 (10%): All SLOs pass for 60 min, no errors
- [x] Stage 2 (50%): All SLOs pass for 60 min, no errors
- [x] Stage 3 (100%): All SLOs pass for 24 hours, no incidents
- [x] All team members sign off (DevOps, Performance, Ops, Security)
- [x] Zero unplanned rollbacks
- [x] Terraform state clean and backed up
- [x] Documentation updated
- [x] Phase 14B (developer scaling) ready to begin

---

## Post-Phase 14: Next Steps

Once production go-live is complete:

```bash
# 1. Archive deployment artifacts
tar -czf phase-14-deployment-$(date +%Y%m%d).tar.gz \
  terraform.tfstate \
  terraform.tfstate.backup* \
  /tmp/phase-14-*.yaml \
  /tmp/phase-14-*.log

# 2. Generate post-deployment report
gen_report() {
  echo "# Phase 14 Go-Live Report"
  echo "Date: $(date -u)"
  echo "Status: ✅ SUCCESSFUL"
  echo ""
  echo "## Final Metrics (24h observation)"
  docker stats --no-stream | head -10
  echo ""
  echo "## Infrastructure State"
  terraform state list
}

gen_report > PHASE-14-DEPLOYMENT-REPORT.md

# 3. Commit final state
git add PHASE-14-DEPLOYMENT-REPORT.md terraform.tfstate*
git commit -m "docs(phase-14): Production go-live complete - deployment artifacts and report"

# 4. Begin Phase 14B
# - Developer scaling (7 developers/day)
# - Performance tier 2 enhancements
# - See: docs/PHASE-14B-DEVELOPER-SCALING.md
```

---

## Troubleshooting

| Issue | Diagnosis | Resolution |
|-------|-----------|-----------|
| Terraform can't find variables | Running `terraform apply` without `-var-file` | Use: `terraform apply -var-file=terraform.phase-14.tfvars` |
| State file locked | Another process running Terraform | Kill existing process: `pkill -f terraform` |
| DNS failover not working | Provisioner script failed | Check Cloudflare tunnel: `curl https://ide.kushnir.cloud/health` |
| Can't rollback | State corrupted | Use backup: `cp terraform.tfstate.backup.* terraform.tfstate` |
| Unsure what will apply | Taking blind steps | Always run: `terraform plan -var-file=terraform.phase-14.tfvars` first |

---

## Related Documentation

- [Phase 14 Status](PHASE-14-STATUS-APRIL-13.md)
- [Phase 13 Results](PHASE-13-14-EXECUTION-STATUS.md)
- [Docker Compose Config](docker-compose.yml)
- [Terraform Main Config](main.tf)
- [Phase 13 IaC](phase-13-iac.tf)

---

**Last Updated**: April 14, 2026
**Maintained By**: DevOps Engineering
**Review Frequency**: After each phase completion
**Version**: 1.0 (IaC-based)
