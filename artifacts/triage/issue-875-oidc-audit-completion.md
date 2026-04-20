## Status update for #875 (repo workflow audit completed)

I completed a workflow-level credential-pattern audit and verified OIDC-backed auth in deploy paths.

Audit results across `.github/workflows/*.yml`:
- No matches for long-lived credential patterns used in CI workflows:
  - `GH_PAT`, `PAT`, `PERSONAL_ACCESS_TOKEN`
  - `GCP_SA_KEY`, `SERVICE_ACCOUNT_KEY`
  - `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CREDENTIALS`, `credentials_json`
  - `gcloud auth activate-service-account`
- Positive OIDC evidence present:
  - `.github/workflows/deploy.yml` includes `id-token: write` in deploy jobs.
  - `.github/workflows/portal-oauth-redeploy.yml` includes `id-token: write` and `google-github-actions/auth` with `workload_identity_provider` and service account identity binding.

Interpretation:
- CI workflow auth is now using OIDC/WIF patterns for cloud auth surfaces in repo workflows.
- I did not find PAT/service-account-key based auth usage remaining in workflow YAML.

Conclusion:
- #875 is ready to close for repository implementation scope (workflow code surface).