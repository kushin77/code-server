# Portal OAuth GCP/GSM Bootstrap Runbook

Purpose:
- Define the canonical non-interactive GCP Workload Identity and GSM secret bootstrap path for `portal-oauth-redeploy.yml`.
- Keep the redeploy path immutable, idempotent, and secret-driven.

Scope:
- Applies to `.github/workflows/portal-oauth-redeploy.yml`, `scripts/fetch-gsm-secrets.sh`, and `scripts/deploy/redeploy-portal-oauth-routing.sh`.
- Does not store secret material or replace the canonical secret source in Google Secret Manager.

Canonical contract:
- `GCP_PROJECT`: GCP project ID used by `google-github-actions/setup-gcloud@v2`.
- `GCP_SA`: service account email used by `google-github-actions/auth@v2`.
- `GCP_WIF_PROVIDER`: full Workload Identity Provider resource name in the canonical form `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<POOL>/providers/<PROVIDER>`.
- `GSM_PROJECT`: GSM project used by `scripts/fetch-gsm-secrets.sh`; default is `gcp-eiq`.
- The workflow normalizes legacy provider prefixes as a compatibility shim, but the stored secret should still be the full resource name.
- The GSM-backed secrets needed by the workflow are ephemeral and written only to `.env` in the runner workspace.

Execution order:
1. Authenticate to GCP with Workload Identity.
2. Set up `gcloud`.
3. Bootstrap `.env` from GSM.
4. Run `bash scripts/deploy/redeploy-portal-oauth-routing.sh --local`.
5. Verify apex and IDE redirects.
6. Remove `.env` if the job created it.

Validation:
- `google-github-actions/auth@v2` must complete without `invalid_request audience`.
- `scripts/fetch-gsm-secrets.sh` must complete without prompting for manual login.
- The workflow must leave no secret files behind after cleanup.
- Live curl checks must return distinct apex and IDE redirect URIs.

Failure modes:
- `invalid_request audience`: `GCP_WIF_PROVIDER` secret is not the canonical provider resource name.
- `gcloud secrets versions access` fails: WIF auth or service account access is broken.
- `docker not found`: runner image is missing the Docker engine.
- `Permission denied (publickey,password)`: old SSH path; workflow should use local execution on the self-hosted runner.

References:
- [../triage/ISSUE-BLOCKER-P0-OAUTH-REDEPLOY.md](../triage/ISSUE-BLOCKER-P0-OAUTH-REDEPLOY.md)
- [../triage/AUTONOMOUS-EXECUTION-PLAYBOOK-2026-04-18.md](../triage/AUTONOMOUS-EXECUTION-PLAYBOOK-2026-04-18.md)
- [../status/AUTONOMOUS-OPEN-ISSUE-STATUS-2026-04-18.md](../status/AUTONOMOUS-OPEN-ISSUE-STATUS-2026-04-18.md)
- [../../scripts/fetch-gsm-secrets.sh](../../scripts/fetch-gsm-secrets.sh)
- [../../.github/workflows/portal-oauth-redeploy.yml](../../.github/workflows/portal-oauth-redeploy.yml)
