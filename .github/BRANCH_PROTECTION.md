# Branch Protection Rules — Enforcement Backbone

This document specifies **non-negotiable** branch protection settings for the repository.

Branch protection rules are not "nice to have" — they are the backbone of our quality and security enforcement. They prevent human error and ensure every change meets our standards.

---

## Main Branch Protection Policy

Settings: **Settings → Branches → main → Branch protection rules**

### ✅ Require Pull Request Reviews Before Merging
- **Required approvals**: 2
- **Require review from code owners**: ✅ YES
- **Dismiss stale pull request approvals when new commits are pushed**: ✅ YES
- **Require approval of the most recent reviewable push**: ✅ YES

**Rationale**: Two eyes on every change. Code owners ensure architectural/security alignment. Stale approvals rejected if code changes.

---

### ✅ Require Status Checks to Pass Before Merging

All of the following **must pass**:

#### CI/Quality Gates
- `ci-validate` (lint, format, unit tests)
- Coverage threshold enforced (minimum 80%)
- Any linting errors block merge

#### Security Gates
- `security/dependency-check` (CVE detection)
- `security/secret-scan` (hardcoded credentials)
- `security/sast` (static analysis)
- `security/container-scan` (Docker image vulnerabilities — if applicable)

#### Infrastructure Gates (if `.tf` files changed)
- `terraform-validate` (Terraform syntax)
- `terraform-policy` (OPA/Conftest security policies)

**Rationale**: Automated gates catch issues before human review. No exceptions for "we'll fix it later."

---

### ✅ Require Branches to Be Up to Date Before Merging
- **Require branches to be up to date**: ✅ YES

**Rationale**: Prevent integration issues. All PRs must re-validate against latest main before merge.

---

### ✅ Require Code Owner Reviews Before Merging
- **Include administrators**: ✅ YES

**Rationale**: No self-approvals, even for admins. Architecture and security experts review critical paths.

---

### ✅ Require Signed Commits
- **Require signed commits**: ✅ YES (Elite Tier)

**Rationale**: Cryptographic proof of authorship. Non-repudiable audit trail.

**Setup**:
```bash
# Generate GPG key (one-time)
gpg --full-generate-key

# Configure Gi
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true

# Sign on commi
git commit -S -m "Your message"


---

### ✅ Restrict Direct Pushes
- **Allow force pushes**: ❌ NO
- **Allow deletions**: ❌ NO
- **Restrict who can push to matching branches**: ✅ YES (Maintainers only)

**Rationale**: Prevent accidental force-push or deletion. All changes must go through PR process.

---

### ✅ Enable Linear History (Optional but Recommended)
- **Require linear history**: ✅ YES (for production repos)

**Rationale**: Clean Git history, easier bisecting for bugs, easier rebasing.

**Workflow**: Use GitHub "Rebase and merge" only (not "Squash and merge" or "Create merge commit").

---

### ✅ Automatic Deletion of Head Branches
- **Automatically delete head branches**: ✅ YES

**Rationale**: Prevent branch proliferation. Branches auto-deleted after merge.

---

## Enforcement Checklis

Before considering branch protection "configured":

- [ ] 2 approvals required (1 code owner)
- [ ] All CI checks passing (lint, test, coverage)
- [ ] All security checks passing (dependency, secret, SAST)
- [ ] All IaC checks passing (if Terraform files)
- [ ] Require up-to-date branches
- [ ] Code owner reviews enabled
- [ ] Require signed commits
- [ ] Force pushes disabled
- [ ] Deletions disabled
- [ ] Linear history enforced
- [ ] Auto-delete branches enabled

---

## How to Configure (GitHub UI)

1. **Settings → Branches**
2. **Click "Add rule"**
3. **Branch name pattern**: `main
4. **Check all boxes** as specified above
5. **Save changes**

**Verify**: Try pushing directly to main — should be blocked.

---

## How to Configure (GitHub REST API)

```bash
curl -X PUT \
  -H "Authorization: token YOUR_GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/kushin77/code-server/branches/main/protection \
  -d '{
    "required_status_checks": {
      "strict": true,
      "contexts": ["ci-validate", "security/dependency-check", "security/secret-scan", "security/sast"]
    },
    "required_pull_request_reviews": {
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": true,
      "required_approving_review_count": 2
    },
    "enforce_admins": true,
    "require_linear_history": true,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "require_signed_commits": true,
    "required_conversation_resolution": true
  }'


---

## Exception Process

**Rule: No exceptions without documented justification.**

If a change **must** bypass branch protection:

1. **Create a GitHub issue** explaining why
2. **Post in Slack** (#engineering-review)
3. **Get principal engineer approval** (@kushin77)
4. **Document the exception** in issue (audit trail)
5. **Temporarily dismiss rule** (GitHub UI)
6. **Merge PR**
7. **Re-enable rule immediately**
8. **Post-mortem**: Execute post-merge to prevent recurrence

**Note**: If you're using exceptions regularly, you have a process problem. Fix the process, not the rule.

---

## Testing Your Setup

After configuring branch protection:

```bash
# Try to push directly to main (should fail)
git checkout main
git commit --allow-empty -m "Test commit"
git push origin main
# Expected: ❌ "protected branch" error

# Try to merge PR without approvals (should fail)
# Try to merge PR with failing tests (should fail)
# Try to delete main branch (should fail)


All should be blocked. If not, configuration incomplete.

---

## Troubleshooting

### "Push rejected" on PR merge
- Check: Are required reviews approved?
- Check: Are all status checks passing?
- Check: Is branch up-to-date with main?

### "Status check X is failing"
- Check: CI/CD logs in PR
- Fix the failing check locally
- Push to PR branch
- Re-run check (usually automatic)

### "I need to force-push to fix Git history"
- Don't. Open a new PR instead.
- Exception: Only admins, and only with documented approval.

### "Rule is too strict"
- Don't disable rule. Improve process instead.
- Root cause: Why is passing CI hard?
- Fix: Add better tooling, documentation, or training.

---

## References

- [GitHub Branch Protection Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule)
- [GitHub Signed Commits](https://docs.github.com/en/authentication/managing-commit-signature-verification)
- [CONTRIBUTING.md](../CONTRIBUTING.md) — Full contributing guidelines
- [CODEOWNERS](CODEOWNERS) — Code ownership rules
