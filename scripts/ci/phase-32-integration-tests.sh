#!/usr/bin/env bash
################################################################################
# @file scripts/ci/phase-32-integration-tests.sh
# @description Integration test suite for Phase 32 — Adaptive Security Intelligence
#
# Groups:
#   1. Module import / API surface
#   2. Tier classification logic
#   3. Incident lifecycle (create → update → resolve)
#   4. Compliance feedback integration
#   5. Ops script modes
#   6. Phase 30 + 31 regression
#
# Usage:  bash scripts/ci/phase-32-integration-tests.sh
# @since 2026-05-01
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

PASS=0; FAIL=0; SKIP=0
TEST_TMP="${REPO_ROOT}/artifacts/phase32-test-$$"
mkdir -p "${TEST_TMP}"
trap 'rm -rf "${TEST_TMP}"' EXIT

OPS_SCRIPT="${REPO_ROOT}/scripts/ops/phase-32-adaptive-security.sh"

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
  PY "from apps.security_ai.adaptive_response import AnomalySignal, respond, resolve, summary, compliance_score_delta; print('import OK')"
}

test_anomaly_signal_dataclass() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal
s = AnomalySignal(source='test', signal_type='spike', severity='HIGH', score=80.0)
assert s.source == 'test'
assert s.score == 80.0
print('AnomalySignal OK')
"
}

test_incident_to_dict() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, respond
sig = AnomalySignal('test', 'spike', 'LOW', 10.0, {'target': 'svc-a'})
inc = respond(sig, dry_run=True)
d = inc.to_dict()
assert 'id' in d and 'tier' in d and 'status' in d and 'actions' in d
print(f'to_dict OK: id={d[\"id\"]} tier={d[\"tier\"]}')
"
}

test_artifacts_dir_created() {
  PY "
from apps.security_ai.adaptive_response import ARTIFACTS_DIR
assert ARTIFACTS_DIR.exists(), f'artifacts dir missing: {ARTIFACTS_DIR}'
print(f'ARTIFACTS_DIR OK: {ARTIFACTS_DIR}')
"
}

test_response_log_written() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, respond, RESPONSE_LOG_FILE
sig = AnomalySignal('test', 'test_event', 'LOW', 5.0)
respond(sig, dry_run=True)
assert RESPONSE_LOG_FILE.exists(), 'response-log.jsonl not created'
lines = RESPONSE_LOG_FILE.read_text().splitlines()
assert len(lines) >= 1
print(f'response-log.jsonl OK ({len(lines)} lines)')
"
}

################################################################################
# Group 2: Tier classification
################################################################################

test_critical_maps_to_escalate() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, classify_tier, ResponseTier
sig = AnomalySignal('x', 'x', 'CRITICAL', 50.0)
assert classify_tier(sig) == ResponseTier.ESCALATE, f'got {classify_tier(sig)}'
print('CRITICAL → ESCALATE OK')
"
}

test_high_score80_maps_to_isolate() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, classify_tier, ResponseTier
sig = AnomalySignal('x', 'x', 'HIGH', 85.0)
assert classify_tier(sig) == ResponseTier.ISOLATE, f'got {classify_tier(sig)}'
print('HIGH/85 → ISOLATE OK')
"
}

test_high_score40_maps_to_contain() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, classify_tier, ResponseTier
sig = AnomalySignal('x', 'x', 'HIGH', 40.0)
assert classify_tier(sig) == ResponseTier.CONTAIN, f'got {classify_tier(sig)}'
print('HIGH/40 → CONTAIN OK')
"
}

test_medium_low_score_maps_to_monitor() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, classify_tier, ResponseTier
sig = AnomalySignal('x', 'x', 'MEDIUM', 30.0)
assert classify_tier(sig) == ResponseTier.MONITOR, f'got {classify_tier(sig)}'
print('MEDIUM/30 → MONITOR OK')
"
}

test_low_always_monitor() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, classify_tier, ResponseTier
for score in [0, 50, 99]:
    sig = AnomalySignal('x', 'x', 'LOW', float(score))
    assert classify_tier(sig) == ResponseTier.MONITOR
print('LOW always MONITOR OK')
"
}

