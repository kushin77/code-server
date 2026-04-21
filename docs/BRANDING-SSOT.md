# Branding SSOT - Kushnir.cloud / KC

**Status**: Canonical branding source of truth
**Owner**: Platform Engineering
**Last Updated**: 2026-04-21
**Depends On**: #1187

## Purpose

This document defines the approved branding model for the active project surfaces in this repository. Use this document when deciding how to name services, labels, docs, UI copy, and config-driven identifiers.

The goal is to keep active project-owned surfaces consistent while preserving upstream and historical references where they are required.

## Canonical Brand Terms

| Term | Canonical Value | Usage |
|------|-----------------|-------|
| Public brand | `Kushnir.cloud` | External-facing product and deployment branding |
| Short form | `KC` | Internal shorthand for services, dashboards, and team references |
| Apex domain | `kushnir.cloud` | Primary public domain |
| IDE domain | `ide.kushnir.cloud` | Public IDE hostname |
| Portal domain | `kushnir.cloud` | Public portal hostname |

## Variable Names

These names are the canonical vocabulary for brand-driven configuration:

| Variable | Meaning | Precedence / Notes |
|----------|---------|--------------------|
| `APEX_DOMAIN` | Public apex / portal hostname | Canonical runtime env var; backed by Terraform `domain` |
| `IDE_DOMAIN` | IDE hostname | Canonical runtime env var |
| `DOMAIN` | Legacy compatibility alias | Keep only when a surface has not yet been migrated |
| `BRAND_PUBLIC_NAME` | Human-facing public brand string | `Kushnir.cloud` |
| `BRAND_SHORT_NAME` | Internal shorthand | `KC` |
| `PROJECT_BRAND` | Full project brand label | `Kushnir.cloud (KC)` when a combined label is needed |

### Precedence Rules

1. Runtime environment variables override all other sources.
2. Terraform and deployment variables define canonical infra values.
3. `.env.defaults` provides documented fallback values.
4. Documentation, comments, and issue text must mirror the approved values above.

## Allowed `code-server` References

Keep `code-server` only when it is required for one of these reasons:

- Upstream dependency names or image references that are owned externally.
- Third-party protocol names or APIs that explicitly use `code-server`.
- Historical archive material that documents prior state and should remain unchanged.
- Exact package names or vendor strings that must match external tooling.

## Replace `code-server` In Active Surfaces

Replace `code-server` with brand-driven language in active project-owned contexts such as:

- User-facing docs and runbooks
- Service labels and identifiers that are project-owned
- Script output and logging visible to operators
- Terraform labels, tags, and friendly names
- GitHub workflow names and comments
- UI copy and descriptive titles

## Naming Rules

- Use `Kushnir.cloud` for public-facing product and deployment branding.
- Use `KC` for internal shorthand where the full brand is unnecessary.
- Use `APEX_DOMAIN` and `IDE_DOMAIN` for deployment hostnames.
- Keep `DOMAIN` only as a compatibility alias while legacy surfaces are being migrated.
- Use `BRAND_PUBLIC_NAME` and `BRAND_SHORT_NAME` in docs or UI copy when a brand label must be derived from configuration.
- Do not introduce a new project-owned `code-server` label if the same meaning can be expressed with brand variables.

## Exception Handling

When `code-server` appears in active text or code:

1. Classify it as upstream, historical, or project-owned.
2. Keep upstream and historical references unchanged.
3. Replace project-owned references with approved brand terms.
4. If the match is ambiguous, document the rationale in the replacement matrix issue: #1186.

## Relationship To Other Issues

- [docs/BRANDING-REPLACEMENT-MATRIX.md](BRANDING-REPLACEMENT-MATRIX.md) provides the replacement matrix and exception catalog.
- #1184 uses this SSOT to update active code and configuration.
- #1185 uses this SSOT to update documentation, comments, tests, and archives.

## Migration Note

This SSOT supersedes ad hoc brand notes in scattered docs and comments. New work should reference this file when deciding whether a `code-server` reference should remain or be replaced.