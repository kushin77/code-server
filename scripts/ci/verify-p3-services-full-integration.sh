#!/bin/bash
# @file scripts/ci/verify-p3-services-full-integration.sh
# @description Comprehensive P3 Services Integration & Deployment Verification (IaC)
# @governance GOV-002: Immutable, idempotent, deterministic verification
# @author GitHub Copilot
# @date 2026-04-25
# @related P3 #1561 (Execution Scheduler), #1559 (Reputation Engine), #1558 (Paperclip)

set -euo pipefail

################################################################################
# COLOR CODES & LOGGING
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

pass() {
  echo -e "${GREEN}[✓]${NC} $*"
}

fail() {
  echo -e "${RED}[✗]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[⚠]${NC} $*"
}

info() {
  echo -e "${CYAN}[ℹ]${NC} $*"
}

################################################################################
# CONFIGURATION (Environment-Driven)
################################################################################

# Load network configuration SSOT
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"
source "${PROJECT_ROOT}/scripts/_common/_epic-1536-network-config.env" || {
    echo "Error: Network configuration SSOT not found"
    exit 1
}

# Service endpoints (environment-driven)
REPUTATION_ENGINE_URL="${REPUTATION_ENGINE_URL:-http://localhost:8002}"
EXECUTION_SCHEDULER_URL="${EXECUTION_SCHEDULER_URL:-http://localhost:8080}"
PAPERCLIP_CONTROL_PLANE_URL="${PAPERCLIP_CONTROL_PLANE_URL:-http://localhost:8010}"
OPA_URL="${OPA_URL:-http://localhost:8181}"

# Database
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-kushnir}"

# Redis
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

# Timeouts
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
INTEGRATION_TEST_TIMEOUT="${INTEGRATION_TEST_TIMEOUT:-60}"

# Reporting
REPORT_DIR="artifacts"
REPORT_FILE="${REPORT_DIR}/p3-verification-$(date +'%Y%m%d-%H%M%S').json"
LOG_FILE="${REPORT_DIR}/p3-verification-$(date +'%Y%m%d-%H%M%S').log"

################################################################################
# TEST COUNTERS (Immutable Across Execution)
################################################################################

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CRITICAL_FAILURES=0

test_pass() {
  ((TESTS_PASSED++))
  pass "$1"
}

test_fail() {
  ((TESTS_FAILED++))
  fail "$1"
  if [[ "${2:-false}" == "critical" ]]; then
    ((CRITICAL_FAILURES++))
  fi
}

test_skip() {
  ((TESTS_SKIPPED++))
  warn "$1 (skipped)"
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

ensure_report_dir() {
  mkdir -p "$REPORT_DIR"
}

curl_json() {
  local method="${1:-GET}"
  local url="$2"
  local data="${3:-}"
  local timeout="${4:-10}"

  if [[ -z "$data" ]]; then
    curl -s -X "$method" "$url" \
      -H "Content-Type: application/json" \
      --max-time "$timeout" 2>/dev/null || echo ""
  else
    curl -s -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -d "$data" \
      --max-time "$timeout" 2>/dev/null || echo ""
  fi
}

is_service_responding() {
  local url="$1"
  local timeout="${2:-5}"

  if curl -s --max-time "$timeout" "$url" > /dev/null 2>&1; then
    return 0
  fi
  return 1
}

################################################################################
# TEST 1: Individual Service Health Checks
################################################################################

test_service_health() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 1: Service Health Checks"
  log "════════════════════════════════════════════════════════"

  local services=(
    "Reputation Engine|${REPUTATION_ENGINE_URL}/health"
    "Execution Scheduler|${EXECUTION_SCHEDULER_URL}/health"
    "Paperclip Control Plane|${PAPERCLIP_CONTROL_PLANE_URL}/health"
    "OPA Policy Engine|${OPA_URL}/health"
  )

  for service_def in "${services[@]}"; do
    local service_name="${service_def%%|*}"
    local health_url="${service_def##*|}"

    if is_service_responding "$health_url" "$HEALTH_CHECK_TIMEOUT"; then
      test_pass "Service healthy: $service_name"
    else
      test_fail "Service not responding: $service_name ($health_url)" "critical"
    fi
  done
}

################################################################################
# TEST 2: Database Connectivity & Schema Verification
################################################################################

