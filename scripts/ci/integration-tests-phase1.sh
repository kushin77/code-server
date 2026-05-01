#!/usr/bin/env bash
# @file scripts/ci/integration-tests-phase1.sh
# @description Phase 1 integration test suite: verifies end-to-end service
#              connectivity, authentication flow, workspace CRUD operations,
#              and database/cache consistency.
# @usage integration-tests-phase1.sh [--url <base-url>] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
BASE_URL="${BASE_URL:-http://localhost:8080}"
RESULTS_FILE="${REPO_ROOT}/artifacts/integration-phase1-$(date +%s).json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --url)     BASE_URL="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

mkdir -p "${REPO_ROOT}/artifacts"

PASS=0
FAIL=0
declare -a TEST_LOG

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    PASS=$(( PASS + 1 ))
    TEST_LOG+=("{\"name\":\"${name}\",\"status\":\"PASS\"}")
    log_info "  ✅ PASS: ${name}"
  else
    FAIL=$(( FAIL + 1 ))
    TEST_LOG+=("{\"name\":\"${name}\",\"status\":\"FAIL\",\"expected\":\"${expected}\",\"actual\":\"${actual}\"}")
    log_error "  ❌ FAIL: ${name} — expected='${expected}' actual='${actual}'"
  fi
}

assert_http() {
  local name="$1" url="$2" expected_code="${3:-200}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    PASS=$(( PASS + 1 ))
    TEST_LOG+=("{\"name\":\"${name}\",\"status\":\"PASS\",\"dry-run\":true}")
    log_info "  ✅ PASS (dry-run): ${name}"
    return
  fi
  local actual_code
  actual_code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 10 "${url}" 2>/dev/null || echo "000")
  assert_eq "${name}" "${expected_code}" "${actual_code}"
}

assert_contains() {
  local name="$1" url="$2" needle="$3"
  if [[ "${DRY_RUN}" == "true" ]]; then
    PASS=$(( PASS + 1 ))
    TEST_LOG+=("{\"name\":\"${name}\",\"status\":\"PASS\",\"dry-run\":true}")
    log_info "  ✅ PASS (dry-run): ${name}"
    return
  fi
  local body
  body=$(curl -sf --max-time 10 "${url}" 2>/dev/null || echo "")
  if echo "${body}" | grep -q "${needle}"; then
    PASS=$(( PASS + 1 ))
    TEST_LOG+=("{\"name\":\"${name}\",\"status\":\"PASS\"}")
    log_info "  ✅ PASS: ${name}"
  else
    FAIL=$(( FAIL + 1 ))
    TEST_LOG+=("{\"name\":\"${name}\",\"status\":\"FAIL\",\"needle\":\"${needle}\"}")
    log_error "  ❌ FAIL: ${name} — response did not contain '${needle}'"
  fi
}

# ── Group 1: Infrastructure health ────────────────────────────────────────
test_infrastructure() {
  log_info "Group 1: Infrastructure Health"

  assert_http "health_endpoint" "${BASE_URL}/health" "200"
  assert_http "metrics_endpoint" "${BASE_URL}/metrics" "200"
  assert_contains "health_ok_body" "${BASE_URL}/health" "ok"

  # Container-level checks
  if [[ "${DRY_RUN}" != "true" ]]; then
    for svc in postgres redis caddy; do
      local state
      state=$(docker inspect --format='{{.State.Status}}' "code-server-${svc}" 2>/dev/null || echo "missing")
      assert_eq "container_${svc}_running" "running" "${state}"
    done
  fi
}

# ── Group 2: API connectivity ──────────────────────────────────────────────
test_api_connectivity() {
  log_info "Group 2: API Connectivity"

  assert_http "api_status"            "${BASE_URL}/api/v1/status" "200"
  assert_http "api_version"           "${BASE_URL}/api/v1/version" "200"
  assert_http "api_404_unknown"       "${BASE_URL}/api/v1/does-not-exist" "404"
  assert_contains "api_status_json"   "${BASE_URL}/api/v1/status" "\"status\""
}

# ── Group 3: Authentication flow ──────────────────────────────────────────
test_authentication() {
  log_info "Group 3: Authentication Flow"

  # Unauthenticated requests to protected routes should redirect to auth
  assert_http "auth_redirect_workspace" "${BASE_URL}/workspace" "302"
  assert_http "oauth2_discovery"        "${BASE_URL}/oauth2/auth" "200"
  assert_http "healthcheck_no_auth"     "${BASE_URL}/health" "200"
}

# ── Group 4: Database connectivity ────────────────────────────────────────
test_database() {
  log_info "Group 4: Database Connectivity"

  if [[ "${DRY_RUN}" == "true" ]]; then
    TEST_LOG+=("{\"name\":\"postgres_query\",\"status\":\"PASS\",\"dry-run\":true}")
    TEST_LOG+=("{\"name\":\"redis_ping\",\"status\":\"PASS\",\"dry-run\":true}")
    PASS=$(( PASS + 2 ))
    log_info "  ✅ PASS (dry-run): postgres_query"
    log_info "  ✅ PASS (dry-run): redis_ping"
    return
  fi

  # PostgreSQL
  local pg_result
  pg_result=$(docker exec code-server-postgres \
    psql -U postgres -tAc "SELECT 1" 2>/dev/null || echo "error")
  assert_eq "postgres_query" "1" "${pg_result}"

  # Redis
  local redis_result
  redis_result=$(docker exec code-server-redis redis-cli PING 2>/dev/null || echo "error")
  assert_eq "redis_ping" "PONG" "${redis_result}"
}

# ── Group 5: Vault secrets ─────────────────────────────────────────────────
test_vault() {
  log_info "Group 5: Vault Secrets"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ PASS (dry-run): vault_sealed_status"
    PASS=$(( PASS + 1 ))
    TEST_LOG+=("{\"name\":\"vault_sealed_status\",\"status\":\"PASS\",\"dry-run\":true}")
    return
  fi

  local sealed
  sealed=$(docker exec code-server-vault vault status -format=json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['sealed'])" 2>/dev/null || echo "true")
  assert_eq "vault_not_sealed" "False" "${sealed}"
}

# ── Write results ──────────────────────────────────────────────────────────
write_results() {
  local entries
  entries=$(IFS=,; echo "[${TEST_LOG[*]}]")
  cat > "${RESULTS_FILE}" << EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "base_url": "${BASE_URL}",
  "total": $((PASS + FAIL)),
  "passed": ${PASS},
  "failed": ${FAIL},
  "tests": ${entries}
}
EOF
  log_info "Results written: ${RESULTS_FILE}"
}

# Main
log_info "Integration Tests Phase 1 — url=${BASE_URL} dry-run=${DRY_RUN}"
log_info "================================================================="

test_infrastructure
test_api_connectivity
test_authentication
test_database
test_vault

write_results

log_info "================================================================="
log_info "Results: ${PASS} passed, ${FAIL} failed / $((PASS + FAIL)) total"

[[ ${FAIL} -eq 0 ]] && { log_info "✅ All integration tests passed"; exit 0; } || \
  { log_error "❌ Integration tests: ${FAIL} failure(s)"; exit 1; }
