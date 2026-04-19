#!/bin/bash
# @file        scripts/priority-enforcer.sh
# @module      operations
# @description priority enforcer — on-prem code-server
# @owner       platform
# @status      active
# Priority Issue Enforcement Hook
# MANDATORY: Forces all issue selection through priority system
# Blocks random/unstructured issue selection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO="${1:-kushin77/eiq-linkedin}"

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "❌ ERROR: GITHUB_TOKEN environment variable not set"
  exit 1
fi

get_p0_issues() {
  # Get all OPEN P0 issues (critical/blocking)
  curl -s "https://api.github.com/repos/$REPO/issues?state=open&labels=P0&per_page=100" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" | \
    jq -r '.[] | "#\(.number) [\(.state | ascii_upcase)]: \(.title)"' 2>/dev/null || echo ""
}

get_p1_issues() {
  # Get all OPEN P1 issues (high priority)
  curl -s "https://api.github.com/repos/$REPO/issues?state=open&labels=P1&per_page=100" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" | \
    jq -r '.[] | "#\(.number) [\(.state | ascii_upcase)]: \(.title)"' 2>/dev/null || echo ""
}

get_p2_issues() {
  # Get all OPEN P2 issues
  curl -s "https://api.github.com/repos/$REPO/issues?state=open&labels=P2&per_page=100" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" | \
    jq -r '.[] | "#\(.number) [\(.state | ascii_upcase)]: \(.title)"' 2>/dev/null || echo ""
}

get_p3_issues() {
  # Get all OPEN P3 issues
  curl -s "https://api.github.com/repos/$REPO/issues?state=open&labels=P3&per_page=100" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" | \
    jq -r '.[] | "#\(.number) [\(.state | ascii_upcase)]: \(.title)"' 2>/dev/null || echo ""
}

get_unprioritized_issues() {
  # Get issues WITHOUT any priority label (should be labeled!)
  curl -s "https://api.github.com/repos/$REPO/issues?state=open&per_page=100" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" | \
    jq -r '.[] | select((.labels | map(.name) | index("P0", "P1", "P2", "P3") | . == null)) | "#\(.number): \(.title)"' 2>/dev/null || echo ""
}

# Main prioritized issue list
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         🟥 PRIORITY-ORDERED ISSUE LIST (MANDATORY)            ║"
echo "║                                                                ║"
echo "║ RULE: ALWAYS work on HIGHEST priority first                  ║"
echo "║ NO RANDOM SELECTION ALLOWED                                   ║"
echo "║ NO SKIPPING PRIORITIES (except if empty)                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"

echo ""
echo "🔴 CRITICAL (P0) - DO THESE FIRST:"
p0_count=$(get_p0_issues | wc -l)
if [[ $p0_count -gt 0 ]]; then
  get_p0_issues | nl
  echo "   ⚠️  $p0_count critical issues blocking team!"
else
  echo "   ✅ No P0 issues"
fi

echo ""
echo "🟠 HIGH (P1) - DO THESE SECOND:"
p1_count=$(get_p1_issues | wc -l)
if [[ $p1_count -gt 0 ]]; then
  get_p1_issues | nl
  echo "   ⚠️  $p1_count high-priority issues pending"
else
  echo "   ✅ No P1 issues"
fi

echo ""
echo "🟡 MEDIUM (P2) - DO THESE THIRD:"
p2_count=$(get_p2_issues | wc -l)
if [[ $p2_count -gt 0 ]]; then
  get_p2_issues | nl
  echo "   📋 $p2_count medium-priority issues"
else
  echo "   ✅ No P2 issues"
fi

echo ""
echo "🟢 LOW (P3) - DO THESE LAST:"
p3_count=$(get_p3_issues | wc -l)
if [[ $p3_count -gt 0 ]]; then
  get_p3_issues | nl
  echo "   💡 $p3_count low-priority items"
else
  echo "   ✅ No P3 issues"
fi

echo ""
echo "⚠️  UNPRIORITIZED (MUST LABEL):"
unprioritized=$(get_unprioritized_issues)
if [[ -n "$unprioritized" ]]; then
  echo "$unprioritized" | nl
  echo ""
  echo "   ❌ THESE ISSUES MUST BE PRIORITIZED!"
  echo "   Use: ./scripts/priority-issue-cli.sh prioritize <issue-number> P1"
else
  echo "   ✅ All issues properly labeled"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "ENFORCEMENT RULE: You MUST work on P0 first, then P1, then P2"
echo "NO EXCEPTIONS. NO RANDOM SELECTION."
echo "════════════════════════════════════════════════════════════════"

# Return highest priority P0 issue number
highest_priority=$(get_p0_issues | head -1 | grep -o '^#[0-9]*' | tr -d '#')
if [[ -z "$highest_priority" ]]; then
  highest_priority=$(get_p1_issues | head -1 | grep -o '^#[0-9]*' | tr -d '#')
fi
if [[ -z "$highest_priority" ]]; then
  highest_priority=$(get_p2_issues | head -1 | grep -o '^#[0-9]*' | tr -d '#')
fi

if [[ -n "$highest_priority" ]]; then
  echo ""
  echo "✅ NEXT ISSUE TO WORK ON: #$highest_priority"
  echo "   Run: ./scripts/priority-issue-cli.sh show $highest_priority"
else
  echo ""
  echo "🎉 All prioritized issues complete!"
fi
