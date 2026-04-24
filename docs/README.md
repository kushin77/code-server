# Infrastructure Documentation

This directory contains documentation related to the infrastructure management, deployment, and operations of the Code Server Enterprise environment.

## Key Documents

- [Infrastructure Lifecycle Runbook](RUNBOOK-INFRASTRUCTURE-LIFECYCLE.md): Guide for managing the full lifecycle of the infrastructure.
- [Governance Model (GOV-002)](../scripts/ops/infrastructure-health-check.sh): Built-in compliance and health check definitions.

## Project Structure

- `terraform/`: Infrastructure as Code definitions.
- `scripts/ops/`: Operational scripts for maintenance and deployment.
- `docker-compose.yml`: Primary service orchestration.
- `Caddyfile`: Edge proxy and SSL configuration.

## Operational Procedures

1. **Health Check**: Run `bash scripts/ops/infrastructure-health-check.sh`
2. **Deployment**: Run `bash scripts/ops/deployment-pipeline.sh production`
3. **Compliance**: Run `bash scripts/ops/compliance-validation.sh`
