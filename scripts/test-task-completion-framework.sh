#!/usr/bin/env bash
# @file        scripts/test-task-completion-framework.sh
# @module      task-management/tests
# @description Smoke tests for elite enhancements to task-completion-framework
#

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/task-completion-framework.sh"

PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# ── 1. Registration + timestamps ────────────────────────────────────────────
echo ""
echo "── Test: register_dod_item with command ──"
register_dod_item "build"  "Build image"   "agent"       ""           "echo build-ok"
register_dod_item "push"   "Push registry" "credentials" "needs creds" ""
register_dod_item "verify" "Smoke test"    "manual"      ""           ""

[[ ${_DOD_INITIALIZED} -eq 1 ]]            && ok "initialized flag set" || fail "initialized flag not set"
[[ -n "${_DOD_TIMESTAMPS[build:registered]}" ]] && ok "timestamp recorded on registration" || fail "missing timestamp"

# ── 2. run_dod_item auto-complete ────────────────────────────────────────────
echo ""
echo "── Test: run_dod_item (success path) ──"
run_dod_item "build"
[[ "${_DOD_COMPLETION[build]}" == "completed" ]] && ok "auto-marked completed on command success" || fail "not marked completed"
[[ -n "${_DOD_TIMESTAMPS[build:completed]}" ]]   && ok "completion timestamp recorded"            || fail "missing completion timestamp"

# ── 3. run_dod_item failure → auto-blocked ───────────────────────────────────
echo ""
echo "── Test: run_dod_item (failure path) ──"
register_dod_item "bad-cmd" "Intentional fail" "agent" "" "false"
run_dod_item "bad-cmd" || true
[[ "${_DOD_COMPLETION[bad-cmd]}" == "blocked" ]] && ok "auto-marked blocked on command failure" || fail "not blocked on failure"

# ── 4. mark_dod_blocked + blocker reason ────────────────────────────────────
echo ""
echo "── Test: mark_dod_blocked ──"
mark_dod_blocked "push" "SSH key not provided"
[[ "${_DOD_COMPLETION[push]}"  == "blocked" ]]              && ok "status is blocked"       || fail "wrong status"
[[ "${_DOD_BLOCKERS[push]}"    == "SSH key not provided" ]] && ok "blocker reason stored"   || fail "reason not stored"
[[ -n "${_DOD_TIMESTAMPS[push:blocked]}" ]]                 && ok "blocked timestamp set"   || fail "missing blocked timestamp"

# ── 5. validate_definition_of_done returns non-zero while blocked ─────────
echo ""
echo "── Test: validate_definition_of_done ──"
validate_definition_of_done && fail "should return 1 while items pending/blocked" || ok "correctly returns 1 while incomplete"

# ── 6. list_dod_items renders ────────────────────────────────────────────────
echo ""
echo "── Test: list_dod_items ──"
list_dod_items | grep -q "build" && ok "list contains build" || fail "build missing from list"
list_dod_items blocked | grep -q "push" && ok "filtered list shows blocked push" || fail "push missing from filtered list"

# ── 7. get_completion_status json includes per-item timing ───────────────────
echo ""
echo "── Test: get_completion_status json ──"
json_out="$(get_completion_status json)"
echo "$json_out" | grep -q '"total"'    && ok "json has total field"    || fail "json missing total"
echo "$json_out" | grep -q '"duration_secs"' && ok "json has duration_secs" || fail "json missing duration_secs"
echo "$json_out" | grep -q '"age_secs"'      && ok "json has age_secs"      || fail "json missing age_secs"

# ── 8. audit log ─────────────────────────────────────────────────────────────
echo ""
echo "── Test: enable_dod_audit ──"
AUDIT_FILE="$(mktemp /tmp/dod-audit-XXXX.log)"
enable_dod_audit "$AUDIT_FILE"
register_dod_item "audit-test" "Audit item" "agent"
mark_dod_complete "audit-test"
grep -q "REGISTERED" "$AUDIT_FILE" && ok "REGISTERED event in audit log" || fail "REGISTERED not in log"
grep -q "COMPLETED"  "$AUDIT_FILE" && ok "COMPLETED event in audit log"  || fail "COMPLETED not in log"
rm -f "$AUDIT_FILE"

