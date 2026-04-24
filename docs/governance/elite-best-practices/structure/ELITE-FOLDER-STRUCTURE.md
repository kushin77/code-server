# Elite Folder Structure

Purpose: enforce predictable structure with no loose operational files in repository root.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## Canonical Top-Level Domains

- `docs/`
- `scripts/`
- `terraform/`
- `docker/` or canonical compose files
- `backend/`
- `frontend/`
- `extensions/`
- `tests/`

## Placement Rules

- New docs go under `docs/<domain>/<capability>/<lifecycle>/...`
- New scripts go under `scripts/` and reuse `_common/` libraries
- IaC files remain under `terraform/` unless bootstrap entrypoint at root is required
- Temporary investigation logs go to `archived/` or are deleted before merge

## Root Hygiene Standard

- No new phase/status loose files in root
- No duplicate variant files when one canonical file + templating works
- Every exception must be documented in issue and PR rationale
