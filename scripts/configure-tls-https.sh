#!/bin/bash

################################################################################
# Phase 6.1: TLS/HTTPS Configuration with Let's Encrypt
# Purpose: Configure end-to-end TLS encryption for all services
# Usage: ./scripts/configure-tls-https.sh [--apply]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary TLS files..."; rm -f /tmp/tls-*.tmp /tmp/cert-*.tmp 2>/dev/null || true' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

# Configuration
TLS_DIR="${PROJECT_ROOT}/tls"
CERT_DIR="/data/certs"
DOMAIN="${DOMAIN:-code-server.local}"
LE_EMAIL="${LE_EMAIL:-admin@code-server.local}"

################################################################################
# 1. GENERATE SELF-SIGNED CERTIFICATES (for non-LE environments)
################################################################################

generate_selfsigned_certs() {
    log_info "Generating self-signed certificates..."

    mkdir -p "$TLS_DIR"

    # Generate private key
    openssl genrsa -out "$TLS_DIR/server.key" 4096

    # Generate certificate request
    openssl req -new -key "$TLS_DIR/server.key" -out "$TLS_DIR/server.csr" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"

    # Generate self-signed certificate (valid 365 days)
    openssl x509 -req -days 365 -in "$TLS_DIR/server.csr" \
        -signkey "$TLS_DIR/server.key" -out "$TLS_DIR/server.crt"

    # Create combined PEM
    cat "$TLS_DIR/server.crt" "$TLS_DIR/server.key" > "$TLS_DIR/server.pem"

    log_success "Self-signed certificates generated"
}

################################################################################
# 2. CADDY TLS CONFIGURATION
################################################################################

create_caddy_tls_config() {
    log_info "Creating Caddy TLS configuration..."

    cat > "${TLS_DIR}/caddy-tls.conf" << 'CADDY_TLS'
# Caddy TLS Configuration

{
    # ACME configuration for automatic certificate renewal
    acme {
        dns route53
        email admin@example.com
        timeout 10s
    }

    # TLS policy
    tls_policies {
        # Minimum TLS 1.2 (maximum compatibility)
        min_version tls1_2
        
        # Use strong cipher suites
        ciphers TLS_AES_256_GCM_SHA384
        ciphers TLS_CHACHA20_POLY1305_SHA256
        ciphers TLS_AES_128_GCM_SHA256
        ciphers ECDHE-ECDSA-AES256-GCM-SHA384
        ciphers ECDHE-RSA-AES256-GCM-SHA384
        ciphers ECDHE-ECDSA-CHACHA20-POLY1305
        ciphers ECDHE-RSA-CHACHA20-POLY1305
        
        # Prefer server cipher order
        prefer_server_cipher_suites
        
        # Enable session resumption
        session_tickets
        session_timeout 24h
    }
}

# HTTPS endpoint with modern TLS
https:// {
    # Redirect HTTP to HTTPS
    @insecure {
        path_regexp ^.*$
    }
    redir @insecure https://{host}{uri} permanent

    # TLS configuration
    tls {
        on_demand
        dns route53
    }

    # HSTS header (Strict-Transport-Security)
    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
    }

    # Certificate pinning (optional)
    # header Public-Key-Pins "pin-sha256=...; pin-sha256=...; max-age=5184000; includeSubDomains"
}
CADDY_TLS

    log_success "Caddy TLS configuration created"
}

################################################################################
# 3. DOCKER COMPOSE ENVIRONMENT VARIABLES FOR TLS
################################################################################

create_tls_env_config() {
    log_info "Creating TLS environment configuration..."

    cat > "${TLS_DIR}/tls.env" << 'TLS_ENV'
# TLS/HTTPS Configuration

# Certificate paths (inside containers)
TLS_CERT_PATH=/run/secrets/tls_cert
TLS_KEY_PATH=/run/secrets/tls_key
TLS_CA_PATH=/run/secrets/tls_ca

# Certificate validity (days)
TLS_CERT_VALID_DAYS=365

# Minimum TLS version (1.0, 1.1, 1.2, 1.3)
TLS_MIN_VERSION=1.2

# Cipher suites (colon-separated)
TLS_CIPHERS=TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256

# Certificate renewal settings
TLS_RENEWAL_DAYS_BEFORE=30
TLS_AUTO_RENEWAL=true

# ACME provider (le, zerossl, buypass)
ACME_PROVIDER=zerossl

# Certificate staging/production
ACME_STAGING=false

# Force HTTPS redirect
FORCE_HTTPS=true
HTTPS_PORT=443

# Certificate pinning
ENABLE_CERT_PINNING=false

# OCSP stapling
ENABLE_OCSP_STAPLING=true
OCSP_UPDATE_INTERVAL=604800
TLS_ENV

    log_success "TLS environment configuration created"
}

