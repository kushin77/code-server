# Memory Schema Versioning and Migration Strategy

## Canonical Schema

- Canonical file: `schemas/memory-snapshot.v1.schema.json`
- Current version: `1.0.0`
- Canonical payload fields:
  - `schema_version`
  - `intent_map`
  - `suggestion_history`
  - `vector_store`
  - `conversation_history`
  - `retention`

## Backward Compatibility Targets

The migration layer supports three input formats:

1. Canonical `1.0.0` snapshot
2. Pre-version full persistence snapshot (same fields, no `schema_version`)
3. Legacy lightweight `exportSnapshot()` output (`intent_map`, `active_goals`, `contradictions`, `github_context`)

## Migration Policy

- All loaded snapshots are normalized through `migrateAndValidateMemorySnapshot(...)`.
- If migration succeeds, payload is validated against the canonical JSON schema.
- Invalid payloads fail fast with detailed schema validation errors.

## Versioning Rules

- Patch version (`1.0.x`): additive non-breaking schema clarifications only.
- Minor/major (`1.x`/`2.x`): requires migration adapter updates and backward-compat tests.
- Every schema bump must include:
  - new schema artifact,
  - migration function update,
  - validation tests,
  - compatibility tests for previous version.

## Retention and Pruning

Retention is configurable via env vars or constructor options:

- `MEMORY_RESOLVED_GOAL_TTL_MS`
- `MEMORY_MAX_CONVERSATION_TURNS`
- `MEMORY_SUGGESTION_RETENTION_MS`
- `MEMORY_CONTRADICTION_RETENTION_MS`
- `MEMORY_RETENTION_DAYS` (backend-level snapshot retention)

Pruning occurs before persistence and through backend expiration routines.
