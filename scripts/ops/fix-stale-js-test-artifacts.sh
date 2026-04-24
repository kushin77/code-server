#!/usr/bin/env bash
# @file        scripts/ops/fix-stale-js-test-artifacts.sh
# @module      maintenance/cleanup
# @description Remove stale .js transpiled test artifacts conflicting with .ts sources
#
# Issue: #1707 - Tests fail due to vitest mock path resolution with stale .js files
# Solution: Delete all .js test files that have corresponding .ts versions
# Pattern: Idempotent - safe to run multiple times

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🧹 Removing stale .js test artifacts...${NC}"

# List of stale .js files that have .ts equivalents (to be removed)
STALE_FILES=(
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

REMOVED_COUNT=0
SKIPPED_COUNT=0

for file in "${STALE_FILES[@]}"; do
    if [ -f "$file" ]; then
        # Check if corresponding .ts file exists
        ts_file="${file%.js}.ts"
        if [ -f "$ts_file" ]; then
            echo -e "${GREEN}✓ Removing: $file${NC}"
            rm -f "$file"
            ((REMOVED_COUNT++))
        else
            echo -e "${YELLOW}⊘ Skipping: $file (no .ts equivalent)${NC}"
            ((SKIPPED_COUNT++))
        fi
    fi
done

echo ""
echo -e "${GREEN}✅ Cleanup Complete${NC}"
echo "   Removed: $REMOVED_COUNT stale .js files"
echo "   Skipped: $SKIPPED_COUNT files (no .ts equivalent)"
echo ""
echo "🔍 Verifying test files are now .ts only..."
find apps -name "*.test.js" -type f | wc -l > /tmp/remaining_js_tests.txt
REMAINING=$(cat /tmp/remaining_js_tests.txt)
if [ "$REMAINING" -eq 0 ]; then
    echo -e "${GREEN}✓ No stale .js test files remain${NC}"
else
    echo -e "${YELLOW}⚠ $REMAINING stale .js files still present (may be intentional)${NC}"
fi
