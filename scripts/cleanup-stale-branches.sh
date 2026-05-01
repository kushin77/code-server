#!/usr/bin/env bash
###############################################################################
# @file        scripts/cleanup-stale-branches.sh
# @module      cleanup-stale-branches
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/_common/init.sh"
###############################################################################
#
# Clean up stale merged branches
# Removes local and remote branches that were merged >N days ago
#
# Prerequisites:
#   - Requires write access to repository
#   - Must be in repository working directory
#
# Usage:
#   bash scripts/cleanup-stale-branches.sh [--days 30] [--dry-run]
#
# Examples:
#   # List branches that would be deleted (dry-run)
#   bash scripts/cleanup-stale-branches.sh --dry-run
#
#   # Delete branches merged >30 days ago
#   bash scripts/cleanup-stale-branches.sh --days 30
#
#   # Delete branches merged >60 days ago
#   bash scripts/cleanup-stale-branches.sh --days 60
#

set -euo pipefail

# Default values
DAYS_THRESHOLD=30
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --days)
      DAYS_THRESHOLD="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--days N] [--dry-run]"
      exit 1
      ;;
  esac
done

echo "🧹 Git Stale Branch Cleanup"
echo "   Threshold: ${DAYS_THRESHOLD} days"
echo "   Dry-run: ${DRY_RUN}"
echo ""

# Ensure we're on main/master branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
  echo "⚠️  Currently on branch: $CURRENT_BRANCH"
  echo "   Switching to main for safety..."
  git checkout main 2>/dev/null || git checkout master 2>/dev/null || {
    echo "❌ Could not find main or master branch"
    exit 1
  }
fi

# Fetch latest branches
echo "📡 Fetching branch information..."
git fetch origin --prune

# Calculate cutoff date
CUTOFF_DATE=$(date -d "$DAYS_THRESHOLD days ago" +%s 2>/dev/null || date -v-${DAYS_THRESHOLD}d +%s)

echo ""
echo "🔍 Scanning for merged branches older than $DAYS_THRESHOLD days..."
echo ""

# Local merged branches
echo "📦 LOCAL BRANCHES (merged into main):"
DELETED_LOCAL=0
while IFS= read -r branch; do
  if [[ -z "$branch" || "$branch" == "main" || "$branch" == "master" ]]; then
    continue
  fi
  
  # Get last commit date of branch
  COMMIT_DATE=$(git log -1 --format=%ct "$branch" 2>/dev/null || echo 0)
  
  if [[ $COMMIT_DATE -lt $CUTOFF_DATE ]]; then
    echo "   🗑️  $branch (merged: $(date -d @$COMMIT_DATE '+%Y-%m-%d' 2>/dev/null || echo "unknown"))"
    
    if [[ "$DRY_RUN" == "false" ]]; then
      git branch -d "$branch" 2>/dev/null || echo "      ⚠️  Could not delete (not fully merged)"
      DELETED_LOCAL+=1
    fi
  fi
done < <(git branch -r --merged | grep -E '^\s+origin/' | sed 's/^\s*origin\///g' | grep -v 'HEAD\|main\|master')

if [[ $DELETED_LOCAL -gt 0 ]]; then
  echo "   ✅ Deleted $DELETED_LOCAL local branches"
fi

echo ""
echo "🌐 REMOTE BRANCHES (merged into main):"
DELETED_REMOTE=0
while IFS= read -r branch; do
  if [[ -z "$branch" || "$branch" == "main" || "$branch" == "master" ]]; then
    continue
  fi
  
  # Get last commit date of remote branch
  COMMIT_DATE=$(git log -1 --format=%ct "origin/$branch" 2>/dev/null || echo 0)
  
  if [[ $COMMIT_DATE -lt $CUTOFF_DATE ]]; then
    echo "   🗑️  origin/$branch (merged: $(date -d @$COMMIT_DATE '+%Y-%m-%d' 2>/dev/null || echo "unknown"))"
    
    if [[ "$DRY_RUN" == "false" ]]; then
      git push origin --delete "$branch" 2>/dev/null || echo "      ⚠️  Could not delete remote branch"
      DELETED_REMOTE+=1
    fi
  fi
done < <(git branch -r --merged | grep -E '^\s+origin/' | sed 's/^\s*origin\///g' | grep -v 'HEAD\|main\|master')

if [[ $DELETED_REMOTE -gt 0 ]]; then
  echo "   ✅ Deleted $DELETED_REMOTE remote branches"
fi

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo "🔐 DRY RUN: No branches were actually deleted"
  echo "   Re-run without --dry-run to apply deletions"
else
  TOTAL=$((DELETED_LOCAL + DELETED_REMOTE))
  if [[ $TOTAL -gt 0 ]]; then
    echo "✅ Successfully cleaned up $TOTAL stale branches"
  else
    echo "✨ No stale branches found"
  fi
fi
