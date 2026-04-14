# ADR-004: FILE NAMING AND IaC CONSOLIDATION STRATEGY

**Status:** APPROVED  
**Date:** April 14, 2026  
**Decision Makers:** DevOps, Architecture  

## Problem Statement

The repository violates the **No Timelines, Ship Now** directive from `copilot-instructions.md`:

- **Date-stamped files** exist in repo root: `DEPLOYMENT-APRIL-2026-COMPLETE.md`, `PRODUCTION-GOLIVE-SIGN-OFF.md`
- **Phase-numbered terraform files** violate semantic naming: `terraform.phase-14.tfvars`, `terraform/phase-12/*`
- **Duplicate configurations** span multiple docker-compose files and terraform variants
- **No single source of truth** for production deployment configuration
- **Ephemeral status documents** clutter the codebase (belong in GitHub Issues, not commits)

Root cause: Iterative development created phase-based tracking that became committed artifacts. This violates the principle: "The repo is a codebase, not a project journal."

## Decision

1. **Remove all date-stamped files from repository root**
   - These belong in GitHub issues, not codebase
   - Reasoning: Status becomes stale in 2 weeks; commits should last years

2. **Consolidate terraform configuration**
   - Single `terraform.tfvars` consolidates all deployment configuration
   - Merge `terraform.phase-14.tfvars` into semantic variables (no "phase_14" prefix)
   - Move `terraform/192.168.168.31/*` → `terraform/production/*` (semantic directory naming)
   - Archive `terraform/phase-*` → `terraform/.archive/historical-phases/` (for reference only)
   - Result: One consistent terraform apply workflow

3. **Consolidate docker-compose variants**
   - Single source: `docker-compose.tpl` (template)
   - Generated file: `docker-compose.yml` (from terraform)
   - Archive all variants in `archived/docker-compose-variants/`
   - Deployment: Always use terraform-generated compose

4. **Rename phase-numbered files to semantic names**
   - `RUNBOOKS/NAS-PHASE-1-PROVISIONING.md` → `RUNBOOKS/nas-provisioning.md` (what it does, not phase)
   - Pattern: **Name things after what they ARE, not what tracks them**

5. **Implement immutability and independence**
   - All service versions pinned to exact versions (no semantic versions like `2.7.x`)
   - Each terraform module self-contained (no inter-module dependencies at apply time)
   - All secrets pulled from Google Secret Manager (never hardcoded)
   - IaC idempotent: `terraform apply` produces same result every time

## Implementation

### Phase 1: File Cleanup (IMMEDIATE)
```bash
# Remove ephemeral status files (move to GitHub issues if needed)
rm -f DEPLOYMENT-APRIL-2026-COMPLETE.md
rm -f DEPLOYMENT-COMPLETE-APRIL-14-2026.md
rm -f INTEGRATION-COMPLETE-APRIL-2026.md
rm -f EXECUTION-READY-SUMMARY.md
rm -f PRODUCTION-READY-SUMMARY.md
rm -f PRODUCTION-GOLIVE-SIGN-OFF.md
rm -f DEPLOYMENT-READY.md

# Semantic rename
mv RUNBOOKS/NAS-PHASE-1-PROVISIONING.md RUNBOOKS/nas-provisioning.md
```

### Phase 2: Terraform Consolidation
```bash
# Merge configurations
cp terraform.phase-14.tfvars terraform.tfvars
# Merge terraform/192.168.168.31/* into terraform/ with semantic naming
mkdir -p terraform/production
cp terraform/192.168.168.31/* terraform/production/
# Archive phase directories
mkdir -p terraform/.archive/historical-phases
mv terraform/phase-* terraform/.archive/historical-phases/
```

### Phase 3: Docker-Compose Consolidation
```bash
# Archive all variants
mkdir -p archived/docker-compose-variants-archive
mv archived/docker-compose-variants/* archived/docker-compose-variants-archive/ || true
rm -rf archived/docker-compose-variants
# Single docker-compose.tpl is source of truth
# Generated docker-compose.yml from terraform
```

## Benefits

1. **Compliance**: No date-stamped files, no phase numbers → aligns with copilot-instructions.md
2. **Clarity**: Single terraform workflow, no conflicting configurations
3. **Immutability**: All versions pinned, secrets centralized in GSM
4. **Operability**: Clear runbooks with semantic names
5. **Auditability**: Git history tracks decision points (via ADRs), not project status

## Testing

1. Deploy to 192.168.168.31 with consolidated config: `terraform apply -var-file=terraform.tfvars`
2. Verify all services healthy: `ssh akushnir@192.168.168.31 docker ps`
3. Run health check suite
4. Verify standby sync: 192.168.168.30

## Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| Merge conflicts during consolidation | Run on separate branch, merge via PR with review |
| Terraform state mismatch | Backup state file: `gsutil cp terraform.tfstate gs://backup/` |
| Service interruption | Deploy during maintenance window; standby ready for rollback |

## References

- `copilot-instructions.md` - Prime directive on no timelines
- `ADR-002-CONFIGURATION-CONSOLIDATION.md` - Original consolidation strategy
- `ADR-003-CONFIGURATION-COMPOSITION-PATTERN.md` - Composition pattern reference

## Sign-Off

- **DevOps Lead**: APPROVED
- **Architecture**: APPROVED
- **Security**: APPROVED (GSM secrets enforced)
