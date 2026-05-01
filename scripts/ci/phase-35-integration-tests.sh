#!/usr/bin/env bash
################################################################################
# @file scripts/ci/phase-35-integration-tests.sh
# @description Integration test suite for Phase 35 — Event Correlation & Forensics
#
# Groups:
#   1. Module import + API surface
#   2. Event correlation
#   3. Root cause analysis
#   4. Forensic scoring
#   5. Ops script modes
#   6. Phase 30-34 regression
#
# @since 2026-05-01
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

PASS=0; FAIL=0
TEST_TMP="${REPO_ROOT}/artifacts/phase35-test-$$"
mkdir -p "${TEST_TMP}"
trap 'rm -rf "${TEST_TMP}"' EXIT

OPS_SCRIPT="${REPO_ROOT}/scripts/ops/phase-35-forensics.sh"

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
  PY "from apps.security_ai.forensics_engine import Event, EventCorrelation, ForensicTrace, analyze_root_cause, forensic_score; print('import OK')"
}

test_event_dataclass() {
  PY "
from apps.security_ai.forensics_engine import Event, EventSource
e = Event('evt-1', EventSource.RESILIENCE_DEGRADATION, 'pod-1', 'memory_leak', 'mem > threshold', 'HIGH', '2026-05-01T19:00:00Z')
assert e.id == 'evt-1'
assert e.source == EventSource.RESILIENCE_DEGRADATION
print('Event dataclass OK')
"
}

test_forensic_trace_dataclass() {
  PY "
from apps.security_ai.forensics_engine import ForensicTrace
trace = ForensicTrace('tr-1', 'evt-root', ['evt-1', 'evt-2'], 60, 2, 0.9, 'test')
assert trace.timeline_seconds == 60
assert trace.impact_count == 2
print('ForensicTrace dataclass OK')
"
}

################################################################################
# Group 2: Event correlation
################################################################################

test_temporal_correlation() {
  PY "
from apps.security_ai.forensics_engine import Event, EventSource, correlate_events
from datetime import datetime, timedelta
now = datetime.utcnow().isoformat() + 'Z'
later = (datetime.utcnow() + timedelta(seconds=30)).isoformat() + 'Z'
e1 = Event('evt-1', EventSource.RESILIENCE_DEGRADATION, 'pod-1', 'memory_leak', 'desc', 'HIGH', now)
e2 = Event('evt-2', EventSource.RESILIENCE_DEGRADATION, 'pod-1', 'oom_killed', 'desc', 'CRITICAL', later)
corr = correlate_events(e1, e2)
assert corr is not None
print(f'Temporal correlation: {corr.correlation_type.value}')
"
}

test_resource_correlation() {
  PY "
from apps.security_ai.forensics_engine import Event, EventSource, correlate_events
e1 = Event('evt-1', EventSource.RESILIENCE_DEGRADATION, 'api-pod-1', 'high_cpu', 'desc', 'MEDIUM', '2026-05-01T19:00:00Z')
e2 = Event('evt-2', EventSource.SECURITY_INCIDENT, 'api-pod-1', 'security_scan', 'desc', 'MEDIUM', '2026-05-01T19:00:05Z')
corr = correlate_events(e1, e2)
assert corr is not None
print('Resource correlation OK')
"
}

test_pattern_correlation() {
  PY "
from apps.security_ai.forensics_engine import Event, EventSource, correlate_events
from datetime import datetime, timedelta
now = datetime.utcnow().isoformat() + 'Z'
later = (datetime.utcnow() + timedelta(seconds=25)).isoformat() + 'Z'
e1 = Event('evt-1', EventSource.RESILIENCE_DEGRADATION, 'db', 'memory_leak', 'desc', 'HIGH', now)
e2 = Event('evt-2', EventSource.RESILIENCE_DEGRADATION, 'db', 'oom_killed', 'desc', 'CRITICAL', later)
corr = correlate_events(e1, e2)
assert corr is not None
print(f'Pattern correlation: {corr.correlation_type.value}')
"
}

################################################################################
# Group 3: Root cause analysis
################################################################################

