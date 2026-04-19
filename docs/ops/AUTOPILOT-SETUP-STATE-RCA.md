# Autopilot Setup-State RCA

Summary:
- The false `Finish Setup` prompt is a setup-state drift problem, not a confirmed auth-path failure.

Reproduction class:
- Functional GitHub operations succeed.
- Auth-backed automation succeeds.
- Persisted extension state still advertises incomplete setup.

Root cause classification:
- `STATE_CACHE_STALE`: persisted extension state contains stale setup markers.
- `AUTH_ENV_DRIFT`: canonical GSM environment differs from the enforced runtime contract.
- `AUTH_SCOPE_MISSING`: the runtime has auth configured but lacks the effective token or scope.
- `PORTAL_UNREACHABLE`: the portal policy source cannot be reached, so setup cannot be confirmed.
- `AUTH_KEEPALIVE_STOPPED`: the refresh daemon is not maintaining the expected runtime state.

Evidence bundle:
- `scripts/ops/reconcile-setup-state.sh` emits a structured JSON report with reason codes.
- `scripts/ci/check-autopilot-setup-drift.sh` fails when setup-state drift reappears while capability probes remain healthy.
- `scripts/ops/reconcile-setup-state.sh` now bootstraps `GITHUB_TOKEN` from GSM when the shell does not already export it.
- `docs/ops/AUTOPILOT-SETUP-STATE-RUNBOOK.md` captures the immutable operator recovery flow.
- `docs/ops/AUTOPILOT-SETUP-STATE-REGRESSION-MATRIX.md` defines the reason-code regression matrix and expected remediation behavior.
- `scripts/ci/validate-autopilot-setup-state-reconciler.sh` validates the RCA contract, regression matrix, and report schema.
- The reconciler report now includes `started_at`, `finished_at`, and `elapsed_seconds` for startup timing evidence.

Validated remediation:
- Enforce canonical auth env at startup.
- Run a deterministic reconciler instead of relying on stale UI cache.
- Only clear setup flags when capability probes are healthy.
- Prefer GSM-backed auth bootstrap over ad hoc token export when running the reconciler locally.

Actionable diagnostics:
- Operators should use the reconciler reason codes instead of a generic setup CTA.