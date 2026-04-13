Subject: Welcome — code-server developer onboarding

Hi <New Developer>,

Welcome to the project. Quick start checklist:

- Clone the repo and run `./setup-dev.sh`.
- Install and run `pre-commit` and `./scripts/validate.sh` before opening PRs.
- Read `DEV_ONBOARDING.md` and `CONTRIBUTING.md` for policy and CI requirements.
- PRs must pass `CI Validate` checks and any required status checks before merging.

Security & compliance:
- Do not commit secrets or Terraform state. Use GitHub Secrets and GCS remote state (CMEK).
- Follow the `CODEOWNERS` and branch protection rules.

If you need help, ping `platform-engineering@company.com` or open an issue.

— Platform Engineering
