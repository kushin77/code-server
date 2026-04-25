#!/bin/bash
###############################################################################
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# Purpose: Hardens SSL/TLS configuration for Caddy, OPA, and other services
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #412 (Security P0)
###############################################################################

set -euo pipefail

# Configuration (all env-var driven)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly CERT_DIR="${CERT_DIR:-${PROJECT_ROOT}/certs/ssl}"
readonly CA_CERT="${CA_CERT:-${CERT_DIR}/ca.crt}"
readonly CA_KEY="${CA_KEY:-${CERT_DIR}/ca.key}"
readonly SERVER_CERT="${SERVER_CERT:-${CERT_DIR}/server.crt}"
readonly SERVER_KEY="${SERVER_KEY:-${CERT_DIR}/server.key}"
readonly CERT_VALIDITY_DAYS="${CERT_VALIDITY_DAYS:-365}"
readonly TLS_MIN_VERSION="${TLS_MIN_VERSION:-1.2}"

log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"; }
log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"; }
log_error() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*"; }

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
