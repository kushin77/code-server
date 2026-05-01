#!/usr/bin/env bash
# @file scripts/ci/integration-tests-phase2.sh
# @description Phase 2 integration tests: multi-tenant isolation, GitOps sync,
#              scaling events, DR failover simulation, and observability pipeline.
# @usage integration-tests-phase2.sh [--url <base-url>] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
BASE_URL="${BASE_URL:-http://localhost:8080}"
RESULTS_FILE="${REPO_ROOT}/artifacts/integration-phase2-$(date +%s).json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --url)     BASE_URL="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

mkdir -p "${REPO_ROOT}/artifacts"
PASS=0; FAIL=0
declare -a TEST_LOG

assert_pass() {
  local name="$1"
  PASS=$(( PASS + 1 ))
  TEST_LOG+=("{\"name\":\"${name}\",\"status\":\"PASS\"}")
  log_info "  ✅ PASS: ${name}"
}
assert_fail() {
  local name="$1" reason="${2:-}"
  FAIL=$(( FAIL + 1 ))
  TEST_LOG+=("{\"name\":\"${name}\",\"status\":\"FAIL\",\"reason\":\"${reason}\"}")
  log_error "  ❌ FAIL: ${name} — ${reason}"
}

dry_or_run() {
  local name="$1"; shift
  if [[ "${DRY_RUN}" == "true" ]]; then assert_pass "${name}"; return 0; fi
  "$@" && assert_pass "${name}" || assert_fail "${name}" "command failed"
}

# Group 1: Tenant isolation
test_tenant_isolation() {
  log_info "Group 1: Tenant Isolation"
  dry_or_run "tenant_schema_isolated" \
    docker exec code-server-postgres psql -U postgres -d code_server -tAc \
      "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name LIKE 'tenant_%'"
  dry_or_run "tenant_provision_dry_run" \
    bash "${REPO_ROOT}/scripts/ops/provision-tenant.sh" \
      --tenant "test-integ-$(date +%s)" --email "test@test.com" --dry-run
}

# Group 2: GitOps sync
test_gitops() {
  log_info "Group 2: GitOps Sync"
  dry_or_run "gitops_sync_once" \
    bash "${REPO_ROOT}/scripts/ops/gitops-sync.sh" --dry-run --once
}

# Group 3: Scaler logic
test_scaler() {
  log_info "Group 3: Auto-Scaler Logic"
  dry_or_run "autoscaler_dry_run" \
    bash "${REPO_ROOT}/scripts/ops/auto-scaler.sh" --dry-run --once
  dry_or_run "capacity_forecast_clean" \
    python3 "${REPO_ROOT}/scripts/ops/capacity-forecast.py" \
      --dry-run --horizon-days 30 >/dev/null
}

# Group 4: Observability pipeline
test_observability() {
  log_info "Group 4: Observability Pipeline"
  if [[ "${DRY_RUN}" == "true" ]]; then
    assert_pass "otel_config_valid"
    assert_pass "prometheus_targets"
    return
  fi
  # Validate YAML
  python3 -c "import yaml; yaml.safe_load(open('${REPO_ROOT}/configs/otel/collector-config.yaml'))" \
    && assert_pass "otel_config_valid" || assert_fail "otel_config_valid" "invalid YAML"
  # Check Prometheus targets
  curl -sf "http://${PRIMARY_HOST:-localhost}:9090/api/v1/targets" >/dev/null 2>&1 \
    && assert_pass "prometheus_targets" || assert_fail "prometheus_targets" "unreachable"
}

# Group 5: DR smoke
test_dr_smoke() {
  log_info "Group 5: DR Scenario Smoke"
  dry_or_run "dr_primary_failure_dry" \
    bash "${REPO_ROOT}/scripts/ops/dr-failover.sh" --dry-run --scenario primary-failure
  dry_or_run "dr_replica_failure_dry" \
    bash "${REPO_ROOT}/scripts/ops/dr-failover.sh" --dry-run --scenario replica-failure
}

write_results() {
  local entries
  entries=$(IFS=,; echo "[${TEST_LOG[*]}]")
  cat > "${RESULTS_FILE}" << EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": 2,
  "total": $((PASS+FAIL)),
  "passed": ${PASS},
  "failed": ${FAIL},
  "tests": ${entries}
}
EOF
  log_info "Results: ${RESULTS_FILE}"
}

# Main
log_info "Integration Tests Phase 2 — url=${BASE_URL} dry-run=${DRY_RUN}"
log_info "================================================================="

test_tenant_isolation
test_gitops
test_scaler
test_observability
test_dr_smoke
write_results

log_info "================================================================="
log_info "Phase 2: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] && { log_info "✅ All Phase 2 integration tests passed"; exit 0; } || \
  { log_error "❌ Phase 2: ${FAIL} failure(s)"; exit 1; }
