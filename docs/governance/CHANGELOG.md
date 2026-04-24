# Governance Policy Changelog

**Purpose**: Governance Policy Changelog — reference and operational document.

## 2026-04-18
- Added canonical policy index and precedence model in docs/governance/POLICY-INDEX.md
- Added CI policy SSOT checks via scripts/ci/check-policy-ssot.sh
- Added policy change control workflow in .github/workflows/policy-ssot-guard.yml
- Established canonical domain ownership and compatibility note requirements

## 2026-04-19
- Added machine-readable policy domain registry in config/governance-policy-domains.json
- Added CI policy domain registry validator in scripts/ci/validate-policy-domain-registry.sh
- Updated policy SSOT guard workflow to enforce policy domain registry checks
- Extended POLICY-INDEX canonical domains to include quality and infrastructure governance
- Added governance issue AC text overlap validator in scripts/ci/validate-governance-issue-ac-text-overlap.sh
- Updated policy SSOT guard workflow to block duplicate acceptance-criteria text across governance epics
- Added governance landing page at docs/governance/README.md and linked it from docs/README.md
- Expanded scripts/ci/check-policy-ssot.sh to scan governance docs recursively
- Added canonical deployment checklist at docs/ops/DEPLOYMENT-CHECKLIST.md for ops triage alignment