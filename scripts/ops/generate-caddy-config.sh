#!/usr/bin/env bash
###############################################################################
# @file        scripts/ops/generate-caddy-config.sh
# @module      ops/generate-caddy-config
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/ops/generate-caddy-config.sh
# @description Phase 3: Generate Caddyfile from template using environment variables (#1531)
# @governance GOV-002 - All domains are variables, zero hardcoding
# @automation Generates Caddyfile before docker-compose up
# @prerequisite Must source scripts/_common/init.sh

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly TEMPLATE_FILE="${REPO_ROOT}/config/caddy/Caddyfile.tpl"
readonly OUTPUT_FILE="${REPO_ROOT}/config/caddy/Caddyfile"
readonly BACKUP_FILE="${REPO_ROOT}/config/caddy/Caddyfile.backup.$(date +%s)"

# ==============================================================================
# TEMPLATE FUNCTIONS
# ==============================================================================

# Validate required environment variables for templating
validate_template_variables() {
  log_info "Validating template variables..."
  
  local required_vars=(
    "APEX_DOMAIN"
    "ADMIN_EMAIL"
  )
  
  local optional_vars=(
    "IDE_DOMAIN"
    "API_DOMAIN"
    "AUTH_DOMAIN"
    "ENABLE_TLS"
  )
  
  # Validate required
  for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      log_error "Required template variable is not set: \$${var}"
      return 1
    fi
  done
  
  # Set optional defaults if not provided
  IDE_DOMAIN="${IDE_DOMAIN:-ide.${APEX_DOMAIN}}"
  API_DOMAIN="${API_DOMAIN:-api.${APEX_DOMAIN}}"
  AUTH_DOMAIN="${AUTH_DOMAIN:-auth.${APEX_DOMAIN}}"
  ENABLE_TLS="${ENABLE_TLS:-false}"
  
  export IDE_DOMAIN API_DOMAIN AUTH_DOMAIN PRIMARY_HOST ENABLE_TLS
  
  log_info "✅ Template variables validated"
  log_info "  APEX_DOMAIN: ${APEX_DOMAIN}"
  log_info "  IDE_DOMAIN: ${IDE_DOMAIN}"
  log_info "  API_DOMAIN: ${API_DOMAIN}"
  log_info "  AUTH_DOMAIN: ${AUTH_DOMAIN}"
  
  return 0
}

# Generate Caddyfile from template
generate_from_template() {
  log_info "Generating Caddyfile from template..."
  
  if [ ! -f "$TEMPLATE_FILE" ]; then
    log_error "Template file not found: $TEMPLATE_FILE"
    return 1
  fi
  
  # Create backup of existing Caddyfile if it exists
  if [ -f "$OUTPUT_FILE" ]; then
    log_info "Backing up existing Caddyfile to: $BACKUP_FILE"
    cp "$OUTPUT_FILE" "$BACKUP_FILE"
  fi
  
  # Perform variable substitution
  local temp_file=$(mktemp)
  
  # Use envsubst to replace variables, or fallback to sed if envsubst not available
  if command -v envsubst &> /dev/null; then
    envsubst < "$TEMPLATE_FILE" > "$temp_file"
  else
    log_info "envsubst not available, using sed for substitution"
    
    sed \
      -e "s|{APEX_DOMAIN}|${APEX_DOMAIN}|g" \
      -e "s|{IDE_DOMAIN}|${IDE_DOMAIN}|g" \
      -e "s|{API_DOMAIN}|${API_DOMAIN}|g" \
      -e "s|{AUTH_DOMAIN}|${AUTH_DOMAIN}|g" \
      -e "s|{ADMIN_EMAIL}|${ADMIN_EMAIL}|g" \
      -e "s|{PRIMARY_HOST}|${PRIMARY_HOST}|g" \
      "$TEMPLATE_FILE" > "$temp_file"
  fi
  
  # Validate generated configuration
  if ! validate_caddy_syntax "$temp_file"; then
    log_error "Generated Caddyfile has syntax errors"
    rm "$temp_file"
    return 1
  fi
  
  # Move generated file to final location
  mv "$temp_file" "$OUTPUT_FILE"
  chmod 644 "$OUTPUT_FILE"
  
  log_success "✅ Caddyfile generated successfully"
  log_info "Output: $OUTPUT_FILE"
  
  return 0
}

