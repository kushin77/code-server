#!/usr/bin/env bash
################################################################################
# File:          scripts/_common/ssh.sh
# Owner:         Platform Engineering
# Purpose:       Centralized SSH remote-execution helpers.
#                Eliminates inline ssh akushnir@192.168.168.31 patterns
#                duplicated across 50+ scripts.
# Compatibility: bash 4.0+
# Dependencies:  _common/config.sh, _common/logging.sh
# Source:        Loaded automatically by _common/init.sh — do NOT source directly
# Last Updated:  April 14, 2026
################################################################################

[[ -n "${_COMMON_SSH_LOADED:-}" ]] && return 0
readonly _COMMON_SSH_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CORE REMOTE EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

# Execute a command on the primary deploy host
# Usage: ssh_exec "docker ps"
ssh_exec() {
    log_debug "ssh_exec → $DEPLOY_USER@$DEPLOY_HOST: $*"
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$DEPLOY_USER@$DEPLOY_HOST" "$@"
}

# Execute a command on the standby host
# Usage: ssh_standby "docker ps"
ssh_standby() {
    log_debug "ssh_standby → $STANDBY_USER@$STANDBY_HOST: $*"
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$STANDBY_USER@$STANDBY_HOST" "$@"
}

# Stream a local script to the remote host and execute it
# Usage: ssh_stream ./scripts/some-script.sh [args...]
ssh_stream() {
    local script="$1"
    shift
    require_file "$script"
    log_debug "ssh_stream → $DEPLOY_USER@$DEPLOY_HOST: $script $*"
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$DEPLOY_USER@$DEPLOY_HOST" "bash -s -- $*" < "$script"
}

# Upload a file to the deploy host
# Usage: ssh_upload ./local-file.sh /remote/path/file.sh
ssh_upload() {
    local src="$1"
    local dst="$2"
    require_file "$src"
    log_debug "ssh_upload: $src → $DEPLOY_USER@$DEPLOY_HOST:$dst"
    scp $SSH_OPTS "$src" "$DEPLOY_USER@$DEPLOY_HOST:$dst"
}

# Upload a directory recursively
# Usage: ssh_upload_dir ./local-dir /remote/path
ssh_upload_dir() {
    local src="$1"
    local dst="$2"
    require_dir "$src"
    log_debug "ssh_upload_dir: $src → $DEPLOY_USER@$DEPLOY_HOST:$dst"
    scp $SSH_OPTS -r "$src" "$DEPLOY_USER@$DEPLOY_HOST:$dst"
}

# ─────────────────────────────────────────────────────────────────────────────
# CONNECTIVITY CHECKS
# ─────────────────────────────────────────────────────────────────────────────

# Assert SSH connectivity before running any remote operation
# Usage: assert_ssh_up
assert_ssh_up() {
    local target_host="${1:-$DEPLOY_HOST}"
    local target_user="${2:-$DEPLOY_USER}"
    if ! timeout "$SSH_CONNECT_TIMEOUT" ssh $SSH_OPTS "$target_user@$target_host" "echo OK" > /dev/null 2>&1; then
        log_fatal "Cannot SSH to $target_user@$target_host — is the host reachable?"
    fi
    log_debug "✓ SSH connectivity confirmed: $target_user@$target_host"
}

# Assert a TCP port is reachable
# Usage: assert_port_open 443
assert_port_open() {
    local port="$1"
    local host="${2:-$DEPLOY_HOST}"
    if ! nc -z -w "${SSH_CONNECT_TIMEOUT}" "$host" "$port" > /dev/null 2>&1; then
        log_fatal "Port $port unreachable on $host"
    fi
    log_debug "✓ Port $port open on $host"
}

# ─────────────────────────────────────────────────────────────────────────────
# REMOTE CD + EXEC HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Run a command in DEPLOY_DIR on the remote host
# Usage: ssh_in_deploy_dir "docker compose ps"
ssh_in_deploy_dir() {
    ssh_exec "cd $DEPLOY_DIR && $*"
}

# Run a docker compose command on the remote host
# Usage: ssh_compose "up -d code-server"
ssh_compose() {
    ssh_in_deploy_dir "docker compose $*"
}

# Verify key-only SSH authentication for one or more remote targets.
# Usage:
#   verify_passwordless_ssh                       # checks primary + standby
#   verify_passwordless_ssh "user1@host1" "user2@host2"
verify_passwordless_ssh() {
    local targets=("$@")
    local failed=0

    if [[ ${#targets[@]} -eq 0 ]]; then
        targets=(
            "$DEPLOY_USER@$DEPLOY_HOST"
            "$STANDBY_USER@$STANDBY_HOST"
        )
    fi

    for target in "${targets[@]}"; do
        if ssh $SSH_OPTS "$target" "echo passwordless-ok" >/dev/null 2>&1; then
            log_success "Passwordless SSH verified: $target"
        else
            log_failure "Passwordless SSH failed: $target"
            failed=1
        fi
    done

    if [[ $failed -ne 0 ]]; then
        log_error "One or more passwordless SSH checks failed"
        return 1
    fi

    return 0
}
