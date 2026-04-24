# @file        docs/architecture/ENV-YAML-SPEC.md
# @module      infrastructure/parity
# @description Specification for the env.yaml environment parity engine
# @status      draft

# ENV-YAML Specification v1.0

The `env.yaml` file is the Source of Truth (SSOT) for the runtime environment of an ElevatedIQ project. It defines the compute, storage, data, and AI services required for the application to function correctly across local, CI, and production environments.

## 1. Schema Overview

```yaml
version: "1.0"
metadata:
  name: kushnir-cloud-core
  env: local | staging | production

compute:
  replicas: 2
  profiles: ["ai", "tracing"]

data:
  postgres:
    version: "15"
    ha: true
  redis:
    version: "7"
    mode: sentinel

ai:
  providers:
    - name: ollama
      models: ["llama3:8b", "codellama:13b"]
    - name: openai
      enabled: false

networking:
  domain: ide.kushnir.cloud
  tls: provider-managed
```

## 2. Core Principles

1. **Deterministic Parity**: The same `env.yaml` + the same code = the same behavior.
2. **Immutable Infrastructure**: Environment changes are applied by updating the `env.yaml` and re-provisioning.
3. **Sovereign First**: Local-first defaults (Ollama, local Postgres) with optional cloud fallbacks.
4. **Validation-Ready**: Every `env.yaml` must pass against [schemas/env-yaml.v1.json](../schemas/env-yaml.v1.json).

## 3. Tooling (ElevatedIQ CLI)

- `elevatediq env validate`: Checks syntax and schema compliance.
- `elevatediq env clone --from production --to local`: Clones environment configuration (not data) for local debugging.
- `elevatediq env diff local production`: Shows delta between two environments.
- `elevatediq env promote --from local --to production`: Submits `env.yaml` changes for production rollout.

## 4. Provisioning Logic

The Environment Provisioner (`apps/env-provisioner`) parses the `env.yaml` and generates:
- `docker-compose.yaml` (Local/CI)
- `.env` files (GSM-backed)
- Terraform variables (Production)