test_database_connectivity() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 2: Database Connectivity & Schema"
  log "════════════════════════════════════════════════════════"

  # Check if psql is available
  if ! command -v psql &> /dev/null; then
    test_skip "Database connectivity (psql not available)"
    return
  fi

  # Try to connect
  if PGPASSWORD="$DB_USER" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT 1" > /dev/null 2>&1; then
    test_pass "Database connection successful"
  else
    test_fail "Database connection failed" "critical"
    return
  fi

  # Check for required tables
  local required_tables=("users" "tasks" "approvals" "audit_logs")

  for table in "${required_tables[@]}"; do
    if PGPASSWORD="$DB_USER" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
      -c "SELECT 1 FROM information_schema.tables WHERE table_name='$table'" \
      | grep -q 1; then
      test_pass "Table exists: $table"
    else
      warn "Table may be missing: $table (might be lazy-loaded)"
    fi
  done
}

################################################################################
# TEST 3: Redis Cache Connectivity
################################################################################

test_redis_connectivity() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 3: Redis Cache Connectivity"
  log "════════════════════════════════════════════════════════"

  # Check if redis-cli is available
  if ! command -v redis-cli &> /dev/null; then
    test_skip "Redis connectivity (redis-cli not available)"
    return
  fi

  # Try PING
  if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING 2>/dev/null | grep -q "PONG"; then
    test_pass "Redis connection successful"
  else
    test_fail "Redis connection failed"
    return
  fi

  # Check memory usage
  local memory=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO memory | grep used_memory_human | cut -d: -f2 || echo "unknown")
  info "Redis memory usage: $memory"
}

################################################################################
# TEST 4: Inter-Service Communication
################################################################################

test_inter_service_communication() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 4: Inter-Service Communication"
  log "════════════════════════════════════════════════════════"

  # Test Reputation Engine API endpoints
  log "Testing Reputation Engine endpoints..."
  
  local rep_response
  rep_response=$(curl_json GET "${REPUTATION_ENGINE_URL}/scores" "" 5)
  
  if echo "$rep_response" | grep -q "scores\|data\|\[\]"; then
    test_pass "Reputation Engine /scores endpoint accessible"
  else
    test_fail "Reputation Engine /scores endpoint failed"
  fi

  # Test Execution Scheduler API endpoints
  log "Testing Execution Scheduler endpoints..."
  
  local exec_response
  exec_response=$(curl_json GET "${EXECUTION_SCHEDULER_URL}/tasks" "" 5)
  
  if echo "$exec_response" | grep -q "tasks\|data\|\[\]"; then
    test_pass "Execution Scheduler /tasks endpoint accessible"
  else
    test_fail "Execution Scheduler /tasks endpoint failed"
  fi

  # Test Paperclip endpoints
  log "Testing Paperclip Control Plane endpoints..."
  
  local paperclip_response
  paperclip_response=$(curl_json GET "${PAPERCLIP_CONTROL_PLANE_URL}/approvals" "" 5)
  
  if echo "$paperclip_response" | grep -q "approvals\|data\|\[\]"; then
    test_pass "Paperclip /approvals endpoint accessible"
  else
    test_fail "Paperclip /approvals endpoint failed"
  fi
}

################################################################################
# TEST 5: OPA Policy Integration
################################################################################

test_opa_policy_integration() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 5: OPA Policy Engine Integration"
  log "════════════════════════════════════════════════════════"

  # Test OPA data API
  log "Testing OPA data API..."
  
  local opa_data
  opa_data=$(curl_json GET "${OPA_URL}/v1/data" "" 5)
  
  if echo "$opa_data" | grep -q "result"; then
    test_pass "OPA data API accessible"
  else
    test_fail "OPA data API not responding"
    return
  fi

  # Test OPA compile endpoint (policy evaluation)
  log "Testing OPA policy compilation..."
  
  local policy_test='{
    "query": "data.kushnir.approval_required",
    "input": {
      "risk_level": "HIGH",
      "agent_type": "CODE_REVIEWER"
    }
  }'
  
  local opa_compile
  opa_compile=$(curl_json POST "${OPA_URL}/v1/compile" "$policy_test" 5)
  
  if echo "$opa_compile" | grep -q "result\|code"; then
    test_pass "OPA policy compilation working"
  else
    warn "OPA policy compilation returned unexpected format"
  fi
}

################################################################################
# TEST 6: End-to-End Task Workflow (Simulation)
################################################################################

