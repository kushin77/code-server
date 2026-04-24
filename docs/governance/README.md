# Governance Policy SSOT

Purpose: canonical entry point for governance policy, precedence, and change control.

## Canonical Order

When governance statements conflict, apply precedence from highest to lowest:

1. [POLICY.md](POLICY.md)
2. [POLICY-INDEX.md](POLICY-INDEX.md)
3. [GLOBAL-DEDUP-GOVERNANCE.md](GLOBAL-DEDUP-GOVERNANCE.md)
4. [WAIVERS.md](WAIVERS.md)
5. [WAIVER-REQUEST.md](WAIVER-REQUEST.md)

## What Belongs Here

- Security, quality, CI, and infrastructure policy
- Duplicate detection and waiver lifecycle rules
- Policy versioning and change control requirements
- Canonical references for governance-related automation

## Quick Links

- [INSTRUCTIONS-INTENT-MEMORY-SSOT.md](INSTRUCTIONS-INTENT-MEMORY-SSOT.md) - canonical instruction, intent, and memory lifecycle index
- [POLICY-INDEX.md](POLICY-INDEX.md) - machine-readable policy registry and ownership map
- [POLICY.md](POLICY.md) - canonical policy text
- [GLOBAL-DEDUP-GOVERNANCE.md](GLOBAL-DEDUP-GOVERNANCE.md) - overlap and deduplication policy
- [WAIVERS.md](WAIVERS.md) - approved waiver inventory
- [WAIVER-REQUEST.md](WAIVER-REQUEST.md) - request format for temporary exceptions
- [CONFIG-SSOT.md](CONFIG-SSOT.md) - canonical configuration ownership and precedence map
- [CHANGELOG.md](CHANGELOG.md) - governance policy history
- [config/governance-policy-domains.json](../../config/governance-policy-domains.json) - domain registry
- [scripts/ci/check-policy-ssot.sh](../../scripts/ci/check-policy-ssot.sh) - governance SSOT guard
- [.github/workflows/policy-ssot-guard.yml](../../.github/workflows/policy-ssot-guard.yml) - CI enforcement workflow

## Migration Rule

Legacy governance text must be reduced to references to the canonical files above. New policy should be added to the canonical file for its domain first, then indexed here.