# ── 9. save_dod_state / load_dod_state round-trip ────────────────────────────
echo ""
echo "── Test: save_dod_state / load_dod_state ──"
STATE_FILE="$(mktemp /tmp/dod-state-XXXX.json)"
save_dod_state "$STATE_FILE"
[[ -f "$STATE_FILE" ]]                    && ok "state file created"    || fail "state file missing"
grep -q '"build"' "$STATE_FILE"           && ok "build item serialized"  || fail "build not in state"
grep -q '"completed"' "$STATE_FILE"       && ok "completed status saved" || fail "completed not in state"

reset_dod
[[ ${_DOD_INITIALIZED} -eq 0 ]] && ok "reset_dod cleared state" || fail "reset_dod did not clear"

load_dod_state "$STATE_FILE"
[[ -n "${_DOD_REGISTRY[build]:-}" ]]          && ok "build restored after load"      || fail "build not restored"
[[ "${_DOD_COMPLETION[build]}" == "completed" ]] && ok "completion status restored"  || fail "status not restored"
[[ "${_DOD_COMPLETION[push]}"  == "blocked" ]]   && ok "blocked status restored"    || fail "blocked not restored"
[[ "${_DOD_BLOCKERS[push]:-}" == "SSH key not provided" ]] \
  && ok "blocker reason restored" || fail "blocker reason not restored"
rm -f "$STATE_FILE"

# ── 10. _dod_duration after round-trip ───────────────────────────────────────
echo ""
echo "── Test: _dod_duration ──"
dur="$(_dod_duration "build")"
[[ -n "$dur" && "$dur" -ge 0 ]] && ok "_dod_duration returns non-negative integer" || fail "_dod_duration broken"

# ── 11. sourcing library does not mutate caller strict-mode flags ───────────
echo ""
echo "── Test: library sourcing preserves caller shell options ──"
strict_state="$(FRAMEWORK_PATH="$SCRIPT_DIR/lib/task-completion-framework.sh" bash -c '
  set +e +u
  set +o pipefail
  source "$FRAMEWORK_PATH"
  printf "%s|%s|%s" "$(set -o | awk '\''$1=="errexit"{print $2}'\'')" "$(set -o | awk '\''$1=="nounset"{print $2}'\'')" "$(set -o | awk '\''$1=="pipefail"{print $2}'\'')"
')"
[[ "$strict_state" == "off|off|off" ]] && ok "caller shell options preserved" || fail "caller shell options mutated: $strict_state"


# ── 12. safe_task_complete blocked verdict ──────────────────────────────────
echo ""
echo "── Test: safe_task_complete blocked verdict ──"
reset_dod
TEST_WORKSPACE="$(mktemp -d /tmp/dod-workspace-XXXX)"
export DOD_WORKSPACE_ROOT="$TEST_WORKSPACE"
export DOD_ARTIFACT_DIR="$TEST_WORKSPACE/.task-completion"
register_dod_item "agent-step" "Finish implementation" "agent"
register_dod_item "manual-step" "QA sign-off" "manual"
if safe_task_complete 1234; then
  fail "safe_task_complete should not succeed while agent items remain"
else
  rc=$?
  [[ "$rc" -eq 1 ]] && ok "blocked verdict returns exit code 1" || fail "blocked verdict returned $rc"
fi
grep -q 'VERDICT=blocked' "$DOD_ARTIFACT_DIR/issue-1234-status.env" && ok "blocked receipt written" || fail "blocked receipt missing"
grep -q 'READY_FOR_TASK_COMPLETE=false' "$DOD_ARTIFACT_DIR/issue-1234-status.env" && ok "blocked receipt marks task_complete false" || fail "blocked receipt readiness incorrect"
rm -rf "$TEST_WORKSPACE"
unset DOD_WORKSPACE_ROOT DOD_ARTIFACT_DIR

