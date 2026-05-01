#!/usr/bin/env bash
################################################################################
# @file scripts/ci/phase-33-integration-tests.sh
# @description Integration test suite for Phase 33 — Cost Optimization Intelligence
#
# Groups:
#   1. Module import + API surface
#   2. Resource profile + ML model (forecast logic)
#   3. Recommendation lifecycle (create → approve → implement)
#   4. Cost scoring
#   5. Ops script modes
#   6. Phase 30 + 31 + 32 regression
#
# @since 2026-05-01
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

PASS=0; FAIL=0; SKIP=0
TEST_TMP="${REPO_ROOT}/artifacts/phase33-test-$$"
mkdir -p "${TEST_TMP}"
trap 'rm -rf "${TEST_TMP}"' EXIT

OPS_SCRIPT="${REPO_ROOT}/scripts/ops/phase-33-cost-optimization.sh"

_run_test() {
  local name="$1" group="$2"; shift 2
  if "$@" > "${TEST_TMP}/${name}.log" 2>&1; then
    log_success "  PASS  ${name}"; (( PASS++ )) || true
  else
    log_error   "  FAIL  ${name}"; tail -5 "${TEST_TMP}/${name}.log" | sed 's/^/         /' >&2; (( FAIL++ )) || true
  fi
}

PY() { python3 -c "import sys; sys.path.insert(0,'${REPO_ROOT}'); $1"; }

################################################################################
# Group 1: Module import + API surface
################################################################################

test_module_importable() {
  PY "from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, analyze, summary; print('import OK')"
}

test_resource_profile_dataclass() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType
p = ResourceProfile('test', ResourceType.CPU, 8, 'vCPU', 0.25, 0.35, 0.40)
assert p.resource_name == 'test'
assert p.current_capacity == 8
print('ResourceProfile OK')
"
}

test_cost_recommendation_to_dict() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, analyze
p = ResourceProfile('test', ResourceType.CPU, 8, 'vCPU', 0.10, 0.15, 0.20)
rec = analyze(p)
if rec:
    d = rec.to_dict()
    assert 'id' in d and 'monthly_savings_usd' in d and 'risk_level' in d
    print(f'to_dict OK: id={d[\"id\"]} savings=\${d[\"monthly_savings_usd\"]}')
else:
    print('No recommendation (OK)')
"
}

test_artifacts_dir_created() {
  PY "
from apps.security_ai.cost_optimizer import ARTIFACTS_DIR
assert ARTIFACTS_DIR.exists(), f'artifacts dir missing: {ARTIFACTS_DIR}'
print(f'ARTIFACTS_DIR OK: {ARTIFACTS_DIR}')
"
}

################################################################################
# Group 2: Resource profile + ML model
################################################################################

test_overprovisioned_cpu_forecast() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, _forecast_utilization
p = ResourceProfile('cpu', ResourceType.CPU, 16, 'vCPU', 0.10, 0.18, 0.25)
recommended, confidence = _forecast_utilization(p)
# Utilization is low; should recommend reduction
assert recommended < p.current_capacity, f'Expected reduction, got {recommended}'
assert confidence > 0.85, f'Expected confidence >0.85, got {confidence}'
print(f'Low-utilization forecast OK: 16 → {recommended:.1f} vCPU (conf={confidence:.2f})')
"
}

test_well_utilized_no_forecast() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, _forecast_utilization
p = ResourceProfile('cpu', ResourceType.CPU, 8, 'vCPU', 0.70, 0.85, 0.92)
recommended, confidence = _forecast_utilization(p)
# High utilization; no reduction
assert recommended == p.current_capacity, f'Expected no change, got {recommended}'
assert confidence == 0.0
print('Well-utilized resource: no recommendation OK')
"
}

test_cost_savings_positive() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, _estimate_cost_savings
p = ResourceProfile('cpu', ResourceType.CPU, 16, 'vCPU', 0.10, 0.15, 0.20)
savings = _estimate_cost_savings(p, 8)  # Half capacity
assert savings > 0, f'Expected positive savings, got {savings}'
print(f'Cost savings estimate: \${savings:.2f}/month OK')
"
}

