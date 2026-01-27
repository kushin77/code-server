# HOWTO: Configure Snyk token in Google Secret Manager and GitHub Workload Identity

This document shows the recommended, secure approach to provide a Snyk token to GitHub Actions using Google Secret Manager (GSM) and Workload Identity Federation.

Prerequisites
- GCP project with Secret Manager enabled.
- A Snyk account and token stored in Secret Manager (name: `snyk-token` or other).
- Owner/Editor access to the GitHub repository to add repo secrets.

High-level steps
1. Create a GCP service account for GitHub Actions (example: `snyk-runner@PROJECT.iam.gserviceaccount.com`).
2. Grant the service account the `roles/secretmanager.secretAccessor` role on the secret.
3. Create a Workload Identity Pool and Provider (or reuse existing) and configure trust with GitHub.
4. Allow the provider to impersonate the service account via IAM binding:

```sh
PROJECT=your-gcp-project
SA=snyk-runner@${PROJECT}.iam.gserviceaccount.com
POOL=github-pool
PROVIDER=github-provider
# Grant workload identity user role
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/${PROJECT}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/kushin77/code-server"
```

5. Store the Snyk token in Secret Manager (if not already):

```sh
echo -n "${SNYK_TOKEN}" | gcloud secrets create snyk-token --data-file=- --project=${PROJECT}
# or add a new version
echo -n "${SNYK_TOKEN}" | gcloud secrets versions add snyk-token --data-file=- --project=${PROJECT}
```

6. Add repository secrets in GitHub (Settings → Secrets):
- `GCP_WIF_PROVIDER` — the full Workload Identity Provider resource name, e.g.: `projects/123/locations/global/workloadIdentityPools/pool/providers/provider`.
- `GCP_SA` — service account email (e.g. `snyk-runner@PROJECT.iam.gserviceaccount.com`).
- `GCP_PROJECT` — GCP project id.
- `GSM_SNYK_SECRET_NAME` — secret name in GSM (e.g. `snyk-token`).

Verification
1. Once the secrets are added, re-run the `Security Scans` workflow on a PR or by pushing a commit to trigger the workflow.
2. The workflow will authenticate via `google-github-actions/auth`, access the secret via `gcloud secrets versions access latest`, and run Snyk.

Notes
- Using GSM + Workload Identity avoids storing long-lived Snyk tokens in GitHub Secrets. It uses short-lived OIDC tokens for secure access.
- If you prefer a quicker setup, you can still add `SNYK_TOKEN` directly to GitHub Secrets (less recommended).

If you want, I can add example `gcloud` commands to create the Workload Identity Pool/provider and the provider mapping — tell me and I will add them.
