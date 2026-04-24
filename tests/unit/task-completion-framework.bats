#!/usr/bin/env bats
# @file        tests/unit/task-completion-framework.bats
# @module      tests/unit
# @description Regression coverage for task completion framework verdicts and receipts.
#

load test_helper.bash

setup() {
    setup_test_env
    mkdir -p "$TEST_TMPDIR/workspace"
    export DOD_WORKSPACE_ROOT="$TEST_TMPDIR/workspace"
    export DOD_ARTIFACT_DIR="$TEST_TMPDIR/workspace/.task-completion"
}

teardown() {
    teardown_test_env
}

@test "sourcing the framework does not mutate caller shell strict-mode flags" {
    run bash -c 'set +e +u; set +o pipefail; source "$REPO_ROOT/scripts/lib/task-completion-framework.sh"; printf "%s|%s|%s" "$(set -o | awk '\''$1=="errexit"{print $2}'\'')" "$(set -o | awk '\''$1=="nounset"{print $2}'\'')" "$(set -o | awk '\''$1=="pipefail"{print $2}'\'')"'
    [ "$status" -eq 0 ]
    [ "$output" = "off|off|off" ]
}

@test "safe_task_complete stays blocked while agent-owned work remains" {
    run bash -c 'source "$REPO_ROOT/scripts/lib/task-completion-framework.sh"; register_dod_item "agent-step" "Finish implementation" "agent"; register_dod_item "manual-step" "QA sign-off" "manual"; safe_task_complete 1234'
    [ "$status" -eq 1 ]
    [[ "$output" == *"agent-owned Definition of Done items remain"* ]]

    run cat "$TEST_TMPDIR/workspace/.task-completion/issue-1234-status.env"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERDICT=blocked"* ]]
    [[ "$output" == *"READY_FOR_TASK_COMPLETE=false"* ]]
    [[ "$output" == *"REMAINING_AGENT_ITEMS=1"* ]]
}

@test "safe_task_complete returns handoff when only non-agent blockers remain" {
    run bash -c 'source "$REPO_ROOT/scripts/lib/task-completion-framework.sh"; register_dod_item "agent-step" "Finish implementation" "agent"; register_dod_item "manual-step" "QA sign-off" "manual"; mark_dod_complete "agent-step"; safe_task_complete 4321'
    [ "$status" -eq 2 ]
    [[ "$output" == *"non-agent DoD items remain"* ]]

    run cat "$TEST_TMPDIR/workspace/.task-completion/issue-4321-status.env"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERDICT=handoff"* ]]
    [[ "$output" == *"READY_FOR_HANDOFF=true"* ]]
    [[ "$output" == *"AGENT_WORK_COMPLETE=true"* ]]
    [[ "$output" == *"REMAINING_AGENT_ITEMS=0"* ]]
}

@test "safe_task_complete returns ready and writes receipts when all items are complete" {
    run bash -c 'source "$REPO_ROOT/scripts/lib/task-completion-framework.sh"; register_dod_item "agent-step" "Finish implementation" "agent"; mark_dod_complete "agent-step"; safe_task_complete 777'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Task completion is ready for issue #777"* ]]

    run cat "$TEST_TMPDIR/workspace/.task-completion/issue-777-status.env"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERDICT=ready"* ]]
    [[ "$output" == *"READY_FOR_TASK_COMPLETE=true"* ]]
    [[ "$output" == *"AGENT_WORK_COMPLETE=true"* ]]

    run test -f "$TEST_TMPDIR/workspace/.task-completion/issue-777-summary.txt"
    [ "$status" -eq 0 ]

    run test -f "$TEST_TMPDIR/workspace/.task-completion/issue-777-dod-state.json"
    [ "$status" -eq 0 ]
}

@test "reset_dod clears timestamps and side-channel state" {
    run bash -c 'source "$REPO_ROOT/scripts/lib/task-completion-framework.sh"; enable_dod_verbose; enable_dod_audit "$TEST_TMPDIR/audit.log"; set_dod_github_repo "kushin77/code-server"; register_dod_item "agent-step" "Finish implementation" "agent"; mark_dod_complete "agent-step"; reset_dod; printf "%s|%s|%s|%s|%s" "${#_DOD_REGISTRY[@]}" "${#_DOD_TIMESTAMPS[@]}" "$_DOD_AUDIT_LOG" "$_DOD_GITHUB_REPO" "$_COMPLETION_VERBOSE"'
    [ "$status" -eq 0 ]
    [ "$output" = "0|0|||0" ]
}