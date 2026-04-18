# Autopilot Setup-State Recovery Runbook

Objective:
- Restore a healthy code-server setup state when the UI shows a stale `Finish Setup` prompt.
- Prefer the canonical GSM-backed auth path and keep remediation idempotent.

Scope:
- This runbook is for the setup-state drift path described in [AUTOPILOT-SETUP-STATE-RCA.md](AUTOPILOT-SETUP-STATE-RCA.md).
- It does not change product behavior; it only reconciles persisted state and validates the runtime contract.

Prerequisites:
- `gcloud` authenticated against the canonical GSM project.
- `scripts/fetch-gsm-secrets.sh` available in the workspace.
- `scripts/ops/reconcile-setup-state.sh` on `main`.
- Read/write access to the local VS Code user state directory.

Canonical variables:
- `GSM_PROJECT=gcp-eiq`
- `GSM_SECRET_NAME=github-token`
- `AUTOPILOT_SETUP_REPORT=/tmp/autopilot-setup-drift-report.json`
- `SETUP_RECONCILE_REPORT=/tmp/setup-reconcile-report.json`

Procedure:
1. Confirm the canonical auth path is healthy.
   - `bash scripts/ops/reconcile-setup-state.sh --dry-run`
   - Expect all probes to pass.

2. If the token probe fails, verify GSM access before changing anything.
   - `gcloud --quiet secrets versions access latest --secret=github-token --project=gcp-eiq >/dev/null`
   - If this fails, stop and resolve GSM auth first.

3. Bootstrap the GSM-backed token in the current shell only if needed.
   - `source scripts/fetch-gsm-secrets.sh`
   - The bootstrap is ephemeral; do not persist the token in files or shell history.

4. Reconcile the setup state.
   - `bash scripts/ops/reconcile-setup-state.sh --fix`
   - The script is idempotent and only clears stale flags when the capability probes are healthy.

5. Re-run the drift guard.
   - `bash scripts/ci/check-autopilot-setup-drift.sh`
   - This is the acceptance check for the false-positive setup prompt path.

6. Capture evidence.
   - Save the reconcile report from `SETUP_RECONCILE_REPORT`.
   - Save the drift report from `AUTOPILOT_SETUP_REPORT`.
   - Include the timing fields (`started_at`, `finished_at`, `elapsed_seconds`) in any issue or PR comment.
   - Keep evidence ephemeral unless it is needed for an issue comment or PR.

Validation criteria:
- `git-credential-helper` is healthy.
- `auth-keepalive` is running.
- `gsm-env-canonical` matches `gcp-eiq/github-token`.
- `github-token` is present.
- `admin-portal-reachable` succeeds.
- `scripts/ci/check-autopilot-setup-drift.sh` exits 0.

Rollback / recovery:
- If reconciliation fails, rerun `bash scripts/ops/reconcile-setup-state.sh --dry-run` and inspect the `reason-codes` field.
- Do not edit persisted setup state by hand.
- If GSM access is unavailable, resolve that dependency first and retry; do not substitute a one-off token file.

Operational notes:
- The reconciler now self-bootstraps `GITHUB_TOKEN` from GSM when the shell does not already export it.
- The local token bootstrap is ephemeral by design and should not be committed.
- Use this runbook only for setup-state drift; it is not a general auth debugging guide.