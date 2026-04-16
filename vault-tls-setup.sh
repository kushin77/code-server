#!/bin/bash
# Vault TLS/mTLS Setup Script
# Implements P0 #413 Phase 1: TLS Configuration
# Run on 192.168.168.31 (primary) after Vault is initialized

set -euo pipefail

VAULT_ADDR=${VAULT_ADDR:-"http://localhost:8200"}
VAULT_TOKEN=${VAULT_TOKEN:-""}
DAYS_VALID=3650  # 10-year certificates
CERT_DIR="/etc/vault/tls"
CA_CERT="$CERT_DIR/ca.crt"
CA_KEY="$CERT_DIR/ca.key"
VAULT_CERT="$CERT_DIR/vault.crt"
VAULT_KEY="$CERT_DIR/vault.key"

echo "═══════════════════════════════════════════════════════════════"
echo "Vault TLS/mTLS Setup — P0 #413 Phase 1"
echo "═══════════════════════════════════════════════════════════════"

# 1. Create certificate directory
echo ""
echo "✓ Step 1: Create certificate directory"
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

# 2. Generate CA certificate (self-signed for on-prem)
echo "✓ Step 2: Generate CA certificate"
if [ ! -f "$CA_CERT" ]; then
  openssl req -new -x509 -days $DAYS_VALID -nodes \
    -out "$CA_CERT" -keyout "$CA_KEY" \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=vault-ca"
  chmod 600 "$CA_KEY"
  echo "  Created: $CA_CERT"
  echo "  Created: $CA_KEY"
else
  echo "  Already exists: $CA_CERT"
fi

# 3. Generate Vault server certificate
echo "✓ Step 3: Generate Vault server certificate"
if [ ! -f "$VAULT_CERT" ]; then
  # Create CSR config
  cat > /tmp/vault-csr.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Organization
CN = vault.kushnir.local

[v3_req]
subjectAltName = DNS:vault.kushnir.local,DNS:localhost,IP:127.0.0.1,IP:192.168.168.31
EOF

  # Create key + CSR
  openssl req -new -nodes -out /tmp/vault.csr \
    -keyout "$VAULT_KEY" \
    -config /tmp/vault-csr.conf
  chmod 600 "$VAULT_KEY"

  # Sign CSR with CA
  openssl x509 -req -days $DAYS_VALID \
    -in /tmp/vault.csr \
    -CA "$CA_CERT" -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$VAULT_CERT" \
    -extensions v3_req \
    -extfile /tmp/vault-csr.conf

  echo "  Created: $VAULT_CERT"
  echo "  Created: $VAULT_KEY"
  rm /tmp/vault.csr /tmp/vault-csr.conf
else
  echo "  Already exists: $VAULT_CERT"
fi

# 4. Verify certificates
echo "✓ Step 4: Verify certificates"
echo "  CA Certificate:"
openssl x509 -in "$CA_CERT" -text -noout | grep -A 2 "Subject:\|Issuer:\|Not Before\|Not After"
echo ""
echo "  Vault Server Certificate:"
openssl x509 -in "$VAULT_CERT" -text -noout | grep -A 2 "Subject:\|Issuer:\|Not Before\|Not After\|DNS:\|IP Address"

# 5. Configure Vault for TLS
echo "✓ Step 5: Update Vault HCL configuration"
cat > /tmp/vault-tls.hcl << EOF
# TLS Configuration
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "$VAULT_CERT"
  tls_key_file  = "$VAULT_KEY"
  tls_min_version = "tls12"
  tls_cipher_suites = [
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
  ]
}
EOF

echo "  Generated: /tmp/vault-tls.hcl"
echo "  → Review and merge into /etc/vault/vault.hcl"

# 6. Output validation commands
echo "✓ Step 6: Validation commands"
cat << 'EOF'

VERIFY TLS (after Vault restart):
  curl --cacert /etc/vault/tls/ca.crt https://localhost:8200/v1/sys/health

ENABLE mTLS (requires client certificates):
  - Generate client cert with same CA
  - Configure in Terraform provider: tls_ca_cert_file = "/etc/vault/tls/ca.crt"

EOF

echo "═══════════════════════════════════════════════════════════════"
echo "✓ TLS Setup Complete"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Next Steps:"
echo "1. Review Vault HCL configuration at /tmp/vault-tls.hcl"
echo "2. Merge TLS settings into /etc/vault/vault.hcl"
echo "3. Restart Vault: systemctl restart vault"
echo "4. Verify: curl --cacert $CA_CERT https://localhost:8200/v1/sys/health"
echo "5. Enable audit logging (P0 #413 Phase 1 Step 2)"
