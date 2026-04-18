# Setup-State Reconciler Proof — 2026-04-18

Purpose:
- Capture the verified scenario proof for the Autopilot setup-state reconciler and its drift guard.

Context:
- The false `Finish Setup` prompt is a stale setup-state problem, not a product auth failure.
- The reconciler now bootstraps `GITHUB_TOKEN` from GSM when needed and records timing telemetry in its JSON report.

Verified commands:
1. Dry-run reconciliation
   - `bash scripts/ops/reconcile-setup-state.sh --dry-run`
   - Result: all probes healthy; report emitted to `/tmp/setup-reconcile-report.json`

2. Drift guard
   - `bash scripts/ci/check-autopilot-setup-drift.sh`
   - Result: passed

3. Telemetry verification
   - Report fields confirmed: `started_at`, `finished_at`, `elapsed_seconds`
   - Result: report is machine-readable and suitable for issue evidence

Operator observations:
- `git-credential-helper` was healthy and GSM-backed.
- `auth-keepalive` was running.
- `gsm-env-canonical` matched the canonical `gcp-eiq/github-token` pairing.
- `admin-portal-reachable` succeeded.
- `github-token` was present after GSM bootstrap.

Acceptance evidence:
- The reconciler dry-run completed without modifying persisted state.
- The drift guard passed after reconciliation.
- Timing telemetry is now included in the reconcile report for startup validation evidence.

Operational note:
- Keep the token bootstrap ephemeral; do not persist ad hoc tokens in files or shell history.