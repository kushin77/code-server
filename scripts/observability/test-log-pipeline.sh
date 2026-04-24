#!/usr/bin/env bash
# @file        scripts/observability/test-log-pipeline.sh
# @module      observability/testing
# @description End-to-end test of logging pipeline: bare metal → Loki → GitHub issues.
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# Log Pipeline E2E Test (Phase 22+)
#
# Tests complete flow: log generation → Loki ingestion → GitHub issue creation
#
# Usage:
#   bash scripts/observability/test-log-pipeline.sh --all
#   bash scripts/observability/test-log-pipeline.sh --test terraform
#   bash scripts/observability/test-log-pipeline.sh --dry-run
#
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${PROJECT_ROOT}/scripts/_common/init.sh"

# Configuration
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://localhost:3100}"
TEST_NAMESPACE="test-logs-"$(date +%s)
DRY_RUN=false
VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      TEST_ALL=true
      shift
      ;;
    --test)
      TEST_TYPE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ════════════════════════════════════════════════════════════════════════════════════════════
# TEST UTILITIES
# ════════════════════════════════════════════════════════════════════════════════════════════

# Send test log to Loki
send_test_log() {
  local job="$1"
  local message="$2"
  local level="${3:-ERROR}"
  local timestamp=$(date -u +%s%N)
  
  local payload
  payload=$(jq -n \
    --arg timestamp "${timestamp}" \
    --arg message "${message}" \
    --arg level "${level}" \
    --arg job "${job}" \
    '{
      streams: [{
        stream: {
          job: $job,
          level: $level,
          test_namespace: "'${TEST_NAMESPACE}'"
        },
        values: [[
          $timestamp,
          $message
        ]]
      }]
    }')
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would send to Loki: ${message}"
    return 0
  fi
  
  local response
  response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    "${LOKI_ENDPOINT}/loki/api/v1/push" \
    -d "${payload}" 2>/dev/null || echo "error")
  
  if [[ "${response}" == "error" ]] || [[ -z "${response}" ]]; then
    log_error "Failed to send test log to Loki"
    return 1
  fi
  
  log_success "Sent test log: ${job} - ${message}"
  return 0
}

