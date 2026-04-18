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
- `#691` Consolidate legacy docs root into canonical folder indexes (closed in GitHub; compatibility stubs landed)
- `#291` VSCode crash RCA and persistent stability tracking (closed in GitHub; persistent tracker)

## Open Issues Without Landed Implementation Yet

- `#692` Provide reachable execution path for portal OAuth redeploy workflow
- `#686` fix(oauth): enforce surface-specific redirect callbacks and add redeploy helper
- `#684` feat(monorepo): bootstrap pnpm workspace and lockfile governance
- `#649` feat(policy): Implement VS Code Enterprise Policy Pack v1.0 (#618)

## Recommended Execution Order

1. `#692` provision a reachable execution path and re-run the hardened portal workflow.
2. `#686` keep the OAuth helper lane aligned with the portal redeploy path and review the open PR.
3. `#684` keep the monorepo/pnpm governance lane moving independently of the release blocker.
4. `#649` keep the policy-pack governance lane moving independently of the release blocker.

## Operational Notes

- The current `main` branch already contains merged scaffolding for several closed issues.
- `#690` is resolved: the deploy SSH secret is now provisioned in GitHub Actions.
- Local portal redeploy dry-run now passes with `bash scripts/deploy/redeploy-portal-oauth-routing.sh --dry-run --local`, and the temporary self-hosted runner validated both the portal dry-run and the VPN gate.
- `#691` is closed: the legacy docs-root bridge files were collapsed to compatibility stubs and the canonical folder indexes remain in place.
- The latest published portal OAuth run still fails in the Redeploy portal services step because the published workflow invokes the helper in SSH mode and the host rejects the key.
- `#686`, `#684`, and `#649` are open PR-backed lanes with existing repo artifacts; they are parallel review tracks, not the current release blocker.
- Keep issue comments current when additional AC evidence lands so GitHub remains usable without local context.