# Terraform Environment Consolidation (Phase 2)

## Single Source of Truth Architecture

This directory (`terraform/environments/_common/`) implements the SSOT pattern for Terraform variable management across all deployment environments.

### Problem Solved

Previously, variables were duplicated across multiple locations:
- `terraform/modules/*/variables.tf` - Module input declarations
- `terraform/environments/private/main.tf` - Environment-specific variable blocks  
- `terraform/environments/private/terraform.tfvars` - Value assignments
- `terraform/environments/air-gapped/variables.tf` - Additional duplicate declarations

This led to maintenance burden, inconsistencies, and drift.

### Solution Architecture

```
terraform/environments/
├── _common/
│   └── terraform.tfvars          # SSOT: Shared values across ALL environments
│
├── private/
│   └── terraform.tfvars          # Private environment: Only overrides + secrets
│
└── air-gapped/
    └── terraform.tfvars          # Air-gapped environment: Only overrides + secrets
```

### How It Works

1. **_common/terraform.tfvars** - Defines all shared values:
   - `apex_domain = "kushnir.cloud"`
   - `admin_email = "ops@kushnir.cloud"`
   - Global security, observability, and persistence settings
   - Default feature flags

2. **Environment-Specific Overrides** - Each environment adds only what's unique:
   - `private/terraform.tfvars`: Network hosts (192.168.168.x), credentials
   - `air-gapped/terraform.tfvars`: Internal network hosts (10.0.0.x), local registry

3. **Module Variables** (terraform/modules/*/variables.tf):
   - ✅ UNCHANGED and CORRECT - Modules still declare their input variables
   - This is how Terraform modules work (inputs must be declared)
   - Values are provided via tfvars files

### Variable Resolution Order

When running `terraform apply -var-file=_common/terraform.tfvars -var-file=private/terraform.tfvars`:

1. Load common values from `_common/terraform.tfvars`
2. Apply environment-specific overrides from `private/terraform.tfvars`
3. Pass merged values to module input variables
4. Module uses these values to configure resources

### Implementation Steps Completed

✅ **Phase 2a** - Create _common/terraform.tfvars with shared values
✅ **Phase 2b** - Update private/terraform.tfvars to reference _common
✅ **Phase 2c** - Create air-gapped/terraform.tfvars from template
⏳ **Phase 2d** - Update Terraform CLI invocation (see below)
⏳ **Phase 2e** - Clean up duplicate variable declarations in main.tf files

### Using the Consolidated Configuration

#### Private Environment
```bash
cd terraform/environments/private
terraform plan \
  -var-file=../_common/terraform.tfvars \
  -var-file=terraform.tfvars
terraform apply \
  -var-file=../_common/terraform.tfvars \
  -var-file=terraform.tfvars
```

#### Air-Gapped Environment
```bash
cd terraform/environments/air-gapped
terraform plan \
  -var-file=../_common/terraform.tfvars \
  -var-file=terraform.tfvars
terraform apply \
  -var-file=../_common/terraform.tfvars \
  -var-file=terraform.tfvars
```

### Benefits

- **Single Source of Truth**: Each value defined once in _common/terraform.tfvars
- **Environment Isolation**: Each environment only specifies what's different
- **Reduced Maintenance**: Changes to shared values made in one place
- **Clear Dependencies**: Comments in environment files show which values come from _common
- **Improved Auditability**: History of changes centralized in _common/terraform.tfvars

### Next Steps (Phase 3)

1. Update scripts to pass `-var-file=../_common/terraform.tfvars` to all terraform commands
2. Remove duplicate variable declarations from `environments/*/main.tf` 
3. Consolidate `.env` files using same pattern
4. Document consolidation in `.instructions.md`

### Related Issues

- Issue #1531 - IaC Consolidation: Eliminate SSOT violations
- VARIABLE_CONSOLIDATION_PLAN.md - Full consolidation strategy

