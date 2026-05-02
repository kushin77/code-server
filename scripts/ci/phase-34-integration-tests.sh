#!/usr/bin/env bash
################################################################################
# @file scripts/ci/phase-34-integration-tests.sh
# @description Integration test suite for Phase 34 — Infrastructure Resilience
#
# Groups:
#   1. Module import + API surface
#   2. Degradation detection
#   3. Remediation action selection
#   4. Resilience scoring
#   5. Ops script modes
#   6. Phase 30-33 regression
#
# @since 2026-05-01
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

PASS=0; FAIL=0
TEST_TMP="${REPO_ROOT}/artifacts/phase34-test-$$"
mkdir -p "${TEST_TMP}"
trap 'rm -rf "${TEST_TMP}"' EXIT

OPS_SCRIPT="${REPO_ROOT}/scripts/ops/phase-34-resilience.sh"

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
  PY "from apps.security_ai.resilience_engine import HealthMetric, Degradation, detect_and_remediate, resilience_score; print('import OK')"
}

test_health_metric_dataclass() {
  PY "
from apps.security_ai.resilience_engine import HealthMetric
m = HealthMetric('pod-1', 'pod', 'memory_usage', 2.5, 2.0, 'GB')
assert m.resource_id == 'pod-1'
assert m.value == 2.5
print('HealthMetric OK')
"
}

test_degradation_to_dict() {
  PY "
from apps.security_ai.resilience_engine import HealthMetric, detect_and_remediate
m = HealthMetric('test', 'pod', 'cpu_usage', 0.95, 0.80, 'ratio')
action = detect_and_remediate(m, dry_run=True)
assert action is not None
print('detect_and_remediate OK')
"
}

################################################################################
# Group 2: Degradation detection
################################################################################

test_memory_degradation_detected() {
  PY "
from apps.security_ai.resilience_engine import HealthMetric, _detect_degradations
m = HealthMetric('pod', 'pod', 'memory_usage', 3.5, 2.0, 'GB')
deg = _detect_degradations(m)
assert deg is not None
print(f'Memory degradation detected: {deg.degradation_type.value}')
"
}

test_cpu_degradation_detected() {
  PY "
from apps.security_ai.resilience_engine import HealthMetric, _detect_degradations
m = HealthMetric('svc', 'service', 'cpu_usage', 0.92, 0.80, 'ratio')
deg = _detect_degradations(m)
assert deg is not None
print(f'CPU degradation detected: {deg.degradation_type.value}')
"
}

test_no_degradation_within_threshold() {
  PY "
from apps.security_ai.resilience_engine import HealthMetric, _detect_degradations
m = HealthMetric('pod', 'pod', 'cpu_usage', 0.82, 0.80, 'ratio')
deg = _detect_degradations(m)
assert deg is None, f'Expected no degradation, got {deg}'
print('Within-threshold metric: no degradation OK')
"
}

test_severity_classification() {
  PY "
from apps.security_ai.resilience_engine import HealthMetric, _detect_degradations
# Critical: 100% over threshold
m1 = HealthMetric('p1', 'pod', 'memory_usage', 4.0, 2.0, 'GB')
deg1 = _detect_degradations(m1)
assert deg1 and deg1.severity == 'CRITICAL', f'Expected CRITICAL, got {deg1.severity if deg1 else None}'
print(f'Severity classification: {deg1.severity}')
"
}

################################################################################
# Group 3: Remediation action selection
################################################################################

test_remediation_action_selected() {
  PY "
from apps.security_ai.resilience_engine import HealthMetric, detect_and_remediate
m = HealthMetric('pod', 'pod', 'memory_usage', 3.0, 2.0, 'GB')
action = detect_and_remediate(m, dry_run=True)
assert action is not None
assert action.action_type.value in ['restart_container', 'scale_up_replicas', 'drain_connections', 'restart_service']
print(f'Remediation selected: {action.action_type.value}')
"
}

test_remediation_json_valid() {
  PY "
import json
from apps.security_ai.resilience_engine import HealthMetric, detect_and_remediate, REMEDIATIONS_FILE
m = HealthMetric('pod', 'pod', 'cpu_usage', 0.95, 0.80, 'ratio')
detect_and_remediate(m, dry_run=True)
data = json.loads(REMEDIATIONS_FILE.read_text())
assert 'remediations' in data
assert len(data['remediations']) > 0
print(f'remediations.json OK ({len(data[\"remediations\"])} entries)')
"
}

test_remediate_success() {
  PY "
from apps.security_ai.resilience_engine import HealthMetric, detect_and_remediate, remediate_success
m = HealthMetric('pod', 'pod', 'memory_usage', 2.8, 2.0, 'GB')
action = detect_and_remediate(m, dry_run=True)
if action:
    ok = remediate_success(action.id)
    assert ok
    print(f'remediate_success() OK')
"
}

################################################################################
# Group 4: Resilience scoring
################################################################################

