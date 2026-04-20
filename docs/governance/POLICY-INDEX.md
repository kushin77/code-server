# Governance Policy Index

Date: 2026-04-18
Issue: #704

## Objective
Provide a single authoritative policy index with precedence, ownership, and versioning for governance controls.

This index is the machine-oriented companion to [README.md](README.md), which is the human entry point for governance policy navigation.

## Precedence Rules
When statements conflict, apply precedence from highest to lowest:
1. docs/governance/POLICY.md
2. docs/governance/POLICY-INDEX.md
3. docs/governance/GLOBAL-DEDUP-GOVERNANCE.md
4. docs/governance/WAIVERS.md
5. docs/governance/WAIVER-REQUEST.md

If a lower-precedence document conflicts with higher-precedence policy text, the lower-precedence statement is non-authoritative and must be updated to reference canonical text.

## Canonical Domains and Owners
| Domain | Canonical Source | Primary Owner | Secondary Owner |
|---|---|---|---|
| Security governance | docs/governance/POLICY.md | Security Engineering | Platform Engineering |
| Code quality governance | docs/governance/POLICY.md | Platform Engineering | Repository Owners |
| CI policy enforcement | .github/workflows/governance-enforcement.yml | Platform Engineering | Security Engineering |
| Infrastructure governance | docs/governance/P0-ENFORCEMENT-SLA-AND-OWNERSHIP.md | Platform Engineering | Infrastructure Team |
| Deduplication policy | docs/governance/GLOBAL-DEDUP-GOVERNANCE.md | Platform Engineering | Repository Owners |
| Waiver lifecycle | docs/governance/WAIVERS.md | Security Engineering | Repository Owners |
| Waiver request format | docs/governance/WAIVER-REQUEST.md | Repository Owners | Security Engineering |

Machine-readable registry: config/governance-policy-domains.json

## Versioning
- Policy version stamp: YYYY-MM-DD in each canonical policy update PR
- Compatibility notes: required for changes that alter mandatory controls
- Changelog requirement: every governance policy change must update docs/governance/CHANGELOG.md

## CI Controls
- scripts/ci/check-policy-ssot.sh detects duplicate and contradictory normative statements
- .github/workflows/policy-ssot-guard.yml runs detection and policy-change controls
- Governance policy changes must update [CHANGELOG.md](CHANGELOG.md) and the relevant canonical policy file.

## Migration Rule
Legacy overlapping policy text must be migrated to references to canonical files in this index and removed from duplicated locations.
