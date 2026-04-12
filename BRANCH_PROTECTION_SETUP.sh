#!/bin/bash
# Branch Protection Setup Script for kushin77/code-server
# This script configures the main branch with enterprise-grade protection rules
# REQUIRES: GitHub CLI (gh) installed and authenticated
# RUN: bash BRANCH_PROTECTION_SETUP.sh

set -euo pipefail

REPO="kushin77/code-server"
BRANCH="main"

echo "🔐 Branch Protection Configuration - kushin77/code-server"
echo "================================================================"

# Check GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is required but not installed"
    echo "   Install: https://cli.github.com"
    exit 1
fi

# Verify authentication
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub CLI"
    echo "   Run: gh auth login"
    exit 1
fi

# Verify repository access
echo "✓ Verifying repository access..."
gh repo view $REPO > /dev/null || {
    echo "❌ Cannot access repository $REPO"
    exit 1
}

echo "✓ Repository verified: $REPO"
echo ""

# Configure branch protection rule via GitHub API
echo "📋 Configuring branch protection for '$BRANCH' branch..."
echo ""

# Build the API request payload
PAYLOAD=$(cat <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "ci-validate",
      "security/dependency-check",
      "security/secret-scan"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": true,
    "required_approving_review_count": 2
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "auto_delete_branch_on_merge": true,
  "require_signed_commits": true
}
EOF
)

echo "📡 Sending configuration to GitHub API..."
echo "   - Require 2 code owner approvals"
echo "   - Enforce signed commits"
echo "   - Block force pushes and deletions"
echo "   - Require linear history"
echo "   - Status checks: ci-validate, security/dependency-check, security/secret-scan"
echo ""

# Apply via GitHub API REST endpoint
RESPONSE=$(gh api \
  --method PUT \
  "/repos/$REPO/branches/$BRANCH/protection" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d "$PAYLOAD" 2>&1) || {
    echo "❌ Failed to configure branch protection"
    echo "   Response: $RESPONSE"
    echo ""
    echo "   This may happen if:"
    echo "   - CI workflow checks don't exist yet (can add later)"
    echo "   - Account permissions insufficient"
    echo ""
    echo "   Manual setup: GitHub Settings → Branches → main → Edit protection rule"
    exit 1
}

echo "✅ Branch protection configured successfully!"
echo ""
echo "📊 Active Protection Rules:"
echo "   ✓ Require 2 approvals (code owners only)"
echo "   ✓ Require signed commits"
echo "   ✓ Enforce linear history"
echo "   ✓ Block force pushes and deletions"
echo "   ✓ Status checks required (ci-validate, security/*)"
echo "   ✓ Auto-delete head branches on merge"
echo ""
echo "🎯 Next Steps:"
echo "   1. Set up CI workflow in .github/workflows/ (optional)"
echo "   2. Announce enforcement to team (see Issue #75)"
echo "   3. Configure GPG signing for local development:"
echo "      - gpg --full-generate-key"
echo "      - git config --global user.signingkey <KEY_ID>"
echo "      - git config --global commit.gpgsign true"
echo ""
echo "📖 Reference: .github/BRANCH_PROTECTION.md"
echo "================================================================"
