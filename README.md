# code-server Enterprise (On-Prem)

This repository manages a local-first code-server platform with observability,
secure access control, and deterministic Linux deployment workflows.

## Production Targets

- Primary deploy host: 192.168.168.31
- Standby host: 192.168.168.30
- NAS host: 192.168.168.56

## Canonical Entry Points

- Container orchestration: docker-compose.yml
- Infrastructure as code: terraform/
- Shared script config: scripts/_common/config.sh
- Linux deployment scripts: scripts/

## Deployment (Linux, Remote)

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
docker compose pull
docker compose up -d
docker compose ps
```

## Clean Rebuild (Linux, Remote)

```bash
bash scripts/deploy/rebuild-clean-remote.sh --with-prune
```

## Secrets (Google Secret Manager)

Fetch and inject runtime secrets before deploy:

```bash
source scripts/fetch-gsm-secrets.sh
```

This exports TF_VAR_* and runtime OAuth/Gateway secrets for compose and Terraform.

## Guardrails

- Linux-only operations (no PowerShell requirement for deploy path)
- Pinned versions for runtime images and providers
- Avoid duplicate authoritative configs
- Prefer key-only SSH for external hosts
