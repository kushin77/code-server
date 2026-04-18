# Deep Shared Indexed Meta

Purpose: define metadata and indexing model for large-repo discoverability and agent-safe execution.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## Meta Index Principles

- Every critical domain has one index doc with links to canonical files.
- Index docs are maintained under `docs/` and referenced from parent README files.
- Deprecated docs are marked and linked to active replacement.

## Shared Ownership

- `scripts/_common/` owns shared shell utilities.
- `docs/governance/` owns process and policy standards.
- `terraform/` owns IaC source of truth.
- `docker-compose.yml` remains canonical compose entrypoint.

## Anti-Duplication Checks

- Duplicate filename variants should be archived or removed.
- Root-level loose markdown growth is blocked by policy.
- New operational docs must live under `docs/` taxonomy.
