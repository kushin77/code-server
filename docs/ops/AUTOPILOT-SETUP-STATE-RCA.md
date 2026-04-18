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

Validated remediation:
- Enforce canonical auth env at startup.
- Run a deterministic reconciler instead of relying on stale UI cache.
- Only clear setup flags when capability probes are healthy.

Actionable diagnostics:
- Operators should use the reconciler reason codes instead of a generic setup CTA.