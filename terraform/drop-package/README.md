# Terraform Drop Package

This bundle is the portable Terraform entrypoint for the sovereign KC DevOS stack.

## Usage
1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Fill in the required domain, host, registry, and admin values.
3. Run `terraform init`.
4. Run `terraform validate`.
5. Review `terraform plan` and then apply.

## Air-Gapped Mode
- Mirror all images to an internal registry first.
- Use digest-pinned image references only.
- Never depend on `latest` tags or external pulls during apply.

## Immutability Rules
- No manual drift outside Terraform.
- No host-specific literals in module code.
- All deployment inputs must come from variables.
