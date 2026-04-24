# Infrastructure Documentation

This directory contains documentation related to the infrastructure management, deployment, and operations of the Code Server Enterprise environment. It serves as the single source of truth for the project's layout, operational principles, and governance compliance.

## Key Documents

- [Infrastructure Lifecycle Runbook](RUNBOOK-INFRASTRUCTURE-LIFECYCLE.md): Guide for managing the full lifecycle of the infrastructure, including provisioning, scaling, and deprovisioning.
- [Governance Model (GOV-002)](../scripts/ops/infrastructure-health-check.sh): Built-in compliance and health check definitions requiring standard headers and non-root users.

## Project Structure

- `terraform/`: Infrastructure as Code (IaC) definitions using Terraform 1.7.x with provider pinning.
- `scripts/ops/`: Operational scripts for maintenance, deployment, and health monitoring.
- `docker-compose.yml`: Primary service orchestration with resource limits and non-root user enforcement.
- `Caddyfile`: Edge proxy and SSL configuration, managing external traffic and internal routing.
- `OPA/`: Open Policy Agent definitions for infrastructure compliance and audit logging.

## Operational Procedures

1. **Health Check**: Run `bash scripts/ops/infrastructure-health-check.sh` to validate system health across 10 categories.
2. **Deployment**: Run `bash scripts/ops/deployment-pipeline.sh production` for standardized, immutable deployments.
3. **Compliance**: Run `bash scripts/ops/compliance-validation.sh` to ensure all scripts meet GOV-002 headers.
4. **Log Rotation**: Run `bash scripts/ops/setup-log-rotation.sh` to generate a logrotate snippet for preventing disk exhaustion.

## Maintenance Tasks

- **Image Pinning**: To ensure immutability, run `bash scripts/ops/pin-docker-images.sh --execute`. This updates the Docker Compose file with exact SHAs.
- **Secret Scanning**: Regularly validate that no secrets are committed using `bash scripts/ops/validate-secrets.sh`.
- **Idempotency Verification**: Use `bash scripts/ops/idempotency-enforcer.sh` to scaffold new idempotent scripts or verify existing ones.
- **Drift Detection**: Run `bash scripts/ops/drift-detection-and-remediation.sh` to identify and fix configuration drift between the repository and running environment.

## Security Controls

The infrastructure follows a Zero Trust architecture:
- All services run as non-root users (UID 65534/1000).
- Resource limits are enforced via Docker `deploy` blocks.
- Network traffic is managed by Caddy with automatic SSL and TLS termination.
- Audit logging is integrated into the operational pipeline and OPA policies.

## Disaster Recovery

Refer to the [Infrastructure Lifecycle Runbook](RUNBOOK-INFRASTRUCTURE-LIFECYCLE.md) for detailed recovery steps and drift remediation strategies. In case of a major failure, the `scripts/ops/` directory contains tools for state recovery and volume backup verification.