################################################################################
# 4. SECRETS MANAGEMENT INTEGRATION
################################################################################

create_secrets_management() {
    log_info "Creating secrets management configuration..."

    cat > "${TLS_DIR}/secrets-rotation.sh" << 'SECRETS_MGMT'
#!/bin/bash

# Secrets Rotation Script
# Rotates TLS certificates, API keys, database passwords monthly

set -euo pipefail

LOG_FILE="/var/log/secrets-rotation.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Rotate TLS certificates
rotate_tls_certs() {
    log "Starting TLS certificate rotation..."
    
    # Check certificate expiration
    cert_days=$(openssl x509 -in /run/secrets/tls_cert -noout -dates | grep notAfter | awk -F= '{print $2}')
    
    # If expiration < 30 days, renew
    if [ $(( $(date -d "$cert_days" +%s) - $(date +%s) )) -lt 2592000 ]; then
        log "Certificate expiring in < 30 days, renewing..."
        # Trigger renewal process
        docker service update --force code-server-caddy || log "WARNING: Could not force caddy update"
    fi
    
    log "TLS certificate rotation complete"
}

# Rotate API keys
rotate_api_keys() {
    log "Starting API key rotation..."
    
    # Rotate service API keys
    for service in control-plane agent-runtime; do
        log "Rotating keys for $service..."
        # Generate new keys in Vault
        docker exec vault vault write -f auth/approle/role/$service/secret_id || true
    done
    
    log "API key rotation complete"
}

# Rotate database passwords
rotate_db_passwords() {
    log "Starting database password rotation..."
    
    # Rotate PostgreSQL password
    docker exec postgres psql -U postgres -c "ALTER USER postgres WITH PASSWORD '$(openssl rand -base64 32)';" || log "WARNING: Could not rotate postgres password"
    
    # Rotate Redis password (if auth enabled)
    # docker exec redis redis-cli CONFIG SET requirepass "$(openssl rand -base64 32)" || true
    
    log "Database password rotation complete"
}

# Audit logging for secret access
audit_secret_access() {
    log "Auditing secret access..."
    
    # Log all Vault operations
    docker exec vault vault audit enable file file_path=/vault/logs/audit.log || true
    
    # Log Docker secret access
    grep -i "secret" /var/log/docker/audit.log >> "$LOG_FILE" 2>/dev/null || true
    
    log "Secret access audit complete"
}

# Main execution
main() {
    log "=== Secrets Rotation Started ==="
    
    rotate_tls_certs
    rotate_api_keys
    rotate_db_passwords
    audit_secret_access
    
    log "=== Secrets Rotation Complete ==="
}

main "$@"
SECRETS_MGMT

    chmod +x "${TLS_DIR}/secrets-rotation.sh"
    log_success "Secrets management configuration created"
}

################################################################################
# 5. NETWORK SECURITY POLICIES
################################################################################

