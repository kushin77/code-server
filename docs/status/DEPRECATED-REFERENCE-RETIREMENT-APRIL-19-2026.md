# Deprecated Reference Retirement - April 19, 2026

Status: Active
Scope: Retire active-path references to archived or deprecated components and duplicate implementation trails.

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
