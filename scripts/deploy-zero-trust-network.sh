#!/usr/bin/env bash
################################################################################
# @file        scripts/deploy-zero-trust-network.sh
# @module      security/zero-trust
# @description Deploy and verify zero-trust network access controls (mTLS, egress policy, audit logs).
# @owner       platform
# @status      active
#
# USAGE
#   scripts/deploy-zero-trust-network.sh [apply|verify|audit] [--dry-run]
#
# ENVIRONMENT VARIABLES (from .env, loaded by _common/init.sh)
#   DEPLOY_HOST       - Production host IP/FQDN (e.g., 192.168.168.31)
#   DEPLOY_USER       - SSH user (e.g., akushnir)
#   DOMAIN            - Public domain (e.g., kushnir.cloud)
#
# EXIT CODES
#   0 - Success
#   1 - General error
#   2 - Config error
#   127 - Missing required command
#
# NOTES
#   - This script follows GOV-001 (Canonical Libraries) and GOV-002 (Metadata Headers)
#   - It orchestrates existing mTLS and iptables scripts instead of duplicating their logic
#   - The 24h rotation schedule is installed via a systemd timer
#   - All configuration comes from environment variables, never hardcoded
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

source "$SCRIPT_DIR/_common/init.sh"

readonly MTLS_SCRIPT="${SCRIPT_DIR}/mtls-certificate-management.sh"
readonly NETWORK_SCRIPT="${SCRIPT_DIR}/network-security-management.sh"
readonly MTLS_ROTATION_SERVICE="/etc/systemd/system/zero-trust-mtls-rotation.service"
readonly MTLS_ROTATION_TIMER="/etc/systemd/system/zero-trust-mtls-rotation.timer"
readonly NETWORK_POLICY_SERVICE="/etc/systemd/system/zero-trust-network-policy.service"

DRY_RUN="false"
COMMAND="apply"

require_command "bash" "bash is required to orchestrate zero-trust scripts"

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy-zero-trust-network.sh [apply|verify|audit] [--dry-run]

Commands:
  apply    Bootstrap mTLS, install rotation timer, apply egress policy, verify, and audit
  verify   Validate certificates, policy state, and audit visibility
  audit    Show recent zero-trust audit events

Options:
  --dry-run  Log the actions that would be performed without changing the system
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      apply|verify|audit)
        COMMAND="$1"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown argument: $1"
        usage
        return 1
        ;;
    esac
  done

}

privileged() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would run privileged command: $*"
    return 0
  fi

  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    require_command "sudo" "sudo is required for privileged zero-trust operations"
    sudo "$@"
  fi
}

run_script() {
  local script_path="$1"
  local script_args=("${@:2}")

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would run: bash ${script_path} ${script_args[*]}"
    return 0
  fi

  bash "$script_path" "${script_args[@]}"
}

write_unit() {
  local target="$1"
  local content="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would write systemd unit: $target"
    return 0
  fi

  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    printf '%s' "$content" | tee "$target" >/dev/null
  else
    require_command "sudo" "sudo is required to write systemd units"
    printf '%s' "$content" | sudo tee "$target" >/dev/null
  fi
}

bootstrap_mtls() {
  if [[ -f "${SCRIPT_DIR}/mtls-ca/ca.crt" && -f "${SCRIPT_DIR}/mtls-ca/ca.key" ]]; then
    log_info "Refreshing existing mTLS certificates"
    run_script "$MTLS_SCRIPT" rotate
  else
    log_info "Bootstrapping mTLS CA and initial certificates"
    run_script "$MTLS_SCRIPT" init
  fi
}

install_rotation_timer() {
  log_info "Installing 24h mTLS rotation timer"

  local service_content="[Unit]
Description=Zero-Trust mTLS Certificate Rotation
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/bin/bash ${MTLS_SCRIPT} rotate
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
"

  local timer_content="[Unit]
Description=Run zero-trust mTLS certificate rotation every 24 hours

[Timer]
OnBootSec=15m
OnUnitActiveSec=24h
Persistent=true

[Install]
WantedBy=timers.target
"

write_unit "$MTLS_ROTATION_SERVICE" "$service_content"
write_unit "$MTLS_ROTATION_TIMER" "$timer_content"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY-RUN] Would reload systemd and enable zero-trust-mtls-rotation.timer"
  return 0
fi

privileged systemctl daemon-reload
privileged systemctl enable --now zero-trust-mtls-rotation.timer
}

install_network_policy_service() {
  log_info "Installing network policy boot service"

  local service_content="[Unit]
Description=Zero-Trust Network Policy
After=network.target docker.service
Wants=docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/bin/bash ${NETWORK_SCRIPT} apply
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
"

  write_unit "$NETWORK_POLICY_SERVICE" "$service_content"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would reload systemd and enable zero-trust-network-policy.service"
    return 0
  fi

  privileged systemctl daemon-reload
  privileged systemctl enable zero-trust-network-policy.service
  privileged systemctl start zero-trust-network-policy.service
}

verify_audit_visibility() {
  log_info "Checking recent zero-trust audit visibility"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would inspect journalctl for ZERO-TRUST events"
    return 0
  fi

  if command -v journalctl >/dev/null 2>&1; then
    journalctl -k -g "ZERO-TRUST" --since "24 hours ago" --no-pager 2>/dev/null | tail -20 || true
  else
    log_warn "journalctl not available; skipping audit log inspection"
  fi
}

apply_zero_trust() {
  log_info "Applying zero-trust network access"
  bootstrap_mtls
  install_rotation_timer
  install_network_policy_service

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would verify certificates and network policy after deployment"
    return 0
  fi

  run_script "$MTLS_SCRIPT" verify
  run_script "$NETWORK_SCRIPT" verify
  verify_audit_visibility
}

verify_zero_trust() {
  log_info "Verifying zero-trust network access"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would verify mTLS certificates, egress policy, and timer/service state"
    return 0
  fi

  run_script "$MTLS_SCRIPT" verify
  run_script "$NETWORK_SCRIPT" verify

  privileged systemctl is-enabled zero-trust-mtls-rotation.timer >/dev/null
  privileged systemctl is-enabled zero-trust-network-policy.service >/dev/null
  verify_audit_visibility
}

audit_zero_trust() {
  verify_audit_visibility
}

main() {
  parse_args "$@"

  case "$COMMAND" in
    apply)
      apply_zero_trust
      ;;
    verify)
      verify_zero_trust
      ;;
    audit)
      audit_zero_trust
      ;;
    *)
      log_error "Unsupported command: $COMMAND"
      usage
      return 2
      ;;
  esac

  log_info "Zero-trust network access workflow completed successfully"
}

main "$@"