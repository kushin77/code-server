# Root Loose File Inventory (2026-04-18)

Purpose: baseline for root-level dedup and documentation migration.

Status: ACTIVE
Lifecycle: active-production

## Baseline

- Root markdown files: 1 (`README.md`)
- Target steady-state: maintain a single root markdown entrypoint and keep operational docs under `docs/`

## Current State

- Root markdown sprawl remediation is complete for active documentation.
- Remaining root files are operational entrypoints and configuration files.
- New root markdown files are prohibited by governance unless explicitly approved with migration plan.

## Migration Strategy

1. Move newly discovered historical summaries to `docs/archives/` in small batches.
2. Keep active SSOT docs in `docs/governance/elite-best-practices/`.
3. Replace moved root docs with index references if still needed.
4. Enforce root markdown budget in CI (`scripts/ci/check-root-hygiene.sh`).

## Safety Rules

- Move in small PR batches.
- Preserve git history with `git mv`.
- Verify all references are updated in the same PR.
- Do not close issue until links and CI are green.
# Root Loose File Inventory (2026-04-18)

Purpose: baseline for root-level dedup and documentation migration.

Status: ACTIVE
Lifecycle: active-production

## Baseline

- Root markdown files: 1
- Target steady-state: root markdown budget stays at 1; all operational/guidance docs under `docs/`

## Current State

- Root markdown cleanup is effectively complete.
- Remaining root markdown file is a compatibility/entrypoint artifact.
- No new loose root markdown files are permitted for active work.

## Migration Strategy

1. Keep active SSOT docs in `docs/governance/elite-best-practices/`.
2. Route new runbooks to `docs/ops/` and architecture to `docs/adr/`.
3. Reject PRs adding new root markdown files unless explicitly approved.
4. Enforce root markdown budget in CI and track drift in issue comments.

## Safety Rules

- Move in small PR batches.
- Preserve git history with `git mv`.
- Verify all references are updated in same PR.
- Do not close issue until links and CI are green.
