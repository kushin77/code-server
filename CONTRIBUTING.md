# Contributing

Contributions follow these minimal rules to remain compliant with the `GCP-landing-zone` mandates:

- All changes must pass local `pre-commit` checks and CI workflows.
- Do not add secrets or Terraform state files to commits. Use GitHub Secrets and GCS remote state.
- PRs must include a short description of how the change impacts security/compliance (if any).
- For infrastructure IaC changes, include steps to validate policy (OPA) and CI gates.

Local checks
- `pre-commit run --all-files`
- `./scripts/validate.sh` (if present)

CI
- `ci-validate.yml` runs on PRs and enforces format/lint/pre-commit.
- `security.yml` runs vulnerability scans; maintainers must ensure secret tokens (SNYK_TOKEN) are set in repo secrets for full scans.
