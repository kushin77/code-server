# SSOT Registry

**Purpose**: SSOT Registry — reference and operational document.

Version: 2026-04-19

This registry defines the canonical ownership surface for cross-consistency checks. It is the versioned entry point for the SSOT integrity auditor.

## Canonical Surfaces

| Domain | Canonical files | Owner | Validation surface |
| --- | --- | --- | --- |
| Config precedence and ownership | [CONFIG-SSOT.md](CONFIG-SSOT.md), [.env.schema.json](../../.env.schema.json) | Platform Engineering | config drift checks, schema validation |
| Governance policy statements | [WAIVERS.md](WAIVERS.md), [WAIVER-REQUEST.md](WAIVER-REQUEST.md), [REPO-RULES-SSOT.md](elite-best-practices/repo-rules/REPO-RULES-SSOT.md) | Platform Engineering | policy SSOT checks |
| Ops routing and runbooks | [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md), [../runbooks/production-readiness-gate.md](../runbooks/production-readiness-gate.md) | Platform Engineering | workflow validation, issue routing |
| Deployment contracts | [../runbooks/full-redeploy-certification.md](../runbooks/full-redeploy-certification.md), [../runbooks/dual-host-restart-harvest.md](../runbooks/dual-host-restart-harvest.md) | Platform Engineering | redeploy and restart preflight |

## Required Checks

- Config drift scan
- Policy SSOT scan
- Versioned registry update review
- Nightly issue routing for mismatches

## Change Rule

If a canonical file changes meaning or ownership, update this registry in the same change.