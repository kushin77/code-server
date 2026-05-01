#!/usr/bin/env bash
################################################################################
# @file scripts/ci/phase-36-integration-tests.sh
# @description Integration tests for Phase 36 — Zero-Trust Policy Engine
#
# Groups:
#   1. module       — imports, get_policies, summary, policy_score
#   2. policies     — built-in policy evaluators
#   3. violations   — evaluate_policies, persist, multiple contexts
#   4. remediations — remediate_violation, status update
#   5. orchestrator — ops script modes
#   6. regression   — Phase 32+34+35 still pass
#
# @since 2026-05-01
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

PASS=0; FAIL=0
TEST_TMP="${REPO_ROOT}/artifacts/phase36-test-$$"
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
from apps.security_ai.policy_engine import (
    get_policies, get_policy_by_id, evaluate_policies,
    remediate_violation, policy_score, summary,
    Policy, PolicyViolation, RemediationRecord,
    PolicyCategory, PolicySeverity, RemediationAction, ViolationStatus
)
print('Phase 36 imports OK')
"
}

test_get_policies_returns_list() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import get_policies
policies = get_policies()
assert len(policies) >= 5, f'Expected at least 5 policies, got {len(policies)}'
print(f'get_policies() returned {len(policies)} policies')
for p in policies:
    print(f'  {p.policy_id}: {p.name} [{p.category.value}]')
"
}

test_get_policy_by_id() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import get_policy_by_id
p = get_policy_by_id('p001')
assert p is not None, 'p001 should exist'
assert p.name == 'no_root_containers', f'Expected no_root_containers, got {p.name}'
print(f'get_policy_by_id(p001): {p.name} — OK')

missing = get_policy_by_id('p999')
assert missing is None, 'p999 should return None'
print('get_policy_by_id(p999): None — OK')
"
}

test_summary_structure() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import summary
s = summary()
assert isinstance(s, dict)
required = {'total_violations', 'open_violations', 'total_remediations',
            'policy_score', 'total_policies', 'violations_by_severity'}
missing = required - set(s.keys())
assert not missing, f'summary() missing keys: {missing}'
print('summary() structure OK:', list(s.keys()))
"
}

################################################################################
# Group 2: Built-in policy evaluators
################################################################################

test_policy_no_root_containers_pass() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import get_policy_by_id
p = get_policy_by_id('p001')
passed, reason = p.evaluate({'user_uid': 1000, 'container_name': 'c1'})
assert passed, f'uid=1000 should pass: {reason}'
print(f'no_root_containers PASS (uid=1000): OK')
"
}

test_policy_no_root_containers_fail() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import get_policy_by_id
p = get_policy_by_id('p001')
passed, reason = p.evaluate({'user_uid': 0, 'container_name': 'c1'})
assert not passed, f'uid=0 should fail but got passed=True'
print(f'no_root_containers FAIL (uid=0): {reason} — correctly detected')
"
}

test_policy_secrets_in_env_fail() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import get_policy_by_id
p = get_policy_by_id('p003')
ctx = {'env_vars': {'DATABASE_PASSWORD': 'secret123', 'APP_NAME': 'code-server'}}
passed, reason = p.evaluate(ctx)
assert not passed, 'PASSWORD in env should fail'
print(f'secrets_not_in_env FAIL detection: {reason} — OK')
"
}

test_policy_secrets_in_env_pass() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import get_policy_by_id
p = get_policy_by_id('p003')
ctx = {'env_vars': {'APP_NAME': 'code-server', 'LOG_LEVEL': 'info'}}
passed, reason = p.evaluate(ctx)
assert passed, f'Clean env should pass: {reason}'
print(f'secrets_not_in_env PASS (no sensitive vars): OK')
"
}