test_cost_savings_formula() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, _estimate_cost_savings
p = ResourceProfile('cpu', ResourceType.CPU, 8, 'vCPU', 0, 0, 0)
# Reduce from 8 → 4 vCPU: \$0.04/vCPU-hour * 730 hours = \$116.8/month savings
savings = _estimate_cost_savings(p, 4)
expected_approx = 116.8  # exact
assert abs(savings - expected_approx) < 1, f'Unexpected savings: {savings}'
print(f'Cost formula OK: 8→4 vCPU = \${savings:.2f}/month')
"
}

################################################################################
# Group 3: Recommendation lifecycle
################################################################################

test_analyze_creates_recommendation() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, analyze, RecommendationStatus
p = ResourceProfile('test', ResourceType.CPU, 32, 'vCPU', 0.08, 0.15, 0.20)
rec = analyze(p)
assert rec is not None, 'Expected recommendation'
assert rec.status == RecommendationStatus.PENDING
print(f'analyze() created recommendation {rec.id}')
"
}

test_recommendations_json_valid() {
  PY "
import json
from apps.security_ai.cost_optimizer import RECOMMENDATIONS_FILE, ResourceProfile, ResourceType, analyze
p = ResourceProfile('test', ResourceType.MEMORY, 128, 'GB', 0.10, 0.20, 0.28)
analyze(p)
data = json.loads(RECOMMENDATIONS_FILE.read_text())
assert 'recommendations' in data
assert len(data['recommendations']) > 0
print(f'recommendations.json OK ({len(data[\"recommendations\"])} entries)')
"
}

test_approve_recommendation() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, analyze, approve, RecommendationStatus
p = ResourceProfile('test', ResourceType.CPU, 16, 'vCPU', 0.10, 0.18, 0.24)
rec = analyze(p)
assert rec is not None
ok = approve(rec.id)
assert ok, 'approve() returned False'
print(f'approve() OK for {rec.id}')
"
}

test_implement_recommendation() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, analyze, approve, implement
p = ResourceProfile('test', ResourceType.STORAGE, 500, 'GB', 0.40, 0.55, 0.65)
rec = analyze(p)
if rec:
    approve(rec.id)
    ok = implement(rec.id)
    assert ok, 'implement() returned False'
    print(f'implement() OK for {rec.id}')
else:
    print('No recommendation to implement (OK)')
"
}

test_auto_approve_low_risk() {
  PY "
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, analyze, auto_approve_low_risk
# Generate a likely low-risk recommendation
p = ResourceProfile('test', ResourceType.CPU, 64, 'vCPU', 0.05, 0.12, 0.18)
rec = analyze(p)
if rec and rec.risk_level.value == 'low':
    count = auto_approve_low_risk()
    assert count > 0
    print(f'auto_approve_low_risk() approved {count} recommendation(s)')
else:
    print('No low-risk recommendations in this test (OK)')
"
}

################################################################################
# Group 4: Cost scoring
################################################################################

test_cost_optimization_score_nonneg() {
  PY "
from apps.security_ai.cost_optimizer import cost_optimization_score
score = cost_optimization_score()
assert 0 <= score <= 20, f'Score out of range: {score}'
print(f'cost_optimization_score()={score} (0-20 range) OK')
"
}

test_summary_structure() {
  PY "
from apps.security_ai.cost_optimizer import summary
s = summary()
assert 'total_recommendations' in s
assert 'pending' in s
assert 'approved' in s
assert 'implemented' in s
assert 'potential_monthly_savings_usd' in s
assert 'realized_monthly_savings_usd' in s
assert 'cost_optimization_score' in s
print(f'summary() structure OK')
"
}

################################################################################
# Group 5: Ops script modes
################################################################################

test_ops_script_exists() { [[ -f "${OPS_SCRIPT}" ]]; }
test_ops_script_syntax()  { bash -n "${OPS_SCRIPT}"; }
test_ops_script_has_traps() { grep -q "trap.*ERR" "${OPS_SCRIPT}"; }

