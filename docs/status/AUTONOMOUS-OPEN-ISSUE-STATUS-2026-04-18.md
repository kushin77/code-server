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
    - `scripts/ci/validate-repo-aware-ai-pipeline.sh`
    - `.github/workflows/repo-aware-ai-pipeline.yml`
    - `docs/ops/REPO-AWARE-AI-PIPELINE-RUNBOOK.md`
    - `docs/status/REPO-AWARE-AI-PIPELINE-PROOF-2026-04-18.md`
  - Remaining gap:
    - production rollout evidence still needs GitHub-side confirmation if the issue remains open there
    - local validation now covers the evaluation set, freshness metrics, and access-control evidence contract

- `#629` Cross-repo contract and compatibility matrix
  - Landed artifacts:
    - `config/ollama-integration-contract.yml`
    - `scripts/ci/validate-ollama-integration-contract.sh`
    - `.github/workflows/ollama-contract-coverage.yml`
    - `docs/ops/OLLAMA-INTEGRATION-CONTRACT-RUNBOOK.md`
    - `docs/status/OLLAMA-INTEGRATION-CONTRACT-PROOF-2026-04-18.md`
  - Remaining gap:
    - production rollout evidence still needed
    - local validation now passes with explicit release handshake and compatibility matrix checks

- `#630` Model promotion gates
  - Landed artifacts:
    - `config/ollama-model-promotion-gates.yml`
    - `scripts/ci/validate-ollama-model-promotion-gates.sh`
    - `.github/workflows/ollama-model-promotion-gates.yml`
    - `docs/AI-MODEL-PROMOTION-GATES-630.md`
    - `docs/ops/OLLAMA-MODEL-PROMOTION-GATES-RUNBOOK.md`
    - `docs/status/OLLAMA-MODEL-PROMOTION-GATES-PROOF-2026-04-18.md`
  - Remaining gap:
    - GitHub issue state still needs confirmation/closure in a signed-in session if it remains open
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
    - local validation now passes for the policy doc, CI enforcement, canary evidence format, and postmortem loop
    ## Open Issues Without Landed Implementation Yet

    - `#291` VSCode crash RCA and persistent stability tracking
- The current `main` branch already contains merged scaffolding for several open issues. Avoid redoing those files from scratch.
    ## Recommended Execution Order

    1. `#291` remains persistent and should never be used as a delivery blocker for unrelated work.