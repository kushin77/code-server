# Contributing

Use [docs/status/CONTRIBUTING.md](../docs/status/CONTRIBUTING.md) as the canonical engineering constitution for review gates, security posture, and release expectations.

## Architecture Decision Records

- Start new decisions from [docs/adr/ADR-0000-template.md](../docs/adr/ADR-0000-template.md).
- Keep long-lived architecture history in [docs/adr/README.md](../docs/adr/README.md).
- For the numbered backfill requested by issue #881, use the bridge aliases in [docs/adr/README.md](../docs/adr/README.md) rather than duplicating content.
- Link the relevant ADR in any PR that changes architecture, security boundaries, deployment topology, or long-lived platform conventions.

## Merge Expectations

- Update the canonical doc before or with the code change.
- Prefer bridge files only for compatibility or migration, not as the primary source of truth.
- Keep ADR naming stable and machine-checkable so CI can validate the document set.
