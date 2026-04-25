#!/usr/bin/env bats
# @file        tests/unit/bash/test_nas.bats
# @description Unit tests for scripts/lib/nas.sh
# @issue       #1537 — Testing & QA 100x: bats unit tests for scripts/_common/
# @coverage    nas_log, nas_mount_latency_ms, check_nas_health, retry_with_backoff, benchmark_nas_mount

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../../" && pwd)"
NAS_SH="${REPO_ROOT}/scripts/lib/nas.sh"

# Shared env for every subshell sourcing nas.sh
_NAS_ENV="
  unset _SCRIPT_INIT_SOURCED
  PRIMARY_HOST=h REPLICA_HOST=r NAS_HOST=n APEX_DOMAIN=e ADMIN_EMAIL=a@e DEPLOYMENT_MODE=test
  SSH_KEY=/tmp/test-key SSH_USER=u BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$
  NAS_MOUNT_PATH=/tmp NAS_LATENCY_THRESHOLD_MS=9999 NAS_RETRY_ATTEMPTS=3 NAS_RETRY_BASE_DELAY_SECONDS=0
  export PRIMARY_HOST REPLICA_HOST NAS_HOST APEX_DOMAIN ADMIN_EMAIL DEPLOYMENT_MODE
  export SSH_KEY SSH_USER BOOTSTRAP_STATE_DIR NAS_MOUNT_PATH NAS_LATENCY_THRESHOLD_MS
  export NAS_RETRY_ATTEMPTS NAS_RETRY_BASE_DELAY_SECONDS
  source '${NAS_SH}'
"

_nas_eval() {
  bash -c "${_NAS_ENV}; $1" 2>&1
}

# ── nas_log ───────────────────────────────────────────────────────────────────

@test "nas_log writes a prefixed message to stderr" {
  run _nas_eval "nas_log 'test message'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[nas]"* ]]
  [[ "${output}" == *"test message"* ]]
}

# ── nas_mount_latency_ms ──────────────────────────────────────────────────────

@test "nas_mount_latency_ms returns a non-negative integer for /tmp" {
  run _nas_eval "nas_mount_latency_ms /tmp"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "nas_mount_latency_ms uses NAS_MOUNT_PATH default when no argument given" {
  run _nas_eval "nas_mount_latency_ms"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "nas_mount_latency_ms returns non-zero for non-existent path" {
  run bash -c "
    ${_NAS_ENV}
    nas_mount_latency_ms /nonexistent/path/that/doesnt/exist
  " 2>&1
  [ "${status}" -ne 0 ]
}

# ── check_nas_health ──────────────────────────────────────────────────────────

@test "check_nas_health passes for /tmp with generous threshold" {
  run _nas_eval "check_nas_health /tmp 9999"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"healthy"* ]]
}

@test "check_nas_health fails for non-existent mount path" {
  run _nas_eval "check_nas_health /nonexistent/mount/xyz 9999"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not reachable"* ]]
}

@test "check_nas_health fails when threshold is 0ms (any operation exceeds it)" {
  run _nas_eval "check_nas_health /tmp 0"
  [ "${status}" -ne 0 ]
}

# ── retry_with_backoff ────────────────────────────────────────────────────────

@test "retry_with_backoff returns 0 when command succeeds immediately" {
  run _nas_eval "retry_with_backoff 3 0 true"
  [ "${status}" -eq 0 ]
}

@test "retry_with_backoff returns non-zero when command always fails" {
  run _nas_eval "retry_with_backoff 2 0 false"
  [ "${status}" -ne 0 ]
}

@test "retry_with_backoff succeeds on second attempt" {
  counter_file="$(mktemp /tmp/bats-counter.XXXXXX)"
  echo "0" > "${counter_file}"

  run bash -c "
    ${_NAS_ENV}
    counter_file='${counter_file}'
    maybe_fail() {
      local n
      n=\$(cat \"\${counter_file}\")
      echo \$((n + 1)) > \"\${counter_file}\"
      [ \"\${n}\" -ge 1 ]
    }
    retry_with_backoff 3 0 maybe_fail
  " 2>&1
  [ "${status}" -eq 0 ]
  rm -f "${counter_file}"
}

# ── benchmark_nas_mount ───────────────────────────────────────────────────────

@test "benchmark_nas_mount returns latency in ms for accessible path" {
  run _nas_eval "benchmark_nas_mount /tmp"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^[0-9]+$ ]]
}
