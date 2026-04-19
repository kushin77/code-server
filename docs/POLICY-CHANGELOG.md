# Policy Changelog

All normative policy changes to `config/code-server/` must be recorded here.  
Format: `YYYY-MM-DD | vX.Y.Z | Author | Summary`

## Change History

| Date | Version | Author | Change Summary |
|------|---------|--------|----------------|
| 2026-04-22 | 1.0.0 | @kushnir | Initial policy version — T1/T2/T3 settings model established; gallery blocked; extension manifest with SHA256 signature; policy-loader.sh startup hook |

## Tier Classification

| Tier | Meaning | Override Policy |
|------|---------|----------------|
| T1 | Immutable | Cannot be overridden by user or workspace settings |
| T2 | Recommended default | User may override per workspace |
| T3 | Seeded preference | Fully user-overridable |

## How to Update Policy

1. Edit the relevant file in `config/code-server/`
2. Run: `bash scripts/policy/generate-policy-version.sh`
3. Add a row to this changelog
4. Open a PR — policy changes require at least one approver review
5. Merge triggers `policy-version-integrity` CI check to verify hash consistency
