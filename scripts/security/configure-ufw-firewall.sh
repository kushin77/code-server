#!/usr/bin/env bash
# @file        scripts/security/configure-ufw-firewall.sh
# @module      security/firewall
# @description Configure UFW firewall rules for production hardening

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR%/scripts*}" && pwd)"

# Source common utilities
source "${PROJECT_ROOT}/scripts/_common/init.sh" || {
  echo "ERROR: Cannot load init.sh" >&2
  exit 1
}

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════

INTERNAL_SUBNET="${INTERNAL_SUBNET:-192.168.168.0/24}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
NAS_HOST="${NAS_HOST:-192.168.168.55}"

DRY_RUN="${DRY_RUN:-0}"

# ════════════════════════════════════════════════════════════════════════════
# Functions
# ════════════════════════════════════════════════════════════════════════════

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_fatal "This script requires root privileges (use sudo)"
  fi
}

check_ufw() {
  if ! command -v ufw &>/dev/null; then
    log_fatal "UFW not installed. Install with: sudo apt-get install ufw"
  fi
  log_info "UFW found at $(which ufw)"
}

ufw_cmd() {
  local cmd="$@"
  
  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] ufw $cmd"
  else
    log_info "Executing: ufw $cmd"
    ufw $cmd
  fi
}

configure_default_policy() {
  log_info "Setting default firewall policies..."
  
  ufw_cmd "default deny incoming"
  ufw_cmd "default allow outgoing"
  ufw_cmd "default deny routed"
  
  log_info "Default policies configured"
}

allow_critical_access() {
  log_info "Allowing critical access..."
  
  # SSH (prevent lockout)
  ufw_cmd "allow 22/tcp comment 'SSH access for administration'"
  
  # HTTP/HTTPS (public-facing)
  ufw_cmd "allow 80/tcp comment 'HTTP - redirects to HTTPS'"
  ufw_cmd "allow 443/tcp comment 'HTTPS - production traffic'"
  
  log_info "Critical access rules added"
}

allow_internal_services() {
  log_info "Allowing internal service access from ${INTERNAL_SUBNET}..."
  
  # Prometheus (metrics scraping)
  ufw_cmd "allow from ${INTERNAL_SUBNET} to any port 9090 comment 'Prometheus metrics'"
  
  # AlertManager (alert routing)
  ufw_cmd "allow from ${INTERNAL_SUBNET} to any port 9093 comment 'AlertManager alerts API'"
  
  # Grafana (dashboards)
  ufw_cmd "allow from ${INTERNAL_SUBNET} to any port 3000 comment 'Grafana dashboards'"
  
  # Redis Sentinel (HA failover from replica)
  ufw_cmd "allow from ${REPLICA_HOST} to any port 26379 comment 'Sentinel from replica HA'"
  
  log_info "Internal service rules added"
}

allow_nas_access() {
  log_info "Allowing NAS (NFS) access to ${NAS_HOST}..."
  
  # NFS (network file system)
  ufw_cmd "allow to ${NAS_HOST} port 2049 comment 'NFS from NAS storage'"
  ufw_cmd "allow to ${NAS_HOST} port 111 comment 'NFS portmapper'"
  
  log_info "NAS access rules added"
}

block_docker_internal() {
  log_info "Blocking Docker internal ports from external access..."
  
  # Docker API (should be socket-only)
  ufw_cmd "deny 2375/tcp comment 'Docker API - must use socket only'"
  ufw_cmd "deny 2376/tcp comment 'Docker TLS API - must use socket only'"
  
  # Redis (allow only from localhost + Sentinel)
  ufw_cmd "deny 6379/tcp comment 'Redis - localhost and container only'"
  
  # PostgreSQL (allow only from container network)
  ufw_cmd "deny 5432/tcp comment 'PostgreSQL - container network only'"
  
  # pgbouncer (internal only)
  ufw_cmd "deny 6432/tcp comment 'pgbouncer - container network only'"
  
  log_info "Docker internal ports blocked"
}

enable_firewall() {
  log_info "Enabling UFW..."
  
  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] ufw enable"
  else
    echo "y" | ufw enable || {
      log_warn "UFW enable returned non-zero, checking status..."
      ufw status verbose
    }
  fi
  
  log_info "Firewall enabled"
}

verify_ssh_access() {
  log_info "Verifying SSH rule is in place..."
  
  if ufw status numbered | grep -q "22/tcp"; then
    log_info "✅ SSH rule verified"
  else
    log_warn "⚠️ SSH rule not found - may have connectivity issues!"
  fi
}

show_status() {
  log_info "Current firewall status:"
  ufw status verbose || log_warn "Could not retrieve status"
}

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

main() {
  log_info "Starting UFW firewall configuration"
  
  if [[ "${DRY_RUN}" == "1" ]]; then
    log_warn "DRY-RUN MODE: No changes will be applied"
  fi
  
  check_root
  check_ufw
  
  configure_default_policy
  allow_critical_access
  allow_internal_services
  allow_nas_access
  block_docker_internal
  enable_firewall
  verify_ssh_access
  show_status
  
  log_info "Firewall configuration completed successfully"
  
  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "To apply changes, run: DRY_RUN=0 sudo $0"
  fi
}

trap 'log_fatal "Configuration failed at line $LINENO"' ERR
main "$@"
