#!/usr/bin/env bash
# @file        scripts/dev/start-work-from-issue.sh
# @module      dev/workflow
# @description Create a correctly named branch from a GitHub issue number

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" 2>/dev/null || true

ISSUE_NUMBER="${1:-}"
TYPE="${2:-feat}"

if [[ -z "$ISSUE_NUMBER" ]]; then
  echo "Usage: $0 <issue-number> [type: feat|fix|chore|docs|refactor|ci]"
  exit 1
fi

ALLOWED_TYPES="feat|fix|chore|docs|refactor|ci"
if ! echo "$TYPE" | grep -qE "^($ALLOWED_TYPES)$"; then
  echo "ERROR: type must be one of: $ALLOWED_TYPES"
  exit 1
fi

# Fetch issue title from GitHub API
GH_REPO_TARGET=$(git remote get-url origin | sed 's|.*github.com[:/]\(.*\)\.git|\1|' | sed 's|.*github.com[:/]\(.*\)|\1|')
TITLE=$(curl -fsSL "https://api.github.com/repos/${GH_REPO_TARGET}/issues/${ISSUE_NUMBER}" \
  -H "Authorization: token ${GITHUB_TOKEN:-}" 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])" 2>/dev/null \
  || echo "issue-${ISSUE_NUMBER}")

# Generate slug: lowercase, replace non-alphanum with -, trim
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g' | cut -c1-40)

BRANCH="${TYPE}/${ISSUE_NUMBER}-${SLUG}"

echo "Creating branch: $BRANCH"
git checkout -b "$BRANCH"
echo "Branch created. Start coding, then:"
echo "  git commit -m '${TYPE}: description  Fixes #${ISSUE_NUMBER}'"
echo "  git push -u origin $BRANCH"
