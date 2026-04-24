#!/usr/bin/env bash
# @file        scripts/auth/test-org-internal-access.sh
# @module      auth/testing
# @description Regression tests for org_internal OAuth 403 prevention on IDE and portal surfaces
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/scripts/_common/init.sh"

TESTS_PASSED=0
TESTS_FAILED=0

test_assert_contains_literal() {
  local test_name="$1"
  local file_path="$2"
  local pattern="$3"

  if grep -qF "$pattern" "$file_path" 2>/dev/null; then
    log_info "PASS: $test_name"
    ((TESTS_PASSED++))
    return 0
  fi

  log_error "FAIL: $test_name -- literal not found in $file_path"
  ((TESTS_FAILED++))
  return 1
}

test_assert_contains() {
  local test_name="$1"
  local file_path="$2"
  local pattern="$3"

  if grep -qE "$pattern" "$file_path" 2>/dev/null; then
    log_info "PASS: $test_name"
    ((TESTS_PASSED++))
    return 0
  fi

  log_error "FAIL: $test_name -- pattern not found in $file_path"
  ((TESTS_FAILED++))
  return 1
}

test_assert_count_at_least() {
  local test_name="$1"
  local file_path="$2"
  local pattern="$3"
  local minimum="$4"

  local count
  count=$(grep -cE "$pattern" "$file_path" 2>/dev/null || true)
  if [[ "$count" -ge "$minimum" ]]; then
    log_info "PASS: $test_name"
    ((TESTS_PASSED++))
    return 0
  fi

  log_error "FAIL: $test_name -- expected at least $minimum matches in $file_path, found $count"
  ((TESTS_FAILED++))
  return 1
}

main() {
  log_info ""
  log_info "Running org_internal OAuth regression checks"

  test_assert_count_at_least \
    "docker-compose.yml keeps both OAuth surfaces on wildcard email domains" \
    "$REPO_ROOT/docker-compose.yml" \
    'OAUTH2_PROXY_EMAIL_DOMAINS:.*\\*' \
    2 || true

  test_assert_contains \
    "docker-compose.production.yml defaults OAuth email domains to wildcard" \
    "$REPO_ROOT/docker-compose.production.yml" \
    'OAUTH2_PROXY_EMAIL_DOMAINS:.*\\*' || true

  test_assert_contains_literal \
    ".env.example documents wildcard IDE email domains" \
    "$REPO_ROOT/.env.example" \
    'OAUTH2_PROXY_IDE_EMAIL_DOMAINS=*' || true

  test_assert_contains_literal \
    ".env.example documents wildcard portal email domains" \
    "$REPO_ROOT/.env.example" \
    'OAUTH2_PROXY_PORTAL_EMAIL_DOMAINS=*' || true

  test_assert_contains_literal \
    ".env.defaults documents wildcard portal email domains" \
    "$REPO_ROOT/.env.defaults" \
    'OAUTH2_PROXY_PORTAL_EMAIL_DOMAINS=*' || true

  test_assert_contains_literal \
    "oauth2-proxy reference config uses wildcard email domains" \
    "$REPO_ROOT/oauth2-proxy.cfg" \
    'email-domains = ["*"]' || true

  test_assert_contains \
    "oauth2-proxy reference config enforces authenticated emails file" \
    "$REPO_ROOT/oauth2-proxy.cfg" \
    'authenticated-emails-file = "/etc/oauth2-proxy/allowed-emails.txt"' || true

  test_assert_count_at_least \
    "docker-compose.yml keeps account chooser enabled on both OAuth surfaces" \
    "$REPO_ROOT/docker-compose.yml" \
    'OAUTH2_PROXY_PROMPT: "select_account"' \
    2 || true

  test_assert_contains \
    "403 alert rule exists for auth regressions" \
    "$REPO_ROOT/config/alert-rules-audit-phase4.yml" \
    'alert: AuditOAuth403Detected' || true

  test_assert_contains \
    "Troubleshooting guide documents org_internal root cause" \
    "$REPO_ROOT/docs/OAUTH-ORG-INTERNAL-403-TROUBLESHOOTING.md" \
    'portal-side restriction caused Google to reject' || true

  local total_tests=$((TESTS_PASSED + TESTS_FAILED))
  log_info ""
  log_info "Org_internal regression results: $TESTS_PASSED/$total_tests passed"

  if [[ "$TESTS_FAILED" -ne 0 ]]; then
    log_error "org_internal regression checks failed"
    exit 1
  fi

  log_info "org_internal regression checks passed"
}

main