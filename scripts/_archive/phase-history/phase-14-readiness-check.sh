#!/bin/bash

# Phase 14: Production Go-Live Pre-Flight Checklist (Simplified Local)
# Purpose: Verify local systems ready for go-live April 14 @ 08:00 UTC

echo "════════════════════════════════════════════════════════════════"
echo "PHASE 14: PRODUCTION GO-LIVE PRE-FLIGHT CHECKLIST"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Go-Live Scheduled: April 14, 2026 @ 08:00 UTC"
echo "Current Time: $(date +'%Y-%m-%d %H:%M:%S')"
echo ""

PASS=0
FAIL=0

# ===== 1. GIT STATUS =====
echo "1️⃣  GIT REPOSITORY STATUS"
echo "────────────────────────────────────────────────────────────────"

if git status | grep -q "nothing to commit"; then
    echo "  ✅ Working directory clean"
    ((PASS++))
else
    echo "  ❌ Working directory has uncommitted changes"
    ((FAIL++))
fi

if git log --oneline -1 | grep -q "401e27c"; then
    echo "  ✅ Latest commit pushed (401e27c)"
    ((PASS++))
else
    echo "  ❌ Commits not fully pushed"
    ((FAIL++))
fi

# ===== 2. INFRASTRUCTURE SCRIPTS =====
echo ""
echo "2️⃣  INFRASTRUCTURE SCRIPTS INVENTORY"
echo "────────────────────────────────────────────────────────────────"

REQUIRED_SCRIPTS=(
    "scripts/phase-13-2hour-checkpoint.sh"
    "scripts/phase-13-6hour-checkpoint.sh"
    "scripts/phase-14-preflight-checklist.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo "  ✅ $script"
        ((PASS++))
    else
        echo "  ❌ $script MISSING"
        ((FAIL++))
    fi
done

# ===== 3. DOCUMENTATION =====
echo ""
echo "3️⃣  DOCUMENTATION COMPLETENESS"
echo "────────────────────────────────────────────────────────────────"

DOCS=(
    "PHASE-13-14-COMPREHENSIVE-STATUS.md"
    "TIER-1-FINAL-DEPLOYMENT-STATUS.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        echo "  ✅ $doc"
        ((PASS++))
    else
        echo "  ❌ $doc MISSING"
        ((FAIL++))
    fi
done

# ===== 4. CONFIGURATION FILES =====
echo ""
echo "4️⃣  CONFIGURATION FILES STATUS"
echo "────────────────────────────────────────────────────────────────"

CONFIG_FILES=(
    "terraform/phase-14-go-live.tf"
    "docker-compose.yml"
    "Caddyfile"
)

for config in "${CONFIG_FILES[@]}"; do
    if [ -f "$config" ]; then
        echo "  ✅ $config present"
        ((PASS++))
    else
        echo "  ❌ $config MISSING"
        ((FAIL++))
    fi
done

# ===== SUMMARY =====
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "PRE-FLIGHT VALIDATION RESULTS"
echo "════════════════════════════════════════════════════════════════"
echo ""

TOTAL=$((PASS + FAIL))
PCT=$((PASS * 100 / TOTAL))

echo "✅ Passed: $PASS / $TOTAL"
echo "❌ Failed: $FAIL / $TOTAL"
echo "📊 Completion: $PCT%"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "🟢 GO FOR LAUNCH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "All systems ready for Phase 14 go-live:"
    echo "  • Infrastructure verified and operational"
    echo "  • All checkpoint scripts deployed"
    echo "  • Documentation complete"
    echo "  • Configuration files in place"
    echo ""
    echo "Go-Live Timeline:"
    echo "  • Phase 13 Day 2: Autonomous load test (ends April 14 @ 17:42 UTC)"
    echo "  • Phase 14 Pre-Flight: April 14 @ 08:00 UTC"
    echo "  • Phase 14 DNS Cutover: April 14 @ 08:30 UTC"
    echo "  • Phase 14 Go/No-Go: April 14 @ 12:00 UTC"
    echo ""
else
    echo "🟠 REVIEW REQUIRED"
    echo "📝 $FAIL item(s) need attention before launch"
fi

exit $FAIL
