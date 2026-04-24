#!/usr/bin/env bash
# @file        scripts/security/provision-mtls-certificates.sh
# @module      security/mtls
# @description Generate mTLS certificates for zero-trust network access (P0 #1273)
#
# Usage:
#   bash scripts/security/provision-mtls-certificates.sh --generate-ca    # Generate CA certificates
#   bash scripts/security/provision-mtls-certificates.sh --generate-certs # Generate service certificates
#   bash scripts/security/provision-mtls-certificates.sh --verify         # Verify all certificates
#
# Environment:
#   CERT_ROOT_DIR: Root directory for certificates (default: ./config/mtls-certs)
#   CA_CN: CA Common Name (default: kushnir.cloud)
#   CERT_VALIDITY: Certificate validity in days (default: 30)
#   CERT_ROTATION_DAYS: Days before rotation (default: 1, rotates daily)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

# Configuration
CERT_ROOT_DIR="${CERT_ROOT_DIR:-$SCRIPT_DIR/config/mtls-certs}"
CA_CN="${CA_CN:-kushnir.cloud}"
CA_ROOT_DIR="$CERT_ROOT_DIR/ca-root"
CA_INTERMEDIATE_DIR="$CERT_ROOT_DIR/ca-intermediate"
SERVICES_CERT_DIR="$CERT_ROOT_DIR/services"
CERT_VALIDITY="${CERT_VALIDITY:-30}"
CERT_ROTATION_DAYS="${CERT_ROTATION_DAYS:-1}"
BACKUP_DIR="/var/lib/cert-rotation/backups"

# Services requiring mTLS certificates
SERVICES=(
  "redis:redis.net-data.local:net-data"
  "postgres:postgres.net-data.local:net-data"
  "pgbouncer:pgbouncer.net-data.local:net-data"
  "code-server:code-server.net-app.local:net-app"
  "caddy:caddy.net-edge.local:net-edge"
  "prometheus:prometheus.net-management.local:net-management"
  "alertmanager:alertmanager.net-management.local:net-management"
  "loki:loki.net-management.local:net-management"
  "promtail:promtail.net-management.local:net-management"
  "error-triage-engine:error-triage-engine.net-app.local:net-app"
  "redis-sentinel-1:redis-sentinel.net-app.local:net-app"
  "redis-sentinel-arbiter:redis-sentinel.net-app.local:net-app"
  "redis-sentinel-2:redis-sentinel.net-app.local:net-app"
)

# ============================================================================
# Helper Functions
# ============================================================================

generate_ca_root() {
  log_info "Generating CA root certificate..."
  
  mkdir -p "$CA_ROOT_DIR"
  
  # CA root private key (4096-bit RSA)
  openssl genrsa -out "$CA_ROOT_DIR/ca-key.pem" 4096 2>/dev/null
  
  # CA root certificate (self-signed, 10-year validity)
  openssl req -new -x509 -days 3650 \
    -key "$CA_ROOT_DIR/ca-key.pem" \
    -out "$CA_ROOT_DIR/ca-cert.pem" \
    -subj "/CN=$CA_CN Root CA/O=Kushnir.cloud/C=US" 2>/dev/null
  
  log_info "✅ CA root certificate created: $CA_ROOT_DIR/ca-cert.pem"
}

generate_ca_intermediate() {
  log_info "Generating intermediate CA certificate..."
  
  mkdir -p "$CA_INTERMEDIATE_DIR"
  
  # Intermediate CA private key
  openssl genrsa -out "$CA_INTERMEDIATE_DIR/ca-intermediate-key.pem" 2048 2>/dev/null
  
  # Intermediate CA CSR
  openssl req -new \
    -key "$CA_INTERMEDIATE_DIR/ca-intermediate-key.pem" \
    -out "$CA_INTERMEDIATE_DIR/ca-intermediate.csr" \
    -subj "/CN=$CA_CN Intermediate CA/O=Kushnir.cloud/C=US" 2>/dev/null
  
  # Sign intermediate with root CA (2-year validity)
  openssl x509 -req -days 730 \
    -in "$CA_INTERMEDIATE_DIR/ca-intermediate.csr" \
    -CA "$CA_ROOT_DIR/ca-cert.pem" \
    -CAkey "$CA_ROOT_DIR/ca-key.pem" \
    -CAcreateserial \
    -out "$CA_INTERMEDIATE_DIR/ca-intermediate-cert.pem" \
    -extensions v3_ca -extfile <(printf "subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer") 2>/dev/null
  
  # Create CA chain certificate
  cat "$CA_INTERMEDIATE_DIR/ca-intermediate-cert.pem" "$CA_ROOT_DIR/ca-cert.pem" \
    > "$CA_INTERMEDIATE_DIR/ca-chain.pem"
  
  log_info "✅ Intermediate CA certificate created: $CA_INTERMEDIATE_DIR/ca-intermediate-cert.pem"
}