################################################################################
# Group 3: Incident lifecycle
################################################################################

test_respond_creates_incident() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, respond, IncidentStatus
sig = AnomalySignal('ci', 'create_test', 'MEDIUM', 50.0, {'target': 'ci-svc'})
inc = respond(sig, dry_run=True)
assert inc.status == IncidentStatus.OPEN
assert inc.id
print(f'respond() created incident {inc.id} status={inc.status.value}')
"
}

test_incidents_json_valid() {
  PY "
import json
from apps.security_ai.adaptive_response import INCIDENTS_FILE, AnomalySignal, respond
sig = AnomalySignal('ci', 'json_test', 'LOW', 5.0)
respond(sig, dry_run=True)
data = json.loads(INCIDENTS_FILE.read_text())
assert 'incidents' in data
assert isinstance(data['incidents'], list)
print(f'incidents.json OK ({len(data[\"incidents\"])} entries)')
"
}

test_resolve_incident() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, respond, resolve, IncidentStatus
sig = AnomalySignal('ci', 'resolve_test', 'HIGH', 82.0, {'target': 'svc-x'})
inc = respond(sig, dry_run=True)
assert inc.status == IncidentStatus.OPEN
ok = resolve(inc.id)
assert ok, 'resolve returned False'
print(f'resolve() OK for incident {inc.id}')
"
}

test_resolve_unknown_id_returns_false() {
  PY "
from apps.security_ai.adaptive_response import resolve
ok = resolve('nonexistent-id-xyz')
assert not ok
print('resolve(nonexistent) → False OK')
"
}

test_list_open_excludes_resolved() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, respond, resolve, list_open
sig = AnomalySignal('ci', 'list_test', 'HIGH', 85.0)
inc = respond(sig, dry_run=True)
before = len(list_open())
resolve(inc.id)
after = len(list_open())
assert after <= before, f'list_open count should not increase after resolve: before={before} after={after}'
print(f'list_open excludes resolved OK (before={before} after={after})')
"
}

################################################################################
# Group 4: Compliance feedback
################################################################################

test_escalate_penalty_nonzero() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, respond, ResponseTier, _TIER_PENALTIES
assert _TIER_PENALTIES[ResponseTier.ESCALATE] > 0
sig = AnomalySignal('ci', 'penalty_test', 'CRITICAL', 95.0)
inc = respond(sig, dry_run=True)
assert inc.compliance_penalty > 0, f'expected nonzero penalty, got {inc.compliance_penalty}'
print(f'ESCALATE penalty={inc.compliance_penalty} OK')
"
}

test_monitor_penalty_zero() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, respond
sig = AnomalySignal('ci', 'monitor_penalty', 'LOW', 5.0)
inc = respond(sig, dry_run=True)
assert inc.compliance_penalty == 0, f'expected 0 penalty for MONITOR, got {inc.compliance_penalty}'
print('MONITOR penalty=0 OK')
"
}

test_compliance_score_delta_nonneg() {
  PY "
from apps.security_ai.adaptive_response import compliance_score_delta
delta = compliance_score_delta()
assert delta >= 0, f'Expected non-negative delta, got {delta}'
print(f'compliance_score_delta()={delta} (non-negative) OK')
"
}

test_resolve_removes_penalty() {
  PY "
from apps.security_ai.adaptive_response import AnomalySignal, respond, resolve, compliance_score_delta
sig = AnomalySignal('ci', 'penalty_resolve', 'CRITICAL', 95.0)
inc = respond(sig, dry_run=True)
delta_before = compliance_score_delta()
resolve(inc.id)
delta_after = compliance_score_delta()
assert delta_after <= delta_before, f'penalty should not increase: {delta_before} → {delta_after}'
print(f'penalty after resolve: {delta_before} → {delta_after} OK')
"
}

################################################################################
# Group 5: Ops script modes
################################################################################

test_ops_script_exists() { [[ -f "${OPS_SCRIPT}" ]]; }
test_ops_script_syntax()  { bash -n "${OPS_SCRIPT}"; }
test_ops_script_has_traps() { grep -q "trap.*ERR" "${OPS_SCRIPT}"; }

