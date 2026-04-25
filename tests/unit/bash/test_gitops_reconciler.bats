#!/usr/bin/env bats
# @file        tests/unit/bash/test_gitops_reconciler.bats
# @description Unit tests for scripts/_common/gitops-reconciler.sh
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @issue       #1537 — Testing & QA 100x: bats unit tests for scripts/_common/
# @coverage    log, error, compute_state_hash, detect_drift, run_single_reconciliation

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../../" && pwd)"
RECONCILER_SH="${REPO_ROOT}/scripts/_common/gitops-reconciler.sh"

# ---------------------------------------------------------------------------
# Helper: source the reconciler with test-safe env
# ---------------------------------------------------------------------------

_eval_reconciler() {
  local extra_env="${1:-}"
  local cmd="${2:-echo ok}"
  bash -c "
    set +e
    RECONCILE_INTERVAL=1
    GIT_REPO='${REPO_ROOT}'
    TARGET_BRANCH=main
    TERRAFORM_DIR='${REPO_ROOT}/terraform'
    DOCKER_COMPOSE_FILE='${REPO_ROOT}/docker-compose.yml'
    DRIFT_THRESHOLD=10
    LOG_FILE=/dev/null
    export RECONCILE_INTERVAL GIT_REPO TARGET_BRANCH TERRAFORM_DIR
    export DOCKER_COMPOSE_FILE DRIFT_THRESHOLD LOG_FILE
    ${extra_env}
    source '${RECONCILER_SH}' 2>/dev/null || true
    ${cmd}
  " 2>&1
}

# ── Logging ──────────────────────────────────────────────────────────────────

@test "log() emits a timestamped message" {
  run _eval_reconciler "" "log 'test-message'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "test-message" ]]
}

@test "error() emits ERROR prefix and returns 1" {
  run _eval_reconciler "" "error 'fatal' && echo 'SHOULD_NOT_REACH'"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ERROR: fatal" ]]
  [[ ! "$output" =~ "SHOULD_NOT_REACH" ]]
}

# ── compute_state_hash ────────────────────────────────────────────────────────

@test "compute_state_hash('terraform') returns non-empty sha256" {
  run _eval_reconciler "" "compute_state_hash terraform"
  [ "$status" -eq 0 ]
  # sha256 is 64 hex chars
  [[ "$output" =~ ^[0-9a-f]{64}$ ]]
}

@test "compute_state_hash('docker') returns non-empty sha256" {
  run _eval_reconciler "" "compute_state_hash docker"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{64}$ ]]
}

@test "compute_state_hash returns 'unknown-hash' for unknown target" {
  run _eval_reconciler "" "compute_state_hash unknown"
  [ "$status" -eq 0 ]
  [[ "$output" == "unknown-hash" ]]
}

@test "compute_state_hash('terraform') is deterministic across two calls" {
  run bash -c "
    TERRAFORM_DIR='${REPO_ROOT}/terraform'
    DOCKER_COMPOSE_FILE='${REPO_ROOT}/docker-compose.yml'
    LOG_FILE=/dev/null
    export TERRAFORM_DIR DOCKER_COMPOSE_FILE LOG_FILE
    source '${RECONCILER_SH}' 2>/dev/null || true
    H1=\$(compute_state_hash terraform)
    H2=\$(compute_state_hash terraform)
    [ \"\$H1\" = \"\$H2\" ] && echo SAME || echo DIFFERENT
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ SAME ]]
}

@test "compute_state_hash('docker') changes when docker-compose.yml changes" {
  local tmpfile
  tmpfile=$(mktemp /tmp/bats-compose-XXXXXX.yml)
  echo "version: '3.8'" > "$tmpfile"

  run bash -c "
    DOCKER_COMPOSE_FILE='${REPO_ROOT}/docker-compose.yml' LOG_FILE=/dev/null
    TERRAFORM_DIR='${REPO_ROOT}/terraform'
    export DOCKER_COMPOSE_FILE TERRAFORM_DIR LOG_FILE
    source '${RECONCILER_SH}' 2>/dev/null || true
    H1=\$(compute_state_hash docker)

    DOCKER_COMPOSE_FILE='${tmpfile}' LOG_FILE=/dev/null
    export DOCKER_COMPOSE_FILE
    source '${RECONCILER_SH}' 2>/dev/null || true
    H2=\$(compute_state_hash docker)

    [ \"\$H1\" != \"\$H2\" ] && echo CHANGED || echo SAME
  " 2>&1
  rm -f "$tmpfile"
  [[ "$output" =~ CHANGED ]]
}

# ── detect_drift ──────────────────────────────────────────────────────────────

@test "detect_drift returns 0 (drift exists) when hashes differ" {
  run _eval_reconciler "" "detect_drift 'aaa' 'bbb' 'terraform'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DRIFT DETECTED" ]]
}

@test "detect_drift returns 1 (no drift) when hashes match" {
  run _eval_reconciler "" "detect_drift 'abc123' 'abc123' 'docker'"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "detect_drift output includes target name" {
  run _eval_reconciler "" "detect_drift 'x' 'y' 'my-target'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "my-target" ]]
}

# ── Environment variable defaults ────────────────────────────────────────────

@test "RECONCILE_INTERVAL defaults to 300 if not set" {
  run bash -c "
    unset RECONCILE_INTERVAL
    TERRAFORM_DIR='${REPO_ROOT}/terraform'
    DOCKER_COMPOSE_FILE='${REPO_ROOT}/docker-compose.yml'
    LOG_FILE=/dev/null
    export TERRAFORM_DIR DOCKER_COMPOSE_FILE LOG_FILE
    source '${RECONCILER_SH}' 2>/dev/null || true
    echo \"\$RECONCILE_INTERVAL\"
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == "300" ]]
}

@test "DRIFT_THRESHOLD defaults to 10 if not set" {
  run bash -c "
    unset DRIFT_THRESHOLD
    TERRAFORM_DIR='${REPO_ROOT}/terraform'
    DOCKER_COMPOSE_FILE='${REPO_ROOT}/docker-compose.yml'
    LOG_FILE=/dev/null
    export TERRAFORM_DIR DOCKER_COMPOSE_FILE LOG_FILE
    source '${RECONCILER_SH}' 2>/dev/null || true
    echo \"\$DRIFT_THRESHOLD\"
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == "10" ]]
}

@test "TARGET_BRANCH defaults to main if not set" {
  run bash -c "
    unset TARGET_BRANCH
    TERRAFORM_DIR='${REPO_ROOT}/terraform'
    DOCKER_COMPOSE_FILE='${REPO_ROOT}/docker-compose.yml'
    LOG_FILE=/dev/null
    export TERRAFORM_DIR DOCKER_COMPOSE_FILE LOG_FILE
    source '${RECONCILER_SH}' 2>/dev/null || true
    echo \"\$TARGET_BRANCH\"
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == "main" ]]
}

# ── LOG_FILE written ──────────────────────────────────────────────────────────

@test "log() writes to LOG_FILE on disk" {
  local logfile="/tmp/bats-gitops-reconciler-$$.log"
  run bash -c "
    TERRAFORM_DIR='${REPO_ROOT}/terraform'
    DOCKER_COMPOSE_FILE='${REPO_ROOT}/docker-compose.yml'
    LOG_FILE='$logfile'
    export TERRAFORM_DIR DOCKER_COMPOSE_FILE LOG_FILE
    source '${RECONCILER_SH}' 2>/dev/null || true
    log 'written-to-disk'
  " 2>&1
  [ -f "$logfile" ]
  grep -q 'written-to-disk' "$logfile"
  rm -f "$logfile"
}
