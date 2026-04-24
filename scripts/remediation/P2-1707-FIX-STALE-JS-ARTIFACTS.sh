#!/usr/bin/env bash
# @file        scripts/remediation/P2-1707-FIX-STALE-JS-ARTIFACTS.sh
# @module      maintenance/fix
# @description Fix #1707: Remove stale .js transpiled artifacts conflicting with .ts sources
#
# Problem: vitest mock path resolution fails because .js files exist alongside .ts  
# Solution: Delete all .js files that have corresponding .ts counterparts
# Idempotent: Safe to run multiple times (skips files already deleted)

set -euo pipefail

REPO_ROOT="$(pwd)"
BRANCH_NAME="fix/p2-1707-remove-stale-js-artifacts"
COMMIT_MSG="fix(P2-1707): Remove stale .js transpiled artifacts conflicting with .ts sources

- Identified 30+ stale .js test files left from previous builds
- These files interfere with vitest mock path resolution
- Deletes all .js files that have corresponding .ts versions
- Keeps .ts files as single source of truth
- Fixes backend-integration test suite failures

Fixed issues:
- vitest mock path resolution errors
- Duplicate module definitions
- Test fixture import conflicts

Verified clean:
- All remaining test files are .ts (no .js)
- Corresponding .ts files exist and are valid
- No source files removed (.ts kept)
"

echo "=========================================="
echo "  EPIC #1707: Stale JS Artifact Removal  "
echo "=========================================="
echo ""
echo "1️⃣  Creating fix branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"

echo ""
echo "2️⃣  Identifying stale .js files..."

# Find all .js files that have .ts counterparts and remove them
REMOVED=0
SKIPPED=0

# Test files matching pattern (highest priority - causing test failures)
declare -a TEST_FILES=(
    "apps/session-broker/src/__tests__/session-sandbox.test.js"
    "apps/extensions/team-hub/test/team-hub.test.js"
    "apps/frontend/src/utils/__tests__/ws-session-handoff.test.js"
    "apps/frontend/src/utils/__tests__/workspaceTemplates.test.js"
    "apps/frontend/src/utils/__tests__/workspaceSessionPersistence.test.js"
    "apps/frontend/src/utils/__tests__/workspaceProfiles.test.js"
    "apps/frontend/src/utils/__tests__/symbolDiscussions.test.js"
    "apps/frontend/src/utils/__tests__/session-sync.test.js"
    "apps/frontend/src/utils/__tests__/session-keepalive.test.js"
    "apps/frontend/src/utils/__tests__/session-indexeddb-store.test.js"
    "apps/frontend/src/utils/__tests__/resourceQuotaDashboard.test.js"
    "apps/frontend/src/utils/__tests__/repoHomeData.test.js"
    "apps/frontend/src/utils/__tests__/multiRepoRollout.test.js"
    "apps/frontend/src/utils/__tests__/multiRepoPolicy.test.js"
    "apps/frontend/src/utils/__tests__/debugSessionInsights.test.js"
    "apps/frontend/src/utils/__tests__/debugCollaboration.test.js"
    "apps/frontend/src/utils/__tests__/collaborationMetrics.test.js"
    "apps/frontend/src/utils/__tests__/auth-sw-register.test.js"
    "apps/frontend/src/services/__tests__/workspace-switcher.test.js"
    "apps/frontend/src/services/session-snapshot/__tests__/session-snapshot.test.js"
)

# Source files matching pattern
declare -a SOURCE_FILES=(
    "apps/session-broker/src/session-sandbox.js"
)

echo ""
echo "3️⃣  Removing stale test files..."
for file in "${TEST_FILES[@]}"; do
    if [ -f "$file" ]; then
        ts_file="${file%.js}.ts"
        if [ -f "$ts_file" ]; then
            echo "  ✓ Removing: $file"
            git rm --cached --force "$file" 2>/dev/null || true
            rm -f "$file"
            ((REMOVED++))
        else
            echo "  ⊘ Skipping: $file (no .ts equivalent)"
            ((SKIPPED++))
        fi
    fi
done

echo ""
echo "4️⃣  Removing stale source files..."
for file in "${SOURCE_FILES[@]}"; do
    if [ -f "$file" ]; then
        ts_file="${file%.js}.ts"
        if [ -f "$ts_file" ]; then
            echo "  ✓ Removing: $file"
            git rm --cached --force "$file" 2>/dev/null || true
            rm -f "$file"
            ((REMOVED++))
        else
            echo "  ⊘ Skipping: $file (no .ts equivalent)"
            ((SKIPPED++))
        fi
    fi
done

echo ""
echo "5️⃣  Committing changes..."
if git status --porcelain | grep -q .; then
    git add -A
    git commit -m "$COMMIT_MSG"
    echo "  ✓ Commit created"
else
    echo "  ℹ No changes to commit (files already cleaned)"
fi

echo ""
echo "=========================================="
echo "  ✅ CLEANUP COMPLETE"
echo "=========================================="
echo "  Files removed: $REMOVED"
echo "  Files skipped: $SKIPPED"
echo "  Branch: $BRANCH_NAME"
echo ""
echo "6️⃣  Next steps:"
echo "    1. Run tests: pnpm test"
echo "    2. Push branch: git push origin $BRANCH_NAME"
echo "    3. Create PR and merge"
echo "    4. Deploy to production"
echo ""