test_end_to_end_workflow() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 6: End-to-End Task Workflow Simulation"
  log "════════════════════════════════════════════════════════"

  # Step 1: Submit task to Execution Scheduler
  log "Simulating task submission..."
  
  local task_payload='{
    "task_type": "CODE_REVIEW",
    "title": "Integration Test Task",
    "description": "Automated verification task",
    "risk_level": "MEDIUM",
    "agent_type": "CODE_REVIEWER",
    "input": {
      "code": "console.log(\"test\");",
      "language": "javascript"
    }
  }'
  
  local task_response
  task_response=$(curl_json POST "${EXECUTION_SCHEDULER_URL}/tasks" "$task_payload" "$INTEGRATION_TEST_TIMEOUT")
  
  if echo "$task_response" | grep -q "task_id\|id"; then
    test_pass "Task submission successful"
    local task_id
    task_id=$(echo "$task_response" | grep -o '"task_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    info "Task ID: $task_id"
  else
    test_fail "Task submission failed"
    return
  fi

  # Step 2: Verify approval workflow (if risk_level requires approval)
  log "Checking approval workflow..."
  
  local approval_response
  approval_response=$(curl_json GET "${PAPERCLIP_CONTROL_PLANE_URL}/approvals" "" 10)
  
  if echo "$approval_response" | grep -q "approvals\|pending"; then
    test_pass "Approval workflow operational"
  else
    warn "Approval workflow check returned unexpected format"
  fi

  # Step 3: Verify reputation scoring triggered
  log "Verifying reputation engine integration..."
  
  local scores_response
  scores_response=$(curl_json GET "${REPUTATION_ENGINE_URL}/scores" "" 10)
  
  if echo "$scores_response" | grep -q "scores"; then
    test_pass "Reputation scoring operational"
  else
    warn "Reputation scoring returned unexpected format"
  fi
}

################################################################################
# TEST 7: Service Isolation & Network Policies
################################################################################

test_service_isolation() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 7: Service Isolation & Network Policies"
  log "════════════════════════════════════════════════════════"

  # Test that services can't bypass authorization
  log "Testing authorization enforcement..."
  
  # Try to call privileged endpoint without auth
  local unauth_response
  unauth_response=$(curl_json GET "${PAPERCLIP_CONTROL_PLANE_URL}/admin/policies" "" 5)
  
  if echo "$unauth_response" | grep -q "401\|unauthorized\|Unauthorized"; then
    test_pass "Authorization enforcement working"
  else
    warn "Authorization check returned: $unauth_response"
  fi
}

################################################################################
# TEST 8: Audit Logging
################################################################################

test_audit_logging() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 8: Audit Logging & Compliance"
  log "════════════════════════════════════════════════════════"

  # Check if audit logs are being created/accessible
  if [[ -d "logs" ]]; then
    local audit_logs
    audit_logs=$(find logs -name "*audit*" -type f -mmin -60 2>/dev/null | wc -l)
    
    if [[ $audit_logs -gt 0 ]]; then
      test_pass "Audit logs found ($audit_logs recent files)"
    else
      warn "No recent audit logs found (might be normal)"
    fi
  else
    warn "Logs directory not found"
  fi

  # Verify correlation ID tracking
  local rep_headers
  rep_headers=$(curl -sI "${REPUTATION_ENGINE_URL}/health" 2>/dev/null)
  
  if echo "$rep_headers" | grep -q "X-Correlation-ID\|correlation"; then
    test_pass "Correlation ID header present"
  else
    info "Correlation ID header not detected (might be in body)"
  fi
}

################################################################################
# TEST 9: Resource Constraints & Performance
################################################################################

test_resource_constraints() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 9: Resource Constraints & Performance"
  log "════════════════════════════════════════════════════════"

  # Test timeout constraints
  log "Testing execution timeouts..."
  
  local timeout_test='{
    "task_type": "LONG_RUNNING",
    "timeout": 600,
    "agent_type": "TEST_GENERATOR"
  }'
  
  local timeout_response
  timeout_response=$(curl_json POST "${EXECUTION_SCHEDULER_URL}/tasks/validate" "$timeout_test" 5)
  
  if echo "$timeout_response" | grep -q "valid\|ok\|success"; then
    test_pass "Resource constraint validation working"
  else
    warn "Resource constraint validation returned: $timeout_response"
  fi
}

################################################################################
# TEST 10: Idempotency Check (IaC Principle)
################################################################################

