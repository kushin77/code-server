#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/setup-passwordless-sudo.sh
# @module      infrastructure/security
# @description Configure passwordless sudo for deployment operations (P1 #1636)
# @owner       platform
# @status      active
#
# USAGE
#   scripts/ops/setup-passwordless-sudo.sh [host1 host2 ...]
#
# Last Updated: April 23, 2026
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

require_command ssh "ssh is required for sudo configuration verification"

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa_onprem}"
SUDO_USER="${SUDO_USER:-${DEPLOY_USER}}"
SUDOERS_TEMPLATE="$SCRIPT_DIR/../../etc/sudoers.d/akushnir"

require_file "$SSH_KEY_PATH"
require_file "$SUDOERS_TEMPLATE"

if [[ $# -gt 0 ]]; then
    TARGET_HOSTS=("$@")
else
    TARGET_HOSTS=("$DEPLOY_HOST" "$STANDBY_HOST")
fi

apply_sudoers() {
    local host="$1"

    log_info "Checking sudo access on ${host}"
    assert_ssh_target "$host" "$SUDO_USER" "$SSH_KEY_PATH"

    if ssh_exec_target "$host" "$SUDO_USER" "sudo -n true" "$SSH_KEY_PATH" >/dev/null 2>&1; then
        log_info "${host} already has passwordless sudo"
        return 0
    fi

    log_warn "${host} still requires sudo password; verification will stop here"
    log_info "Manual bootstrap required on ${host} using /etc/sudoers.d/akushnir"
    return 0
}

main() {
    log_info "Starting passwordless sudo verification for deployment operations"
    log_info "Sudoers template: ${SUDOERS_TEMPLATE}"

    for host in "${TARGET_HOSTS[@]}"; do
        apply_sudoers "$host"
    done

    log_info "Passwordless sudo verification complete"
    log_info "Use the sudoers template to manually bootstrap any replica still requiring a password"
}

main "$@"
