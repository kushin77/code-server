# Autopilot Setup-State Regression Matrix

Purpose:
- Define the reproducible regression matrix for setup-state drift and the expected reason-code taxonomy.

Scope:
- Applies to the reconciler in [scripts/ops/reconcile-setup-state.sh](../../scripts/ops/reconcile-setup-state.sh).
- Used by [scripts/ci/validate-autopilot-setup-state-reconciler.sh](../../scripts/ci/validate-autopilot-setup-state-reconciler.sh) to keep the RCA contract machine-checkable.

Reason-code taxonomy:
- `HEALTHY` means the probe passed and no remediation is required.
- `STATE_CACHE_STALE` means persisted setup markers are stale and should only be cleared when all capability probes are healthy.
- `AUTH_ENV_DRIFT` means the canonical GSM environment does not match the runtime contract.
- `AUTH_SCOPE_MISSING` means a token or scope is missing even though auth is configured.
- `PORTAL_UNREACHABLE` means the policy source or portal endpoint could not be reached.
- `AUTH_KEEPALIVE_STOPPED` means the refresh daemon is not maintaining the expected runtime state.

Regression matrix:

| Scenario | Probe / Condition | Expected Reason Code | Expected Action |
|----------|-------------------|----------------------|-----------------|
| Healthy baseline | All capability probes pass | `HEALTHY` | No change |
| Stale setup marker | Persisted setup state contains stale finish markers | `STATE_CACHE_STALE` | Clear only after all capabilities are healthy |
| GSM env mismatch | `GSM_PROJECT` or `GSM_SECRET_NAME` diverges from the canonical pair | `AUTH_ENV_DRIFT` | Do not clear setup state until env is corrected |
| Missing token | `GITHUB_TOKEN` is absent after GSM bootstrap | `AUTH_SCOPE_MISSING` | Bootstrap canonical auth and retry |
| Portal outage | Portal or policy endpoint is unreachable | `PORTAL_UNREACHABLE` | Fail safe; do not auto-clear state |
| Keepalive stopped | `auth-keepalive` is not running | `AUTH_KEEPALIVE_STOPPED` | Start keepalive before reconciliation |

Validation rule:
- The reconciler may only auto-correct stale setup flags when the healthy capability probes remain healthy and the regression matrix is satisfied.

Evidence rule:
- Any issue comment or proof artifact should reference the reason code, the report timestamp, and the action taken.