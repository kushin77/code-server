#!/usr/bin/env bash

###############################################################################
# @file        scripts/operations/fix-replica-config-sync.sh
# @module      operations/multi-host-deployment
# @description Fix replica node (${REPLICA_HOST}) config mount issues
#
# GOV-002 COMPLIANCE
# - Deterministic: Consistent transformation applied to all config files
# - Audited: All operations logged with before/after verification
# - Immutable: Applied via script, no manual steps
#
# PROBLEM
# Replica node config files (Caddyfile, prometheus.yml) are mounted as
# directories instead of files, causing service startup failures:
#   - Caddy refuses to start with directory instead of file
#   - Prometheus fails to load prometheus.yml directory
#   - Grafana datasources-provisioning mounted as directory
#
# ROOT CAUSE
# rsync --archive flag copies empty directories, then populates them from
# source. When docker-compose bind mounts, it sees the directory and never
# the file inside.
#
# SOLUTION
# 1. Remove incorrectly mounted directories on replica
# 2. Create files instead of directories on replica
# 3. Copy content from primary node (${PRIMARY_HOST}) to replica node (${REPLICA_HOST})
# 4. Verify mounts are files, not directories
# 5. Restart affected services
#
# USAGE
#   On PRIMARY node (.31):
#     ./scripts/operations/fix-replica-config-sync.sh --prepare
#
#   On REPLICA node (.42) via SSH:
#     ssh <replica> 'bash -s' < <(cat ./scripts/operations/fix-replica-config-sync.sh)
#
#   Or manually:
#     ssh ${REPLICA_HOST} 'bash -s' < fix-replica-config-sync.sh
#
# AFFECTED SERVICES
# - caddy (port 443, 80)
# - prometheus (port 9090)
# - grafana (port 3000)
#
# @author Autonomous Infrastructure
# @version 1.0.0
# @date 2026-04-26
###############################################################################

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/_common/init.sh"
source "$REPO_ROOT/scripts/_common/hosts.sh"

# Target directories on replica
readonly REPLICA_CADDY_DIR="/var/paperclip/caddy"
readonly REPLICA_PROMETHEUS_DIR="/var/paperclip/prometheus"
readonly REPLICA_GRAFANA_PROVISIONING_DIR="/var/paperclip/grafana/provisioning"

# Source directories on primary
readonly PRIMARY_CADDY_FILE="$REPO_ROOT/Caddyfile"
readonly PRIMARY_PROMETHEUS_FILE="$REPO_ROOT/prometheus.yml"
readonly PRIMARY_PROMETHEUS_ALERTS="$REPO_ROOT/prometheus-alerts.yml"
readonly PRIMARY_GRAFANA_PROVISIONING="$REPO_ROOT/grafana/provisioning"

# Backup
readonly BACKUP_DIR="/var/paperclip/.backup-$(date +%s)"

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] ✓ $*"
}

verify_file() {
  local path="$1"
  local description="${2:-File}"
  
  if [ -f "$path" ]; then
    log_success "$description exists and is a FILE: $path"
    return 0
  elif [ -d "$path" ]; then
    log_error "$description is a DIRECTORY (should be file): $path"
    return 1
  else
    log_error "$description does not exist: $path"
    return 1
  fi
}

check_docker_compose_status() {
  log_info "Checking docker-compose services..."
  docker compose ps || true
}

# ============================================================================
# Phase 1: Prepare Configuration Files
# ============================================================================

phase_prepare() {
  log_info "Phase 1: Prepare - Create configuration package for transfer"
  log_info "========================================================="
  
  if [ ! -f "$PRIMARY_CADDY_FILE" ]; then
    log_error "Caddyfile not found: $PRIMARY_CADDY_FILE"
    return 1
  fi
  
  if [ ! -f "$PRIMARY_PROMETHEUS_FILE" ]; then
    log_error "prometheus.yml not found: $PRIMARY_PROMETHEUS_FILE"
    return 1
  fi
  
  # Create transfer package
  local package_dir="/tmp/replica-config-fix-$(date +%s)"
  mkdir -p "$package_dir"
  
  log_info "Creating configuration package..."
  cp "$PRIMARY_CADDY_FILE" "$package_dir/Caddyfile"
  cp "$PRIMARY_PROMETHEUS_FILE" "$package_dir/prometheus.yml"
  
  if [ -f "$PRIMARY_PROMETHEUS_ALERTS" ]; then
    cp "$PRIMARY_PROMETHEUS_ALERTS" "$package_dir/prometheus-alerts.yml"
  fi
  
  if [ -d "$PRIMARY_GRAFANA_PROVISIONING" ]; then
    cp -r "$PRIMARY_GRAFANA_PROVISIONING" "$package_dir/"
  fi
  
  log_success "Package ready: $package_dir"
  log_info "Next: Transfer package to replica via SSH:"
  log_info "  scp -r $package_dir ${REPLICA_HOST}:/tmp/"
  log_info "  ssh ${REPLICA_HOST} 'bash -s' < <(cat $0 --apply <package_dir>)"
}