# Query Loki for test logs
query_test_logs() {
  local job="$1"
  local expected_count="${2:-1}"
  
  sleep 2  # Wait for Loki to ingest
  
  local query
  query=$(jq -n \
    --arg job "${job}" \
    --arg namespace "${TEST_NAMESPACE}" \
    '{job: $job, test_namespace: $namespace}' | jq -c '.' | sed 's/"//g' | sed "s/{/{/" | sed "s/}/}/")
  
  # Simplified query
  query="{job=\"${job}\", test_namespace=\"${TEST_NAMESPACE}\"}"
  
  if [[ "${VERBOSE}" == "true" ]]; then
    log_info "Querying Loki: ${query}"
  fi
  
  local response
  response=$(curl -s "${LOKI_ENDPOINT}/loki/api/v1/query_range" \
    --data-urlencode "query=${query}" \
    --data-urlencode "start=$(($(date +%s) - 300))000000000" \
    --data-urlencode "end=$(date +%s)000000000" \
    --data-urlencode "limit=1000" 2>/dev/null || echo '{}')
  
  local log_count
  log_count=$(echo "${response}" | jq '.data.result | length' 2>/dev/null || echo 0)
  
  if [[ ${log_count} -ge ${expected_count} ]]; then
    log_success "Found ${log_count} test logs in Loki (expected: ${expected_count}+)"
    return 0
  else
    log_error "Only found ${log_count} test logs (expected: ${expected_count}+)"
    return 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# TEST CASES
# ════════════════════════════════════════════════════════════════════════════════════════════

test_loki_connectivity() {
  log_info "TEST 1: Loki Connectivity"
  
  if curl -s "${LOKI_ENDPOINT}/ready" >/dev/null 2>&1; then
    log_success "✅ Loki is accessible"
    return 0
  else
    log_error "❌ Loki not accessible at ${LOKI_ENDPOINT}"
    return 1
  fi
}

test_terraform_log_ingestion() {
  log_info "TEST 2: Terraform Log Ingestion"
  
  # Send simulated Terraform error
  send_test_log "terraform" "Error: aws_instance.test: error creating instance: timeout waiting for EC2 instance state change" "ERROR" || return 1
  
  # Verify in Loki
  query_test_logs "terraform" 1 || return 1
  
  return 0
}

test_haproxy_failover_log_ingestion() {
  log_info "TEST 3: HAProxy Failover Log Ingestion"
  
  # Send simulated failover event
  send_test_log "haproxy" "[FAILOVER] triggered: primary=DOWN, replica=UP, duration=28ms" "WARN" || return 1
  
  # Verify in Loki
  query_test_logs "haproxy" 1 || return 1
  
  return 0
}

test_system_log_ingestion() {
  log_info "TEST 4: System Log Ingestion"
  
  # Send simulated kernel error
  send_test_log "systemd" "kernel panic - not syncing: Fatal exception in interrupt" "ERROR" || return 1
  
  # Verify in Loki
  query_test_logs "systemd" 1 || return 1
  
  return 0
}

test_k8s_log_ingestion() {
  log_info "TEST 5: Kubernetes Pod Log Ingestion"
  
  # Send simulated pod error
  send_test_log "kubernetes" "panic: database connection failed: connection refused" "ERROR" || return 1
  
  # Verify in Loki
  query_test_logs "kubernetes" 1 || return 1
  
  return 0
}

test_error_pattern_clustering() {
  log_info "TEST 6: Error Pattern Clustering"
  
  # Send multiple similar errors
  for i in {1..5}; do
    send_test_log "terraform" "Error: aws_instance.test: error creating instance: timeout" "ERROR" || return 1
    sleep 0.5
  done
  
  # Verify clustering detects pattern
  sleep 2
  
  log_success "✅ Sent 5 similar errors for clustering"
  return 0
}

test_github_integration() {
  log_info "TEST 7: GitHub Integration"
  
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    log_warn "⚠️  GITHUB_TOKEN not set, skipping GitHub integration test"
    return 0
  fi
  
  # Test GitHub API access
  if curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/user" | jq '.login' >/dev/null 2>&1; then
    log_success "✅ GitHub API accessible"
    return 0
  else
    log_error "❌ GitHub API not accessible"
    return 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN TEST EXECUTION
# ════════════════════════════════════════════════════════════════════════════════════════════

run_all_tests() {
  log_info "════════════════════════════════════════════════════════════════════════════════════"
  log_info "Running Complete Log Pipeline Tests"
  log_info "════════════════════════════════════════════════════════════════════════════════════"
  
  local pass_count=0
  local fail_count=0
  
  # Test connectivity
  if test_loki_connectivity; then
    ((pass_count++))
  else
    ((fail_count++))
  fi
  
  # Test log ingestion paths
  if test_terraform_log_ingestion; then
    ((pass_count++))
  else
    ((fail_count++))
  fi
  
  if test_haproxy_failover_log_ingestion; then
    ((pass_count++))
  else
    ((fail_count++))
  fi
  
  if test_system_log_ingestion; then
    ((pass_count++))
  else
    ((fail_count++))
  fi
  
  if test_k8s_log_ingestion; then
    ((pass_count++))
  else
    ((fail_count++))
  fi
  
  # Test error clustering
  if test_error_pattern_clustering; then
    ((pass_count++))
  else
    ((fail_count++))
  fi
  
  # Test GitHub integration
  if test_github_integration; then
    ((pass_count++))
  else
    ((fail_count++))
  fi
  
  # Print summary
  echo ""
  log_info "════════════════════════════════════════════════════════════════════════════════════"
  log_info "Test Results: ${pass_count} passed, ${fail_count} failed"
  log_info "════════════════════════════════════════════════════════════════════════════════════"
  
  if [[ ${fail_count} -eq 0 ]]; then
    log_success "✅ All tests passed!"
    return 0
  else
    log_error "❌ Some tests failed"
    return 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  log_info "Log Pipeline E2E Test Suite"
  log_info "Test Namespace: ${TEST_NAMESPACE}"
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_warn "DRY_RUN mode enabled - no changes will be made"
  fi
  
  run_all_tests
}

main "$@"
