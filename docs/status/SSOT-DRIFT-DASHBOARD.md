# SSOT Drift Dashboard

This dashboard summarizes active SSOT drift evidence and links it back to the versioned registry.

## Inputs

- `policy-ssot-report.json`
- `artifacts/config-ssot/config-ssot-report.json`
- Nightly workflow issue comments and generated issue bodies

## Status

- Registry version: 2026-04-19
- Nightly scan: enabled via `.github/workflows/ssot-integrity-auditor.yml`
- Issue routing: enabled

## Open Drift Items

Populate this section from the latest nightly issue body. Each open item should include:

- Canonical file(s)
- Drift summary
- Severity
- Linked issue number

## Operational Notes

- Update the registry first, then the dashboard.
- Any new canonical surface must be added to [docs/governance/SSOT-REGISTRY.md](../governance/SSOT-REGISTRY.md).