# Root Loose File Inventory (2026-04-18)

Purpose: baseline for root-level dedup and documentation migration.

Status: ACTIVE
Lifecycle: active-production

## Baseline

- Root markdown files: 36
- Target steady-state: only entrypoint docs at root; operational docs under `docs/`

## High-Confidence Migration Candidates

- Session summaries (`SESSION-*`)
- Phase summaries (`PHASE-*`)
- Migration status docs (`MIGRATION-*`)
- Implementation summaries (`IMPLEMENTATION_*`)
- Quality gate status docs

## Migration Strategy

1. Move historical summaries to `archived/phase-summaries/` or `docs/.../historical/`.
2. Keep active SSOT docs in `docs/governance/elite-best-practices/`.
3. Replace moved root docs with index references if still needed.
4. Enforce root markdown budget in CI.

## Safety Rules

- Move in small PR batches.
- Preserve git history with `git mv`.
- Verify all references are updated in same PR.
- Do not close issue until links and CI are green.
