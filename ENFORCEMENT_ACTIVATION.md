# ENFORCEMENT ACTIVATION GUIDE

## Quick Start (5 minutes)

### Step 1: Run Branch Protection Setup

**On Linux/macOS:**
```bash
chmod +x BRANCH_PROTECTION_SETUP.sh
./BRANCH_PROTECTION_SETUP.sh


**On Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File BRANCH_PROTECTION_SETUP.ps1 -Confirm


### Step 2: Verify Configuration

Visit: https://github.com/kushin77/code-server/settings/branches

Confirm these settings are **enabled**:
- ✅ Require a pull request before merging
  - ✅ Require 2 approvals
  - ✅ Require review from code owners
  - ✅ Require approval of most recent push
  - ✅ Dismiss stale reviews
- ✅ Require status checks to pass
  - ✅ Require branches to be up to date
- ✅ Require signed commits
- ✅ Require linear history
- ✅ Restrict who can push to matching branches (Maintainers)
- ✅ Allow force pushes: OFF
- ✅ Allow deletions: OFF
- ✅ Auto-delete head branches: ON

### Step 3: Configure GPG Signing (Team-wide)

Each developer must set up GPG signing to comply with the "require signed commits" rule.

**First-time setup (one-time per developer):**

```bash
# Generate a new GPG key (keep the passphrase secure)
gpg --full-generate-key

# List your keys and note the KEY_ID (40-character hex string)
gpg --list-secret-keys --keyid-format=long

# Configure Git to sign all commits
git config --global user.signingkey <YOUR_KEY_ID>
git config --global commit.gpgsign true

# Verify configuration
git config --global --list | grep -E "(signingkey|gpgsign)"


**For each commit (automatic after setup):**
```bash
# Just commit normally - Git will automatically sign
git commit -m "Your commit message"  # Will prompt for GPG passphrase if needed


**GitHub Integration:**
- Add your GPG public key to GitHub: https://github.com/settings/keys
  ```bash
  gpg --armor --export YOUR_KEY_ID | pbcopy  # macOS
  gpg --armor --export YOUR_KEY_ID | xclip   # Linux


---

## Verification Checklis

**For Individual Developers:**

- [ ] Local GPG signing configured
- [ ] GitHub GPG public key added
- [ ] Test: Create a test branch and submit PR
  - [ ] Verify PR requires 2 approvals
  - [ ] Verify commit shows as "verified" with green checkmark
  - [ ] Confirm I cannot merge my own PR (even as owner)

**For Team Leads:**

- [ ] All team members have branch protection rules active
- [ ] Issue #75 enforcement timeline started
- [ ] Team announcement sent (template: Issue #75)
- [ ] CI/CD workflows configured (if using status checks)
  - [ ] `ci-validate` status check
  - [ ] `security/dependency-check` status check
  - [ ] `security/secret-scan` status check

---

## Enforcement Timeline

**Today (Immediate):**
- [ ] Branch protection activated via BRANCH_PROTECTION_SETUP.sh
- [ ] Team notified of changes
- [ ] Grace period begins (see below)

**This Week:**
- [ ] All developers configure GPG signing
- [ ] PR template validation begins
- [ ] First PRs pass through new process

**April 20 (2 weeks):**
- [ ] Full enforcemen
  - All PRs require 2 approvals
  - All commits must be signed
  - No force pushes or deletions allowed
  - Stale approvals automatically rejected

---

## Grace Period & Enforcement Phases

### Phase 0: Announce & Configure (Days 1-3)
- PR templates in effec
- Branch protection active
- Signed commit requirement: **OPTIONAL** (warning in PR template)

### Phase 1: Signing Enforcement (Days 4-10)
- All commits must be signed
- PRs blocked if not signed
- 2-approvals enforced by automation

### Phase 2: Full Enforcement (Days 11+)
- All CONTRIBUTING.md standards active
- All branch protection rules active
- All architectural decisions must follow ADR process
- All deployments measured against SLOs

---

## Troubleshooting

### Issue: "Commit is not signed"

**Cause:** Commit was created before GPG signing was configured.

**Fix:**
```bash
# Amend the last commit with GPG signature
git commit --amend -S

# Force push (only on feature branches!)
git push --force origin <branch-name>


### Issue: "GPG command not found"

**Fix:**
- Install GPG: https://www.gnupg.org/download/
- Verify installation: `gpg --version

### Issue: "Passphrase prompt stuck in terminal"

**Fix (macOS):**
```bash
# Use pinentry-mac for GUI passphrase entry
brew install pinentry-mac
echo "pinentry-program /usr/local/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agen


**Fix (Linux, Debian/Ubuntu):**
```bash
apt-get install pinentry-gnome3
echo "pinentry-program /usr/bin/pinentry-gnome3" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agen


### Issue: "2-approval requirement too strict"

**Context:** Branch protection requires 2 reviewers. If your team is small:

**Option 1 - Maintain requirement** (Recommended for security)
- Keep 2-approval requiremen
- Second approval can be self-review if code is trivial
- Focus on architectural/security reviews

**Option 2 - Adjust to 1 approval**
```bash
# Edit BRANCH_PROTECTION_SETUP.ps1 or BRANCH_PROTECTION_SETUP.sh
# Change: "required_approving_review_count": 2
# To:     "required_approving_review_count": 1
# Re-run setup scrip


---

## Reference Documentation

- **Full enforcement policy:** [CONTRIBUTING.md](../CONTRIBUTING.md)
- **Branch protection details:** [.github/BRANCH_PROTECTION.md](../.github/BRANCH_PROTECTION.md)
- **PR template:** [.github/pull_request_template.md](../.github/pull_request_template.md)
- **Code ownership:** [.github/CODEOWNERS](../.github/CODEOWNERS)
- **Architecture decisions:** [docs/adr/README.md](../docs/adr/README.md)
- **Service level objectives:** [docs/slos/README.md](../docs/slos/README.md)
- **Enforcement roadmap:** [GitHub Issue #75](https://github.com/kushin77/code-server/issues/75)

---

## Suppor

**Questions?** Comment on [Issue #75](https://github.com/kushin77/code-server/issues/75)

**CI/CD Help:** See [CONTRIBUTING.md - CI/CD Pipeline](../CONTRIBUTING.md#cicd-pipeline)

**GPG Issues:** See [GitHub GPG Help](https://docs.github.com/en/authentication/managing-commit-signature-verification)

---

**Enforcement System Status:** ✅ **ACTIVE**

All code contributions must now pass the enterprise engineering gate.

Last updated: 2026-01-27
