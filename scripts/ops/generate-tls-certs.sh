#!/bin/bash
# TLS Certificate Generation Script
# Generates self-signed certificates for development/testing
# For production, use Let's Encrypt via Caddy's ACME integration

set -e

CERT_DIR="${1:-.}"
DOMAIN="${2:-kushnir.cloud}"
VALIDITY_DAYS="${3:-365}"

echo "📋 TLS Certificate Generation"
echo "=========================================="
echo "Certificates: $CERT_DIR"
echo "Domain: $DOMAIN"
echo "Validity: $VALIDITY_DAYS days"
echo ""

# Create certificate directory
mkdir -p "$CERT_DIR"

# Generate private key
echo "🔐 Generating private key..."
openssl genrsa -out "$CERT_DIR/private.key" 2048

# Generate certificate signing request
echo "📝 Generating certificate signing request..."
openssl req -new \
  -key "$CERT_DIR/private.key" \
  -out "$CERT_DIR/request.csr" \
  -subj "/C=US/ST=California/L=San Francisco/O=Code-Server/CN=$DOMAIN"

# Generate self-signed certificate
echo "✅ Generating self-signed certificate..."
openssl x509 -req \
  -days "$VALIDITY_DAYS" \
  -in "$CERT_DIR/request.csr" \
  -signkey "$CERT_DIR/private.key" \
  -out "$CERT_DIR/cert.pem" \
  -extensions SAN \
  -extfile <(printf "subjectAltName=DNS:$DOMAIN,DNS:*.kushnir.cloud,DNS:localhost,DNS:*.localhost")

# Create combined certificate (PEM format for some applications)
cat "$CERT_DIR/cert.pem" "$CERT_DIR/private.key" > "$CERT_DIR/combined.pem"

# Display certificate information
echo ""
echo "📊 Certificate Details:"
openssl x509 -in "$CERT_DIR/cert.pem" -text -noout | grep -E "Subject:|Issuer:|Not Before:|Not After:|DNS:"

echo ""
echo "✅ Certificate generation complete!"
echo ""
echo "Files created:"
echo "  ✓ $CERT_DIR/private.key     - Private key"
echo "  ✓ $CERT_DIR/cert.pem        - Certificate"
echo "  ✓ $CERT_DIR/combined.pem    - Combined key + cert"
echo "  ✓ $CERT_DIR/request.csr     - Certificate signing request (can be deleted)"
echo ""
echo "For production, configure Let's Encrypt via Caddy:"
echo "  On_Demand: false  # Pre-generate certificates"
echo "  Ask: false        # Don't ask for domain"
echo ""
