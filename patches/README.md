# KC Patch Boundary

This directory is reserved for KC-specific patch artifacts applied on top of upstream `coder/code-server` updates.

## Purpose

- Keep upstream syncs clean and reviewable.
- Isolate KC customizations from direct upstream edits.
- Support the monthly upstream sync workflow in `.github/workflows/upstream-sync.yml`.

## Rules

- Do not copy full upstream trees into this directory.
- Store only patch files or patch metadata required for KC customization.
- Reference related issues/PRs in patch filenames or adjacent notes.