test_resilience_score_range() {
  PY "
from apps.security_ai.resilience_engine import resilience_score
score = resilience_score()
assert 0 <= score <= 20, f'Score {score} out of range'
print(f'resilience_score()={score} (0-20) OK')
"
}

test_summary_structure() {
  PY "
from apps.security_ai.resilience_engine import summary
s = summary()
assert 'total_degradations' in s
assert 'open_degradations' in s
assert 'total_remediations' in s
assert 'successful_remediations' in s
assert 'resilience_score' in s
print('summary() structure OK')
"
}

################################################################################
# Group 5: Ops script modes
################################################################################

test_ops_script_exists() { [[ -f "${OPS_SCRIPT}" ]]; }
test_ops_script_syntax()  { bash -n "${OPS_SCRIPT}"; }
test_ops_script_has_traps() { grep -q "trap.*ERR" "${OPS_SCRIPT}"; }
test_ops_demo_mode()      { bash "${OPS_SCRIPT}" --mode demo; }
test_ops_summary_mode()   { bash "${OPS_SCRIPT}" --mode summary; }
test_ops_monitor_mode()   { bash "${OPS_SCRIPT}" --mode monitor; }

################################################################################
# Group 6: Regression — all previous phases
################################################################################

test_phase30_24_pass() {
  local out; out="$(SKIP_REGRESSION=1 timeout 120 bash "${REPO_ROOT}/scripts/ci/phase-30-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "FAIL:\s+0"
}

test_phase31_22_pass() {
  local out; out="$(SKIP_REGRESSION=1 timeout 120 bash "${REPO_ROOT}/scripts/ci/phase-31-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "FAIL:\s+0"
}

test_phase32_27_pass() {
  local out; out="$(SKIP_REGRESSION=1 timeout 120 bash "${REPO_ROOT}/scripts/ci/phase-32-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "FAIL:\s+0"
}

test_phase33_25_pass() {
  local out; out="$(SKIP_REGRESSION=1 timeout 120 bash "${REPO_ROOT}/scripts/ci/phase-33-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "FAIL:\s+0"
}

################################################################################
# Main
################################################################################

main() {
  log_info "Running Phase 34 integration tests"
  echo ""

  echo "--- Group 1: Module import + API surface ---"
  _run_test "module_importable"      "import"    test_module_importable
  _run_test "health_metric_cls"      "import"    test_health_metric_dataclass
  _run_test "degradation_detect"     "import"    test_degradation_to_dict

  echo ""
  echo "--- Group 2: Degradation detection ---"
  _run_test "memory_degradation"     "detection" test_memory_degradation_detected
  _run_test "cpu_degradation"        "detection" test_cpu_degradation_detected
  _run_test "no_degrad_threshold"    "detection" test_no_degradation_within_threshold
  _run_test "severity_classification" "detection" test_severity_classification

  echo ""
  echo "--- Group 3: Remediation action selection ---"
  _run_test "remediation_selected"   "remediate" test_remediation_action_selected
  _run_test "remediations_json"      "remediate" test_remediation_json_valid
  _run_test "remediate_success"      "remediate" test_remediate_success

  echo ""
  echo "--- Group 4: Resilience scoring ---"
  _run_test "score_in_range"         "scoring"   test_resilience_score_range
  _run_test "summary_structure"      "scoring"   test_summary_structure

  echo ""
  echo "--- Group 5: Ops script modes ---"
  _run_test "ops_script_exists"      "ops"       test_ops_script_exists
  _run_test "ops_script_syntax"      "ops"       test_ops_script_syntax
  _run_test "ops_script_has_traps"   "ops"       test_ops_script_has_traps
  _run_test "ops_demo_mode"          "ops"       test_ops_demo_mode
  _run_test "ops_summary_mode"       "ops"       test_ops_summary_mode
  _run_test "ops_monitor_mode"       "ops"       test_ops_monitor_mode

  echo ""
  echo "--- Group 6: Regression ---"
  if [[ "${SKIP_REGRESSION:-0}" != "1" ]]; then
    _run_test "phase30_24_pass"        "regression" test_phase30_24_pass
    _run_test "phase31_22_pass"        "regression" test_phase31_22_pass
    _run_test "phase32_27_pass"        "regression" test_phase32_27_pass
  else
    echo "  [SKIP] Regression tests skipped (called from parent suite)"
  fi
  _run_test "phase33_25_pass"        "regression" test_phase33_25_pass

  echo ""
  echo "======================================="
  echo " Phase 34 Integration Test Results"
  echo "======================================="
  printf " PASS:  %s\n" "${PASS}"
  printf " FAIL:  %s\n" "${FAIL}"
  printf " TOTAL: %s\n" "$(( PASS + FAIL ))"
  echo "======================================="

  if [[ "${FAIL}" -gt 0 ]]; then log_error "✗ ${FAIL} test(s) failed"; exit 1
  else log_success "✓ All tests passed!"; exit 0; fi
}

main