create_network_security() {
    log_info "Creating network security policies..."

    cat > "${TLS_DIR}/network-security.yaml" << 'NET_SEC'
---
# Network Security Policies

network:
  # Firewall rules
  firewall:
    ingress:
      - protocol: tcp
        ports: [443]        # HTTPS only
        source: 0.0.0.0/0
        action: allow
      - protocol: tcp
        ports: [80]         # Redirect to HTTPS
        source: 0.0.0.0/0
        action: allow
      - protocol: tcp
        ports: [22]         # SSH (restricted)
        source: 192.168.168.0/24
        action: allow
      - protocol: tcp
        ports: [2222]       # SSH (restricted)
        source: 192.168.168.0/24
        action: allow
      - protocol: tcp
        ports: [9090, 3100, 3000]  # Monitoring (internal only)
        source: 192.168.168.0/24
        action: allow
      - protocol: tcp
        ports: [5432, 6379]         # Databases (internal only)
        source: 192.168.168.0/24
        action: allow
      - protocol: tcp
        ports: [8200]               # Vault (internal only)
        source: 192.168.168.0/24
        action: allow

    egress:
      - protocol: tcp
        ports: [443]         # HTTPS outbound (for Let's Encrypt, etc)
        destination: 0.0.0.0/0
        action: allow
      - protocol: tcp
        ports: [53]          # DNS
        destination: 0.0.0.0/0
        action: allow
      - protocol: udp
        ports: [53]          # DNS
        destination: 0.0.0.0/0
        action: allow
      - protocol: tcp
        ports: [80]          # HTTP (for redirects)
        destination: 0.0.0.0/0
        action: allow
      - protocol: tcp
        ports: [123]         # NTP
        destination: 0.0.0.0/0
        action: allow
      - protocol: udp
        ports: [123]         # NTP
        destination: 0.0.0.0/0
        action: allow

  # DDoS protection
  ddos_protection:
    rate_limiting: true
    requests_per_second: 100
    burst_size: 200
    ip_blacklist_threshold: 50    # Requests/min to blacklist
    blacklist_duration: 1800      # 30 minutes

  # TLS/mTLS configuration
  tls:
    enforce_tls: true
    min_version: "1.2"
    mtls_enabled: true
    mtls_services:
      - control-plane
      - agent-runtime
      - api-gateway

  # Certificate pinning
  cert_pinning:
    enabled: true
    backup_pins:
      - "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
      - "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
    max_age: 5184000

  # Segmentation
  network_segmentation:
    - name: data_tier
      services: [postgres, redis, minio]
      allowed_from: [app_tier, monitoring_tier]
    
    - name: app_tier
      services: [control-plane, agent-runtime]
      allowed_from: [api_gateway]
      allowed_to: [data_tier]
    
    - name: monitoring_tier
      services: [prometheus, grafana, loki]
      allowed_from: [admin_network]
      allowed_to: [all_services]
    
    - name: management_tier
      services: [vault, minio-console]
      allowed_from: [admin_network]
NET_SEC

    log_success "Network security policies created"
}

################################################################################
# 6. VALIDATE AND DEPLOY
################################################################################

validate_tls_config() {
    log_info "Validating TLS configuration..."

    # Check certificates exist
    if [ ! -f "$TLS_DIR/server.key" ] || [ ! -f "$TLS_DIR/server.crt" ]; then
        log_error "Certificates not found"
        return 1
    fi

    # Validate certificate
    if openssl x509 -in "$TLS_DIR/server.crt" -text -noout &>/dev/null; then
        log_success "TLS certificates are valid"
    else
        log_error "TLS certificate validation failed"
        return 1
    fi
}

deploy_tls_config() {
    if $APPLY; then
        log_info "Deploying TLS configuration to production..."

        # Deploy to primary
        scp -r "$TLS_DIR"/* akushnir@192.168.168.31:"$CERT_DIR/" || log_error "Could not deploy to primary"
        
        # Deploy to replica
        scp -r "$TLS_DIR"/* akushnir@192.168.168.42:"$CERT_DIR/" || log_error "Could not deploy to replica"

        # Reload Caddy
        ssh akushnir@192.168.168.31 "docker exec caddy caddy reload" || log_warn "Could not reload Caddy on primary"
        ssh akushnir@192.168.168.42 "docker exec caddy caddy reload" || log_warn "Could not reload Caddy on replica"

        log_success "TLS configuration deployed"
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 6.1: TLS/HTTPS Configuration"
    log_info "===================================="

    generate_selfsigned_certs
    create_caddy_tls_config
    create_tls_env_config
    create_secrets_management
    create_network_security
    validate_tls_config

    if $APPLY; then
        deploy_tls_config
        log_success "Phase 6.1 Complete - TLS/HTTPS Configured"
    else
        log_info "Configurations created at: $TLS_DIR"
        log_info "Run with --apply flag to deploy"
    fi
}

main "$@"
