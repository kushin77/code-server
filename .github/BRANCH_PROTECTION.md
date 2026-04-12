# Branch protection recommendations

Recommended branch protection settings for `main` (set via repo Settings → Branches):

- Require pull request reviews before merging (1-2 reviewers).
- Require status checks to pass before merging:
  - `ci-validate` (workflow name: `CI Validate`)
  - `security.yml` (scheduled scans) — optional for PR gating
- Require signed commits (if your org enforces commit signing).
- Include `CODEOWNERS` enforcement to require approvals from code owners.
- Enable `Require linear history` if desired.
- Restrict who can push to `main` to maintainers only.

To configure via the API or automation, see GitHub REST API `repos/branches/protection`.

Example required status checks (names used in GitHub UI):
- `ci-validate` (runs on PRs)
