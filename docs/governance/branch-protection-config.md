# GitHub Branch Protection Configuration

## Overview

This document specifies the branch protection rules for the `main` branch as part of issue #1534 Repository Governance epic.

## Main Branch Protection Rules

### Rule 1: Enforce Admins
- **Status**: Enabled
- **Purpose**: Prevent repository administrators from bypassing protection rules via force-push or direct deletion
- **Impact**: Even admins must go through normal PR review process
- **Rationale**: Maintains audit trail and ensures all changes follow governance standards

### Rule 2: Require Status Checks
- **Status**: Enabled
- **Required Checks**:
  - `lint`: Code quality and style validation
  - `test`: Unit and integration tests passing
  - `build`: Successful artifact build
- **Update Before Merge**: Yes (PR must be up-to-date with base branch before merge)
- **Purpose**: Ensure only tested, passing code reaches production
- **Rationale**: Prevents regressions and maintains code quality baseline

### Rule 3: Require Code Reviews
- **Status**: Enabled
- **Required Reviews**: 1
- **Require Code Owner Reviews**: Yes
- **Dismiss Stale Reviews**: Yes
- **Purpose**: At least one independent review + CODEOWNERS approval
- **Rationale**: 
  - Catches logic errors and security issues
  - CODEOWNERS ensures domain experts review changes to their area
  - Stale review dismissal ensures reviewers re-check after updates

### Rule 4: Disable Force Pushes
- **Status**: Disabled (force-push not allowed)
- **Purpose**: Maintain clean git history and audit trail
- **Rationale**: All commits must be atomic, traceable, and reversible

### Rule 5: Disable Branch Deletion
- **Status**: Disabled (deletion not allowed)
- **Purpose**: Prevent accidental loss of work
- **Rationale**: Ensures release branches and feature branches remain recoverable

## Configuration Methods

### Method 1: GitHub CLI

```bash
# Configure using script
bash scripts/configure-branch-protection.sh kushin77 code-server main
```

### Method 2: GitHub Web UI

1. Go to Repository Settings → Branches
2. Click "Edit" on main branch protection rule
3. Enable the following:
   - ✓ Require status checks to pass before merging
   - ✓ Require branches to be up to date before merging
   - ✓ Require a pull request before merging
   - ✓ Require code reviews before merging (1 approval)
   - ✓ Require code owner reviews
   - ✓ Dismiss stale pull request approvals when new commits are pushed
   - ✓ Restrict who can push to matching branches
   - ✓ Restrict who can push to matching branches → Include administrators

### Method 3: GitHub API

```bash
# Using curl + GitHub API
curl -X PUT "https://api.github.com/repos/kushin77/code-server/branches/main/protection" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -d '{
    "enforce_admins": true,
    "required_status_checks": {
      "strict": true,
      "contexts": ["lint", "test", "build"]
    },
    "required_pull_request_reviews": {
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": true,
      "required_approving_review_count": 1
    },
    "allow_force_pushes": false,
    "allow_deletions": false,
    "block_creations": false,
    "required_linear_history": false,
    "restrictions": null
  }'
```

## Implementation Status

| Rule | Status | Script | Manual | API |
|------|--------|--------|--------|-----|
| Enforce admins | 📋 Pending | ✓ configure-branch-protection.sh | ✓ Web UI | ✓ API endpoint |
| Require status checks | 📋 Pending | ✓ configure-branch-protection.sh | ✓ Web UI | ✓ API endpoint |
| Require PR reviews | 📋 Pending | ✓ configure-branch-protection.sh | ✓ Web UI | ✓ API endpoint |
| CODEOWNERS enforcement | ✅ Active | N/A | N/A | Auto (via .github/CODEOWNERS) |
| Dismiss stale reviews | 📋 Pending | ✓ configure-branch-protection.sh | ✓ Web UI | ✓ API endpoint |
| Disable force-push | 📋 Pending | ✓ configure-branch-protection.sh | ✓ Web UI | ✓ API endpoint |
| Disable deletion | 📋 Pending | ✓ configure-branch-protection.sh | ✓ Web UI | ✓ API endpoint |

## Verification

After applying rules, verify with:

```bash
# Check current branch protection status
gh repo rule view --repository=kushin77/code-server --branch=main

# Or via API
curl -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/kushin77/code-server/branches/main/protection"
```

## Related Issues

- **Issue #1534**: Repository Governance epic
- **Phase 1**: ✅ Documentation standards, governance framework
- **Phase 2**: ✅ pnpm workspace, CODEOWNERS
- **Phase 3**: 📋 Branch protection rules (this document)
- **Phase 4**: 📋 Enforce CI checks for naming conventions, hardcoded IPs, duplicates