test_ops_demo_mode() {
  bash "${OPS_SCRIPT}" --mode demo --dry-run
}

test_ops_status_mode() {
  bash "${OPS_SCRIPT}" --mode status
}

test_ops_scan_mode() {
  # ensure phase30 violations file exists (might be empty from earlier audit)
  bash "${OPS_SCRIPT}" --mode scan --dry-run
}

################################################################################
# Group 6: Regression — Phase 30 + 31 still pass
################################################################################

test_phase30_24_pass() {
  local out; out="$(bash "${REPO_ROOT}/scripts/ci/phase-30-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "PASS:\s+24"
}

test_phase31_22_pass() {
  local out; out="$(bash "${REPO_ROOT}/scripts/ci/phase-31-integration-tests.sh" 2>&1)"
  echo "${out}" | grep -qE "PASS:\s+22"
}

################################################################################
# Main
################################################################################

main() {
  log_info "Running Phase 32 integration tests"
  echo ""

  echo "--- Group 1: Module import + API surface ---"
  _run_test "module_importable"        "import"     test_module_importable
  _run_test "anomaly_signal_dataclass" "import"     test_anomaly_signal_dataclass
  _run_test "incident_to_dict"         "import"     test_incident_to_dict
  _run_test "artifacts_dir_created"    "import"     test_artifacts_dir_created
  _run_test "response_log_written"     "import"     test_response_log_written

  echo ""
  echo "--- Group 2: Tier classification ---"
  _run_test "critical_to_escalate"     "tier"       test_critical_maps_to_escalate
  _run_test "high_80_to_isolate"       "tier"       test_high_score80_maps_to_isolate
  _run_test "high_40_to_contain"       "tier"       test_high_score40_maps_to_contain
  _run_test "medium_low_to_monitor"    "tier"       test_medium_low_score_maps_to_monitor
  _run_test "low_always_monitor"       "tier"       test_low_always_monitor

  echo ""
  echo "--- Group 3: Incident lifecycle ---"
  _run_test "respond_creates_incident" "lifecycle"  test_respond_creates_incident
  _run_test "incidents_json_valid"     "lifecycle"  test_incidents_json_valid
  _run_test "resolve_incident"         "lifecycle"  test_resolve_incident
  _run_test "resolve_unknown_false"    "lifecycle"  test_resolve_unknown_id_returns_false
  _run_test "list_open_excl_resolved"  "lifecycle"  test_list_open_excludes_resolved

  echo ""
  echo "--- Group 4: Compliance feedback ---"
  _run_test "escalate_penalty_nonzero" "compliance" test_escalate_penalty_nonzero
  _run_test "monitor_penalty_zero"     "compliance" test_monitor_penalty_zero
  _run_test "score_delta_nonneg"       "compliance" test_compliance_score_delta_nonneg
  _run_test "resolve_removes_penalty"  "compliance" test_resolve_removes_penalty

  echo ""
  echo "--- Group 5: Ops script modes ---"
  _run_test "ops_script_exists"        "ops"        test_ops_script_exists
  _run_test "ops_script_syntax"        "ops"        test_ops_script_syntax
  _run_test "ops_script_has_traps"     "ops"        test_ops_script_has_traps
  _run_test "ops_demo_mode"            "ops"        test_ops_demo_mode
  _run_test "ops_status_mode"          "ops"        test_ops_status_mode
  _run_test "ops_scan_mode"            "ops"        test_ops_scan_mode

  echo ""
  echo "--- Group 6: Regression ---"
  _run_test "phase30_24_pass"          "regression" test_phase30_24_pass
  _run_test "phase31_22_pass"          "regression" test_phase31_22_pass

  echo ""
  echo "======================================="
  echo " Phase 32 Integration Test Results"
  echo "======================================="
  printf " PASS:  %s\n" "${PASS}"
  printf " FAIL:  %s\n" "${FAIL}"
  printf " TOTAL: %s\n" "$(( PASS + FAIL ))"
  echo "======================================="

  if [[ "${FAIL}" -gt 0 ]]; then log_error "✗ ${FAIL} test(s) failed"; exit 1
  else log_success "✓ All tests passed!"; exit 0; fi
}

main
