#!/usr/bin/env bash
# @file        scripts/run-e2e-tests-with-gsm.sh
# @module      ci/testing
# @description Run E2E tests with QA credentials fetched from Google Secret Manager
#
# This script:
# 1. Fetches QA credentials from GSM (qa-user-email, qa-service-account-key)
# 2. Sets environment variables for Playwright tests
# 3. Runs full E2E test suite (Issues #986-990, 556 tests)
# 4. Authenticates as qa@kushnir.cloud service account
#
# Prerequisites:
#   - Google Cloud CLI authenticated
#   - GSM secrets configured (via setup-qa-service-account.sh)
#   - Node.js + npm (Playwright)
#   - Tests in tests/e2e/specs/
#
# Usage:
#   bash scripts/run-e2e-tests-with-gsm.sh [--project chromium|firefox|webkit|all]
#
# Examples:
#   bash scripts/run-e2e-tests-with-gsm.sh                    # All browsers
#   bash scripts/run-e2e-tests-with-gsm.sh --project chromium # Chromium only
#   bash scripts/run-e2e-tests-with-gsm.sh --project firefox  # Firefox only
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# ============================================================================
# Configuration
# ============================================================================

GCP_PROJECT="${GCP_PROJECT:-kushin77-ops}"
QA_EMAIL_SECRET_ID="qa-user-email"
QA_KEY_SECRET_ID="qa-service-account-key"
PLAYWRIGHT_PROJECT="${PLAYWRIGHT_PROJECT:-all}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PLAYWRIGHT_PROJECT="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ============================================================================
# Verify Prerequisites
# ============================================================================

log_info "Verifying prerequisites..."

if ! command -v gcloud &> /dev/null; then
  log_error "gcloud CLI not found"
  exit 1
fi

if ! command -v npx &> /dev/null; then
  log_error "npm/npx not found"
  exit 1
fi

if [ ! -d "tests/e2e" ]; then
  log_error "tests/e2e directory not found"
  exit 1
fi

log_success "Prerequisites verified"

# ============================================================================
# PART 1: Fetch QA Credentials from GSM
# ============================================================================

log_info "Part 1: Fetching QA credentials from Google Secret Manager..."

# Fetch QA email
log_info "Fetching $QA_EMAIL_SECRET_ID from GSM..."
if ! QA_EMAIL=$(gcloud secrets versions access latest \
  --secret="$QA_EMAIL_SECRET_ID" \
  --project="$GCP_PROJECT" 2>/dev/null); then
  log_error "Failed to fetch $QA_EMAIL_SECRET_ID from GSM"
  log_info "Make sure GSM secrets are set up by running:"
  log_info "  bash scripts/setup-qa-service-account.sh --apply"
  exit 1
fi
log_success "✓ QA email: $QA_EMAIL"

# Fetch service account key (JSON format)
log_info "Fetching $QA_KEY_SECRET_ID from GSM..."
if ! QA_KEY=$(gcloud secrets versions access latest \
  --secret="$QA_KEY_SECRET_ID" \
  --project="$GCP_PROJECT" 2>/dev/null); then
  log_error "Failed to fetch $QA_KEY_SECRET_ID from GSM"
  exit 1
fi

# Save key to temporary file for Playwright config
QA_KEY_FILE=$(mktemp)
echo "$QA_KEY" > "$QA_KEY_FILE"
chmod 600 "$QA_KEY_FILE"
log_success "✓ QA service account key stored ($(wc -c < "$QA_KEY_FILE") bytes)"

# ============================================================================
# PART 2: Set Environment Variables for Tests
# ============================================================================

log_info "Part 2: Setting up test environment variables..."

export E2E_USER_EMAIL="$QA_EMAIL"
export E2E_USER_KEY="$QA_KEY"
export E2E_USER_KEY_FILE="$QA_KEY_FILE"
export GCP_PROJECT="$GCP_PROJECT"
export REQUIRE_VPN=0
export REQUIRE_SINGLE_LOGIN=1

log_success "✓ Environment variables set"

# ============================================================================
# PART 3: Run E2E Tests
# ============================================================================

log_info "Part 3: Running E2E tests with GSM credentials..."

test_count=0
test_passed=0
test_failed=0

case "$PLAYWRIGHT_PROJECT" in
  chromium|firefox|webkit)
    log_info "Running tests for $PLAYWRIGHT_PROJECT browser..."
    if npx playwright test tests/e2e/specs/ --project="$PLAYWRIGHT_PROJECT"; then
      test_passed=$((test_passed + 1))
    else
      test_failed=$((test_failed + 1))
    fi
    ;;
  all)
    log_info "Running tests for all browsers (chromium, firefox, webkit)..."
    if npx playwright test tests/e2e/specs/; then
      test_passed=$((test_passed + 1))
    else
      test_failed=$((test_failed + 1))
    fi
    ;;
  *)
    log_error "Invalid project: $PLAYWRIGHT_PROJECT (use: chromium, firefox, webkit, all)"
    exit 1
    ;;
esac

# ============================================================================
# PART 4: Cleanup and Summary
# ============================================================================

log_info "Part 4: Cleaning up..."

# Remove temporary key file
rm -f "$QA_KEY_FILE"
log_success "✓ Temporary files cleaned up"

# ============================================================================
# SUMMARY
# ============================================================================

log_info ""
log_info "=========================================="
log_info "E2E Test Execution Complete"
log_info "=========================================="
log_info ""

if [ "$test_failed" -eq 0 ]; then
  log_success "✅ All tests passed!"
  log_info "QA account used: $QA_EMAIL"
  log_info "Credentials source: Google Secret Manager"
  exit 0
else
  log_error "❌ Some tests failed"
  log_info "QA account used: $QA_EMAIL"
  log_info "Check test output above for details"
  exit 1
fi
