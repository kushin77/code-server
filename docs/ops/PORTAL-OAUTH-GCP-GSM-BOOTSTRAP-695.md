# Portal OAuth GCP/GSM Bootstrap Runbook (#695)

## Purpose

Canonical runbook for the non-interactive GCP Workload Identity and GSM bootstrap path used by `portal-oauth-redeploy.yml` on self-hosted runners.

## Canonical Contract

- `GCP_PROJECT`: GCP project selector used by `google-github-actions/setup-gcloud@v2`. The workflow also reuses it when constructing the fallback provider path, so that fallback only works when the secret resolves to the numeric project number.
- `GCP_SA`: service account impersonated by `google-github-actions/auth@v2`.
- `GCP_WIF_PROVIDER`: canonical full workload identity provider resource.
- `GSM_PROJECT`: Secret Manager project that stores portal secrets.

Accepted provider forms:

- `projects/<project-number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`
- `//iam.googleapis.com/projects/<project-number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`
- `https://iam.googleapis.com/projects/<project-number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`

The workflow strips the `//iam.googleapis.com/` and `https://iam.googleapis.com/` prefixes before auth.

If `GCP_PROJECT` is not numeric, treat the secret contract as incomplete and fix the provider resource or the secret value before retrying.

## Execution Order

1. Resolve `GCP_WIF_PROVIDER` from the secret or the repo default.
2. Authenticate to GCP via `google-github-actions/auth@v2`.
3. Configure gcloud with `google-github-actions/setup-gcloud@v2`.
4. Bootstrap an ephemeral `.env` from GSM using `scripts/fetch-gsm-secrets.sh --non-interactive`.
5. Run `scripts/deploy/redeploy-portal-oauth-routing.sh --local`.
6. Verify redirect targets for the apex and IDE callbacks.

## Failure Modes

- `invalid_request audience`: the provider value is not a canonical numeric provider resource.
- `invalid_target`: the provider value is canonical, but the backing workload identity pool/provider does not resolve in GCP.
- `invalid_rapt`: local workstation gcloud refresh has expired; reauthenticate before attempting provider discovery on the workstation.
- `docker` missing on runner: the workflow is not executing on the approved Docker-capable self-hosted host.
- `Non-interactive GSM mode requires active gcloud auth or GOOGLE_APPLICATION_CREDENTIALS`: runner identity is not configured for unattended GSM access.

## Validation

- `curl -skI 'https://kushnir.cloud/oauth2/start?rd=%2F' | tr -d '\r' | grep -i '^location:'`
- `curl -skI 'https://ide.kushnir.cloud/oauth2/start?rd=%2F' | tr -d '\r' | grep -i '^location:'`

## Acceptance Criteria

- Auth succeeds.
- GSM bootstrap writes an ephemeral `.env` and cleans it up after the job.
- Both redirect checks point to their surface-specific callbacks.
- Evidence is posted in issues `#695` and `#692`.

## References

- [Portal OAuth blocker note](../triage/ISSUE-BLOCKER-P0-OAUTH-REDEPLOY.md)
- [Autonomous execution playbook](../triage/AUTONOMOUS-EXECUTION-PLAYBOOK-2026-04-18.md)
- [Open issue status](../status/AUTONOMOUS-OPEN-ISSUE-STATUS-2026-04-18.md)
- [Portal 502 follow-up issue](../triage/ISSUE-BLOCKER-P0-OAUTH-REDEPLOY.md)
- [Portal OAuth redeploy workflow](../../.github/workflows/portal-oauth-redeploy.yml)
- [GSM bootstrap script](../../scripts/fetch-gsm-secrets.sh)
- [Redeploy helper](../../scripts/deploy/redeploy-portal-oauth-routing.sh)