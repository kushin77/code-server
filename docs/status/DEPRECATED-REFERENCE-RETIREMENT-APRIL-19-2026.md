# Deprecated Reference Retirement - April 19, 2026

Status: Complete (2026-04-20)
Scope: Retire active-path references to archived or deprecated components and duplicate implementation trails.

## Retirement Status (Updated 2026-04-20)

All retirement targets addressed. Closure criteria met.

| File / Pattern | Status | Canonical Target | Action Taken |
|---|---|---|---|
| `scripts/common-functions.sh` | ✅ ARCHIVED | `scripts/_common/` | `# ARCHIVED` + `# DO NOT USE` marker; enforced by `scripts/ci/check-deprecated-script-shims.sh` |
| `scripts/logging.sh` | ✅ ARCHIVED | `scripts/_common/logging.sh` | `# ARCHIVED` marker; enforced by deprecated shim checker |
| `main.tf` (root) | ✅ DEPRECATED | `terraform/main.tf` | Deprecation notice added 2026-04-20; `# DO NOT MAKE CHANGES HERE` |
| `variables.tf` (root) | ✅ DEPRECATED | `terraform/variables.tf` | Deprecation notice added 2026-04-20; `# DO NOT MAKE CHANGES HERE` |
| `Caddyfile.clean` | ✅ FROZEN | `Caddyfile` | Read-only snapshot; CI `check-root-hygiene.sh` enforces known-good list |
| `Caddyfile.known-good` | ✅ FROZEN | `Caddyfile` | Known-good rollback snapshot; CI enforces |
| `Caddyfile.tpl` | ✅ FROZEN | `Caddyfile` | Terraform template snapshot; CI `enforce-global-dedup.sh` enforces |
| `docker-compose.yml.remote` | ✅ FROZEN | `docker-compose.yml` | Remote-target variant; read-only reference |
| `docker-compose.socket-override.yml` | ✅ FROZEN | `docker-compose.yml` | Override for Docker socket; CI enforces canonical compose usage |
| Legacy docs bridges (root-level `.md`) | ✅ ARCHIVED | `docs/` structure | All root-level bridge docs have canonical replacements; bridges archived or stubbed |
| `scripts/dev/refactor-phase2-task1.sh` | ✅ READ-ONLY | `scripts/_common/` | Refactoring artifact; not in active execution path |

### CI Enforcement in Place

- `scripts/ci/check-deprecated-script-shims.sh` — validates archived shim markers
- `scripts/ci/check-root-hygiene.sh` — validates known Caddyfile/compose variant allowlist
- `scripts/ci/enforce-global-dedup.sh` — blocks new duplicate file additions
- `.github/workflows/code-smell-governance.yml` — CI gate on all PRs

### Closure Criteria — All Met

- ✅ Every remaining legacy reference has a canonical target (see table above)
- ✅ No active-path docs point at deprecated implementations without a stub or redirect
- ✅ The retirement list is complete and time-bound (all items resolved 2026-04-20)

## Purpose

This is the canonical retirement register for issue #802. It records the remaining overlap patterns, the canonical replacements, and the order in which the active-path references should be removed or frozen.

## Evidence Reviewed

- [../governance/GLOBAL-DEDUP-TRIAGE.md](../governance/GLOBAL-DEDUP-TRIAGE.md)
- [../triage/LEGACY-DOCS-ROOT-INVENTORY-2026-04-18.md](../triage/LEGACY-DOCS-ROOT-INVENTORY-2026-04-18.md)
- [../MONOREPO.md](../MONOREPO.md)
- [../SHARED-LIBRARIES.md](../SHARED-LIBRARIES.md)
- [../ops/BRANCH-POLICY.md](../ops/BRANCH-POLICY.md)

## Remaining Retirement Targets

| Category | Current Risk | Canonical Replacement | Retirement Action |
| --- | --- | --- | --- |
| Legacy docs bridges | Duplicate guidance can confuse operators and agents. | Status/governance SSOT docs. | Replace active references with canonical status or governance docs and archive the bridge only after validation. |
| Overlap-prone runtime variants | Multiple variants can drift from runtime behavior. | Canonical runtime files and guards. | Freeze legacy variants, migrate consumers, then archive. |
| Root-level bridges | Root-level docs can survive long after their canonical targets exist. | The canonical docs index. | Add redirect/stub references or remove the bridge once callers migrate. |
| Duplicate implementation trails | Multiple paths can implement the same behavior. | Shared libraries and canonical scripts. | Consolidate helpers into the shared library surface and delete one-off duplicates. |

## Retirement Order

1. Freeze the active-path references that already have a canonical replacement.
2. Migrate remaining consumers to the canonical runtime or doc target.
3. Archive the obsolete bridge or duplicate implementation trail.
4. Leave a short stub only when a redirect period is required.

## Guardrails

- Do not delete a bridge until the canonical target is proven current.
- Keep the dedup triage and branch-policy guard as the enforcement backstop.
- Prefer archive stubs over silent removal when operator workflows still depend on the path.

## Closure Criteria

- Every remaining legacy reference has a canonical target.
- No active-path docs point at deprecated implementations without a stub or redirect.
- The retirement list is empty or explicitly time-bound.

## Cross-References

- Status index: [README.md](README.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
