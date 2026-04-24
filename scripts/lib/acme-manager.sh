#!/usr/bin/env bash
# @file        scripts/lib/acme-manager.sh
# @module      infrastructure/tls
# @description ACME TLS certificate provisioning for custom domains (Phase 4 #1674)
# IaC: Idempotent - safe to run multiple times
# Immutable: All state in database and file system

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/logging.sh"
source "$SCRIPT_DIR/../_common/init.sh"

CADDY_ADMIN_URL="${CADDY_ADMIN_URL:-http://localhost:2019}"
CERT_STORE_PATH="${CERT_STORE_PATH:-.caddy/certificates}"
ACME_EMAIL="${ACME_EMAIL:-admin@kushnir.cloud}"
DATABASE_URL="${DATABASE_URL:-postgres://codeserver@localhost:5432/codeserver}"

# ════════════════════════════════════════════════════════════════════════════
# Helper: Query database for verified domains needing TLS
# ════════════════════════════════════════════════════════════════════════════
function get_verified_domains_needing_tls() {
  psql "$DATABASE_URL" -t -c "
    SELECT id, domain_name FROM custom_domains
    WHERE is_verified = true
    AND (tls_cert_path IS NULL OR tls_cert_expiry < NOW() + INTERVAL '30 days')
    AND status IN ('verified', 'active')
    AND deleted_at IS NULL
    LIMIT 10
  "
}

# ════════════════════════════════════════════════════════════════════════════
# Helper: Request ACME certificate (idempotent - certbot checks if renewal needed)
# ════════════════════════════════════════════════════════════════════════════
function request_acme_certificate() {
  local domain_name="$1"
  local domain_id="$2"
  
  log_info "Requesting ACME certificate for: $domain_name"
  
  # Idempotent: certbot checks if cert already exists and valid
  if certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "$ACME_EMAIL" \
    --domain "$domain_name" \
    --cert-name "$domain_name" \
    2>&1 | tee /tmp/acme-$domain_name.log; then
    
    log_info "✓ Certificate provisioned: $domain_name"
    
    # Get certificate paths
    local cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"
    local expiry=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
    
    # Update database with certificate info (idempotent)
    psql "$DATABASE_URL" -c "
      UPDATE custom_domains
      SET status = 'active',
          tls_cert_path = '$cert_path',
          tls_cert_expiry = '$expiry'::timestamp,
          error_message = NULL
      WHERE id = '$domain_id'
    " || log_warn "Database update failed for $domain_id"
    
    log_info "Database updated for: $domain_name"
    return 0
  else
    log_error "Failed to provision certificate for: $domain_name"
    
    local error_msg=$(tail -5 /tmp/acme-$domain_name.log | head -1)
    psql "$DATABASE_URL" -c "
      UPDATE custom_domains
      SET status = 'failed',
          error_message = '$error_msg'
      WHERE id = '$domain_id'
    " || true
    
    return 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Helper: Update Caddy with new certificate (idempotent - only if cert changed)
# ════════════════════════════════════════════════════════════════════════════
function update_caddy_certificate() {
  local domain_name="$1"
  local cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
  local key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"
  
  if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
    log_error "Certificate files not found for: $domain_name"
    return 1
  fi
  
  log_info "Updating Caddy certificate for: $domain_name"
  
  # Get certificate content (base64 encoded for JSON)
  local cert_content=$(cat "$cert_path" | base64 -w0)
  local key_content=$(cat "$key_path" | base64 -w0)
  
  # Call Caddy Admin API to provision certificate (idempotent)
  local payload=$(cat <<EOF
{
  "cert": "$cert_content",
  "key": "$key_content",
  "format": "pem"
}
EOF
  )
  
  if curl -s -X POST "$CADDY_ADMIN_URL/admin/certs/issue/$domain_name" \
    -H "Content-Type: application/json" \
    -d "$payload" | grep -q "success"; then
    
    log_info "✓ Caddy certificate updated: $domain_name"
    return 0
  else
    log_error "Failed to update Caddy certificate for: $domain_name"
    return 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Helper: Reload Caddy configuration (idempotent - graceful reload)
# ════════════════════════════════════════════════════════════════════════════
function reload_caddy() {
  log_info "Reloading Caddy configuration..."
  
  if curl -s -X POST "$CADDY_ADMIN_URL/admin/reload" > /dev/null; then
    log_info "✓ Caddy reloaded successfully"
    return 0
  else
    log_warn "Caddy reload may have failed (check Caddy logs)"
    return 0  # Don't fail - Caddy might be ok
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Main: Process all verified domains needing TLS
# ════════════════════════════════════════════════════════════════════════════
function main() {
  log_info "════════════════════════════════════════════════════════════════"
  log_info "ACME Manager — Idempotent TLS Provisioning"
  log_info "════════════════════════════════════════════════════════════════"
  
  # Check dependencies
  require_command certbot
  require_command psql
  require_command curl
  require_command openssl
  
  local processed=0
  local failed=0
  
  # Get domains needing TLS
  while IFS='|' read -r domain_id domain_name; do
    domain_id=$(echo "$domain_id" | xargs)
    domain_name=$(echo "$domain_name" | xargs)
    
    if [ -z "$domain_id" ] || [ -z "$domain_name" ]; then
      continue
    fi
    
    log_info ""
    log_info "Processing: $domain_name (ID: $domain_id)"
    
    # Request certificate (idempotent)
    if request_acme_certificate "$domain_name" "$domain_id"; then
      # Update Caddy (idempotent)
      if update_caddy_certificate "$domain_name"; then
        ((processed++))
      else
        ((failed++))
      fi
    else
      ((failed++))
    fi
  done < <(get_verified_domains_needing_tls)
  
  # Reload Caddy once for all certificates (idempotent)
  if [ $processed -gt 0 ]; then
    reload_caddy
  fi
  
  log_info ""
  log_info "════════════════════════════════════════════════════════════════"
  log_info "Summary: $processed provisioned, $failed failed"
  log_info "════════════════════════════════════════════════════════════════"
  
  if [ $failed -gt 0 ]; then
    return 1
  fi
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# Export Functions
# ════════════════════════════════════════════════════════════════════════════
export -f request_acme_certificate
export -f update_caddy_certificate
export -f reload_caddy

# ════════════════════════════════════════════════════════════════════════════
# Execute
# ════════════════════════════════════════════════════════════════════════════
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  main "$@"
fi