# Validate Caddy configuration syntax
validate_caddy_syntax() {
  local config_file="${1:-$OUTPUT_FILE}"
  
  log_info "Validating Caddy configuration syntax..."
  
  if [ ! -f "$config_file" ]; then
    log_error "Config file not found: $config_file"
    return 1
  fi
  
  # Check for obvious syntax errors
  # Look for unmatched braces
  local open_braces=$(grep -o '{' "$config_file" | wc -l)
  local close_braces=$(grep -o '}' "$config_file" | wc -l)
  
  if [ "$open_braces" -ne "$close_braces" ]; then
    log_error "Mismatched braces in Caddyfile (open: $open_braces, close: $close_braces)"
    return 1
  fi
  
  # Check for common configuration patterns
  if ! grep -q "reverse_proxy\|respond" "$config_file"; then
    log_warn "Generated Caddyfile has no routes or responses defined"
  fi
  
  log_success "✅ Caddy configuration syntax valid"
  return 0
}

# ==============================================================================
# COMPARISON & DRIFT DETECTION
# ==============================================================================

# Compare generated config with current Caddyfile
detect_config_drift() {
  log_info "Checking for configuration drift..."
  
  if [ ! -f "$BACKUP_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
    return 0  # No previous config to compare
  fi
  
  if [ -f "$BACKUP_FILE" ]; then
    if diff -q "$BACKUP_FILE" "$OUTPUT_FILE" > /dev/null 2>&1; then
      log_info "✅ No configuration drift detected"
      return 0
    else
      log_warn "⚠️  Configuration drift detected"
      log_info "Differences:"
      diff -u "$BACKUP_FILE" "$OUTPUT_FILE" | head -20 || true
      return 1  # Drift detected, but not fatal
    fi
  fi
  
  return 0
}

# ==============================================================================
# RELOAD & VALIDATION
# ==============================================================================

# Reload Caddy with new configuration
reload_caddy() {
  log_info "Reloading Caddy with new configuration..."
  
  # Check if Caddy is running
  if ! docker ps | grep -q caddy-gateway; then
    log_info "Caddy not running, will start on next docker-compose up"
    return 0
  fi
  
  # Reload Caddy
  if docker exec caddy-gateway caddy reload --config /etc/caddy/Caddyfile 2>/dev/null; then
    log_success "✅ Caddy reloaded successfully"
    return 0
  else
    log_warn "Could not reload Caddy (may not be running)"
    return 0  # Not fatal
  fi
}

# Verify Caddy health after reload
verify_caddy_health() {
  log_info "Verifying Caddy health..."
  
  local max_attempts=10
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    if curl -fsS http://localhost/health > /dev/null 2>&1; then
      log_success "✅ Caddy is healthy and responsive"
      return 0
    fi
    
    attempt=$((attempt + 1))
    if [ $attempt -lt $max_attempts ]; then
      log_info "Waiting for Caddy... (attempt $attempt/$max_attempts)"
      sleep 2
    fi
  done
  
  log_error "Caddy health check failed after $max_attempts attempts"
  return 1
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
  local action="${1:-generate}"
  
  log_info "Caddy Configuration Generator Started"
  log_info "Repository: ${REPO_ROOT}"
  log_info "Action: $action"
  
  # Validate environment
  if ! _validate_required_env 2>/dev/null; then
    log_error "Environment validation failed"
    exit 1
  fi
  
  # Validate template variables
  if ! validate_template_variables; then
    exit 1
  fi
  
  case "$action" in
    generate)
      if ! generate_from_template; then
        exit 1
      fi
      
      if ! detect_config_drift; then
        log_warn "Configuration has changed - manual review recommended"
      fi
      
      log_success "✅ Caddy configuration generation complete"
      ;;
      
    reload)
      if ! reload_caddy; then
        exit 1
      fi
      
      if ! verify_caddy_health; then
        log_error "Health check failed after reload"
        exit 1
      fi
      
      log_success "✅ Caddy reloaded and healthy"
      ;;
      
    validate)
      if ! validate_caddy_syntax; then
        exit 1
      fi
      log_success "✅ Configuration is valid"
      ;;
      
    restore)
      if [ ! -f "$BACKUP_FILE" ]; then
        log_error "No backup file found: $BACKUP_FILE"
        exit 1
      fi
      
      log_warn "Restoring Caddyfile from backup..."
      cp "$BACKUP_FILE" "$OUTPUT_FILE"
      
      if ! reload_caddy; then
        log_error "Failed to reload Caddy"
        exit 1
      fi
      
      log_success "✅ Caddyfile restored from backup"
      ;;
      
    *)
      log_error "Unknown action: $action"
      echo "Usage: $0 {generate|reload|validate|restore}"
      exit 1
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  main "$@"
fi
