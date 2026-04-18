# Autonomous Open Issue Status - 2026-04-18

## Purpose

This file is the authoritative repo-side execution ledger for the remaining open GitHub issues after the April 18, 2026 push to `main`.

Use this document for autonomous agent work selection and issue hygiene.

Canonical machine-readable companion:
- `config/issues/agent-execution-manifest.json`

## Rules

- GitHub label priority (`P1`, `P2`, `P3`) is authoritative.
- Some issue bodies still contain stale original priority text. Do not use body text as the priority source of truth.
- If code is merged but the issue is still open, treat the issue as `partial` until acceptance criteria are explicitly verified.
- If a file is not committed to `main`, it does not exist for execution planning.

## Fully Closed In GitHub

- `#650` Org-wide auth and policy baseline
- `#643` org_internal 403 auth fix
- `#657` thin-client control-plane foundation
- `#626` entitlement sync foundation
- `#627` Enterprise IDE policy rollout epic
- `#628` Repo-aware AI pipeline
- `#629` Cross-repo contract and compatibility matrix
- `#630` Model promotion gates
- `#631` Replica GPU routing and failover
- `#632` Secretsless AI access
- `#633` Dedicated E2E service account
- `#634` Production endpoint E2E testing program epic
- `#635` VPN-only testing path
- `#636` Dedicated service-account feature profile and regression coverage
- `#637` Deterministic browser automation kit
- `#639` Autopilot setup-state drift epic
- `#640` Autopilot setup-state RCA
- `#641` Setup-state reconciler and self-healing
- `#291` VSCode crash RCA and persistent stability tracking (closed in GitHub; persistent tracker)

## Open Issues Without Landed Implementation Yet

- `#690` Provision GitHub Actions SSH secret for portal OAuth redeploy

## Recommended Execution Order

1. `#690` provision the deploy SSH secret and re-run the hardened portal workflow.

## Operational Notes

- The current `main` branch already contains merged scaffolding for several closed issues.
- Keep issue comments current when additional AC evidence lands so GitHub remains usable without local context.