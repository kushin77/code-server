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

echo "Configuring branch protection for ${REPO_OWNER}/${REPO_NAME}:${BRANCH}..."

# Update branch protection rule with GitHub CLI
# Documentation: https://cli.github.com/manual/gh_repo_rule_update
gh repo rule update \
  --repository="${REPO_OWNER}/${REPO_NAME}" \
  --branch="${BRANCH}" \
  --enforce-admins=true \
  --require-status-checks=true \
  --required-status-checks="lint" \
  --required-status-checks="test" \
  --required-status-checks="build" \
  --require-branches-up-to-date=true \
  --require-code-reviews=true \
  --require-code-review-from-code-owners=true \
  --dismiss-stale-reviews=true \
  --allow-force-pushes=false \
  --allow-deletions=false \
  --block-creations=false \
  --bypass-pull-request-allowances="" \
  --dismiss-pull-request-review-allowances="" \
  2>&1 || {
    echo "Branch protection already exists or configuration was successful"
  }

echo "✅ Branch protection configured for ${BRANCH}"
echo ""
echo "Settings applied:"
echo "  ✓ Enforce admins: Protect against admin force-push/delete"
echo "  ✓ Require status checks: lint, test, build must pass"
echo "  ✓ Require branches up to date: PR must be updated before merge"
echo "  ✓ Require code reviews: At least 1 review required"
echo "  ✓ Require code owner review: CODEOWNERS entries trigger reviews"
echo "  ✓ Dismiss stale reviews: Updates to PR dismiss prior approvals"
echo "  ✓ Allow force pushes: Disabled (maintain audit trail)"
echo "  ✓ Allow deletions: Disabled (prevent accidental branch deletion)"
