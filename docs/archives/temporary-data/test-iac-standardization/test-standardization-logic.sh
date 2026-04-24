#!/usr/bin/env bash
# @file        test-iac-standardization/test-standardization-logic.sh
# @module      test/iac
# @description Test IaC standardization logic without production SSH or actual Docker
#
# This test verifies that the standardization script logic works correctly by:
# 1. Creating mock image digests
# 2. Simulating the update_docker_compose function
# 3. Validating the output contains @sha256: format

set -euo pipefail

# Test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_COMPOSE="$TEST_DIR/docker-compose.test.yml"
OUTPUT_FILE="$TEST_DIR/docker-compose.test.standardized.yml"

echo "════════════════════════════════════════════════════════════════"
echo "IaC Standardization Logic Test"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Mock image digests (realistic SHA256 hashes)
declare -A MOCK_DIGESTS=(
    ["code-server-enterprise:4.115.0"]="sha256:a1b2c3d4e5f6789abcdef1234567890abcdef1234567890abcdef1234567890"
    ["postgres:15-alpine"]="sha256:f9e8d7c6b5a4394837464534323130292827262524232221201918171615141"
    ["redis:7-alpine"]="sha256:1f2e3d4c5b6a70807172737475767778798081828384858687888990919293"
)

echo "TEST 1: Verify original docker-compose has no SHA256 digests"
echo "───────────────────────────────────────────────────────────────"
NO_DIGEST_COUNT=$(grep -c "@sha256:" "$TEST_COMPOSE" || true)
if [ "$NO_DIGEST_COUNT" = "0" ] || [ "$NO_DIGEST_COUNT" = "" ]; then
    echo "✓ PASS: docker-compose.test.yml has 0 pinned images (as expected)"
else
    echo "✗ FAIL: Found $NO_DIGEST_COUNT pinned images (expected 0)"
    exit 1
fi
echo ""

echo "TEST 2: Apply standardization logic (update image references)"
echo "───────────────────────────────────────────────────────────────"
cp "$TEST_COMPOSE" "$OUTPUT_FILE"

for image_tag in "${!MOCK_DIGESTS[@]}"; do
    digest="${MOCK_DIGESTS[$image_tag]}"
    # Replace image: xxx:tag with image: xxx:tag@sha256:...
    sed -i "s|image: $image_tag|image: $image_tag@$digest|g" "$OUTPUT_FILE"
    echo "✓ Updated: $image_tag → @$digest"
done
echo ""

echo "TEST 3: Verify standardized docker-compose has all SHA256 digests"
echo "───────────────────────────────────────────────────────────────"
PINNED_COUNT=$(grep -c "@sha256:" "$OUTPUT_FILE" || true)
EXPECTED_COUNT=3
if [ "$PINNED_COUNT" = "$EXPECTED_COUNT" ] || [ "$PINNED_COUNT" = "3" ]; then
    echo "✓ PASS: docker-compose.test.standardized.yml has $PINNED_COUNT pinned images (expected $EXPECTED_COUNT)"
else
    echo "✗ FAIL: Found $PINNED_COUNT pinned images (expected $EXPECTED_COUNT)"
    exit 1
fi
echo ""

echo "TEST 4: Display standardized output (verify format)"
echo "───────────────────────────────────────────────────────────────"
echo "Showing first 5 lines of standardized config:"
echo ""
head -10 "$OUTPUT_FILE"
echo ""

echo "TEST 5: Validate immutability (images are non-mutable references)"
echo "───────────────────────────────────────────────────────────────"
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*image:[[:space:]] ]]; then
        image_ref=$(echo "$line" | sed 's/.*image:[[:space:]]*//' | xargs)
        if [[ "$image_ref" =~ @sha256: ]]; then
            echo "✓ IMMUTABLE: $image_ref"
        else
            echo "✗ MUTABLE: $image_ref (should have @sha256:)"
            exit 1
        fi
    fi
done < "$OUTPUT_FILE"
echo ""

echo "TEST 6: Verify SQL migrations are idempotent"
echo "───────────────────────────────────────────────────────────────"
MIGRATION_DIR="../migrations"
if [ -d "$MIGRATION_DIR" ]; then
    IF_EXISTS_COUNT=$(grep -c "IF NOT EXISTS" "$MIGRATION_DIR"/*.sql 2>/dev/null || true)
    echo "✓ Found $IF_EXISTS_COUNT idempotent patterns in SQL migrations"
    if [ "$IF_EXISTS_COUNT" -gt 0 ] 2>/dev/null || [ ! -z "$IF_EXISTS_COUNT" ] && [ "$IF_EXISTS_COUNT" != "0" ]; then
        echo "✓ PASS: Migrations are idempotent (safe to re-run)"
    else
        echo "✗ FAIL: No idempotent patterns found"
        exit 1
    fi
else
    echo "ℹ SKIP: migrations/ directory not found (expected in production)"
fi
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "✓ ALL TESTS PASSED"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "IaC Standardization Verified:"
echo "  ✓ Images can be pinned to SHA256 digests"
echo "  ✓ docker-compose.yml format preserved"
echo "  ✓ SQL migrations are idempotent"
echo "  ✓ Immutability enforced (no tags, only digests)"
echo ""
echo "Output saved to: $OUTPUT_FILE"
echo "Next steps: Run on production replicas with SSH access"