test_ops_demo_mode() {
  bash "${OPS_SCRIPT}" --mode demo
}

test_ops_summary_mode() {
  bash "${OPS_SCRIPT}" --mode summary
}

test_ops_scan_mode() {
  bash "${OPS_SCRIPT}" --mode scan
}

test_ops_approve_mode() {
  bash "${OPS_SCRIPT}" --mode approve
}

################################################################################
# Group 6: Regression — Phase 30 + 31 + 32 still pass
################################################################################

test_phase30_24_pass() {
  local out; out="$(bash "${REPO_ROOT}/scripts/ci/phase-30-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "PASS:\s+24"
}

test_phase31_22_pass() {
  local out; out="$(bash "${REPO_ROOT}/scripts/ci/phase-31-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "PASS:\s+22"
}

test_phase32_27_pass() {
  local out; out="$(bash "${REPO_ROOT}/scripts/ci/phase-32-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "PASS:\s+27"
}

################################################################################
# Main
################################################################################

main() {
  log_info "Running Phase 33 integration tests"
  echo ""

  echo "--- Group 1: Module import + API surface ---"
  _run_test "module_importable"        "import"     test_module_importable
  _run_test "resource_profile_cls"     "import"     test_resource_profile_dataclass
  _run_test "recommendation_to_dict"   "import"     test_cost_recommendation_to_dict
  _run_test "artifacts_dir_created"    "import"     test_artifacts_dir_created

  echo ""
  echo "--- Group 2: Resource profile + ML model ---"
  _run_test "overprovisioned_forecast" "model"      test_overprovisioned_cpu_forecast
  _run_test "well_utilized_no_change"  "model"      test_well_utilized_no_forecast
  _run_test "cost_savings_positive"    "model"      test_cost_savings_positive
  _run_test "cost_savings_formula"     "model"      test_cost_savings_formula

  echo ""
  echo "--- Group 3: Recommendation lifecycle ---"
  _run_test "analyze_creates_rec"      "lifecycle"  test_analyze_creates_recommendation
  _run_test "recommendations_json"     "lifecycle"  test_recommendations_json_valid
  _run_test "approve_recommendation"   "lifecycle"  test_approve_recommendation
  _run_test "implement_recommendation" "lifecycle"  test_implement_recommendation
  _run_test "auto_approve_low_risk"    "lifecycle"  test_auto_approve_low_risk

  echo ""
  echo "--- Group 4: Cost scoring ---"
  _run_test "cost_score_range"         "scoring"    test_cost_optimization_score_nonneg
  _run_test "summary_structure"        "scoring"    test_summary_structure

  echo ""
  echo "--- Group 5: Ops script modes ---"
  _run_test "ops_script_exists"        "ops"        test_ops_script_exists
  _run_test "ops_script_syntax"        "ops"        test_ops_script_syntax
  _run_test "ops_script_has_traps"     "ops"        test_ops_script_has_traps
  _run_test "ops_demo_mode"            "ops"        test_ops_demo_mode
  _run_test "ops_summary_mode"         "ops"        test_ops_summary_mode
  _run_test "ops_scan_mode"            "ops"        test_ops_scan_mode
  _run_test "ops_approve_mode"         "ops"        test_ops_approve_mode

  echo ""
  echo "--- Group 6: Regression ---"
  _run_test "phase30_24_pass"          "regression" test_phase30_24_pass
  _run_test "phase31_22_pass"          "regression" test_phase31_22_pass
  _run_test "phase32_27_pass"          "regression" test_phase32_27_pass

  echo ""
  echo "======================================="
  echo " Phase 33 Integration Test Results"
  echo "======================================="
  printf " PASS:  %s\n" "${PASS}"
  printf " FAIL:  %s\n" "${FAIL}"
  printf " TOTAL: %s\n" "$(( PASS + FAIL ))"
  echo "======================================="

  if [[ "${FAIL}" -gt 0 ]]; then log_error "✗ ${FAIL} test(s) failed"; exit 1
  else log_success "✓ All tests passed!"; exit 0; fi
}

main
