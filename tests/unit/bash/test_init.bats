#!/usr/bin/env bats
# @file        tests/unit/bash/test_init.bats
# @description Unit tests for scripts/_common/init.sh
# @issue       #1537 — Testing & QA 100x: bats unit tests for scripts/_common/
# @coverage    log_info, log_success, log_warn, log_error, log_warning,
#              source_env_file, verify_git_clean, get_git_sha, validate_required_env

bats_require_minimum_version 1.5.0

# ── Fixtures ──────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../../" && pwd)"
INIT_SH="${REPO_ROOT}/scripts/_common/init.sh"

setup() {
  export PRIMARY_HOST="test-primary.example.com"
  export REPLICA_HOST="test-replica.example.com"
  export NAS_HOST="test-nas.example.com"
  export APEX_DOMAIN="example.com"
  export ADMIN_EMAIL="admin@example.com"
  export DEPLOYMENT_MODE="test"
  export BOOTSTRAP_STATE_DIR="${BATS_TMPDIR}/bootstrap-state"
  mkdir -p "${BOOTSTRAP_STATE_DIR}"
}

teardown() {
  rm -rf "${BATS_TMPDIR}/bootstrap-state"
}

# Shared helper: source init.sh in a clean subshell
_init_eval() {
  bash -c "
    unset _SCRIPT_INIT_SOURCED
    PRIMARY_HOST=test-primary.example.com
    REPLICA_HOST=test-replica.example.com
    NAS_HOST=test-nas.example.com
    APEX_DOMAIN=example.com
    ADMIN_EMAIL=admin@example.com
    DEPLOYMENT_MODE=test
    BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$
    export PRIMARY_HOST REPLICA_HOST NAS_HOST APEX_DOMAIN ADMIN_EMAIL DEPLOYMENT_MODE BOOTSTRAP_STATE_DIR
    source '${INIT_SH}'
    $1
  " 2>&1
}

# ── log_info ──────────────────────────────────────────────────────────────────

@test "log_info writes to stdout with [INFO] tag" {
  run _init_eval "log_info 'hello world'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[INFO]"* ]]
  [[ "${output}" == *"hello world"* ]]
}

@test "log_info output matches ISO-8601 timestamp format" {
  run _init_eval "log_info 'ts-check'"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ]]
}

# ── log_success ───────────────────────────────────────────────────────────────

@test "log_success writes to stdout with [SUCCESS] tag" {
  run _init_eval "log_success 'done'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[SUCCESS]"* ]]
  [[ "${output}" == *"done"* ]]
}

# ── log_warn / log_warning ────────────────────────────────────────────────────

@test "log_warn writes [WARN] tag" {
  run _init_eval "log_warn 'caution'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[WARN]"* ]]
  [[ "${output}" == *"caution"* ]]
}

@test "log_warning is an alias for log_warn" {
  run _init_eval "log_warning 'alias-test'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[WARN]"* ]]
  [[ "${output}" == *"alias-test"* ]]
}

# ── log_error ─────────────────────────────────────────────────────────────────

@test "log_error writes [ERROR] tag" {
  run _init_eval "log_error 'boom'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[ERROR]"* ]]
  [[ "${output}" == *"boom"* ]]
}

# ── source_env_file ───────────────────────────────────────────────────────────

@test "source_env_file loads variables from file" {
  local tmpenv
  tmpenv="$(mktemp /tmp/test.env.XXXXXX)"
  echo 'export TEST_VAR_BATS=hello123' > "${tmpenv}"

  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    PRIMARY_HOST=h REPLICA_HOST=r NAS_HOST=n APEX_DOMAIN=e ADMIN_EMAIL=a@e DEPLOYMENT_MODE=test \
    BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$ source '${INIT_SH}' && source_env_file '${tmpenv}' && echo \"\${TEST_VAR_BATS}\"
  " 2>&1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"hello123"* ]]
  rm -f "${tmpenv}"
}

@test "source_env_file is a no-op when file does not exist" {
  run _init_eval "source_env_file '/nonexistent/path/.env' && echo 'ok'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

# ── get_git_sha ───────────────────────────────────────────────────────────────

@test "get_git_sha returns a non-empty string inside a git repo" {
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    cd '${REPO_ROOT}'
    PRIMARY_HOST=h REPLICA_HOST=r NAS_HOST=n APEX_DOMAIN=e ADMIN_EMAIL=a@e DEPLOYMENT_MODE=test \
    BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$ source '${INIT_SH}' && get_git_sha
  " 2>&1
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "get_git_sha returns 'unknown' outside any git repo" {
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    cd /tmp
    PRIMARY_HOST=h REPLICA_HOST=r NAS_HOST=n APEX_DOMAIN=e ADMIN_EMAIL=a@e DEPLOYMENT_MODE=test \
    BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$ source '${INIT_SH}' && get_git_sha
  " 2>&1
  [ "${status}" -eq 0 ]
  [[ "${output}" == "unknown" ]]
}

# ── verify_git_clean ──────────────────────────────────────────────────────────

@test "verify_git_clean returns 0 when working tree is clean" {
  if [ -n "$(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null)" ]; then
    skip "Working tree has uncommitted changes — skipping clean-state test"
  fi
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    cd '${REPO_ROOT}'
    PRIMARY_HOST=h REPLICA_HOST=r NAS_HOST=n APEX_DOMAIN=e ADMIN_EMAIL=a@e DEPLOYMENT_MODE=test \
    BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$ source '${INIT_SH}' && verify_git_clean
  " 2>&1
  [ "${status}" -eq 0 ]
}

# ── validate_required_env ─────────────────────────────────────────────────────

@test "validate_required_env passes when all required vars are set" {
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    PRIMARY_HOST=h REPLICA_HOST=r NAS_HOST=n APEX_DOMAIN=example.com ADMIN_EMAIL=a@e DEPLOYMENT_MODE=test \
    BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$ source '${INIT_SH}' && validate_required_env
  " 2>&1
  [ "${status}" -eq 0 ]
}

@test "validate_required_env fails when APEX_DOMAIN is empty" {
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    PRIMARY_HOST=h REPLICA_HOST=r NAS_HOST=n APEX_DOMAIN=example.com ADMIN_EMAIL=a@e DEPLOYMENT_MODE=test \
    BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$ source '${INIT_SH}'
    APEX_DOMAIN='' validate_required_env
  " 2>&1
  [ "${status}" -ne 0 ]
}

@test "validate_required_env fails when ADMIN_EMAIL is empty" {
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    PRIMARY_HOST=h REPLICA_HOST=r NAS_HOST=n APEX_DOMAIN=example.com ADMIN_EMAIL=a@e DEPLOYMENT_MODE=test \
    BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$ source '${INIT_SH}'
    ADMIN_EMAIL='' validate_required_env
  " 2>&1
  [ "${status}" -ne 0 ]
}
