# Architecture Decision Records

Purpose:
- Canonical home for long-lived architectural decisions, design rationales, and supersession history.

SSOT:
- [../structure/README.md](../structure/README.md)

## Top-Level ADRs

- [001-containerized-deployment.md](001-containerized-deployment.md)
- [002-oauth2-authentication.md](002-oauth2-authentication.md)
- [003-terraform-infrastructure.md](003-terraform-infrastructure.md)
- [004-configuration-consolidation-patterns.md](004-configuration-consolidation-patterns.md)
- [005-composition-inheritance.md](005-composition-inheritance.md)
- [006-cloudflare-tunnel-architecture.md](006-cloudflare-tunnel-architecture.md)
- [007-dual-portal-architecture.md](007-dual-portal-architecture.md)
- [008-portal-platform-appsmith-vs-backstage.md](008-portal-platform-appsmith-vs-backstage.md)
- [ADR-002-DUAL-PORTAL-ARCHITECTURE.md](ADR-002-DUAL-PORTAL-ARCHITECTURE.md)
- [TEMPLATE.md](TEMPLATE.md)

## Bridge Aliases for Numbered Backfill

- [ADR-0000-template.md](ADR-0000-template.md)
- [ADR-0001-containerized-deployment.md](ADR-0001-containerized-deployment.md)
- [ADR-0002-oauth2-authentication.md](ADR-0002-oauth2-authentication.md)
- [ADR-0003-terraform-infrastructure.md](ADR-0003-terraform-infrastructure.md)
- [ADR-0004-configuration-consolidation-patterns.md](ADR-0004-configuration-consolidation-patterns.md)
- [ADR-0005-composition-inheritance.md](ADR-0005-composition-inheritance.md)
- [ADR-0006-cloudflare-tunnel-architecture.md](ADR-0006-cloudflare-tunnel-architecture.md)
- [ADR-0007-dual-portal-architecture.md](ADR-0007-dual-portal-architecture.md)
- [ADR-0008-portal-platform-appsmith-vs-backstage.md](ADR-0008-portal-platform-appsmith-vs-backstage.md)

## Notes

- These files are the current ADR set retained for historical and architectural reference.
- New architectural decisions should land here using the canonical ADR naming convention from [../structure/README.md](../structure/README.md).
- Prefer one ADR per decision; when a decision changes, supersede instead of overwriting history.
- The bridge aliases above exist to satisfy issue-facing numbered references and CI checks without duplicating the canonical decision content.
