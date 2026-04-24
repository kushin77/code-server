#!/usr/bin/env bash
# @file        scripts/security/configure-egress-firewall.sh
# @module      security/firewall
# @description Configure zero-trust egress firewall rules (iptables) - P0 #1273
#
# Implements default-deny egress policy with whitelist-only exceptions.
# Requires sudo to modify iptables.
#
# Usage:
#   sudo bash scripts/security/configure-egress-firewall.sh --enable   # Enable firewall
#   sudo bash scripts/security/configure-egress-firewall.sh --disable  # Disable firewall
#   sudo bash scripts/security/configure-egress-firewall.sh --status   # Show current rules
#   bash scripts/security/configure-egress-firewall.sh --dry-run       # Preview changes (no sudo)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

DRY_RUN=0

# ============================================================================
# Firewall Configuration
# ============================================================================

enable_egress_firewall() {
  log_info "Configuring zero-trust egress firewall..."
  
  require_command iptables "iptables is required for firewall configuration"
  
  local iptables_cmd="iptables"
  if [ "$DRY_RUN" -eq 1 ]; then
    iptables_cmd="echo [DRY-RUN] iptables"
  fi
  
  # Set default policies
  log_info "Setting default OUTPUT policy to DROP..."
  $iptables_cmd -P OUTPUT DROP 2>/dev/null || log_warn "Could not set OUTPUT policy (may require --preserve-counters)"
  $iptables_cmd -P FORWARD DROP 2>/dev/null || log_warn "Could not set FORWARD policy"
  
  # Flush existing rules (careful!)
  log_warn "Flushing existing OUTPUT rules..."
  $iptables_cmd -F OUTPUT 2>/dev/null || true
  
  # Allow loopback (essential for system operation)
  log_info "  Allowing loopback interface..."
  $iptables_cmd -A OUTPUT -o lo -j ACCEPT
  
  # Allow Docker bridge traffic (inter-service mTLS)
  log_info "  Allowing Docker bridge (inter-service mTLS)..."
  $iptables_cmd -A OUTPUT -o docker0 -j ACCEPT
  $iptables_cmd -A OUTPUT -o br-+ -j ACCEPT
  
  # DNS (required for service discovery and external resolution)
  log_info "  Allowing DNS (UDP 53)..."
  $iptables_cmd -A OUTPUT -p udp --dport 53 -j ACCEPT
  
  # NTP (time synchronization, required for cert validation)
  log_info "  Allowing NTP (UDP 123)..."
  $iptables_cmd -A OUTPUT -p udp --dport 123 -j ACCEPT
  
  # HTTPS (443) for GitHub API, package registries, external APIs
  log_info "  Allowing HTTPS (TCP 443)..."
  $iptables_cmd -A OUTPUT -p tcp --dport 443 -j ACCEPT
  
  # SSH (22) for remote administration
  log_info "  Allowing SSH (TCP 22)..."
  $iptables_cmd -A OUTPUT -p tcp --dport 22 -j ACCEPT
  
  # NAS storage (2049) for backup/archival
  log_info "  Allowing NAS (192.168.168.56:2049)..."
  $iptables_cmd -A OUTPUT -d 192.168.168.56 -p tcp --dport 2049 -j ACCEPT
  $iptables_cmd -A OUTPUT -d 192.168.168.56 -p udp --dport 2049 -j ACCEPT
  
  # NFS portmapper (111) - ephemeral ports for NFS (also 2049)
  log_info "  Allowing NFS portmapper (UDP 111)..."
  $iptables_cmd -A OUTPUT -p udp --dport 111 -j ACCEPT
  
  # Prometheus scrape endpoints (9090-9999) - internal only
  log_info "  Allowing Prometheus metrics (9090-9999)..."
  $iptables_cmd -A OUTPUT -d 127.0.0.0/8 -p tcp --dport 9090:9999 -j ACCEPT
  $iptables_cmd -A OUTPUT -d 172.16.0.0/12 -p tcp --dport 9090:9999 -j ACCEPT  # Docker network
  
  # Replica host (192.168.168.42) for failover
  log_info "  Allowing replica host (192.168.168.42)..."
  $iptables_cmd -A OUTPUT -d 192.168.168.42 -j ACCEPT
  
  # Default deny all other egress traffic
  log_info "  Setting default deny for all other egress..."
  $iptables_cmd -A OUTPUT -j DROP
  
  if [ "$DRY_RUN" -eq 0 ]; then
    log_info "✅ Egress firewall enabled"
    log_warn "⚠️  Note: You may need to adjust rules if applications cannot reach expected destinations"
  else
    log_info "✅ [DRY-RUN] Firewall configuration displayed (no changes made)"
  fi
}

disable_egress_firewall() {
  log_info "Disabling egress firewall..."
  
  require_command iptables "iptables is required"
  
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] iptables -P OUTPUT ACCEPT"
    echo "[DRY-RUN] iptables -F OUTPUT"
    log_info "✅ [DRY-RUN] Firewall disable shown"
  else
    iptables -P OUTPUT ACCEPT
    iptables -F OUTPUT
    log_info "✅ Egress firewall disabled"
  fi
}

show_firewall_status() {
  log_info "Current egress firewall rules:"
  echo ""
  iptables -L OUTPUT -n -v
  echo ""
  log_info "Docker networks:"
  docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.ID}}" || log_warn "Docker not available"
}

show_firewall_preview() {
  log_info "Firewall rules that will be applied:"
  echo ""
  echo "Default OUTPUT policy: DROP"
  echo "Default FORWARD policy: DROP"
  echo ""
  echo "Allowed outbound traffic:"
  echo "  - Loopback interface (lo)"
  echo "  - Docker bridge (docker0, br-*)"
  echo "  - DNS (UDP 53)"
  echo "  - NTP (UDP 123)"
  echo "  - HTTPS (TCP 443)"
  echo "  - SSH (TCP 22)"
  echo "  - NAS storage (192.168.168.56:2049)"
  echo "  - NFS portmapper (UDP 111)"
  echo "  - Prometheus metrics (TCP 9090-9999)"
  echo "  - Replica host (192.168.168.42)"
  echo "  - All inter-Docker traffic"
  echo ""
  echo "All other outbound traffic: DENIED"
  echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
  local command="${1:-}"
  
  case "$command" in
    --enable)
      if [ "$EUID" -ne 0 ]; then
        log_error "Firewall configuration requires root privileges (sudo)"
        exit 1
      fi
      enable_egress_firewall
      ;;
    
    --disable)
      if [ "$EUID" -ne 0 ]; then
        log_error "Firewall configuration requires root privileges (sudo)"
        exit 1
      fi
      disable_egress_firewall
      ;;
    
    --status)
      show_firewall_status
      ;;
    
    --dry-run)
      DRY_RUN=1
      enable_egress_firewall
      show_firewall_preview
      ;;
    
    *)
      log_error "Usage: sudo $0 {--enable|--disable|--status}"
      log_info "       $0 --dry-run"
      log_info ""
      log_info "Commands:"
      log_info "  --enable   Enable zero-trust egress firewall (DROP default)"
      log_info "  --disable  Disable firewall (revert to ACCEPT)"
      log_info "  --status   Show current firewall rules"
      log_info "  --dry-run  Preview firewall rules without applying"
      exit 1
      ;;
  esac
}

main "$@"
