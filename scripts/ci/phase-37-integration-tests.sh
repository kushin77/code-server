#!/usr/bin/env bash
################################################################################
# @file scripts/ci/phase-37-integration-tests.sh
# @description Integration tests for Phase 37 — Security Response Automation
#
# Groups:
#   1. module      — imports, summary, automation_score
#   2. workflows   — trigger_response, workflow steps, severity threshold
#   3. executors   — notify/revoke/isolate/rotate/quarantine (dry-run)
#   4. ledger      — get_executions, execution persistence
#   5. orchestrator — ops script modes
#   6. regression  — Phase 32/35/36 module imports
#
# @since 2026-05-01
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

PASS=0; FAIL=0
TEST_TMP="${REPO_ROOT}/artifacts/phase37-test-$$"
mkdir -p "${TEST_TMP}"
trap 'rm -rf "${TEST_TMP}"' EXIT

_run_test() {
  local name="$1"; shift
  if "$@" > "${TEST_TMP}/${name}.log" 2>&1; then
    log_success "  PASS  ${name}"; (( PASS++ )) || true
  else
    log_error "  FAIL  ${name}"
    tail -5 "${TEST_TMP}/${name}.log" | sed 's/^/         /' >&2
    (( FAIL++ )) || true
  fi
}

################################################################################
# Group 1: Module tests
################################################################################

test_module_imports() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, get_executions, automation_score, summary,
    ResponseTrigger, TriggerSource, ResponseType, ExecutionStatus,
    SeverityThreshold, ResponseWorkflow, WorkflowStep, StepExecution
)
print('Phase 37 imports OK')
"
}

test_summary_structure() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.response_automation import summary
s = summary()
assert isinstance(s, dict)
required = {'total_workflows', 'total_step_executions', 'executions_by_type', 'automation_score'}
missing = required - set(s.keys())
assert not missing, f'summary() missing keys: {missing}'
print('summary() structure OK:', list(s.keys()))
"
}

test_automation_score_range() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.response_automation import automation_score
score = automation_score()
assert 0 <= score <= 20, f'Score {score} out of range'
print(f'automation_score(): {score} (valid 0-20)')
"
}

################################################################################
# Group 2: Workflow tests
################################################################################

test_trigger_response_returns_workflow() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys, uuid
sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, ResponseTrigger, TriggerSource, SeverityThreshold, ResponseWorkflow
)
t = ResponseTrigger(
    trigger_id=str(uuid.uuid4()),
    source=TriggerSource.PHASE36,
    severity='high',
    container_id='code-server-test-1',
    description='test trigger',
)
wf = trigger_response(t, dry_run=True, severity_threshold=SeverityThreshold.ANY)
assert wf is not None, 'high severity should produce a workflow'
assert isinstance(wf, ResponseWorkflow)
assert wf.workflow_id
assert len(wf.steps) >= 1, 'Workflow should have at least 1 step'
print(f'trigger_response OK: workflow_id={wf.workflow_id[:8]}... steps={len(wf.steps)}')
"
}

test_trigger_below_threshold_returns_none() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys, uuid
sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, ResponseTrigger, TriggerSource, SeverityThreshold
)
t = ResponseTrigger(
    trigger_id=str(uuid.uuid4()),
    source=TriggerSource.MANUAL,
    severity='low',
    container_id='code-server-low-1',
    description='low severity test',
)
wf = trigger_response(t, dry_run=True, severity_threshold=SeverityThreshold.HIGH)
assert wf is None, f'low severity below high threshold should return None, got {wf}'
print('trigger_response(low, threshold=high): None — OK')
"
}

test_critical_trigger_has_multiple_steps() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys, uuid
sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, ResponseTrigger, TriggerSource, SeverityThreshold
)
t = ResponseTrigger(
    trigger_id=str(uuid.uuid4()),
    source=TriggerSource.PHASE36,
    severity='critical',
    container_id='code-server-crit-1',
    description='critical security violation detected',
)
wf = trigger_response(t, dry_run=True, severity_threshold=SeverityThreshold.ANY)
assert wf is not None
assert len(wf.steps) >= 2, f'Critical trigger should have >= 2 steps, got {len(wf.steps)}'
types = [s.response_type.value for s in wf.steps]
print(f'Critical trigger: {len(wf.steps)} steps: {types}')
"
}

