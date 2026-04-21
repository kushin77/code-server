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

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "════════════════════════════════"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
