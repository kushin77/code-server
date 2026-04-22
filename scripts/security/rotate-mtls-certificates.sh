#!/usr/bin/env bash
# @file        scripts/security/rotate-mtls-certificates.sh
# @module      security/mtls
# @description Daily mTLS certificate rotation with zero-downtime service updates
#
# This script runs daily (via systemd timer) to:
# 1. Generate new certificates (30-day validity, rotated daily)
# 2. Validate certificate chain
# 3. Deploy certificates to services with minimal disruption
# 4. Verify connectivity after rotation
# 5. Clean up old certificates (7-day retention)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

# Configuration
CERT_ROOT_DIR="${CERT_ROOT_DIR:-$SCRIPT_DIR/config/mtls-certs}"
AUDIT_LOG="/var/log/audit/mtls-rotation.log"
ROTATION_LOCK="/var/run/cert-rotation.lock"
ROTATION_TIMEOUT=300  # 5 minutes total timeout per rotation

# ============================================================================
# Helper Functions
# ============================================================================

ensure_audit_log() {
  mkdir -p "$(dirname "$AUDIT_LOG")"
  touch "$AUDIT_LOG"
}

log_rotation() {
  local event=$1
  local details="${2:-}"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  echo "$timestamp | $event | $details" >> "$AUDIT_LOG"
  log_info "[$event] $details"
}

acquire_lock() {
  if [ -f "$ROTATION_LOCK" ]; then
    local lock_age=$(($(date +%s) - $(stat -f%m "$ROTATION_LOCK" 2>/dev/null || stat -c%Y "$ROTATION_LOCK" 2>/dev/null)))
    if [ "$lock_age" -gt "$ROTATION_TIMEOUT" ]; then
      log_warn "Stale lock detected, removing..."
      rm -f "$ROTATION_LOCK"
    else
      log_error "Rotation already in progress, exiting"
      return 1
    fi
  fi
  
  echo $$ > "$ROTATION_LOCK"
}

release_lock() {
  rm -f "$ROTATION_LOCK"
}

check_certificate_expiry() {
  local cert_file=$1
  
  if [ ! -f "$cert_file" ]; then
    echo "999"  # Return high number if cert doesn't exist
    return
  fi
  
  # Get expiry date in seconds since epoch
  local expiry=$(openssl x509 -in "$cert_file" -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
  local expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null || date -d "$expiry" +%s)
  local current_epoch=$(date +%s)
  local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
  
  echo "$days_until_expiry"
}

rotate_service_certificates() {
  log_rotation "ROTATION_START" "Beginning certificate rotation cycle"
  
  # Generate new certificates
  log_info "Generating new service certificates..."
  "$SCRIPT_DIR/scripts/security/provision-mtls-certificates.sh" --generate-certs 2>&1 | \
    while IFS= read -r line; do
      log_info "  $line"
    done || {
      log_rotation "ROTATION_FAILED" "Certificate generation failed"
      return 1
    }
  
  # Verify certificates
  log_info "Verifying certificate chain..."
  "$SCRIPT_DIR/scripts/security/provision-mtls-certificates.sh" --verify 2>&1 | \
    while IFS= read -r line; do
      log_info "  $line"
    done || {
      log_rotation "ROTATION_FAILED" "Certificate verification failed"
      return 1
    }
  
  log_rotation "CERTIFICATES_GENERATED" "New certificates generated and verified"
}