generate_service_certificate() {
  local service=$1
  local cn=$2
  local network=$3
  
  local service_dir="$SERVICES_CERT_DIR/$service"
  mkdir -p "$service_dir"
  
  # Generate private key
  openssl genrsa -out "$service_dir/key.pem" 2048 2>/dev/null
  
  # Generate CSR with SANs
  openssl req -new \
    -key "$service_dir/key.pem" \
    -out "$service_dir/$service.csr" \
    -subj "/CN=$cn/O=Kushnir.cloud/C=US" \
    -addext "subjectAltName=DNS:$service,DNS:$cn,DNS:localhost,DNS:127.0.0.1" \
    -addext "extendedKeyUsage=serverAuth,clientAuth" 2>/dev/null
  
  # Sign with intermediate CA
  openssl x509 -req -days "$CERT_VALIDITY" \
    -in "$service_dir/$service.csr" \
    -CA "$CA_INTERMEDIATE_DIR/ca-intermediate-cert.pem" \
    -CAkey "$CA_INTERMEDIATE_DIR/ca-intermediate-key.pem" \
    -CAcreateserial \
    -out "$service_dir/cert.pem" \
    -extensions v3_req -extfile <(printf "subjectAltName=DNS:$service,DNS:$cn,DNS:localhost\nextendedKeyUsage=serverAuth,clientAuth") \
    2>/dev/null
  
  # Create full chain certificate
  cat "$service_dir/cert.pem" "$CA_INTERMEDIATE_DIR/ca-chain.pem" \
    > "$service_dir/fullchain.pem"
  
  log_info "✅ Service certificate generated: $service_dir/cert.pem"
}

verify_certificates() {
  log_info "Verifying certificate chain..."
  
  # Verify CA chain
  openssl verify -CAfile "$CA_ROOT_DIR/ca-cert.pem" \
    "$CA_INTERMEDIATE_DIR/ca-intermediate-cert.pem" &>/dev/null && \
    log_info "✅ Intermediate CA verified" || \
    log_error "❌ Intermediate CA verification failed"
  
  # Verify service certificates
  for service_spec in "${SERVICES[@]}"; do
    IFS=':' read -r service cn network <<< "$service_spec"
    local service_dir="$SERVICES_CERT_DIR/$service"
    
    if [ -f "$service_dir/fullchain.pem" ]; then
      openssl verify -CAfile "$CA_INTERMEDIATE_DIR/ca-intermediate-cert.pem" \
        "$service_dir/fullchain.pem" &>/dev/null && \
        log_info "✅ $service certificate verified" || \
        log_error "❌ $service certificate verification failed"
    fi
  done
}

should_rotate_certs() {
  # Check if certificates are older than CERT_ROTATION_DAYS
  [ ! -f "$SERVICES_CERT_DIR/redis/cert.pem" ] && return 0
  
  local cert_age=$(stat -f%m "$SERVICES_CERT_DIR/redis/cert.pem" 2>/dev/null || stat -c%Y "$SERVICES_CERT_DIR/redis/cert.pem" 2>/dev/null)
  local current_time=$(date +%s)
  local age_days=$(( (current_time - cert_age) / 86400 ))
  
  [ "$age_days" -ge "$CERT_ROTATION_DAYS" ]
}

backup_certificates() {
  mkdir -p "$BACKUP_DIR"
  
  local timestamp=$(date +%Y-%m-%d-%H%M%S)
  local backup_path="$BACKUP_DIR/certs-$timestamp.tar.gz"
  
  tar -czf "$backup_path" -C "$CERT_ROOT_DIR" . &>/dev/null
  log_info "✅ Certificates backed up to: $backup_path"
  
  # Keep only 7 days of backups
  find "$BACKUP_DIR" -name "certs-*.tar.gz" -mtime +7 -delete
}

# ============================================================================
# Main
# ============================================================================

main() {
  local command="${1:-}"
  
  case "$command" in
    --generate-ca)
      log_info "Starting CA generation..."
      generate_ca_root
      generate_ca_intermediate
      log_info "✅ CA generation complete"
      ;;
    
    --generate-certs)
      require_file "$CA_ROOT_DIR/ca-cert.pem" "CA root certificate not found. Run with --generate-ca first."
      require_file "$CA_INTERMEDIATE_DIR/ca-intermediate-cert.pem" "Intermediate CA not found. Run with --generate-ca first."
      
      log_info "Generating service certificates..."
      backup_certificates
      
      for service_spec in "${SERVICES[@]}"; do
        IFS=':' read -r service cn network <<< "$service_spec"
        log_info "  Generating certificate for $service..."
        generate_service_certificate "$service" "$cn" "$network"
      done
      
      log_info "✅ Service certificate generation complete"
      ;;
    
    --verify)
      log_info "Verifying all certificates..."
      verify_certificates
      log_info "✅ Certificate verification complete"
      ;;
    
    --rotate)
      if should_rotate_certs; then
        log_info "Certificates need rotation..."
        "$0" --generate-certs
        log_info "✅ Certificate rotation complete"
      else
        log_info "Certificates are still valid, no rotation needed"
      fi
      ;;
    
    *)
      log_error "Usage: $0 {--generate-ca|--generate-certs|--verify|--rotate}"
      log_info "  --generate-ca      Generate root and intermediate CA certificates"
      log_info "  --generate-certs   Generate service certificates (requires CA first)"
      log_info "  --verify           Verify all certificates in the chain"
      log_info "  --rotate           Rotate certificates if needed (daily)"
      exit 1
      ;;
  esac
}

main "$@"
