#!/usr/bin/env bats
# @file        tests/unit/bash/test_rollback_manager.bats
# @description Unit tests for scripts/_common/rollback-manager.sh
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @issue       #1537 — Testing & QA 100x: bats unit tests for scripts/_common/
# @coverage    log, error, success, check_host_health, get_current_commit,
#              get_previous_stable_commit, rollback_target (dry-run)

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../../" && pwd)"
ROLLBACK_SH="${REPO_ROOT}/scripts/_common/rollback-manager.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Source only the function definitions — skip main() execution
_source_rollback() {
  bash -c "
    set +e
    PRIMARY_HOST=primary.test.local
    REPLICA_HOST=replica.test.local
    SSH_USER=testuser
    ROLLBACK_TIMEOUT=30
    HEALTH_CHECK_RETRIES=1
    HEALTH_CHECK_INTERVAL=0
    LOG_FILE=/tmp/bats-rollback-\$\$.log
    export PRIMARY_HOST REPLICA_HOST SSH_USER ROLLBACK_TIMEOUT
    export HEALTH_CHECK_RETRIES HEALTH_CHECK_INTERVAL LOG_FILE
    source '${ROLLBACK_SH}' 2>/dev/null || true
    ${1}
  " 2>&1
}

# ── Logging functions ─────────────────────────────────────────────────────────

@test "log() emits timestamped message" {
  run _source_rollback "log 'hello world'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "hello world" ]]
}

@test "error() emits ERROR prefix and returns 1" {
  run _source_rollback "error 'boom' && echo 'SHOULD_NOT_REACH'"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ERROR: boom" ]]
  [[ ! "$output" =~ "SHOULD_NOT_REACH" ]]
}

@test "success() emits success message" {
  run _source_rollback "success 'all good'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "all good" ]]
}

# ── LOG_FILE written ──────────────────────────────────────────────────────────

@test "log() writes to LOG_FILE" {
  local logfile="/tmp/bats-rollback-logfile-$$.log"
  run bash -c "
    PRIMARY_HOST=h1 REPLICA_HOST=h2 LOG_FILE=$logfile SSH_USER=u
    ROLLBACK_TIMEOUT=30 HEALTH_CHECK_RETRIES=1 HEALTH_CHECK_INTERVAL=0
    export PRIMARY_HOST REPLICA_HOST LOG_FILE SSH_USER ROLLBACK_TIMEOUT HEALTH_CHECK_RETRIES HEALTH_CHECK_INTERVAL
    source '${ROLLBACK_SH}' 2>/dev/null || true
    log 'persistent-message'
  " 2>&1
  [ -f "$logfile" ]
  grep -q 'persistent-message' "$logfile"
  rm -f "$logfile"
}

# ── check_host_health ─────────────────────────────────────────────────────────

@test "check_host_health returns 0 when curl succeeds" {
  # Use a localhost port that's guaranteed to return something
  # We mock curl to always succeed
  run bash -c "
    PRIMARY_HOST=h1 REPLICA_HOST=h2 LOG_FILE=/dev/null SSH_USER=u
    ROLLBACK_TIMEOUT=30 HEALTH_CHECK_RETRIES=1 HEALTH_CHECK_INTERVAL=0
    export PRIMARY_HOST REPLICA_HOST LOG_FILE SSH_USER ROLLBACK_TIMEOUT HEALTH_CHECK_RETRIES HEALTH_CHECK_INTERVAL
    source '${ROLLBACK_SH}' 2>/dev/null || true
    # Override curl to succeed
    curl() { return 0; }
    export -f curl
    check_host_health 'testhost' 'http://testhost:8080/health'
  " 2>&1
  [ "$status" -eq 0 ]
}

@test "check_host_health returns 1 after all retries fail" {
  run bash -c "
    PRIMARY_HOST=h1 REPLICA_HOST=h2 LOG_FILE=/dev/null SSH_USER=u
    ROLLBACK_TIMEOUT=30 HEALTH_CHECK_RETRIES=2 HEALTH_CHECK_INTERVAL=0
    export PRIMARY_HOST REPLICA_HOST LOG_FILE SSH_USER ROLLBACK_TIMEOUT HEALTH_CHECK_RETRIES HEALTH_CHECK_INTERVAL
    source '${ROLLBACK_SH}' 2>/dev/null || true
    # Override curl to always fail
    curl() { return 1; }
    export -f curl
    check_host_health 'badhost' 'http://badhost:9999/health'
  " 2>&1
  [ "$status" -eq 1 ]
}