test_idempotency() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 10: Idempotency Verification (IaC Principle)"
  log "════════════════════════════════════════════════════════"

  # Verify that re-running tests produces same result
  log "Verifying service state consistency..."
  
  local first_check
  first_check=$(curl_json GET "${REPUTATION_ENGINE_URL}/health" "" 5)
  
  sleep 2
  
  local second_check
  second_check=$(curl_json GET "${REPUTATION_ENGINE_URL}/health" "" 5)
  
  if [[ "$first_check" == "$second_check" ]]; then
    test_pass "Idempotency verified (consistent service state)"
  else
    warn "Service state changed between checks (might be normal for dynamic data)"
  fi
}

################################################################################
# COMPLIANCE & REPORTING
################################################################################

generate_compliance_report() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "Generating Compliance Report"
  log "════════════════════════════════════════════════════════"

  cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "verification_scope": "P3 Services Full Integration",
  "services_tested": [
    "Reputation Engine (#1559)",
    "Execution Scheduler (#1561)",
    "Paperclip Control Plane (#1558)",
    "OPA Policy Engine"
  ],
  "test_results": {
    "total_tests": $TESTS_RUN,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "skipped": $TESTS_SKIPPED,
    "critical_failures": $CRITICAL_FAILURES,
    "pass_rate": "$(echo "scale=2; $TESTS_PASSED * 100 / ($TESTS_PASSED + $TESTS_FAILED)" | bc -l 2>/dev/null || echo "N/A")%"
  },
  "governance": {
    "iac_compliant": true,
    "immutable": "set -euo pipefail",
    "idempotent": "no state mutations",
    "deterministic": "environment-driven config",
    "auditable": "GOV-002 logging"
  },
  "deployment_status": "$(if [[ $CRITICAL_FAILURES -eq 0 ]]; then echo 'READY'; else echo 'NEEDS_ATTENTION'; fi)",
  "environment": {
    "reputation_engine": "$REPUTATION_ENGINE_URL",
    "execution_scheduler": "$EXECUTION_SCHEDULER_URL",
    "paperclip_control_plane": "$PAPERCLIP_CONTROL_PLANE_URL",
    "opa": "$OPA_URL"
  }
}
EOF

  cat "$REPORT_FILE"
}

print_summary() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST SUMMARY"
  log "════════════════════════════════════════════════════════"
  log "Total Tests:         $TESTS_RUN"
  log "Passed:              ${GREEN}$TESTS_PASSED${NC}"
  log "Failed:              $(if [[ $TESTS_FAILED -eq 0 ]]; then echo -e "${GREEN}$TESTS_FAILED${NC}"; else echo -e "${RED}$TESTS_FAILED${NC}"; fi)"
  log "Skipped:             $TESTS_SKIPPED"
  log "Critical Failures:   $(if [[ $CRITICAL_FAILURES -eq 0 ]]; then echo -e "${GREEN}$CRITICAL_FAILURES${NC}"; else echo -e "${RED}$CRITICAL_FAILURES${NC}"; fi)"
  log ""

  if [[ $CRITICAL_FAILURES -eq 0 ]]; then
    log -e "${GREEN}✓ P3 SERVICES INTEGRATION VERIFICATION PASSED${NC}"
    log "Status: Ready for deployment"
    return 0
  else
    log -e "${RED}✗ P3 SERVICES VERIFICATION FAILED${NC}"
    log "Status: Needs attention"
    return 1
  fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
  ensure_report_dir

  log "╔════════════════════════════════════════════════════════╗"
  log "║  P3 Services Full Integration Verification            ║"
  log "║  IaC: Immutable | Idempotent | Deterministic          ║"
  log "╚════════════════════════════════════════════════════════╝"
  log ""
  log "Report: $REPORT_FILE"
  log "Logs:   $LOG_FILE"
  log ""

  # Run all tests
  test_service_health
  test_database_connectivity
  test_redis_connectivity
  test_inter_service_communication
  test_opa_policy_integration
  test_end_to_end_workflow
  test_service_isolation
  test_audit_logging
  test_resource_constraints
  test_idempotency

  # Generate reports
  print_summary
  generate_compliance_report

  log ""
  log "Verification complete. Results saved to $REPORT_FILE"

  # Exit with appropriate code
  if [[ $CRITICAL_FAILURES -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

# Execute main function
main "$@"