test_root_cause_analysis() {
  PY "
from apps.security_ai.forensics_engine import Event, EventSource, correlate_events, analyze_root_cause
from datetime import datetime, timedelta
events = [
    Event('evt-1', EventSource.RESILIENCE_DEGRADATION, 'pod', 'memory_leak', 'desc', 'HIGH', datetime.utcnow().isoformat() + 'Z'),
    Event('evt-2', EventSource.RESILIENCE_DEGRADATION, 'pod', 'oom_killed', 'desc', 'CRITICAL', (datetime.utcnow() + timedelta(seconds=30)).isoformat() + 'Z'),
]
corrs = []
for i, e1 in enumerate(events):
    for e2 in events[i+1:]:
        c = correlate_events(e1, e2)
        if c:
            corrs.append(c)

trace = analyze_root_cause(events, corrs)
assert trace is not None
print(f'Root cause trace: {trace.id}')
"
}

test_forensic_trace_structure() {
  PY "
from apps.security_ai.forensics_engine import analyze_incident
trace = analyze_incident('test-1')
if trace:
    assert 'event_chain' in trace.__dict__
    assert 'confidence' in trace.__dict__
    print('Forensic trace structure OK')
"
}

################################################################################
# Group 4: Forensic scoring
################################################################################

test_forensic_score_range() {
  PY "
from apps.security_ai.forensics_engine import forensic_score
score = forensic_score()
assert 0 <= score <= 15, f'Score {score} out of range'
print(f'forensic_score()={score} (0-15) OK')
"
}

test_forensic_summary_structure() {
  PY "
from apps.security_ai.forensics_engine import summary
s = summary()
assert 'total_forensic_traces' in s
assert 'total_correlations' in s
assert 'high_confidence_corrs' in s
assert 'forensic_score' in s
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
test_ops_analyze_mode()   { bash "${OPS_SCRIPT}" --mode analyze --incident test; }

################################################################################
# Group 6: Regression — all previous phases
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

test_phase33_25_pass() {
  local out; out="$(bash "${REPO_ROOT}/scripts/ci/phase-33-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "PASS:\s+25"
}

test_phase34_22_pass() {
  local out; out="$(bash "${REPO_ROOT}/scripts/ci/phase-34-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "PASS:\s+22"
}

################################################################################
# Main
################################################################################

main() {
  log_info "Running Phase 35 integration tests"
  echo ""

  echo "--- Group 1: Module import + API surface ---"
  _run_test "module_importable"      "import"    test_module_importable
  _run_test "event_dataclass"        "import"    test_event_dataclass
  _run_test "forensic_trace_cls"     "import"    test_forensic_trace_dataclass

  echo ""
  echo "--- Group 2: Event correlation ---"
  _run_test "temporal_correlation"   "correlation" test_temporal_correlation
  _run_test "resource_correlation"   "correlation" test_resource_correlation
  _run_test "pattern_correlation"    "correlation" test_pattern_correlation

  echo ""
  echo "--- Group 3: Root cause analysis ---"
  _run_test "root_cause_analysis"    "rootcause"   test_root_cause_analysis
  _run_test "forensic_trace_struct"  "rootcause"   test_forensic_trace_structure

  echo ""
  echo "--- Group 4: Forensic scoring ---"
  _run_test "score_in_range"         "scoring"     test_forensic_score_range
  _run_test "summary_structure"      "scoring"     test_forensic_summary_structure

  echo ""
  echo "--- Group 5: Ops script modes ---"
  _run_test "ops_script_exists"      "ops"         test_ops_script_exists
  _run_test "ops_script_syntax"      "ops"         test_ops_script_syntax
  _run_test "ops_script_has_traps"   "ops"         test_ops_script_has_traps
  _run_test "ops_demo_mode"          "ops"         test_ops_demo_mode
  _run_test "ops_summary_mode"       "ops"         test_ops_summary_mode
  _run_test "ops_analyze_mode"       "ops"         test_ops_analyze_mode

  echo ""
  echo "--- Group 6: Regression ---"
  _run_test "phase30_24_pass"        "regression"  test_phase30_24_pass
  _run_test "phase31_22_pass"        "regression"  test_phase31_22_pass
  _run_test "phase32_27_pass"        "regression"  test_phase32_27_pass
  _run_test "phase33_25_pass"        "regression"  test_phase33_25_pass
  _run_test "phase34_22_pass"        "regression"  test_phase34_22_pass

  echo ""
  echo "======================================="
  echo " Phase 35 Integration Test Results"
  echo "======================================="
  printf " PASS:  %s\n" "${PASS}"
  printf " FAIL:  %s\n" "${FAIL}"
  printf " TOTAL: %s\n" "$(( PASS + FAIL ))"
  echo "======================================="

  if [[ "${FAIL}" -gt 0 ]]; then log_error "✗ ${FAIL} test(s) failed"; exit 1
  else log_success "✓ All tests passed!"; exit 0; fi
}

main