test_policy_secret_age_fail() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import get_policy_by_id
p = get_policy_by_id('p007')
passed, reason = p.evaluate({'secret_age_days': 120, 'max_secret_age_days': 90})
assert not passed, '120 days > 90 day limit should fail'
print(f'secrets_rotation_age FAIL (120 > 90): {reason} — OK')
"
}

test_policy_wildcard_port_fail() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import get_policy_by_id
p = get_policy_by_id('p004')
passed, reason = p.evaluate({'port_bindings': ['0.0.0.0:8080:8080']})
assert not passed, '0.0.0.0 binding should fail'
print(f'port_binding_not_wildcard FAIL (0.0.0.0): {reason} — OK')
"
}

################################################################################
# Group 3: evaluate_policies
################################################################################

test_evaluate_policies_clean_context() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import evaluate_policies
ctx = {
    'container_id': 'clean-001',
    'container_name': 'code-server-clean',
    'user_uid': 1000,
    'privileged': False,
    'env_vars': {'APP_NAME': 'code-server'},
    'port_bindings': ['127.0.0.1:8080:8080'],
    'read_only_rootfs': True,
    'capabilities': [],
    'secret_age_days': 30,
}
violations = evaluate_policies(ctx, dry_run=True)
assert len(violations) == 0, f'Clean context should have 0 violations, got {len(violations)}'
print('evaluate_policies(clean): 0 violations — OK')
"
}

test_evaluate_policies_violating_context() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import evaluate_policies
ctx = {
    'container_id': 'bad-001',
    'container_name': 'code-server-bad',
    'user_uid': 0,          # p001
    'privileged': True,     # p002
    'env_vars': {'API_TOKEN': 'leaked'},  # p003
    'port_bindings': ['0.0.0.0:8080:8080'],  # p004
    'read_only_rootfs': True,
    'capabilities': ['SYS_ADMIN'],  # p006
    'secret_age_days': 100,  # p007
}
violations = evaluate_policies(ctx, dry_run=True)
assert len(violations) >= 5, f'Violating context should have >= 5 violations, got {len(violations)}'
print(f'evaluate_policies(violating): {len(violations)} violations — OK')
"
}

################################################################################
# Group 4: Remediations
################################################################################

test_remediate_violation_dry_run() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import evaluate_policies, remediate_violation, ViolationStatus

ctx = {
    'container_id': 'rem-test-p36',
    'container_name': 'code-server-rem-test',
    'user_uid': 0,
    'privileged': False,
    'env_vars': {},
    'port_bindings': ['127.0.0.1:8080:8080'],
    'read_only_rootfs': True,
    'capabilities': [],
}
violations = evaluate_policies(ctx, dry_run=True)
assert violations, 'Should have at least 1 violation (root uid)'

v = violations[0]
rec = remediate_violation(v.violation_id, dry_run=True)
assert rec is not None, 'remediate_violation should return a record'
assert rec.status == 'success', f'Expected success, got {rec.status}'
assert rec.dry_run is True
print(f'remediate_violation dry_run OK: action={rec.action.value} status={rec.status}')
"
}

test_remediate_nonexistent_violation() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.policy_engine import remediate_violation
rec = remediate_violation('nonexistent-violation-id', dry_run=True)
assert rec is None, f'Expected None for missing violation, got {rec}'
print('remediate_violation(nonexistent): None — OK')
"
}

################################################################################
# Group 5: Orchestrator
################################################################################

test_orchestrator_exists() {
  [[ -f "${REPO_ROOT}/scripts/ops/phase-36-policy-enforcement.sh" ]]
}

test_orchestrator_has_traps() {
  grep -q "trap.*ERR" "${REPO_ROOT}/scripts/ops/phase-36-policy-enforcement.sh"
}

test_orchestrator_help() {
  local out
  out="$(bash "${REPO_ROOT}/scripts/ops/phase-36-policy-enforcement.sh" --help 2>&1)" || true
  echo "${out}" | grep -qiE "usage|mode|audit|enforce|score|demo"
}

