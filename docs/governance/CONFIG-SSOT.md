# Configuration SSOT

Purpose: canonical source-of-truth map for configuration ownership, precedence, and drift prevention across env vars, schema, Terraform, Kubernetes, and runtime docs.

## Precedence Order

When config sources conflict, apply this order from highest to lowest priority:

1. Runtime secret manager values from GSM or Vault for sensitive values.
2. Deployment environment variables supplied to the runtime.
3. Terraform and Kubernetes variables for environment-specific infrastructure inputs.
4. `.env.template` and `.env.example` as documentation contracts only.
5. `.env.schema.json` as the required-variable schema.
6. Narrative docs and runbooks, which must reference but not override the canonical sources above.

## Ownership by Class

| Config class | Canonical owner | Consuming surfaces |
|---|---|---|
| Domains and host topology | [docs/ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md), [docs/NAS-ARCHITECTURE.md](../NAS-ARCHITECTURE.md) | Compose, Terraform, ingress, runbooks; NAS contract is host `192.168.168.56`, export `/export`, mount `/mnt/nas`, protocol `nfs4` |
| OAuth and endpoint auth | [docs/ops/ENDPOINT-CONTRACT-INDEX.md](../ops/ENDPOINT-CONTRACT-INDEX.md), [docs/adr/002-oauth2-authentication.md](../adr/002-oauth2-authentication.md) | oauth2-proxy, Caddy, E2E tests |
| NAS host and export values | [docs/NAS-ARCHITECTURE.md](../NAS-ARCHITECTURE.md) | Scripts, Terraform, deployment preflight; canonical values are host `192.168.168.56`, export `/export`, mount `/mnt/nas`, protocol `nfs4` |
| Secrets and rotation | [docs/SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md), [docs/ops/SECRETS-ROTATION-SCHEDULE.md](../ops/SECRETS-ROTATION-SCHEDULE.md) | GSM, Vault, bootstrap scripts |
| Schema and required env vars | [.env.schema.json](../../.env.schema.json) | Validation scripts, docs generators |
| Drift detection | [scripts/ci/detect-config-drift.sh](../../scripts/ci/detect-config-drift.sh), [scripts/dev/check-config-drift.sh](../../scripts/dev/check-config-drift.sh) | CI, local validation |

## Active Rules

- Every required runtime secret must exist in the schema or bootstrap contract before the deployment path consumes it.
- Hardcoded IPs, domains, URLs, and credentials must be treated as drift unless they are explicitly documented as fixed topology values.
- New config keys require an owner, a source of truth, and a validation path before they reach a production manifest.
- If a variable changes meaning, deprecate the old key through a documented migration window instead of reusing it silently.

## Drift Prevention

Required validation surfaces:

- `.env.schema.json` generation and review
- Compose and Terraform hardcoded-value checks
- Secret rotation evidence
- Endpoint and NAS contract validation
- Production redeploy preflight checks

### Domain Allowlist Policy (Static Docs/Examples)

To avoid false positives while keeping runtime enforcement strict, the config drift detector supports a file-level domain allowlist for intentional static references.

Policy rules:
- Runtime scripts, compose files, and task execution commands must use env-driven values.
- Documentation/example files may contain fixed hostnames only when explicitly allowlisted in `scripts/ci/detect-config-drift.sh` under `DOMAIN_ALLOWLIST_FILES`.
- Every allowlist entry must be documentation-only and must not be consumed as runtime configuration.

Current allowlisted static domain file:
- `docs/service-registry.yaml`

## Related Canonical Docs

- [docs/ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- [docs/NAS-ARCHITECTURE.md](../NAS-ARCHITECTURE.md)
- [docs/ops/ENDPOINT-CONTRACT-INDEX.md](../ops/ENDPOINT-CONTRACT-INDEX.md)
- [docs/SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md)
- [docs/ops/OPS-COMPLIANCE-CHECKLIST.md](../ops/OPS-COMPLIANCE-CHECKLIST.md)

## Operational Note

This file is a contract, not a duplication target. Update the underlying schema, scripts, or deployment variables first, then refresh this index to match.
