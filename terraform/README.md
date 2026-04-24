# Terraform Drop Package

This directory is the canonical Terraform entrypoint for the sovereign KC DevOS stack.

## Goals
- Parameterized deployment with no hardcoded host values in module code.
- Digest-pinned images only.
- Idempotent apply semantics.
- Private, air-gapped, and federated deployment modes.

## Planned Layout
- `modules/core` - networking, ingress, and DNS.
- `modules/identity` - SSO and oauth2-proxy.
- `modules/ide` - code-server and KC IDE customizations.
- `modules/ai` - Ollama and model routing.
- `modules/observability` - Prometheus, Grafana, Loki.
- `modules/policy` - OPA and policy bundles.
- `modules/storage` - NAS volumes and backup wiring.
- `environments/private` - current on-prem deployment.
- `environments/air-gapped` - mirrored artifacts only.
- `environments/federated` - future multi-org mode.
- `drop-package` - distributable bundle.

## Operating Rules
- Use `terraform init`, `terraform validate`, `terraform plan`, and `terraform apply` in that order.
- Do not introduce `latest` tags.
- Keep deploy inputs variable-driven.
