#!/usr/bin/env bash
################################################################################
# @file        scripts/mtls-certificate-management.sh
# @module      security/mtls
# @description mTLS certificate management for zero-trust network access
# @owner       platform
# @status      active
#
# USAGE
#   scripts/mtls-certificate-management.sh [init|rotate|verify]
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
#   - All configuration comes from environment variables, never hardcoded
#   - All errors use log_error / log_fatal from canonical logging library
#   - See scripts/_common/ for shared functions
#
# Last Updated: April 17, 2026
################################################################################

set -euo pipefail

################################################################################
# INITIALIZATION
################################################################################

# Get directory of this script and source the canonical initialization module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Canonical name for this script (used in logging/metrics)
SCRIPT_NAME="$(basename "$0")"

################################################################################
# CONFIGURATION & VALIDATION
################################################################################

# Declare all configuration variables here (sourced from environment by init.sh)
readonly MTLS_CA_DIR="${SCRIPT_DIR}/mtls-ca"
readonly MTLS_CERTS_DIR="${SCRIPT_DIR}/mtls-certs"
readonly MTLS_CA_KEY="${MTLS_CA_DIR}/ca.key"
readonly MTLS_CA_CERT="${MTLS_CA_DIR}/ca.crt"
readonly MTLS_CA_VALIDITY_DAYS=365
readonly MTLS_CERT_VALIDITY_HOURS=24
readonly MTLS_SERVICES=("code-server" "backend" "redis" "ollama" "caddy" "oauth2-proxy" "appsmith")

# Validate required commands exist (use canonical helper from _common/utils.sh)
require_command "openssl" "OpenSSL is required for certificate management"
require_command "docker" "Docker is required to run this script"

################################################################################
# HELPER FUNCTIONS (script-specific, not in _common/)
################################################################################

# HELPER FUNCTIONS (script-specific, not in _common/)

# Initialize CA if not exists
init_ca() {
    log_info "Initializing mTLS Certificate Authority"
    
    mkdir -p "$MTLS_CA_DIR"
    
    if [[ ! -f "$MTLS_CA_KEY" ]]; then
        log_info "Generating CA private key"
        openssl genrsa -out "$MTLS_CA_KEY" 4096
    fi
    
    if [[ ! -f "$MTLS_CA_CERT" ]]; then
        log_info "Generating CA certificate"
        openssl req -x509 -new -nodes \
            -key "$MTLS_CA_KEY" \
            -sha256 \
            -days "$MTLS_CA_VALIDITY_DAYS" \
            -out "$MTLS_CA_CERT" \
            -subj "/CN=Kushnir Code Server CA/O=Development/C=US"
    fi
    
    log_info "CA initialized successfully"
}

# Generate certificate for a service
generate_service_cert() {
    local service="$1"
    local cert_dir="$MTLS_CERTS_DIR/$service"
    local key_file="$cert_dir/$service.key"
    local cert_file="$cert_dir/$service.crt"
    local csr_file="$cert_dir/$service.csr"
    
    log_info "Generating certificate for service: $service"
    
    mkdir -p "$cert_dir"
    
    # Generate private key
    openssl genrsa -out "$key_file" 2048
    
    # Generate CSR
    openssl req -new -key "$key_file" \
        -out "$csr_file" \
        -subj "/CN=$service/O=Services/C=US"
    
    # Sign certificate
    openssl x509 -req \
        -in "$csr_file" \
        -CA "$MTLS_CA_CERT" \
        -CAkey "$MTLS_CA_KEY" \
        -CAcreateserial \
        -out "$cert_file" \
        -days 1 \
        -sha256
    
    # Set permissions
    chmod 600 "$key_file"
    chmod 644 "$cert_file"
    
    log_info "Certificate generated for $service"
}

# Rotate certificates for all services
rotate_certificates() {
    log_info "Rotating mTLS certificates for all services"
    
    for service in "${MTLS_SERVICES[@]}"; do
        generate_service_cert "$service"
    done
    
    log_info "Certificate rotation completed"
}

# Verify certificates
verify_certificates() {
    log_info "Verifying mTLS certificates"
    
    local all_valid=true
    
    for service in "${MTLS_SERVICES[@]}"; do
        local cert_file="$MTLS_CERTS_DIR/$service/$service.crt"
        local key_file="$MTLS_CERTS_DIR/$service/$service.key"
        
        if [[ ! -f "$cert_file" ]] || [[ ! -f "$key_file" ]]; then
            log_error "Missing certificate files for $service"
            all_valid=false
            continue
        fi
        
        # Check certificate validity
        if ! openssl x509 -checkend 3600 -noout -in "$cert_file" >/dev/null 2>&1; then
            log_warn "Certificate for $service expires within 1 hour"
        fi
        
        # Verify certificate chain
        if ! openssl verify -CAfile "$MTLS_CA_CERT" "$cert_file" >/dev/null 2>&1; then
            log_error "Certificate verification failed for $service"
            all_valid=false
        fi
    done
    
    if $all_valid; then
        log_info "All certificates are valid"
        return 0
    else
        log_error "Some certificates are invalid"
        return 1
    fi
}

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    log_info "Starting mTLS Certificate Management"
    
    local command="${1:-}"
    
    case "$command" in
        init)
            init_ca
            rotate_certificates
            ;;
        rotate)
            rotate_certificates
            ;;
        verify)
            verify_certificates
            ;;
        *)
            log_error "Usage: $SCRIPT_NAME {init|rotate|verify}"
            log_error "  init   - Initialize CA and generate initial certificates"
            log_error "  rotate - Rotate certificates for all services"
            log_error "  verify - Verify certificate validity and chain"
            return 2
            ;;
    esac
    
    log_info "mTLS Certificate Management completed successfully"
    return 0
}

################################################################################
# ENTRYPOINT
################################################################################

# Trap signals and ensure cleanup (error-handler.sh provides ERR trap)
trap cleanup EXIT

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "$SCRIPT_NAME exited with code $exit_code"
    fi
    return $exit_code
}

# Run main function and exit with its code
main "$@"
exit $?