test_phase36_secret_trigger_includes_rotate() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys, uuid
sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, ResponseTrigger, TriggerSource, ResponseType, SeverityThreshold
)
t = ResponseTrigger(
    trigger_id=str(uuid.uuid4()),
    source=TriggerSource.PHASE36,
    severity='high',
    container_id='code-server-1',
    description='secret exposed in environment variables',
)
wf = trigger_response(t, dry_run=True, severity_threshold=SeverityThreshold.ANY)
assert wf is not None
types = [s.response_type for s in wf.steps]
assert ResponseType.AUTO_ROTATE in types, f'Phase36 secret trigger should include AUTO_ROTATE, got {[t.value for t in types]}'
print(f'Phase36 secret trigger includes AUTO_ROTATE: OK')
"
}

test_phase35_forensic_trigger_includes_quarantine() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys, uuid
sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, ResponseTrigger, TriggerSource, ResponseType, SeverityThreshold
)
t = ResponseTrigger(
    trigger_id=str(uuid.uuid4()),
    source=TriggerSource.PHASE35,
    severity='critical',
    container_id='code-server-1',
    description='forensic trace completed — root cause confirmed',
)
wf = trigger_response(t, dry_run=True, severity_threshold=SeverityThreshold.ANY)
assert wf is not None
types = [s.response_type for s in wf.steps]
assert ResponseType.AUTO_QUARANTINE in types, f'Phase35 critical should include QUARANTINE, got {[t.value for t in types]}'
print(f'Phase35 critical trigger includes AUTO_QUARANTINE: OK')
"
}

################################################################################
# Group 3: Executor tests
################################################################################

test_notify_executor_dry_run() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.response_automation import WorkflowStep, ResponseType, _execute_step
step = WorkflowStep(
    step_id='s1',
    response_type=ResponseType.AUTO_NOTIFY,
    description='test notify',
    target='security-channel',
    parameters={'message': 'test alert', 'channel': 'security-alerts'},
)
rec = _execute_step(step, 'wf-test-001', dry_run=True)
assert rec.status.value == 'success', f'Expected success, got {rec.status}'
assert 'DRY-RUN' in rec.result or 'dry' in rec.result.lower() or 'sent' in rec.result.lower(), \
    f'Expected DRY-RUN indicator in result: {rec.result}'
print(f'AUTO_NOTIFY dry_run: status={rec.status.value} result={rec.result[:60]}')
"
}

test_isolate_executor_dry_run() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.response_automation import WorkflowStep, ResponseType, _execute_step
step = WorkflowStep(
    step_id='s2',
    response_type=ResponseType.AUTO_ISOLATE,
    description='isolate container',
    target='code-server-test-1',
    parameters={'network_policy': 'deny-all'},
)
rec = _execute_step(step, 'wf-test-002', dry_run=True)
assert rec.status.value == 'success'
print(f'AUTO_ISOLATE dry_run: status={rec.status.value} result={rec.result[:60]}')
"
}

################################################################################
# Group 4: Ledger tests
################################################################################

test_get_executions_returns_list() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.response_automation import get_executions
execs = get_executions()
assert isinstance(execs, list), f'Expected list, got {type(execs)}'
print(f'get_executions(): {len(execs)} records — OK')
"
}

test_get_executions_filtered_by_workflow() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys, uuid
sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, get_executions, ResponseTrigger, TriggerSource, SeverityThreshold
)
t = ResponseTrigger(
    trigger_id=str(uuid.uuid4()),
    source=TriggerSource.MANUAL,
    severity='high',
    container_id='code-server-ledger-1',
    description='ledger test trigger',
)
wf = trigger_response(t, dry_run=True, severity_threshold=SeverityThreshold.ANY)
assert wf is not None

filtered = get_executions(wf.workflow_id)
assert len(filtered) == len(wf.steps), \
    f'Expected {len(wf.steps)} executions for workflow, got {len(filtered)}'
