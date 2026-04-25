#!/bin/bash
# @file scripts/ops/manage-hosts-file.sh
# @description /etc/hosts File Management (Idempotent IaC)
# @governance GOV-002: Deterministic host entry management, versioned in Git
# @author GitHub Copilot
# @date 2026-04-25
# @related P3 #1536 Phase 3 - DNS Architecture

set -euo pipefail

################################################################################
# NETWORK CONFIGURATION SSOT
################################################################################

# Load network configuration SSOT
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../scripts/_common/_epic-1536-network-config.env" || {
    echo "Error: Network configuration SSOT not found"
    exit 1
}

################################################################################
# CONFIGURATION (Environment-Driven)
################################################################################

HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"
BACKUP_DIR="${BACKUP_DIR:-/etc/hosts.backups}"
BACKUP_FILE="${BACKUP_DIR}/hosts.$(date +'%Y%m%d-%H%M%S').bak"

# Infrastructure hosts (override via environment variables)
PRIMARY_HOST="${PRIMARY_HOST:-${ONPREM_PRIMARY_IP}}"
REPLICA_HOST="${REPLICA_HOST:-${ONPREM_REPLICA_IP}}"
NAS_HOST="${NAS_HOST:-${ONPREM_NAS_IP}}"
VRRP_VIP="${VRRP_VIP:-${ONPREM_VRRP_VIP}}"

APEX_DOMAIN="${APEX_DOMAIN:-${DNS_ZONE}}"
IDE_DOMAIN="${IDE_DOMAIN:-${APP_IDE_DOMAIN}}"
API_DOMAIN="${API_DOMAIN:-${APP_API_DOMAIN}}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-${APP_ADMIN_DOMAIN}}"
AUTH_DOMAIN="${AUTH_DOMAIN:-${APP_AUTH_DOMAIN}}"
STATUS_DOMAIN="${STATUS_DOMAIN:-${APP_STATUS_DOMAIN}}"

# Marker for managed entries (prevents clobbering user entries)
MARKER_START="# BEGIN KUSHNIR.CLOUD MANAGED ENTRIES"
MARKER_END="# END KUSHNIR.CLOUD MANAGED ENTRIES"

################################################################################
# COLOR CODES
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

################################################################################
# LOGGING
################################################################################

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

warning() {
  echo -e "${YELLOW}[⚠]${NC} $*"
}

################################################################################
# PREREQUISITES
################################################################################

check_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
  fi
}

ensure_backup_dir() {
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  success "Backup directory ready: $BACKUP_DIR"
}

################################################################################
# BACKUP & IDEMPOTENCY
################################################################################

backup_hosts_file() {
  if [[ ! -f "$HOSTS_FILE" ]]; then
    error "Hosts file not found: $HOSTS_FILE"
  fi

  cp "$HOSTS_FILE" "$BACKUP_FILE"
  chmod 600 "$BACKUP_FILE"
  success "Backed up hosts file: $BACKUP_FILE"
}

is_already_managed() {
  # Check if our managed section exists
  if grep -q "$MARKER_START" "$HOSTS_FILE"; then
    return 0  # Already managed
  fi
  return 1  # Not yet managed
}

remove_old_managed_entries() {
  # Remove old managed section if it exists
  if is_already_managed; then
    log "Removing old managed entries..."
    
    # Create temporary file with entries outside of managed section
    local temp_file
    temp_file=$(mktemp)
    
    awk "
      /$MARKER_START/,/$MARKER_END/ {
        next  # Skip managed section
      }
      { print }
    " "$HOSTS_FILE" > "$temp_file"
    
    mv "$temp_file" "$HOSTS_FILE"
    success "Old managed entries removed"
  fi
}

################################################################################
# GENERATE NEW MANAGED ENTRIES
################################################################################

generate_hosts_entries() {
  cat << EOF

$MARKER_START
# Infrastructure Hosts (Idempotent IaC Management)
# Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
# Update via: manage-hosts-file.sh with environment variables

# Primary infrastructure node
$PRIMARY_HOST    primary.internal
$PRIMARY_HOST    ${APEX_DOMAIN}
$PRIMARY_HOST    ${IDE_DOMAIN}
$PRIMARY_HOST    ${API_DOMAIN}
$PRIMARY_HOST    ${ADMIN_DOMAIN}
$PRIMARY_HOST    ${AUTH_DOMAIN}
$PRIMARY_HOST    ${STATUS_DOMAIN}

# Replica infrastructure node
$REPLICA_HOST    replica.internal
$REPLICA_HOST    replica.${APEX_DOMAIN}

# VRRP Virtual IP (for HA failover)
$VRRP_VIP        vip.internal
$VRRP_VIP        vip.${APEX_DOMAIN}

# NAS Storage
$NAS_HOST        nas.internal
$NAS_HOST        nas.${APEX_DOMAIN}

# Localhost entries (standard)
127.0.0.1        localhost
127.0.0.1        localhost.localdomain
::1              localhost
::1              localhost.localdomain

$MARKER_END
EOF
}

################################################################################
# DEPLOY & VERIFY
################################################################################

apply_hosts_configuration() {
  log "Applying hosts file configuration..."

  # Remove old entries
  remove_old_managed_entries

  # Append new managed entries
  generate_hosts_entries >> "$HOSTS_FILE"

  success "Hosts file updated"
}

