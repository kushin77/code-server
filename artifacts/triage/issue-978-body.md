## Severity: HIGH (Terraform state lost = full infrastructure recreation risk)

---

## Finding 1 — No remote Terraform backend — state file is local only (main.tf:1-30)

### Evidence
```hcl
# main.tf — no backend {} block
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 2.5" }
    local  = { source = "hashicorp/local",    version = "~> 2.5" }
    ...
  }
}
# No backend "s3" {} or backend "http" {} block
```

`terraform/backend.tf` exists (from issue #872 implementation) but the root-level `main.tf` used for deploys has no backend configuration.

### Risk
- Terraform state exists only on the local developer machine
- If the state file is lost (machine failure, accidental deletion, git conflict), Terraform cannot track existing resources
- Running `terraform apply` on a fresh machine recreates ALL Docker resources, causing a full stack outage

### Fix
Option A — HTTP backend (simplest for on-prem):
```hcl
terraform {
  backend "http" {
    address        = "https://gitlab.internal/api/v4/projects/1/terraform/state/production"
    lock_address   = "https://gitlab.internal/api/v4/projects/1/terraform/state/production/lock"
    unlock_address = "https://gitlab.internal/api/v4/projects/1/terraform/state/production/lock"
    username       = "terraform-ci"
    password       = var.terraform_state_token  # from GSM
  }
}
```

Option B — S3-compatible backend (MinIO on NAS):
```hcl
terraform {
  backend "s3" {
    endpoint               = "http://192.168.168.55:9000"
    bucket                 = "terraform-state"
    key                    = "production/terraform.tfstate"
    region                 = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
```

---

## Finding 2 — Root-level deprecated main.tf and variables.tf still parsed by Terraform (main.tf:1-3, variables.tf:1-4)

### Evidence
Both files declare themselves as deprecated but contain real Terraform blocks:
```hcl
# main.tf line 1-3:
# ⚠️  DEPRECATED — use terraform/ directory instead
# This file is a compatibility shim and will be removed in a future release
```
But Terraform `init` and `plan` in the repo root still processes these files.

### Risk
Operators confused about which Terraform root to use may:
- Apply from the repo root (deprecated) instead of `terraform/`
- Get resource conflicts between root and `terraform/` definitions
- Accidentally destroy resources managed by the `terraform/` state

### Fix
```bash
# Remove deprecated files (track in this issue)
git rm main.tf variables.tf terraform.phase-14.tfvars
```
Add CI guard to prevent re-introduction:
```yaml
# .github/workflows/check-no-root-tf.yml
- name: Fail if root-level .tf files exist
  run: |
    if ls *.tf 2>/dev/null | grep -v 'versions.tf'; then
      echo "ERROR: Root-level .tf files found — use terraform/ directory"
      exit 1
    fi
```

---

## Finding 3 — Provider version pins allow minor version drift (main.tf:10-25)

```hcl
version = "~> 2.5"   # allows 2.5.x → 2.9.x
version = "~> 3.0"
version = "~> 5.0"
```

### Fix
Pin to exact versions and manage upgrades explicitly:
```hcl
version = "= 2.5.1"
```

---

## Definition of Done
- [ ] Remote Terraform backend configured (state no longer local-only)
- [ ] `terraform init` on a fresh machine retrieves existing state without error
- [ ] Root-level `main.tf` and `variables.tf` removed
- [ ] CI guard prevents root-level `.tf` file re-introduction
- [ ] Provider versions pinned to exact versions (`= x.y.z`)
- [ ] `terraform plan` produces no changes after backend migration
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
