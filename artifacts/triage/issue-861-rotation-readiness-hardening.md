## Progress update for #861 (rotation-readiness hardening delivered)

Implemented and validated rotation-readiness hardening so the issue no longer depends on ad-hoc env availability during dry-run.

What changed:
- `.env.schema.json`
  - Added missing secret definitions with Vault mappings:
    - `REDIS_PASSWORD` (`secret/redis/password`)
    - `CLOUDFLARE_API_TOKEN` (`secret/cloudflare/api_token`)
  - Added both to required and secret variable lists.
- `scripts/security/rotate-secrets-quarterly.sh`
  - Added schema-aware reference resolver (`has_schema_vault_path`) using `.env.schema.json`.
  - Dry-run now treats Vault-mapped schema references as valid reference sources.
  - Report now includes:
    - `reference_sources` (`env_backed`, `schema_backed`)
    - `missing_references` array
  - Execute mode still requires loaded secret values and fails fast when missing.
- `scripts/ci/check-secrets-rotation-sla.sh`
  - Upgraded from freshness-only to health-enforced checks:
    - Requires `status` in `ready|complete`
    - Requires `missing_reference_count == 0`

Validation evidence:
- `bash -n scripts/security/rotate-secrets-quarterly.sh` passed.
- `bash -n scripts/ci/check-secrets-rotation-sla.sh` passed.
- `bash scripts/security/rotate-secrets-quarterly.sh --dry-run` now produces:
  - `status: ready`
  - `missing_reference_count: 0`
  - `reference_sources: { env_backed: 0, schema_backed: 7 }`
- `bash scripts/ci/check-secrets-rotation-sla.sh` now passes with status/missing checks enforced.
- `bash scripts/ci/check-no-hardcoded-credentials.sh` passes (`No hardcoded credential literals detected`).

Remaining blocker before closure:
- Execute-mode rotation/revocation drill evidence is still required (acceptance explicitly calls for tested rotation/revocation procedures).
- Workflow inventory artifact still contains `needs_review`/`must_remain_or_rotate` entries requiring final owner confirmation and revocation/rotation evidence linkage.

Conclusion:
- Keep #861 open, but narrowed to operational proof (execute-mode drill + final credential review evidence), not schema/readiness plumbing.