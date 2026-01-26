# Developer Onboarding — code-server

This document explains how to get a local developer environment ready and the compliance checks required by the GCP Landing Zone.

Requirements extracted from `GCP-landing-zone`:
- FedRAMP / NIST controls enforced via OPA policies
- Do not store secrets in the repo; use Secret Manager or GitHub Secrets
- Terraform remote state in GCS with CMEK and locking
- VPC Service Controls awareness for networking-dependent tests
- Pre-commit hooks and CI gates (format, lint, security)
- Snyk/Static scans in CI; evidence collection automated

Quick start

1. Clone this repo (already done in workspace):

   git clone https://github.com/kushin77/code-server.git

2. Run local setup script:

```bash
chmod +x ./setup-dev.sh
./setup-dev.sh
```

3. Authenticate to Google Cloud (if you will run cloud commands):

```bash
gcloud auth login
gcloud auth application-default login
```

4. Run pre-commit checks locally:

```bash
pre-commit install
pre-commit run --all-files
```

5. Validate repo-supplied checks (if present):

```bash
./scripts/validate.sh || true
```

Developer obligations
- Always run `pre-commit` before pushing.
- Ensure PRs pass CI (`ci-validate.yml` and `security.yml`).
- Do not check in credentials or Terraform state files.
- Use provided Dockerfile if you need a reproducible containerized dev environment.

Where to get help
- See `GCP-landing-zone/README.md` for platform-specific policy details.
- Open a local issue in `.github/ISSUES` to track onboarding tasks and blockers.

Repo controls and protections

- This repository includes a `.github/CODEOWNERS` placeholder; owners should be replaced with the correct GitHub usernames or team handles.
- Follow the branch protection guidance in `.github/BRANCH_PROTECTION.md` — require `CI Validate` status checks and code owner reviews for `main`.


GCP tflint guidance

- We added a minimal `.tflint.hcl` to this repo. For GCP-specific rules, install `tflint` with the `google` plugin and enable recommended rules:

```bash
# install tflint
curl -sSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
tflint --init
```

## Confirmed onboarding steps I ran

I verified the minimal developer onboarding flow and captured exact commands and outcomes so contributors can reproduce locally.

- Created a Python virtual environment and installed tooling:

```bash
cd /home/akushnir/code-server/code-server
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install pre-commit
```

- Installed and enabled `pre-commit` hooks (hooks installed at `.git/hooks/pre-commit`).

- Ran repository validation script (`scripts/validate.sh`) which runs `pre-commit` and optional terraform checks. Validation output: "Validation completed successfully" (no terraform files found in this repo).

- Tests: There are no repository test suites in `code-server` root; validation and pre-commit are the primary local checks.

Reproduce locally (copy/paste):

```bash
git clone https://github.com/kushin77/code-server.git
cd code-server
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install pre-commit
pre-commit install
bash scripts/validate.sh
```

Notes and recommendations (best practices):

- Use a virtualenv for Python tooling; avoid `pip --user` in venvs (the `setup-dev.sh` uses `pip3 install --user pre-commit` — this repo's onboarding should prefer installing into the venv).
- Keep the `setup-dev.sh` simple (it already checks for `python3`, `pip3`, installs `pre-commit`, and installs hooks). I updated this document rather than editing the script to avoid changing behavior without review.
- Consider adding a CI job that runs `bash scripts/validate.sh` and fails PRs on validation errors. There is an active PR for CI verification: https://github.com/kushin77/code-server/pull/16

If you'd like, I can open a PR with these doc updates, or push them to an existing branch and create a PR for review.


- Example: enable plugin and rules in `.tflint.hcl`:

```
plugin "google" {}
rule "google_compute_instance_no_external_ip" {
   enabled = true
}
```
