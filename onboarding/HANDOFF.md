# code-server Onboarding Handoff

This handoff summarizes the onboarding work done, where to find artifacts, verification commands, and recommended next admin actions.

Summary of completed work
- Onboarding docs: `DEV_ONBOARDING.md`, `CONTRIBUTING.md`.
- Developer tooling: `setup-dev.sh`, `Dockerfile`, `.pre-commit-config.yaml`.
- Validation: `scripts/validate.sh`, `.tflint.hcl`, `infra/backend.tf.example`.
- CI: `.github/workflows/ci-validate.yml`, `.github/workflows/security.yml`.
- Repo controls: `.github/CODEOWNERS` (placeholder), `.github/BRANCH_PROTECTION.md` guidance.
- README.md with CI badges and local CI instructions.

Where to find artifacts
- Onboarding files: [onboarding/](onboarding/)
- Docs: `DEV_ONBOARDING.md`, `CONTRIBUTING.md`
- CI workflows: `.github/workflows/`
- Validation scripts: `scripts/validate.sh` and `.pre-commit-config.yaml`

Quick verification commands

```bash
# Install and run pre-commit
pip3 install --user pre-commit
pre-commit install
pre-commit run --all-files

# Run repository validation
./scripts/validate.sh
```

Next admin actions (recommended)
- Add `SNYK_TOKEN` to repository Secrets to enable full scheduled security scans.
- Replace placeholders in `.github/CODEOWNERS` with actual GitHub usernames or teams.
- Enable branch protection for `main` using `.github/BRANCH_PROTECTION.md` recommendations:
  - Require PR reviews and passing status checks (`CI Validate`).
  - Enforce code owner approvals.
- Optionally configure automated evidence collection integrated with `GCP-landing-zone` automation.

Contacts and support
- Platform engineering: platform-engineering@company.com
- For policy details: `GCP-landing-zone/README.md`

Done by: Onboarding automation (see commit history)
