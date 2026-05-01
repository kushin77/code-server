#!/bin/bash
###############################################################################
# @file        scripts/ops/harden-ssl-tls.sh
# @module      ops/harden-ssl-tls
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/ops/harden-ssl-tls.sh
# @description Hardens SSL/TLS configuration for Caddy, OPA, and other services.
# @governance GOV-002

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Configuration
CERT_DIR="certs/ssl"
CA_CERT="$CERT_DIR/ca.crt"
CA_KEY="$CERT_DIR/ca.key"
SERVER_CERT="$CERT_DIR/server.crt"
SERVER_KEY="$CERT_DIR/server.key"
DAYS=365

# 1. Generate Custom CA and Certificates (for internal services)
setup_internal_pki() {
    log_info "Setting up internal PKI..."
    mkdir -p "$CERT_DIR"
    chmod 700 "$CERT_DIR"

    if [[ ! -f "$CA_KEY" ]]; then
        openssl genrsa -out "$CA_KEY" 4096
        openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days "$DAYS" -out "$CA_CERT" \
            -subj "/C=US/ST=State/L=City/O=CodeServer/CN=InternalCA"
        log_success "Internal CA generated."
    fi

    if [[ ! -f "$SERVER_KEY" ]]; then
        openssl genrsa -out "$SERVER_KEY" 2048
        openssl req -new -key "$SERVER_KEY" -out server.csr \
            -subj "/C=US/ST=State/L=City/O=CodeServer/CN=localhost"
        
        cat <<EOT > server.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
DNS.2 = opa
DNS.3 = caddy
IP.1 = 127.0.0.1
EOT

        openssl x509 -req -in server.csr -CA "$CA_CERT" -CAkey "$CA_KEY" \
            -CAcreateserial -out "$SERVER_CERT" -days "$DAYS" -sha256 -extfile server.ext
        rm server.csr server.ext
        log_success "Internal server certificate generated."
    fi
}

# 2. Harden Caddyfile (Modern TLS standards)
harden_caddy_tls() {
    log_info "Hardening Caddy TLS configuration..."
    CADDYFILE="Caddyfile"
    if [[ -f "$CADDYFILE" ]]; then
        # Use a simpler check and append/prepend to avoid complex sed
        if ! grep -q "protocols tls1.3" "$CADDYFILE"; then
            log_info "Applying TLS 1.3 requirement to Caddyfile..."
            # For this automation, we'll document the change or use a temp file
            cat <<EOT > Caddyfile.new
{
    # Global TLS options
    tls {
        protocols tls1.3
    }
}

$(cat "$CADDYFILE")
EOT
            mv Caddyfile.new "$CADDYFILE"
            log_success "Caddyfile SSL/TLS standards applied (TLS 1.3 only)."
        fi
    fi
}

# 3. Verify SSL configurations
verify_ssl() {
    log_info "Verifying SSL certificates..."
    if [[ -f "$SERVER_CERT" ]]; then
        openssl x509 -in "$SERVER_CERT" -text -noout | grep "Signature Algorithm"
        log_success "SSL verification complete."
    else
        log_error "Server certificate not found."
        exit 1
    fi
}

main() {
    log_info "Starting SSL/TLS Hardening (P1 Priority 2)..."
    setup_internal_pki
    harden_caddy_tls
    verify_ssl
    log_success "SSL/TLS Hardening complete."
}

main