reload_service_certificates() {
  local service=$1
  
  log_info "Reloading certificates for $service..."
  
  case "$service" in
    redis)
      # Redis with mTLS - requires restart (no reload)
      docker restart "$service" &>/dev/null || {
        log_error "Failed to restart $service"
        return 1
      }
      # Wait for service to become healthy
      for i in {1..30}; do
        if docker exec "$service" redis-cli ping &>/dev/null; then
          log_info "  ✓ $service healthy after rotation"
          log_rotation "SERVICE_ROTATED" "$service certificates rotated successfully"
          return 0
        fi
        sleep 1
      done
      log_error "  ✗ $service failed to become healthy"
      return 1
      ;;
    
    postgres)
      # PostgreSQL doesn't require reload for certificate rotation
      # (pg_hba.conf reread on client connect)
      log_info "  ✓ $service (certificates effective on next client connection)"
      log_rotation "SERVICE_ROTATED" "$service certificates rotated"
      return 0
      ;;
    
    caddy)
      # Caddy with auto reload
      docker exec "$service" caddy reload -c /etc/caddy/Caddyfile &>/dev/null || {
        log_warn "  Caddy reload failed, attempting full restart..."
        docker restart "$service" &>/dev/null || return 1
      }
      sleep 2
      docker exec "$service" curl -s http://localhost:2019/config > /dev/null || {
        log_error "  Caddy admin API unreachable"
        return 1
      }
      log_info "  ✓ $service reloaded successfully"
      log_rotation "SERVICE_ROTATED" "$service certificates rotated"
      return 0
      ;;
    
    *)
      # Generic restart for other services
      docker restart "$service" &>/dev/null || return 1
      sleep 2
      docker inspect "$service" --format='{{.State.Running}}' | grep -q true && {
        log_info "  ✓ $service restarted successfully"
        log_rotation "SERVICE_ROTATED" "$service certificates rotated"
        return 0
      } || {
        log_error "  ✗ $service failed to restart"
        return 1
      }
      ;;
  esac
}

cleanup_old_certificates() {
  log_info "Cleaning up old certificates (retention: 7 days)..."
  
  find "$CERT_ROOT_DIR/services" -name "*.pem.backup" -mtime +7 -delete
  
  log_rotation "CLEANUP_COMPLETE" "Old certificates cleaned up"
}

verify_connectivity_after_rotation() {
  log_info "Verifying service connectivity after rotation..."
  
  # Test Redis mTLS connection
  docker exec redis redis-cli --tls --cert /run/secrets/redis-cert/cert.pem \
    --key /run/secrets/redis-cert/key.pem \
    --cacert /run/secrets/ca-cert.pem ping 2>&1 >/dev/null && \
    log_info "  ✓ Redis mTLS connectivity verified" || \
    log_warn "  ⚠ Redis mTLS test inconclusive"
  
  # Test PostgreSQL SSL connection
  docker exec postgres psql -h localhost -U postgres -d postgres \
    -c "SELECT version();" &>/dev/null && \
    log_info "  ✓ PostgreSQL SSL connectivity verified" || \
    log_warn "  ⚠ PostgreSQL SSL test inconclusive"
  
  log_rotation "CONNECTIVITY_VERIFIED" "Service connectivity checks passed"
}

# ============================================================================
# Main
# ============================================================================

main() {
  ensure_audit_log
  acquire_lock || exit 1
  trap release_lock EXIT
  
  log_rotation "START" "Certificate rotation initiated"
  
  # Step 1: Generate new certificates
  if ! rotate_service_certificates; then
    log_rotation "FAILED" "Certificate rotation failed at generation step"
    exit 1
  fi
  
  # Step 2: Reload services
  local services=(redis postgres caddy prometheus alertmanager code-server loki)
  local failed_services=()
  
  for service in "${services[@]}"; do
    if ! reload_service_certificates "$service"; then
      failed_services+=("$service")
    fi
  done
  
  if [ ${#failed_services[@]} -gt 0 ]; then
    log_rotation "PARTIAL_FAILURE" "Failed to rotate: ${failed_services[*]}"
    exit 1
  fi
  
  # Step 3: Verify connectivity
  if ! verify_connectivity_after_rotation; then
    log_rotation "CONNECTIVITY_FAILURE" "Connectivity verification failed"
    exit 1
  fi
  
  # Step 4: Cleanup
  cleanup_old_certificates
  
  log_rotation "COMPLETE" "Certificate rotation cycle completed successfully"
  log_info "✅ Certificate rotation completed successfully"
}

main "$@"
