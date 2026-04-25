# ENV-YAML-SPEC.md — ElevatedIQ Environment Parity Specification

**Version:** 1.0  
**Status:** Production  
**GitHub Issue:** #1553  
**Governance:** GOV-002 — IaC, immutable, idempotent  

---

## Overview

`env.yaml` is the single source of truth for a developer's complete environment.  
Local = Remote = CI = AI. One file, zero drift.

---

## Schema Reference (v1)

```yaml
# env.yaml — ElevatedIQ Portable Dev Environment Spec
version: "1"

runtime:
  mode: local             # local | remote | ci | edge
  host: ide.kushnir.cloud  # required if mode=remote
  fallback: local          # fallback mode if primary unavailable
  resource_limits:
    cpu: 4
    memory: 8Gi

services:
  - name: postgres
    image: postgres:16@sha256:<digest>  # SHA256-pinned for reproducibility
    persistent: true
    env:
      POSTGRES_DB: appdb
      POSTGRES_USER: app
  - name: redis
    image: redis:7@sha256:<digest>
    persistent: false

ai:
  model: llama3:8b
  provider: ollama
  fallback_chain:
    - local               # 192.168.168.31 Ollama
    - private-endpoint
  constraints:
    - no_external_unless_explicit
    - prompt_pii_scan
    - log_all_interactions

policies:
  - no_prod_without_human
  - secrets_never_leave_boundary
  - full_audit_all_actions

compliance:
  frameworks: [SOC2, NIST-800-53]
  data_classification: internal  # public | internal | confidential | restricted
```

---

## Field Reference

### `runtime`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `mode` | enum | ✓ | `local` \| `remote` \| `ci` \| `edge` |
| `host` | string | if mode=remote | Remote host URL |
| `fallback` | enum | | Fallback mode if primary fails |
| `resource_limits.cpu` | number | | CPU cores |
| `resource_limits.memory` | string | | Memory (e.g. `8Gi`) |

### `services[]`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | ✓ | Service name |
| `image` | string | ✓ | Docker image with SHA256 digest for reproducibility |
| `persistent` | boolean | | Whether data persists across restarts |
| `env` | object | | Environment variables |

### `ai`

| Field | Type | Description |
|-------|------|-------------|
| `model` | string | Primary LLM model name |
| `provider` | enum | `ollama` \| `openai` \| `anthropic` |
| `fallback_chain` | list | Ordered list of fallback providers |
| `constraints` | list | Policy constraints applied to all AI calls |

### `policies`

Named OPA policy identifiers enforced at runtime:

| Policy | Description |
|--------|-------------|
| `no_prod_without_human` | Production changes require human approval |
| `secrets_never_leave_boundary` | Secrets are never sent to external APIs |
| `full_audit_all_actions` | All agent actions logged to audit trail |

### `compliance`

| Field | Values | Description |
|-------|--------|-------------|
| `frameworks` | `SOC2`, `NIST-800-53`, `ISO27001` | Active compliance frameworks |
| `data_classification` | `public` \| `internal` \| `confidential` \| `restricted` | Data sensitivity level |

---

## Environment Profiles

Pre-defined profiles live in `apps/env-provisioner/examples/`:

| File | Purpose |
|------|---------|
| `env-local-dev.yaml` | Local Docker Desktop development |
| `env-staging.yaml` | Staging environment on 192.168.168.42 |
| `env-production.yaml` | Production environment on 192.168.168.31 |
| `env-ci.yaml` | CI/CD GitHub Actions environment |

---

## CLI Operations

### Validate

```bash
elevatediq env validate [env.yaml]
# Validates against schemas/env-yaml.v1.json via env-provisioner service
# Falls back to local syntax check if service is unavailable
```

### Diff

```bash
elevatediq env diff env-staging.yaml env-production.yaml
# Shows: runtime changes, service version changes, policy changes
```

### Clone

```bash
elevatediq env clone --from staging --to my-feature
# Copies staging env.yaml to env-my-feature.yaml
# Pin image digests before committing
```

### Offline

```bash
elevatediq env offline [env.yaml]
# Outputs docker pull commands for all images in env.yaml
# After pulling: set RUNTIME_MODE=local to operate offline
```

### Replay

```bash
elevatediq env replay --build-id <github-run-id>
# Fetches exact env.yaml from failed CI run
# Provisions locally to reproduce CI failures deterministically
```

### Promote

```bash
elevatediq env promote --from staging --to production
# Shows diff, enforces OPA no_prod_without_human policy
# Direct promotion to production is BLOCKED — requires PR + approval
```

---

## Provisioner Service

The `apps/env-provisioner/` FastAPI service exposes:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/validate` | POST | Validate env.yaml against JSON schema |
| `/diff` | POST | Compare two env.yaml files |
| `/provision` | POST | Generate Docker Compose override from env.yaml |

Default port: `8007` (configurable via `ENV_PROVISIONER_URL`).

---

## JSON Schema Validation

Schema file: `schemas/env-yaml.v1.json`

VS Code integration — add to `.vscode/settings.json`:

```json
{
  "yaml.schemas": {
    "./schemas/env-yaml.v1.json": ["env.yaml", "env-*.yaml"]
  }
}
```

CI validation — add to `.github/workflows/`:

```yaml
- name: Validate env.yaml
  run: elevatediq env validate env.yaml
```

---

## Environment Fingerprint

The SHA-256 hash of `env.yaml` serves as a cache key in CI:

```yaml
- uses: actions/cache@v3
  with:
    key: env-${{ hashFiles('env.yaml') }}
```

---

## Governance

- All `env.yaml` files are version-controlled in git
- Production `env.yaml` changes require PR + tech_lead approval
- SHA256-pinned images ensure reproducibility across environments
- All provisioning operations are logged to `artifacts/env-operations.log`

---

*Generated: IaC, immutable, idempotent. GOV-002 compliant.*
