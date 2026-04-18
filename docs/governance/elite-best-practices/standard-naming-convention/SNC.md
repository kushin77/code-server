# Standard Naming Convention (SNC)

Purpose: ensure consistent naming for files, branches, services, and docs.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## File Names

- Use uppercase kebab-case for major governance docs
- Use lowercase kebab-case for scripts and config files
- Avoid suffix variants like `-new`, `-final`, `-fixed`

## Branch Names

- `feat/<issue>-<topic>`
- `fix/<issue>-<topic>`
- `chore/<issue>-<topic>`

## Issue Titles

- Prefix priority at start: `P0:`, `P1:`, `P2:`, `P3:`
- Keep title action-oriented and measurable

## Service And Compose Naming

- Align container names with compose service names
- Keep profile names stable and descriptive (`monitoring`, `tracing`, `ai`)