verify_hosts_entries() {
  log "Verifying hosts entries..."

  echo -e "\n${BLUE}=== Managed Entries ===${NC}"
  sed -n "/$MARKER_START/,/$MARKER_END/p" "$HOSTS_FILE" | grep -v "^#" | grep -v "^$"

  # Verify key entries exist
  local test_entries=(
    "$PRIMARY_HOST.*${APEX_DOMAIN}"
    "$REPLICA_HOST.*replica"
    "$VRRP_VIP.*vip"
    "$NAS_HOST.*nas"
  )

  local passed=0
  local failed=0

  for entry in "${test_entries[@]}"; do
    if grep -q "$entry" "$HOSTS_FILE"; then
      ((passed++))
    else
      ((failed++))
      warning "Missing entry: $entry"
    fi
  done

  echo -e "\n${BLUE}=== Verification ===${NC}"
  success "$passed entries verified"
  if [[ $failed -gt 0 ]]; then
    warning "$failed entries missing"
    return 1
  fi
}

test_dns_resolution() {
  log "Testing DNS resolution..."

  echo -e "\n${BLUE}=== Resolution Tests ===${NC}"

  # Test hostname resolution
  local test_hosts=(
    "$APEX_DOMAIN"
    "$IDE_DOMAIN"
    "primary.internal"
    "vip.internal"
  )

  for hostname in "${test_hosts[@]}"; do
    if ip_addr=$(grep -m1 "^[^#]*[[:space:]]${hostname}$" "$HOSTS_FILE" | awk '{print $1}'); then
      echo "✓ $hostname → $ip_addr"
    else
      warning "Resolution failed: $hostname"
    fi
  done
}

################################################################################
# RESTORE FUNCTIONALITY
################################################################################

restore_hosts_file() {
  local backup_file="$1"

  if [[ ! -f "$backup_file" ]]; then
    error "Backup file not found: $backup_file"
  fi

  log "Restoring hosts file from backup: $backup_file"
  cp "$backup_file" "$HOSTS_FILE"
  success "Hosts file restored"
}

list_backups() {
  log "Available backups:"
  if [[ -d "$BACKUP_DIR" ]]; then
    ls -lh "$BACKUP_DIR"/hosts.*.bak | awk '{print $9, "(" $5 ")"}'
  else
    warning "No backups directory found"
  fi
}

################################################################################
# AUDIT & DOCUMENTATION
################################################################################

document_configuration() {
  cat << EOF

╔════════════════════════════════════════════════════════════════╗
║  /etc/hosts Configuration Summary                              ║
╚════════════════════════════════════════════════════════════════╝

Primary Host:        $PRIMARY_HOST
Replica Host:        $REPLICA_HOST
NAS Host:            $NAS_HOST
VRRP Virtual IP:     $VRRP_VIP

Domain (Apex):       $APEX_DOMAIN
IDE Service:         $IDE_DOMAIN
API Gateway:         $API_DOMAIN
Admin Panel:         $ADMIN_DOMAIN
Auth Service:        $AUTH_DOMAIN
Status Page:         $STATUS_DOMAIN

Configuration File:  $HOSTS_FILE
Backup Directory:    $BACKUP_DIR
Managed Marker:      $MARKER_START → $MARKER_END

GOV-002 Compliance:
  ✓ Idempotent (safe to re-run)
  ✓ Deterministic (environment-driven)
  ✓ Audited (backup before apply)
  ✓ Reversible (restore from backup)

EOF
}

################################################################################
# COMMAND-LINE INTERFACE
################################################################################

usage() {
  cat << EOF
Usage: $0 [COMMAND]

Commands:
  apply        Apply hosts file configuration (default)
  verify       Verify current hosts entries
  test         Test DNS resolution via hosts file
  restore      Restore from backup (prompt for selection)
  list         List available backups
  backup       Create backup only (don't apply)
  status       Show current configuration

Environment Variables:
  PRIMARY_HOST         Primary host IP (default: )
  REPLICA_HOST         Replica host IP (default: )
  NAS_HOST             NAS host IP (default: )
  VRRP_VIP             VRRP virtual IP (default: )
  APEX_DOMAIN          Domain name (default: kushnir.cloud)
  HOSTS_FILE           Path to hosts file (default: /etc/hosts)

Examples:
  # Apply configuration
  $0 apply

  # Verify configuration with custom primary host
  PRIMARY_HOST=\${ONPREM_PRIMARY_IP} $0 verify

  # Restore from backup
  $0 restore

  # Show status
  $0 status

EOF
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
  local command="${1:-apply}"

  log "╔════════════════════════════════════════════════════════╗"
  log "║  /etc/hosts IaC Management                            ║"
  log "║  Command: $command"
  log "╚════════════════════════════════════════════════════════╝"

  check_root
  ensure_backup_dir

  case "$command" in
    apply)
      backup_hosts_file
      apply_hosts_configuration
      verify_hosts_entries
      test_dns_resolution
      document_configuration
      success "Hosts configuration applied successfully"
      ;;
    verify)
      verify_hosts_entries
      test_dns_resolution
      ;;
    test)
      test_dns_resolution
      ;;
    restore)
      list_backups
      read -p "Enter backup file path to restore: " backup_file
      restore_hosts_file "$backup_file"
      verify_hosts_entries
      ;;
    list)
      list_backups
      ;;
    backup)
      backup_hosts_file
      ;;
    status)
      document_configuration
      verify_hosts_entries
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      error "Unknown command: $command"
      ;;
  esac
}

main "$@"
