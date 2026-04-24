# Issue-Centric Workflow Policy

**Version:** 1.0.0  
**Date:** 2026-04-18  
**Enforced by:** `.github/workflows/enforce-branch-naming.yml`  

---

## The Workflow

```
1. Pick a GitHub Issue
         ↓
2. Create branch: feat/<issue>-<slug>
   (use: bash scripts/dev/start-work-from-issue.sh <N>)
         ↓
3. Commit: "feat: description  Fixes #<issue>"
         ↓
4. Open PR with body containing "Fixes #<issue>"
         ↓
5. CI validates branch name + issue linkage
         ↓
6. Merge → issue auto-closed by GitHub
```

---

## Branch Naming Convention

Format: `<type>/<issue-number>-<kebab-slug>`

| Type | Usage |
|------|-------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `chore` | Maintenance, deps, tooling |
| `docs` | Documentation only |
| `refactor` | Code restructure, no behavior change |
| `ci` | CI/CD pipeline changes |

**Examples:**
- `feat/624-issue-centric-workflow`
- `fix/621-hadolint-warnings`
- `chore/580-ci-baseline-remediation`

---

## Commit Message Convention

```
<type>(<scope>): <description>

<optional body>

Fixes #<issue-number>
```

Example:
```
fix(ci): clear hadolint warning-failures in active Dockerfiles

- Pin npm package versions in Dockerfile.code-server
- Add SHELL pipefail directive before piped RUN
- Add hadolint ignore with justification for apt pin warnings

Fixes #621
```

---

## Enforcement

The CI workflow `.github/workflows/enforce-branch-naming.yml` enforces:
1. **Branch name** matches `<type>/<issue>-<slug>` pattern
2. **PR body** contains `Fixes #N`, `Closes #N`, or `Resolves #N`

Both checks must pass before merge.

---

## Helper Tools

```bash
# Create a correctly named branch from issue number
bash scripts/dev/start-work-from-issue.sh <issue-number> [type]

# Or use VS Code task:
# Ctrl+Shift+P → Tasks: Run Task → Start Work From Issue
```

---

## Related Issues
- #624 — Issue-centric IDE defaults