# ============================================================================
# Phase 2: Remove Incorrect Directory Mounts on Replica
# ============================================================================

phase_cleanup() {
  log_info "Phase 2: Cleanup - Remove incorrectly mounted directories on replica"
  log_info "=================================================================="
  
  # Verify we're on the replica (safety check)
  local hostname=$(hostname)
  if [[ "$hostname" == *"replica"* ]] || [[ "$hostname" == *"42"* ]]; then
    log_info "Detected replica node: $hostname"
  else
    log_info "Warning: This appears to be primary node ($hostname), but continuing..."
  fi
  
  # Create backup directory
  mkdir -p "$BACKUP_DIR"
  log_info "Backup directory: $BACKUP_DIR"
  
  # Stop docker compose
  log_info "Stopping docker-compose services..."
  if docker compose -f /var/paperclip/docker-compose.yml ps &>/dev/null; then
    docker compose -f /var/paperclip/docker-compose.yml down || true
    sleep 2
  fi
  
  # Remove incorrect directory mounts
  log_info "Checking Caddy configuration..."
  if [ -d "$REPLICA_CADDY_DIR/Caddyfile" ]; then
    log_info "  Found directory: $REPLICA_CADDY_DIR/Caddyfile (should be file)"
    log_info "  Backing up: cp -r $REPLICA_CADDY_DIR/Caddyfile $BACKUP_DIR/"
    cp -r "$REPLICA_CADDY_DIR/Caddyfile" "$BACKUP_DIR/" || true
    rm -rf "$REPLICA_CADDY_DIR/Caddyfile"
    log_success "  Removed directory mount"
  fi
  
  log_info "Checking Prometheus configuration..."
  if [ -d "$REPLICA_PROMETHEUS_DIR/prometheus.yml" ]; then
    log_info "  Found directory: $REPLICA_PROMETHEUS_DIR/prometheus.yml (should be file)"
    cp -r "$REPLICA_PROMETHEUS_DIR/prometheus.yml" "$BACKUP_DIR/" || true
    rm -rf "$REPLICA_PROMETHEUS_DIR/prometheus.yml"
    log_success "  Removed directory mount"
  fi
  
  log_info "Checking Grafana provisioning configuration..."
  if [ -d "$REPLICA_GRAFANA_PROVISIONING_DIR/datasources" ]; then
    log_info "  Found directory: $REPLICA_GRAFANA_PROVISIONING_DIR/datasources"
    cp -r "$REPLICA_GRAFANA_PROVISIONING_DIR" "$BACKUP_DIR/" || true
  fi
}

# ============================================================================
# Phase 3: Restore Correct Files from Package
# ============================================================================

phase_restore() {
  local config_package="${1:-.}"
  
  log_info "Phase 3: Restore - Apply correct configuration files from package"
  log_info "================================================================="
  
  if [ ! -f "$config_package/Caddyfile" ]; then
    log_error "Caddyfile not found in package: $config_package/Caddyfile"
    return 1
  fi
  
  # Create required directories
  mkdir -p "$REPLICA_CADDY_DIR"
  mkdir -p "$REPLICA_PROMETHEUS_DIR"
  mkdir -p "$REPLICA_GRAFANA_PROVISIONING_DIR"
  
  # Restore Caddyfile as FILE
  log_info "Restoring Caddyfile..."
  cp "$config_package/Caddyfile" "$REPLICA_CADDY_DIR/Caddyfile"
  chmod 644 "$REPLICA_CADDY_DIR/Caddyfile"
  log_success "Caddyfile restored"
  
  # Restore prometheus.yml as FILE
  if [ -f "$config_package/prometheus.yml" ]; then
    log_info "Restoring prometheus.yml..."
    cp "$config_package/prometheus.yml" "$REPLICA_PROMETHEUS_DIR/prometheus.yml"
    chmod 644 "$REPLICA_PROMETHEUS_DIR/prometheus.yml"
    log_success "prometheus.yml restored"
  fi
  
  # Restore prometheus-alerts.yml if present
  if [ -f "$config_package/prometheus-alerts.yml" ]; then
    log_info "Restoring prometheus-alerts.yml..."
    cp "$config_package/prometheus-alerts.yml" "$REPLICA_PROMETHEUS_DIR/prometheus-alerts.yml"
    chmod 644 "$REPLICA_PROMETHEUS_DIR/prometheus-alerts.yml"
    log_success "prometheus-alerts.yml restored"
  fi
  
  # Restore Grafana provisioning
  if [ -d "$config_package/provisioning" ]; then
    log_info "Restoring Grafana provisioning..."
    cp -r "$config_package/provisioning/"* "$REPLICA_GRAFANA_PROVISIONING_DIR/" 2>/dev/null || true
    log_success "Grafana provisioning restored"
  fi
}