@test "check_host_health uses port 8080 default endpoint" {
  run bash -c "
    PRIMARY_HOST=h1 REPLICA_HOST=h2 LOG_FILE=/dev/null SSH_USER=u
    ROLLBACK_TIMEOUT=30 HEALTH_CHECK_RETRIES=1 HEALTH_CHECK_INTERVAL=0
    export PRIMARY_HOST REPLICA_HOST LOG_FILE SSH_USER ROLLBACK_TIMEOUT HEALTH_CHECK_RETRIES HEALTH_CHECK_INTERVAL
    source '${ROLLBACK_SH}' 2>/dev/null || true
    CAPTURED_URL=''
    curl() { CAPTURED_URL=\"\$3\"; return 0; }
    export -f curl
    check_host_health 'myhost'
    echo \"URL=\$CAPTURED_URL\"
  " 2>&1
  [[ "$output" =~ "myhost:8080/health" ]]
}

# ── get_current_commit ────────────────────────────────────────────────────────

@test "get_current_commit returns non-empty git SHA" {
  run bash -c "
    cd '${REPO_ROOT}'
    PRIMARY_HOST=h1 REPLICA_HOST=h2 LOG_FILE=/dev/null SSH_USER=u
    ROLLBACK_TIMEOUT=30 HEALTH_CHECK_RETRIES=1 HEALTH_CHECK_INTERVAL=0
    export PRIMARY_HOST REPLICA_HOST LOG_FILE SSH_USER ROLLBACK_TIMEOUT HEALTH_CHECK_RETRIES HEALTH_CHECK_INTERVAL
    source '${ROLLBACK_SH}' 2>/dev/null || true
    get_current_commit
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{7,40}$ ]]
}

# ── get_previous_stable_commit ────────────────────────────────────────────────

@test "get_previous_stable_commit returns a different commit than HEAD" {
  run bash -c "
    cd '${REPO_ROOT}'
    PRIMARY_HOST=h1 REPLICA_HOST=h2 LOG_FILE=/dev/null SSH_USER=u
    ROLLBACK_TIMEOUT=30 HEALTH_CHECK_RETRIES=1 HEALTH_CHECK_INTERVAL=0
    export PRIMARY_HOST REPLICA_HOST LOG_FILE SSH_USER ROLLBACK_TIMEOUT HEALTH_CHECK_RETRIES HEALTH_CHECK_INTERVAL
    source '${ROLLBACK_SH}' 2>/dev/null || true
    HEAD=\$(get_current_commit)
    PREV=\$(get_previous_stable_commit)
    [ \"\$HEAD\" != \"\$PREV\" ] && echo 'DIFFERENT'
  " 2>&1
  [[ "$output" =~ "DIFFERENT" ]]
}

# ── required env guard ────────────────────────────────────────────────────────

@test "sourcing without PRIMARY_HOST exits with error" {
  run bash -c "
    unset PRIMARY_HOST REPLICA_HOST
    source '${ROLLBACK_SH}' 2>&1
  "
  [ "$status" -ne 0 ]
  [[ "$output" =~ "PRIMARY_HOST" ]]
}

@test "sourcing without REPLICA_HOST exits with error" {
  run bash -c "
    PRIMARY_HOST=h1 unset REPLICA_HOST 2>/dev/null
    export PRIMARY_HOST=h1
    unset REPLICA_HOST
    source '${ROLLBACK_SH}' 2>&1
  "
  [ "$status" -ne 0 ]
  [[ "$output" =~ "REPLICA_HOST" ]]
}

# ── rollback_target dry-run ───────────────────────────────────────────────────

@test "rollback_target attempts SSH on the correct host" {
  run bash -c "
    PRIMARY_HOST=primary.test.local REPLICA_HOST=replica.test.local
    LOG_FILE=/dev/null SSH_USER=testuser
    ROLLBACK_TIMEOUT=30 HEALTH_CHECK_RETRIES=1 HEALTH_CHECK_INTERVAL=0
    export PRIMARY_HOST REPLICA_HOST LOG_FILE SSH_USER ROLLBACK_TIMEOUT HEALTH_CHECK_RETRIES HEALTH_CHECK_INTERVAL
    source '${ROLLBACK_SH}' 2>/dev/null || true

    CALLED_HOST=''
    ssh() { CALLED_HOST=\"\$2\"; echo 'ssh-mock-called'; return 1; }
    export -f ssh
    check_host_health() { return 0; }
    export -f check_host_health

    rollback_target 'primary.test.local' 'abc1234' 2>/dev/null || true
    echo \"SSH_HOST=\$CALLED_HOST\"
  " 2>&1
  [[ "$output" =~ "testuser@primary.test.local" ]]
}
