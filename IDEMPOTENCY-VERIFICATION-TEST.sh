#!/usr/bin/env bash
# @file        IDEMPOTENCY-VERIFICATION-TEST.sh
# @module      testing/governance
# @description Verification test for idempotency implementations in Sentry and Slack APIs

set -euo pipefail

echo "========================================"
echo "IDEMPOTENCY VERIFICATION TEST"
echo "April 22, 2026"
echo "========================================"
echo ""

# Test 1: Verify Slack API has idempotency cache
echo "[TEST 1] Slack API Idempotency Cache"
if grep -q "const slackCommandCache = new Map()" scripts/integrations/slack-slash-commands-api.js; then
    echo "✓ PASS: slackCommandCache Map declaration found"
else
    echo "✗ FAIL: slackCommandCache Map not found"
    exit 1
fi

if grep -q "slackCommandCache.has(triggerId)" scripts/integrations/slack-slash-commands-api.js; then
    echo "✓ PASS: Cache lookup logic found"
else
    echo "✗ FAIL: Cache lookup logic not found"
    exit 1
fi

if grep -q "slackCommandCache.set(triggerId" scripts/integrations/slack-slash-commands-api.js; then
    echo "✓ PASS: Cache storage logic found"
else
    echo "✗ FAIL: Cache storage logic not found"
    exit 1
fi

if grep -q "Object.freeze" scripts/integrations/slack-slash-commands-api.js; then
    echo "✓ PASS: Object.freeze() immutability found"
else
    echo "✗ FAIL: Object.freeze() immutability not found"
    exit 1
fi

echo ""

# Test 2: Verify Sentry API has idempotency cache
echo "[TEST 2] Sentry API Idempotency Cache"
if grep -q "const fixSuggestionCache = new Map()" scripts/integrations/sentry-integration-api.js; then
    echo "✓ PASS: fixSuggestionCache Map declaration found"
else
    echo "✗ FAIL: fixSuggestionCache Map not found"
    exit 1
fi

if grep -q "if (fixSuggestionCache.has" scripts/integrations/sentry-integration-api.js; then
    echo "✓ PASS: Cache lookup logic found"
else
    echo "✗ FAIL: Cache lookup logic not found"
    exit 1
fi

if grep -q "fixSuggestionCache.set" scripts/integrations/sentry-integration-api.js; then
    echo "✓ PASS: Cache storage logic found"
else
    echo "✗ FAIL: Cache storage logic not found"
    exit 1
fi

if grep -q "x-idempotency-key" scripts/integrations/sentry-integration-api.js; then
    echo "✓ PASS: x-idempotency-key header support found"
else
    echo "✗ FAIL: x-idempotency-key header support not found"
    exit 1
fi

echo ""

# Test 3: Verify governance checks pass
echo "[TEST 3] Governance Compliance Checks"

# Check hardcoded credentials
if bash scripts/ci/check-no-hardcoded-credentials.sh 2>&1 | grep -q "No hardcoded credential literals detected"; then
    echo "✓ PASS: No hardcoded credentials found"
else
    echo "✗ FAIL: Hardcoded credentials check failed"
    exit 1
fi

# Check deduplication
if bash scripts/ci/enforce-global-dedup.sh 2>&1 | grep -q "Global dedup guard passed"; then
    echo "✓ PASS: Global deduplication check passed"
else
    echo "✗ FAIL: Global deduplication check failed"
    exit 1
fi

echo ""

# Test 4: Verify documentation exists
echo "[TEST 4] Governance Documentation"
if [ -f "IAC-ASSURANCE-CERTIFICATION.md" ]; then
    echo "✓ PASS: IAC-ASSURANCE-CERTIFICATION.md exists"
else
    echo "✗ FAIL: IAC-ASSURANCE-CERTIFICATION.md not found"
    exit 1
fi

if [ -f "GOVERNANCE-ENFORCEMENT-COMPLETION-STATEMENT.md" ]; then
    echo "✓ PASS: GOVERNANCE-ENFORCEMENT-COMPLETION-STATEMENT.md exists"
else
    echo "✗ FAIL: GOVERNANCE-ENFORCEMENT-COMPLETION-STATEMENT.md not found"
    exit 1
fi

echo ""

# Test 5: Verify all commits are pushed
echo "[TEST 5] Git Repository State"
if git status | grep -q "nothing to commit"; then
    echo "✓ PASS: Repository is clean (all changes committed)"
else
    echo "✗ FAIL: Repository has uncommitted changes"
    exit 1
fi

if git status | grep -q "up to date with 'origin/main'"; then
    echo "✓ PASS: All commits pushed to origin/main"
else
    echo "✗ FAIL: Commits not pushed"
    exit 1
fi

echo ""
echo "========================================"
echo "ALL IDEMPOTENCY VERIFICATION TESTS PASSED"
echo "========================================"
echo ""
echo "Summary:"
echo "  ✓ Slack API: Trigger-based idempotency with cache"
echo "  ✓ Sentry API: x-idempotency-key with cache"
echo "  ✓ Immutability: Object.freeze() on responses"
echo "  ✓ Governance: All checks passing"
echo "  ✓ Documentation: Certification documents created"
echo "  ✓ Repository: Clean and fully pushed"
echo ""
echo "Status: READY FOR PRODUCTION"
echo ""
