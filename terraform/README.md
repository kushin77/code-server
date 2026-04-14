# Terraform Infrastructure-as-Code

Purpose: production IaC for on-prem deployment orchestration and generated runtime artifacts.

## Canonical Layout

```
terraform/
├── locals.tf
├── variables.tf
├── users.tf
├── data_sources.tf
├── dns-access-control.tf
├── observability-operations.tf
├── api-gateway.tf
├── kubernetes-orchestration.tf
├── service-mesh.tf
├── caching.tf
├── routing.tf
├── rate-limiting.tf
├── analytics.tf
├── organizations.tf
├── webhooks.tf
└── docker-compose.yml (generated/runtime artifact placeholder)
```

Important: root deployment uses docker-compose.yml in repository root as the canonical compose entrypoint.

## Quick Start (Remote Host)

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise/terraform
terraform init
terraform validate
terraform plan
```

## Secrets Flow (GSM)

Run from repository root before terraform apply:

```bash
source scripts/fetch-gsm-secrets.sh
```

This exports TF_VAR_* values for OAuth and tunnel secrets.

## Validation

```bash
terraform fmt -check
terraform validate
```

## State Safety

- Do not commit terraform.tfstate.
- Do not commit terraform.tfstate.backup.
- Keep secrets out of .tfvars committed files.
- Prefer environment variables and GSM-sourced TF_VAR_* values.

## Operational Notes

- Keep versions pinned in locals and provider blocks.
- Prefer additive module files with clear ownership boundaries.
- Avoid duplicate resource definitions across files.

## References

- ../README.md
- ../scripts/fetch-gsm-secrets.sh
- ../scripts/_common/config.sh