print(f'get_executions(workflow_id): {len(filtered)} records (matches {len(wf.steps)} steps) — OK')
"
}

################################################################################
# Group 5: Orchestrator
################################################################################

test_orchestrator_exists() {
  [[ -f "${REPO_ROOT}/scripts/ops/phase-37-response-automation.sh" ]]
}

test_orchestrator_has_traps() {
  grep -q "trap.*ERR" "${REPO_ROOT}/scripts/ops/phase-37-response-automation.sh"
}

test_orchestrator_help() {
  local out
  out="$(bash "${REPO_ROOT}/scripts/ops/phase-37-response-automation.sh" --help 2>&1)" || true
  echo "${out}" | grep -qiE "usage|mode|status|trigger|demo|replay"
}

test_orchestrator_status() {
  local out
  out="$(bash "${REPO_ROOT}/scripts/ops/phase-37-response-automation.sh" --mode status 2>&1)" || true
  echo "${out}" | grep -qiE "score|workflow|automation|phase.37"
}

test_orchestrator_demo() {
  local out
  out="$(bash "${REPO_ROOT}/scripts/ops/phase-37-response-automation.sh" --mode demo 2>&1)" || true
  echo "${out}" | grep -qiE "demo|scenario|workflow|automation|phase.37"
}

################################################################################
# Group 6: Regression
################################################################################

test_phase36_imports() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import (
    evaluate_policies, policy_score, summary, get_policies
)
print('Phase 36 imports OK, policies:', len(get_policies()))
"
}

test_phase35_imports() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.forensics_engine import (
    correlate_events, forensic_score, summary
)
print('Phase 35 imports OK')
"
}

test_phase32_imports() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.adaptive_response import (
    classify_tier, select_actions, AnomalySignal
)
print('Phase 32 imports OK')
"
}

################################################################################
# Runner
################################################################################

log_info "Starting Phase 37 Integration Tests"
echo ""

log_info "--- Group 1: Module ---"
_run_test "module_imports"                    test_module_imports
_run_test "summary_structure"                 test_summary_structure
_run_test "automation_score_range"            test_automation_score_range

log_info "--- Group 2: Workflows ---"
_run_test "trigger_returns_workflow"          test_trigger_response_returns_workflow
_run_test "trigger_below_threshold_none"      test_trigger_below_threshold_returns_none
_run_test "critical_has_multiple_steps"       test_critical_trigger_has_multiple_steps
_run_test "phase36_secret_includes_rotate"    test_phase36_secret_trigger_includes_rotate
_run_test "phase35_forensic_quarantine"       test_phase35_forensic_trigger_includes_quarantine

log_info "--- Group 3: Executors ---"
_run_test "notify_dry_run"                    test_notify_executor_dry_run
_run_test "isolate_dry_run"                   test_isolate_executor_dry_run

log_info "--- Group 4: Ledger ---"
_run_test "get_executions_returns_list"       test_get_executions_returns_list
_run_test "get_executions_filtered"           test_get_executions_filtered_by_workflow

log_info "--- Group 5: Orchestrator ---"
_run_test "orchestrator_exists"               test_orchestrator_exists
_run_test "orchestrator_has_traps"            test_orchestrator_has_traps
_run_test "orchestrator_help"                 test_orchestrator_help
_run_test "orchestrator_status"               test_orchestrator_status
_run_test "orchestrator_demo"                 test_orchestrator_demo

log_info "--- Group 6: Regression ---"
_run_test "phase36_imports"                   test_phase36_imports
_run_test "phase35_imports"                   test_phase35_imports
_run_test "phase32_imports"                   test_phase32_imports

echo ""
echo "======================================="
echo " Phase 37 Integration Test Results"
echo "======================================="
printf " PASS:  %d\n" "${PASS}"
printf " FAIL:  %d\n" "${FAIL}"
printf " TOTAL: %d\n" "$(( PASS + FAIL ))"
echo "======================================="

if [[ "${FAIL}" -eq 0 ]]; then
  log_success "✓ All tests passed!"
  exit 0
else
  log_error "✗ ${FAIL} test(s) failed"
  exit 1
fi
