#!/bin/bash

# Close Duplicate GitHub Issues Script
# Purpose: Close 7 duplicate issues marked as duplicates of canonical issues
# Requires: GitHub CLI (gh) with admin rights to kushin77/code-server
# Status: Production-ready
# Date: April 16, 2026

set -e

REPO="kushin77/code-server"

echo "=========================================="
echo "GitHub Issue Closure Script"
echo "=========================================="
echo ""
echo "Repository: $REPO"
echo "Requires: GitHub CLI (gh) with admin rights"
echo ""

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI (gh) is not installed"
    echo "Install from: https://cli.github.com"
    exit 1
fi

# Check authentication
echo "Checking GitHub authentication..."
if ! gh auth status &> /dev/null; then
    echo "ERROR: Not authenticated with GitHub"
    echo "Run: gh auth login"
    exit 1
fi

echo "✅ GitHub CLI authenticated"
echo ""

# Define duplicate issues to close
declare -A DUPLICATES=(
    ["386"]="385"
    ["389"]="385"
    ["391"]="385"
    ["392"]="385"
    ["395"]="377"
    ["396"]="377"
    ["397"]="377"
)

CLOSED=0
FAILED=0

for issue in "${!DUPLICATES[@]}"; do
    canonical="${DUPLICATES[$issue]}"
    
    echo "Closing #$issue as duplicate of #$canonical..."
    
    if gh issue close $issue --repo $REPO --reason "duplicate" 2>&1; then
        # Add comment to closed issue linking to canonical
        gh issue comment $issue \
            --repo $REPO \
            --body "Closed as duplicate of #$canonical. See that issue for the consolidated implementation." \
            2>&1 || true
        
        echo "✅ Closed #$issue"
        ((CLOSED++))
    else
        echo "❌ Failed to close #$issue (may require admin rights)"
        ((FAILED++))
    fi
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Closed: $CLOSED"
echo "Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✅ All issues closed successfully!"
    exit 0
else
    echo "⚠️  Some issues could not be closed"
    echo "Ensure you have admin rights to the repository"
    exit 1
fi
