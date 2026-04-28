# Terraform Variables Consolidation Strategy

## Current State Analysis

**Problem**: Variables defined in 4+ locations for same concepts

| Variable | root/variables.tf | modules/core/variables.tf | modules/identity/variables.tf | environments/private/main.tf | environments/air-gapped/variables.tf |
|----------|-------------------|---------------------------|-------------------------------|-------------------------------|--------------------------------------|
| apex_domain | ❌ | ✅ | ✅ | ✅ | ✅ |
| primary_host | ❌ | ✅ | ❌ | ✅ | ❌ |
| replica_host | ❌ | ✅ | ❌ | ✅ | ❌ |
| admin_email | ❌ | ❌ | ✅ | ❌ | ❌ |

## Root Cause

In Terraform, this is **intentional but suboptimal**:
- **Modules require declaring inputs** (terraform/modules/*/variables.tf) ✅ CORRECT
- **Root workspace passes values** (terraform/environments/<env>/{main,variables}.tf)  
- **Duplication** occurs because values hardcoded in multiple environment files instead of centralized

## Solution (Phase 2 - 3 days effort)

### Step 1: Establish Single Source of Truth
Create `terraform/environments/_common/terraform.tfvars`:
```hcl
# Shared values across all environments
apex_domain     = "kushnir.cloud"
admin_email     = "admin@kushnir.cloud"
tls_provider    = "letsencrypt-prod"
terraform_version_pin = "1.7.0"
log_level       = "info"
```

### Step 2: Environment-Specific Overrides
Create `terraform/environments/{private,air-gapped}/terraform.tfvars`:
```hcl
# Private environment
primary_host    = "192.168.168.31"
replica_host    = "192.168.168.42"
nas_host        = "192.168.168.56"
enable_tls      = true

# Air-gapped environment
primary_host    = "10.0.0.10"
local_registry_url = "registry.internal:5000"
bypass_internet_checks = true
```

### Step 3: Module Variable Declarations
Keep `terraform/modules/*/variables.tf` - **this is correct** ✅
- Modules declare inputs they need
- Providers (root workspace) pass values
- This is Terraform best practice

### Step 4: Cleanup
- [ ] Delete duplicate variable declarations in environments/private/main.tf
- [ ] Delete duplicate variable declarations in environments/air-gapped/variables.tf
- [ ] Centralize into _common/terraform.tfvars
- [ ] Update deployment docs to source from .tfvars

## Migration Commands

```bash
# Test variable loading (dry-run)
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars

# Verify no regressions after consolidation
cd terraform/environments/private && terraform plan
cd terraform/environments/air-gapped && terraform plan
```

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Lost sensitivity on secrets | Keep SSOT in scripts/_common/config.env (not .tfvars) |
| Environment confusion | Document .tfvars precedence in README |
| Accidental commits | Add *.tfvars to .gitignore (use terraform.tfvars.example) |

## Status
- **Effort**: 3 days (Phase 2)
- **Risk**: Low (well-established Terraform patterns)
- **Dependency**: config.env SSOT must exist first ✅ DONE
