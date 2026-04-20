# Configuration SSOT Report

Source: `docs/governance/CONFIG-SSOT.md`
Count: 6

| Config class | Canonical owner | Consuming surfaces |
|---|---|---|
| Domains and host topology | [docs/ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md), [docs/NAS-ARCHITECTURE.md](../NAS-ARCHITECTURE.md) | Compose, Terraform, ingress, runbooks; NAS contract is host `192.168.168.56`, export `/export`, mount `/mnt/nas`, protocol `nfs4` |
| OAuth and endpoint auth | [docs/ops/ENDPOINT-CONTRACT-INDEX.md](../ops/ENDPOINT-CONTRACT-INDEX.md), [docs/adr/002-oauth2-authentication.md](../adr/002-oauth2-authentication.md) | oauth2-proxy, Caddy, E2E tests |
| NAS host and export values | [docs/NAS-ARCHITECTURE.md](../NAS-ARCHITECTURE.md) | Scripts, Terraform, deployment preflight; canonical values are host `192.168.168.56`, export `/export`, mount `/mnt/nas`, protocol `nfs4` |
| Secrets and rotation | [docs/SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md), [docs/ops/SECRETS-ROTATION-SCHEDULE.md](../ops/SECRETS-ROTATION-SCHEDULE.md) | GSM, Vault, bootstrap scripts |
| Schema and required env vars | [.env.schema.json](../../.env.schema.json) | Validation scripts, docs generators |
| Drift detection | [scripts/ci/detect-config-drift.sh](../../scripts/ci/detect-config-drift.sh), [scripts/dev/check-config-drift.sh](../../scripts/dev/check-config-drift.sh) | CI, local validation |
