#!/usr/bin/env bash
###############################################################################
# @file        scripts/configure-branch-protection.sh
# @module      configure-branch-protection
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
#
# Configure GitHub branch protection rules for main branch
# This script sets up protection rules aligned with issue #1534 governance standards
#
# Prerequisites:
#   - GitHub CLI (gh) must be installed and authenticated
#   - Must have admin permissions on the repository
#
# Usage:
#   bash scripts/configure-branch-protection.sh <repo-owner> <repo-name> <main-branch>
#   Example: bash scripts/configure-branch-protection.sh kushin77 code-server main
#

set -euo pipefail

REPO_OWNER="${1:?Repository owner required (e.g., kushin77)}"
REPO_NAME="${2:?Repository name required (e.g., code-server)}"
BRANCH="${3:=main}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required but was not found on PATH"
  exit 1
fi

echo "Configuring branch protection for ${REPO_OWNER}/${REPO_NAME}:${BRANCH}..."

TMP_BODY=$(mktemp)
trap 'rm -f "$TMP_BODY"' EXIT

cat >"$TMP_BODY" <<'JSON'
{
  "enforce_admins": true,
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "No loose markdown files in root",
      "Conventional commit format",
      "Branch naming convention",
      "Shell script naming convention (kebab-case)",
      "Validate env.yaml schema",
      "Single Caddyfile source of truth",
      "Validate pnpm workspace configuration"
    ]
  },
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

gh api "repos/${REPO_OWNER}/${REPO_NAME}/branches/${BRANCH}/protection" \
  -X PUT \
  --input "$TMP_BODY" \
  > /dev/null

echo "✅ Branch protection configured for ${BRANCH}"
echo ""
echo "Settings applied:"
echo "  ✓ Enforce admins: Protect against admin force-push/delete"
echo "  ✓ Require status checks: governance checks must pass"
echo "  ✓ Require branches up to date: PR must be updated before merge"
echo "  ✓ Require code reviews: At least 1 review required"
echo "  ✓ Require code owner review: CODEOWNERS entries trigger reviews"
echo "  ✓ Dismiss stale reviews: Updates to PR dismiss prior approvals"
echo "  ✓ Allow force pushes: Disabled (maintain audit trail)"
echo "  ✓ Allow deletions: Disabled (prevent accidental branch deletion)"