# ── 13. safe_task_complete handoff verdict ──────────────────────────────────
echo ""
echo "── Test: safe_task_complete handoff verdict ──"
reset_dod
TEST_WORKSPACE="$(mktemp -d /tmp/dod-workspace-XXXX)"
export DOD_WORKSPACE_ROOT="$TEST_WORKSPACE"
export DOD_ARTIFACT_DIR="$TEST_WORKSPACE/.task-completion"
register_dod_item "agent-step" "Finish implementation" "agent"
register_dod_item "manual-step" "QA sign-off" "manual"
mark_dod_complete "agent-step"
if safe_task_complete 4321; then
  fail "safe_task_complete should return handoff when only non-agent items remain"
else
  rc=$?
  [[ "$rc" -eq 2 ]] && ok "handoff verdict returns exit code 2" || fail "handoff verdict returned $rc"
fi
grep -q 'VERDICT=handoff' "$DOD_ARTIFACT_DIR/issue-4321-status.env" && ok "handoff receipt written" || fail "handoff receipt missing"
grep -q 'READY_FOR_HANDOFF=true' "$DOD_ARTIFACT_DIR/issue-4321-status.env" && ok "handoff receipt marks handoff true" || fail "handoff receipt readiness incorrect"
grep -q 'AGENT_WORK_COMPLETE=true' "$DOD_ARTIFACT_DIR/issue-4321-status.env" && ok "handoff receipt marks agent work complete" || fail "handoff agent completion incorrect"
rm -rf "$TEST_WORKSPACE"
unset DOD_WORKSPACE_ROOT DOD_ARTIFACT_DIR

# ── 14. safe_task_complete ready verdict ────────────────────────────────────
echo ""
echo "── Test: safe_task_complete ready verdict ──"
reset_dod
TEST_WORKSPACE="$(mktemp -d /tmp/dod-workspace-XXXX)"
export DOD_WORKSPACE_ROOT="$TEST_WORKSPACE"
export DOD_ARTIFACT_DIR="$TEST_WORKSPACE/.task-completion"
register_dod_item "agent-step" "Finish implementation" "agent"
mark_dod_complete "agent-step"
if safe_task_complete 777; then
  ok "ready verdict returns exit code 0"
else
  fail "ready verdict should succeed"
fi
grep -q 'VERDICT=ready' "$DOD_ARTIFACT_DIR/issue-777-status.env" && ok "ready receipt written" || fail "ready receipt missing"
grep -q 'READY_FOR_TASK_COMPLETE=true' "$DOD_ARTIFACT_DIR/issue-777-status.env" && ok "ready receipt marks task_complete true" || fail "ready receipt readiness incorrect"
[[ -f "$DOD_ARTIFACT_DIR/issue-777-dod-state.json" ]] && ok "ready state file written" || fail "ready state file missing"
rm -rf "$TEST_WORKSPACE"
unset DOD_WORKSPACE_ROOT DOD_ARTIFACT_DIR

# ── 15. reset_dod clears side-channel state ─────────────────────────────────
echo ""
echo "── Test: reset_dod clears side-channel state ──"
reset_dod
enable_dod_verbose
enable_dod_audit "$(mktemp /tmp/dod-audit-XXXX.log)"
set_dod_github_repo "kushin77/code-server"
register_dod_item "cleanup-step" "Cleanup" "agent"
mark_dod_complete "cleanup-step"
reset_dod
[[ ${#_DOD_TIMESTAMPS[@]} -eq 0 ]] && ok "timestamps cleared on reset" || fail "timestamps not cleared on reset"
[[ -z "$_DOD_AUDIT_LOG" ]] && ok "audit log cleared on reset" || fail "audit log not cleared on reset"
[[ -z "$_DOD_GITHUB_REPO" ]] && ok "GitHub repo cleared on reset" || fail "GitHub repo not cleared on reset"
[[ $_COMPLETION_VERBOSE -eq 0 ]] && ok "verbose flag cleared on reset" || fail "verbose flag not cleared on reset"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "════════════════════════════════"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
