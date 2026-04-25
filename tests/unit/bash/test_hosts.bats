#!/usr/bin/env bats
# @file        tests/unit/bash/test_hosts.bats
# @description Unit tests for scripts/_common/hosts.sh
# @issue       #1537 — Testing & QA 100x: bats unit tests for scripts/_common/
# @coverage    derived FQDN defaults, override behaviour, check_host_connectivity

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../../" && pwd)"
HOSTS_SH="${REPO_ROOT}/scripts/_common/hosts.sh"

_hosts_eval() {
  local extra_env="${1:-}"
  local cmd="${2:-echo ok}"
  bash -c "
    unset _SCRIPT_INIT_SOURCED IDE_HOST API_HOST GRAFANA_HOST
    PRIMARY_HOST=primary.test.local REPLICA_HOST=replica.test.local NAS_HOST=nas.test.local
    APEX_DOMAIN=test.local ADMIN_EMAIL=ops@test.local DEPLOYMENT_MODE=test
    SSH_KEY=/tmp/test-key SSH_USER=ops BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$
    export PRIMARY_HOST REPLICA_HOST NAS_HOST APEX_DOMAIN ADMIN_EMAIL DEPLOYMENT_MODE SSH_KEY SSH_USER BOOTSTRAP_STATE_DIR
    ${extra_env}
    source '${HOSTS_SH}'
    ${cmd}
  " 2>&1
}

# ── Derived FQDN defaults ─────────────────────────────────────────────────────

@test "IDE_HOST defaults to ide.APEX_DOMAIN" {
  run _hosts_eval "" "echo \"\${IDE_HOST}\""
  [ "${status}" -eq 0 ]
  [ "${output}" = "ide.test.local" ]
}

@test "API_HOST defaults to api.APEX_DOMAIN" {
  run _hosts_eval "" "echo \"\${API_HOST}\""
  [ "${status}" -eq 0 ]
  [ "${output}" = "api.test.local" ]
}

@test "GRAFANA_HOST defaults to grafana.APEX_DOMAIN" {
  run _hosts_eval "" "echo \"\${GRAFANA_HOST}\""
  [ "${status}" -eq 0 ]
  [ "${output}" = "grafana.test.local" ]
}

@test "IDE_HOST is overridable via environment" {
  run _hosts_eval "export IDE_HOST=custom-ide.test.local" "echo \"\${IDE_HOST}\""
  [ "${status}" -eq 0 ]
  [ "${output}" = "custom-ide.test.local" ]
}

@test "API_HOST is overridable via environment" {
  run _hosts_eval "export API_HOST=my-api.example.com" "echo \"\${API_HOST}\""
  [ "${status}" -eq 0 ]
  [ "${output}" = "my-api.example.com" ]
}

# ── check_host_connectivity ───────────────────────────────────────────────────

@test "check_host_connectivity reports UNREACHABLE for documentation IPs (RFC-5737)" {
  # 192.0.2.x (TEST-NET-1) are guaranteed unreachable per RFC 5737
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    PRIMARY_HOST=192.0.2.1 REPLICA_HOST=192.0.2.2 NAS_HOST=192.0.2.3
    APEX_DOMAIN=test.local ADMIN_EMAIL=ops@test.local DEPLOYMENT_MODE=test
    SSH_KEY=/tmp/k SSH_USER=ops BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$
    export PRIMARY_HOST REPLICA_HOST NAS_HOST APEX_DOMAIN ADMIN_EMAIL DEPLOYMENT_MODE SSH_KEY SSH_USER BOOTSTRAP_STATE_DIR
    source '${HOSTS_SH}'
    check_host_connectivity 1
  " 2>&1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"UNREACHABLE"* ]]
}

@test "check_host_connectivity reports reachable for 127.0.0.1" {
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    PRIMARY_HOST=127.0.0.1 REPLICA_HOST=127.0.0.1 NAS_HOST=127.0.0.1
    APEX_DOMAIN=test.local ADMIN_EMAIL=ops@test.local DEPLOYMENT_MODE=test
    SSH_KEY=/tmp/k SSH_USER=ops BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$
    export PRIMARY_HOST REPLICA_HOST NAS_HOST APEX_DOMAIN ADMIN_EMAIL DEPLOYMENT_MODE SSH_KEY SSH_USER BOOTSTRAP_STATE_DIR
    source '${HOSTS_SH}'
    check_host_connectivity 2
  " 2>&1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reachable"* ]]
}

# ── Idempotency ────────────────────────────────────────────────────────────────

@test "sourcing hosts.sh twice is idempotent" {
  run bash -c "
    unset _SCRIPT_INIT_SOURCED
    PRIMARY_HOST=primary.test.local REPLICA_HOST=replica.test.local NAS_HOST=nas.test.local
    APEX_DOMAIN=test.local ADMIN_EMAIL=ops@test.local DEPLOYMENT_MODE=test
    SSH_KEY=/tmp/k SSH_USER=ops BOOTSTRAP_STATE_DIR=/tmp/bats-bs-\$\$
    export PRIMARY_HOST REPLICA_HOST NAS_HOST APEX_DOMAIN ADMIN_EMAIL DEPLOYMENT_MODE SSH_KEY SSH_USER BOOTSTRAP_STATE_DIR
    source '${HOSTS_SH}'
    source '${HOSTS_SH}'
    echo 'done'
  " 2>&1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"done"* ]]
}
