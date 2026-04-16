# GitHub Actions Approved Allowlist

This document defines approved third-party GitHub Actions and the update process for immutable pinning.

## Policy

- All external actions in `.github/workflows` must be pinned to full commit SHAs.
- Mutable refs are forbidden: `@v*`, `@main`, `@master`, `@HEAD`, `@latest`.
- Top-level `permissions` is required in every workflow.
- `permissions: write-all` is forbidden.

## Approved Actions

- `actions/checkout`
- `actions/setup-node`
- `actions/setup-python`
- `actions/cache`
- `docker/setup-buildx-action`
- `docker/login-action`
- `docker/metadata-action`
- `docker/build-push-action`
- `github/codeql-action/upload-sarif`
- `trufflesecurity/trufflehog`
- `aquasecurity/trivy-action`
- `returntocorp/semgrep-action`
- `snyk/actions/node`
- `EnricoMi/publish-unit-test-result-action`
- `codecov/codecov-action`
- `crate-ci/typos`

## Update Process

1. Resolve the target version to a commit SHA using GitHub API:
   - `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq '.object.sha'`
   - For branch-only actions, resolve commit directly and record rationale.
2. Open a dedicated PR with scope limited to action pin updates.
3. Include before/after refs in PR body.
4. Run `Workflow Lint` and security checks.
5. Merge only after checks pass (or approved emergency process).

## Emergency Exception Handling

- If a security fix requires temporary mutable refs, create an issue with severity and ETA.
- Exception must be removed in the next PR and linked back to the issue.

## Ownership

- Primary owner: Platform Engineering
- Canonical tracking issue: #310
