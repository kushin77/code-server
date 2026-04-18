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

## Open Issues With Landed Code On Main

These issues already have implementation artifacts in `main`, but they remain open because the full acceptance criteria were not yet verified or because follow-on deliverables are still missing.

### AI / Ollama Lane

- `#628` Repo-aware AI pipeline
  - Landed artifacts:
    - `config/code-server/ai/repo-rag-pipeline.yml`
    - `docs/ai/REPO-KNOWLEDGE-CORPUS-POLICY.md`
    - `scripts/ai-runtime-env`
  - Remaining gap:
    - explicit evaluation set, freshness metrics, and access-control validation still need evidence

- `#629` Cross-repo contract and compatibility matrix
  - Landed artifacts:
    - `config/ollama-integration-contract.yml`
  - Remaining gap:
    - contract doc, CI validation, release handshake, and compatibility-matrix verification still need completion against issue AC

- `#630` Model promotion gates
  - Landed artifacts:
    - `config/ollama-model-promotion-gates.yml`
  - Remaining gap:
    - promotion policy doc, CI enforcement, canary evidence format, and postmortem loop still need completion against issue AC

- `#631` Replica GPU routing and failover
  - Landed artifacts:
    - `docs/ops/OLLAMA-GPU-REPLICA-OPERATIONS.md`
    - `scripts/ollama-init.sh`
    - `scripts/ai-runtime-env`
  - Remaining gap:
    - host validation evidence for `.31` and `.42` plus failover proof still needed

- `#632` Secretsless AI access
  - Landed artifacts:
    - `config/code-server/ai/ai-access-profiles.yml`
    - `config/code-server/ai/model-entitlements.yml`
    - `config/code-server/ai/quota-policy.yml`
    - `docs/ai/SECRETSLESS-AI-ACCESS.md`
  - Remaining gap:
    - end-to-end per-user provisioning validation and quota enforcement evidence still needed

### Autopilot / E2E Lane

- `#633` Dedicated E2E service account
  - Landed artifacts:
    - `config/e2e-service-account-profile.yml`
  - Remaining gap:
    - actual OAuth service-account flow, secret sourcing, and production validation still need proof

- `#635` VPN-only testing path
  - Landed artifacts:
    - `scripts/ci/check-vpn-gate.sh`
  - Remaining gap:
    - CI integration and operator validation still needed

- `#636` Dedicated service-account feature profile and regression coverage
  - Landed artifacts:
    - `config/e2e-service-account-profile.yml`
  - Remaining gap:
    - full regression matrix, ownership model, and release gate coverage still needed

- `#637` Deterministic browser automation kit
  - Landed artifacts:
    - `scripts/ci/setup-e2e-playwright.sh`
  - Remaining gap:
    - fallback policy, shared fixtures, artifact standards, and runbook still needed

- `#640` Autopilot setup-state RCA
  - Landed artifacts:
    - `docs/ops/AUTOPILOT-SETUP-STATE-RCA.md`
    - `scripts/ci/check-autopilot-setup-drift.sh`
  - Remaining gap:
    - reproducible matrix, evidence bundle, and regression definitions still need explicit sign-off
    - reconciler now self-bootstraps `GITHUB_TOKEN` from GSM and passes the drift guard in local verification

- `#641` Setup-state reconciler and self-healing
  - Landed artifacts:
    - `scripts/ops/reconcile-setup-state.sh`
    - `docs/ops/AUTOPILOT-SETUP-STATE-RUNBOOK.md`
    - `docs/status/SETUP-STATE-RECONCILER-PROOF-2026-04-18.md`
  - Remaining gap:
    - local dry-run and fix-mode validation now pass with canonical GSM auth bootstrap
    - reconciler report now includes timing telemetry (`started_at`, `finished_at`, `elapsed_seconds`)

## Open Issues Without Landed Implementation Yet

- `#627` Enterprise IDE policy rollout epic
- `#634` Production endpoint E2E testing program epic
- `#639` Autopilot setup-state drift epic
- `#291` VSCode crash RCA and persistent stability tracking

## Recommended Execution Order

1. `#640` finalize RCA evidence and reason-code taxonomy.
2. `#641` validate reconciler behavior and publish recovery runbook.
3. `#633` complete the real service-account path.
4. `#635` integrate VPN gate into CI and production preflight.
5. `#637` finish deterministic harness and fallback policy.
6. `#636` build the feature-to-scenario regression matrix.
7. `#634` close the E2E epic after child acceptance evidence is complete.
8. `#629` finish the cross-repo contract doc and CI validation.
9. `#630` finish promotion governance and release enforcement.
10. `#631` validate replica failover on `.31` and `.42`.
11. `#632` prove per-user secretsless access and quotas.
12. `#628` finish governed RAG evaluation and retrieval controls.
13. `#627` close the enterprise policy epic after the remaining child AI and entitlement work completes.
14. `#291` remains persistent and should never be used as a delivery blocker for unrelated work.

## Operational Notes

- The current `main` branch already contains merged scaffolding for several open issues. Avoid redoing those files from scratch.
- For open issues listed as `partial`, the next agent should verify acceptance criteria first, then fill the specific remaining gap instead of broad reimplementation.
- Keep issue comments current when additional AC evidence lands so GitHub remains usable without local context.