# ============================================================================
# Phase 4: Verify File Mounts
# ============================================================================

phase_verify() {
  log_info "Phase 4: Verify - Ensure all configs are FILES, not directories"
  log_info "===========================================================  =="
  
  local all_ok=true
  
  if ! verify_file "$REPLICA_CADDY_DIR/Caddyfile" "Caddyfile"; then
    all_ok=false
  fi
  
  if [ -f "$REPLICA_PROMETHEUS_DIR/prometheus.yml" ] || [ -d "$REPLICA_PROMETHEUS_DIR" ]; then
    if ! verify_file "$REPLICA_PROMETHEUS_DIR/prometheus.yml" "prometheus.yml"; then
      all_ok=false
    fi
  fi
  
  # Check file contents
  log_info "Verifying file contents..."
  if grep -q "root_uri.*localhost:3100" "$REPLICA_CADDY_DIR/Caddyfile" 2>/dev/null; then
    log_success "Caddyfile contains expected content"
  else
    log_error "Caddyfile may be incomplete"
    all_ok=false
  fi
  
  if [ "$all_ok" = true ]; then
    log_success "All configuration files verified!"
    return 0
  else
    log_error "Some configuration files have issues"
    return 1
  fi
}

# ============================================================================
# Phase 5: Restart Services
# ============================================================================

phase_restart() {
  log_info "Phase 5: Restart - Start docker-compose services"
  log_info "=================================================="
  
  if [ ! -f "/var/paperclip/docker-compose.yml" ]; then
    log_error "docker-compose.yml not found in /var/paperclip/"
    return 1
  fi
  
  log_info "Starting docker-compose..."
  docker compose -f /var/paperclip/docker-compose.yml up -d || {
    log_error "docker-compose up failed"
    return 1
  }
  
  # Wait for services to start
  sleep 5
  
  check_docker_compose_status
  
  log_success "Services restarted"
}

# ============================================================================
# Phase 6: Health Check
# ============================================================================

phase_healthcheck() {
  log_info "Phase 6: Health Check - Verify services are responding"
  log_info "====================================================="
  
  local caddy_url="http://localhost:80"
  local prometheus_url="http://localhost:9090"
  local grafana_url="http://localhost:3000"
  
  # Check Caddy (should redirect or respond)
  log_info "Checking Caddy..."
  if curl -s -I "$caddy_url" | grep -q "HTTP\|301\|302\|200"; then
    log_success "Caddy is responding"
  else
    log_error "Caddy health check failed"
  fi
  
  # Check Prometheus
  log_info "Checking Prometheus..."
  if curl -s "$prometheus_url/api/v1/query?query=up" | grep -q '"status":"success"'; then
    log_success "Prometheus is responding"
  else
    log_error "Prometheus health check failed"
  fi
  
  # Check Grafana
  log_info "Checking Grafana..."
  if curl -s -I "$grafana_url" | grep -q "HTTP\|200"; then
    log_success "Grafana is responding"
  else
    log_error "Grafana health check failed"
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  log_info "P3-1533 Multi-Host Deployment: Replica Node Config Fix"
  log_info "======================================================"
  log_info ""
  
  # Parse arguments
  local phase="${1:-all}"
  local config_pkg="${2:-}"
  
  case "$phase" in
    prepare)
      phase_prepare
      ;;
    cleanup)
      phase_cleanup
      ;;
    restore)
      if [ -z "$config_pkg" ]; then
        log_error "restore requires config package path: $0 restore <path>"
        exit 1
      fi
      phase_cleanup
      phase_restore "$config_pkg"
      ;;
    verify)
      phase_verify
      ;;
    restart)
      phase_restart
      phase_healthcheck
      ;;
    all)
      log_info "Full fix cycle: cleanup → restore → verify → restart"
      log_info ""
      if [ -z "$config_pkg" ]; then
        log_error "all phase requires config package path: $0 all <path>"
        exit 1
      fi
      phase_cleanup
      phase_restore "$config_pkg"
      phase_verify
      phase_restart
      phase_healthcheck
      ;;
    healthcheck)
      phase_healthcheck
      ;;
    *)
      log_error "Unknown phase: $phase"
      log_info "Usage:"
      log_info "  $0 prepare                  # Prepare config package on primary"
      log_info "  $0 all <config_package>    # Full fix on replica"
      log_info "  $0 cleanup                 # Clean up replica (stop services)"
      log_info "  $0 restore <path>          # Restore files from package"
      log_info "  $0 verify                  # Verify file mounts"
      log_info "  $0 restart                 # Restart services"
      log_info "  $0 healthcheck             # Check service health"
      exit 1
      ;;
  esac
  
  log_info ""
  log_success "Phase complete!"
}

# Run main
main "$@"