test_orchestrator_score_mode() {
  local out
  out="$(bash "${REPO_ROOT}/scripts/ops/phase-36-policy-enforcement.sh" --mode score 2>&1)" || true
  echo "${out}" | grep -qiE "policy.score|phase.36|score|violations|policies"
}

test_orchestrator_demo_mode() {
  local out
  out="$(bash "${REPO_ROOT}/scripts/ops/phase-36-policy-enforcement.sh" --mode demo 2>&1)" || true
  echo "${out}" | grep -qiE "demo|violation|remediat|phase.36|zero.trust"
}

test_orchestrator_audit_mode() {
  local out
  out="$(DRY_RUN=true bash "${REPO_ROOT}/scripts/ops/phase-36-policy-enforcement.sh" \
    --mode audit 2>&1)" || true
  echo "${out}" | grep -qiE "audit|violation|PASS|phase.36|container"
}

################################################################################
# Group 6: Regression (lightweight — full chains verified in each phase's own suite)
################################################################################

test_phase32_imports() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.adaptive_response import (
    classify_tier, select_actions, AnomalySignal, ResponseAction, Incident
)
print('Phase 32 imports OK')
"
}

test_phase35_imports() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.forensics_engine import (
    correlate_events, forensic_score, summary, Event, EventSource
)
print('Phase 35 imports OK')
s = summary()
assert isinstance(s, dict)
print('Phase 35 summary OK:', s)
"
}

test_phase34_imports() {
  cd "${REPO_ROOT}"
  python3 -c "
import sys; sys.path.insert(0, '.')
from apps.security_ai.resilience_engine import (
    detect_and_remediate, resilience_score, summary, HealthMetric
)
print('Phase 34 imports OK')
s = summary()
assert isinstance(s, dict)
print('Phase 34 summary OK:', s)
"
}

################################################################################
# Runner
################################################################################

log_info "Starting Phase 36 Integration Tests"
echo ""

log_info "--- Group 1: Module ---"
_run_test "module_imports"              test_module_imports
_run_test "get_policies_returns_list"   test_get_policies_returns_list
_run_test "get_policy_by_id"            test_get_policy_by_id
_run_test "summary_structure"           test_summary_structure

log_info "--- Group 2: Built-in Policies ---"
_run_test "no_root_containers_pass"     test_policy_no_root_containers_pass
_run_test "no_root_containers_fail"     test_policy_no_root_containers_fail
_run_test "secrets_in_env_fail"         test_policy_secrets_in_env_fail
_run_test "secrets_in_env_pass"         test_policy_secrets_in_env_pass
_run_test "secret_age_fail"             test_policy_secret_age_fail
_run_test "wildcard_port_fail"          test_policy_wildcard_port_fail

log_info "--- Group 3: evaluate_policies ---"
_run_test "evaluate_clean_context"      test_evaluate_policies_clean_context
_run_test "evaluate_violating_context"  test_evaluate_policies_violating_context

log_info "--- Group 4: Remediations ---"
_run_test "remediate_dry_run"           test_remediate_violation_dry_run
_run_test "remediate_nonexistent"       test_remediate_nonexistent_violation

log_info "--- Group 5: Orchestrator ---"
_run_test "orchestrator_exists"         test_orchestrator_exists
_run_test "orchestrator_has_traps"      test_orchestrator_has_traps
_run_test "orchestrator_help"           test_orchestrator_help
_run_test "orchestrator_score"          test_orchestrator_score_mode
_run_test "orchestrator_demo"           test_orchestrator_demo_mode
_run_test "orchestrator_audit"          test_orchestrator_audit_mode

log_info "--- Group 6: Regression ---"
_run_test "phase32_imports"             test_phase32_imports
_run_test "phase34_imports"             test_phase34_imports
_run_test "phase35_imports"             test_phase35_imports

echo ""
echo "======================================="
echo " Phase 36 Integration Test Results"
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
