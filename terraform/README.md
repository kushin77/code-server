# Terraform Infrastructure-as-Code

**Purpose**: Infrastructure-as-Code (IaC) for the entire code-server-enterprise deployment using Terraform.

## Structure

```
terraform/
├── README.md (this file)
├── main.tf - SINGLE SOURCE OF TRUTH (all resources defined here)
├── variables.tf - Input variable definitions
├── outputs.tf - Output definitions
├── versions.tf - Provider version requirements
├── _locals.tf - Local values and computed variables
├── terraform.tfvars - Active variable values (gitignored)
├── terraform.tfvars.example - Template for tfvars
│
├── modules/ - Reusable Terraform modules
│   ├── containers/ - Docker container infrastructure
│   ├── networking/ - Network configuration
│   ├── security/ - Security groups and policies
│   ├── observability/ - Monitoring and logging
│   └── storage/ - Storage volume configuration
│
├── environments/ - Environment-specific variable overrides
│   ├── dev.tfvars - Development environment
│   ├── staging.tfvars - Staging environment
│   └── production.tfvars - Production environment
│
├── hosts/ - Host-specific variable overrides
│   ├── 192.168.168.31.tfvars - Primary host
│   └── 192.168.168.30.tfvars - Failover host
│
└── state/ - Terraform state files (gitignored)
```

## Quick Start

### Initialize Terraform

```bash
cd terraform
terraform init
```

### Plan Changes

```bash
# Preview changes
terraform plan -var-file=environments/production.tfvars
```

### Apply Changes

```bash
# Deploy to production
terraform apply -var-file=environments/production.tfvars -var-file=hosts/192.168.168.31.tfvars
```

## File Organization

### Main.tf (Single Source of Truth)

ALL resources are defined in `main.tf`. This is the single source of truth for the infrastructure.

**Why?**
- Easier to understand entire infrastructure in one place
- Prevents conflicts from multiple module definitions
- Clear dependencies between resources

### Modules

Reusable modules for common infrastructure patterns:

- **containers/**: Docker images, volumes, networks
- **networking/**: Network configuration and connectivity
- **security/**: Security groups, policies, access control
- **observability/**: Prometheus, Grafana, AlertManager
- **storage/**: Data storage (PostgreSQL, Redis, etc.)

Each module should have:
- Clear purpose with README
- Input variables documented
- Outputs well-defined
- No hardcoded values (use variables)

### Variable Hierarchy

Variables are resolved in this order (highest precedence first):

1. **Command-line**: `terraform apply -var="foo=bar"`
2. **Environment files**: `-var-file=environments/production.tfvars`
3. **Host-specific files**: `-var-file=hosts/192.168.168.31.tfvars`
4. **Defaults**: `variables.tf` default values

### Example: Deploy to Production

Combine environment and host-specific variables:

```bash
# Production environment + primary host
terraform apply \
  -var-file=environments/production.tfvars \
  -var-file=hosts/192.168.168.31.tfvars
```

## Common Tasks

### Update a Variable

1. Edit `terraform.tfvars` for non-sensitive values
2. Edit `environments/*.tfvars` for environment-specific values
3. Edit `hosts/*.tfvars` for host-specific values
4. Run `terraform plan` to preview
5. Run `terraform apply` to deploy

### Add New Infrastructure

1. Define input variables in `variables.tf`
2. Define resource in `main.tf` using those variables
3. Define outputs in `outputs.tf` if needed
4. Document with comments in `main.tf` (see CODE-QUALITY-STANDARDS.md)
5. Test with `terraform plan`
6. Apply with `terraform apply`

### Switch Environments

```bash
# Development
terraform plan -var-file=environments/dev.tfvars

# Staging
terraform plan -var-file=environments/staging.tfvars

# Production
terraform plan -var-file=environments/production.tfvars
```

## State Management

Terraform state is stored in `state/` directory (gitignored).

**IMPORTANT**:
- Always commit `terraform.tfstate.backup` to git for reference
- Never commit `terraform.tfstate` with actual values
- Keep `state/` directory in .gitignore
- Use `terraform state` commands to inspect state

## Validation

Validate Terraform configuration:

```bash
terraform validate
terraform fmt -check  # Check formatting
```

## Troubleshooting

### State Lock Timeout

If stuck on "Acquiring state lock":

```bash
# Force unlock (use carefully!)
terraform force-unlock [LOCK_ID]
```

### Resource Already Exists

```bash
# Import existing resource
terraform import resource_type.name resource_id
```

### Preview Changes Without Applying

```bash
# Dry-run - shows what WOULD change
terraform plan -var-file=environments/production.tfvars
```

## Security Notes

- Variables with `sensitive = true` are masked in logs
- Never commit `.tfvars` files with real secrets
- Use `.env` file or environment variables for sensitive data
- Audit `terraform.tfstate` for accidentally stored secrets

## References

- [Terraform Documentation](https://www.terraform.io/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [GOVERNANCE.md](../docs/GOVERNANCE.md) - Repository rules
- [CODE-QUALITY-STANDARDS.md](../docs/CODE-QUALITY-STANDARDS.md) - Header/comment requirements

## Maintenance

**Owner**: @akushnir
**Last Updated**: April 14, 2026
**Status**: Active production infrastructure

---

**Related**:
- [../docs/guides/DEPLOYMENT.md](../docs/guides/DEPLOYMENT.md)
- [../docs/runbooks/](../docs/runbooks/)
