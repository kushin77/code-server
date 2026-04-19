# Documentation Structure SSOT

Purpose:
- Define the canonical documentation layout, naming rules, and source-of-truth boundaries for this repository.
- Prevent overlapping docs, duplicated guidance, and new loose markdown files at the repository root.

## Canonical Folders

- `docs/ai/` - AI governance, AI access policy, model contracts, and model-promotion rules.
- `docs/adr/` - Architecture Decision Records and long-lived design decisions.
- `docs/archives/` - Historical records, retired session notes, and legacy artifacts.
- `docs/elite-best-practices/` - Navigation-only landing zone for monorepo, pnpm, shared, SSOT, repo rules, instructions, and naming convention references.
- `docs/ops/` - Runbooks, operational procedures, recovery steps, and operator evidence.
- `docs/status/` - Proof artifacts, status ledgers, execution summaries, and evidence bundles.
- `docs/triage/` - Issue blockers, execution plans, triage notes, and current remediation paths.
- `docs/structure/` - Documentation structure, repo rules, naming conventions, and indexing guidance.

## Shared

- Share one canonical document per topic.
- If a concept already has a home, link to it instead of creating a parallel copy.
- Prefer short, issue-linked docs over free-form narrative when the document is operational.
- Keep evidence ephemeral unless it needs to be attached to an issue or PR comment.

## Indexed

- `docs/README.md` is the top-level documentation index.
- `docs/elite-best-practices/README.md` is the mirrored best-practices landing page.
- `docs/adr/README.md`, `docs/ai/README.md`, `docs/archives/README.md`, `docs/ops/README.md`, `docs/status/README.md`, and `docs/triage/README.md` are the canonical folder indexes for their respective areas.
- This file is the canonical index for structure, naming, and doc placement rules.
- Use issue-linked bridge docs only when a migration is in progress.

## Meta

- New markdown files must include a clear title and a one-line purpose.
- Status and proof documents should include a date in the filename when they are time-bound.
- Operator evidence should reference the issue number or workflow run when possible.
- Root-level markdown files are legacy migration artifacts and should not be added for new work.

## Structure

- Keep long-lived operational docs in `docs/ops/`.
- Keep validation evidence in `docs/status/`.
- Keep issue-facing blocker notes in `docs/triage/`.
- Keep AI governance and contract material in `docs/ai/`.
- Keep architectural decisions in `docs/adr/`.
- Keep historical records in `docs/archives/`.

## Repo Rules

- Avoid duplicate guidance across files; update the SSOT and link to it.
- Prefer one doc per workflow, policy, or runbook.
- If a new file overlaps an existing one, consolidate instead of copying.
- Do not create new root-level markdown files unless there is a strong reason and a migration plan.

## Instructions

1. Choose the canonical folder before creating a new doc.
2. Check whether a matching doc already exists.
3. If it exists, update it and link to it.
4. If it does not exist, create the new doc in the correct folder.
5. Update `docs/README.md` when the index changes.
6. Use `docs/elite-best-practices/` only as a navigation layer; keep the SSOT in this file.

## SSOT

- `docs/README.md` is the documentation entrypoint.
- This file is the SSOT for structure and naming rules.
- Issue trackers remain the SSOT for outstanding work.
- Evidence and proofs should point back to the tracker or workflow that generated them.

## Standard Naming Convention (SNC)

- Use `README.md` for folder indexes only.
- Use `TOPIC-ISSUE-NUMBER.md` for issue-backed docs and evidence.
- Use `ADR-###-TITLE.md` for architecture decisions.
- Use `YYYY-MM-DD` in filenames for session and proof artifacts when the date matters.
- Keep names uppercase with hyphens for long-lived issue-linked docs.

## Migration Notes

- Legacy docs root migration was completed in issue #691; the remaining root files are compatibility stubs only.
- The current bridge inventory lives in [../triage/LEGACY-DOCS-ROOT-INVENTORY-2026-04-18.md](../triage/LEGACY-DOCS-ROOT-INVENTORY-2026-04-18.md).
- Bridge docs at the repository root should point to the canonical folder indexes instead of duplicating content.
- New work should land in the canonical folder immediately instead of adding another flat file.
- If a bridge doc is still needed, point it at the canonical doc rather than copying the content.
