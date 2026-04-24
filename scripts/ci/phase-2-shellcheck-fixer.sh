#!/usr/bin/env bash
# @file        scripts/ci/phase-2-shellcheck-fixer.sh
# @module      p0-1604/phase-2-execution
# @description Automated Phase 2 fixer - applies all shellcheck violations from PHASE-2-SHELLCHECK-FIXES-GUIDE.md
#
# This script automates the execution of all Phase 2 fixes for P0 #1604.
# Fixes shellcheck violations in 6 scripts and re-validates governance.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== P0 #1604 Phase 2: Shellcheck Violations Fixer ===${NC}"
echo "Starting Phase 2 automated remediation..."
echo ""

# List of scripts to fix
declare -a SCRIPTS=(
    "scripts/_common/issue-create-unified.sh"
    "scripts/ci/check-error-handling-consistency.sh"
    "scripts/error-triage-engine.sh"
    "scripts/infrastructure/fix-ssl-protocol-error.sh"
    "scripts/ops/error-fingerprint-triage.sh"
    "scripts/triage/generate-weekly-error-triage-report.sh"
)

cd "$PROJECT_ROOT"

# Step 1: Verify shellcheck is installed
if ! command -v shellcheck &>/dev/null; then
    echo -e "${RED}ERROR: shellcheck not installed${NC}"
    echo "Install with: apt install shellcheck (Linux) or brew install shellcheck (macOS)"
    exit 1
fi

# Step 2: Scan for violations in all scripts
echo -e "${YELLOW}Step 1: Scanning for violations...${NC}"
violations_found=0
for script in "${SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        echo -e "${RED}  ✗ $script NOT FOUND${NC}"
        continue
    fi
    
    echo -n "  Checking $script... "
    if shellcheck -x --severity=error "$script" 2>/dev/null; then
        echo -e "${GREEN}✓ NO ERRORS${NC}"
    else
        echo -e "${RED}✗ HAS VIOLATIONS${NC}"
        violations_found=$((violations_found + 1))
        # Show first 3 violations
        shellcheck -x --severity=error "$script" 2>&1 | head -3 | sed 's/^/    /'
    fi
done

echo ""
if [ $violations_found -eq 0 ]; then
    echo -e "${GREEN}✅ No shellcheck violations found! Phase 2 already complete.${NC}"
    exit 0
fi

echo -e "${YELLOW}Step 2: Applying fixes...${NC}"

# Fix 1: scripts/_common/issue-create-unified.sh
echo "  Fixing scripts/_common/issue-create-unified.sh..."
# SC2168: Remove 'local' from script scope (lines with declare -A)
sed -i 's/^local declare/declare/g' "scripts/_common/issue-create-unified.sh"
# SC2199: Array expansion issues - ensure proper syntax
sed -i 's/\${PRIORITY_LABELS\[@\]}/${!PRIORITY_LABELS[@]}/g' "scripts/_common/issue-create-unified.sh"
echo "    ✓ Applied SC2168, SC2199 fixes"

# Fix 2-6: Generic fixes for remaining scripts
for script in "scripts/ci/check-error-handling-consistency.sh" \
              "scripts/error-triage-engine.sh" \
              "scripts/infrastructure/fix-ssl-protocol-error.sh" \
              "scripts/ops/error-fingerprint-triage.sh" \
              "scripts/triage/generate-weekly-error-triage-report.sh"; do
    if [ ! -f "$script" ]; then continue; fi
    echo "  Fixing $script..."
    
    # SC2168: Remove 'local' from script scope
    sed -i 's/^local //' "$script" 2>/dev/null || true
    
    # SC2199: Fix array subscripts
    sed -i 's/\${VAR\[@\]}/${VAR[*]}/g' "$script" 2>/dev/null || true
    
    # SC1072/SC1073: Fix quote escaping
    sed -i 's/\\"/"\\"/g' "$script" 2>/dev/null || true
    
    echo "    ✓ Applied fixes"
done

echo ""
echo -e "${YELLOW}Step 3: Verifying fixes...${NC}"

violations_after=0
for script in "${SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then continue; fi
    echo -n "  Checking $script... "
    if shellcheck -x --severity=error "$script" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        violations_after=$((violations_after + 1))
    fi
done

echo ""
if [ $violations_after -eq 0 ]; then
    echo -e "${GREEN}✅ All shellcheck violations resolved!${NC}"
    echo ""
    echo -e "${YELLOW}Step 4: Running full governance validation...${NC}"
    if bash scripts/ci/run-governance-checks.sh; then
        echo -e "${GREEN}✅ Governance validation PASSED${NC}"
        
        echo ""
        echo -e "${YELLOW}Step 5: Committing fixes to main...${NC}"
        git add scripts/
        git commit -m "fix(p0-1604): Phase 2 - resolve shellcheck violations in 6 scripts (Closes #1600)"
        git push origin main
        
        echo -e "${GREEN}✅ PHASE 2 COMPLETE - All fixes committed and pushed${NC}"
        exit 0
    else
        echo -e "${RED}✗ Governance validation failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Some violations remain after fixes${NC}"
    echo "  Manual review required - see PHASE-2-SHELLCHECK-FIXES-GUIDE.md"
    exit 1
fi
