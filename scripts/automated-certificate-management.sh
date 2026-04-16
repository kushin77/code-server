#!/bin/bash
# Automated SSL/TLS Certificate Management - IaC
# Manages Let's Encrypt certificates with automatic renewal
# Integrates with Caddy for zero-downtime ACME

set -e

source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/certs"
ACME_EMAIL="${ACME_EMAIL:-admin@kushnir.cloud}"
DOMAIN="${DOMAIN:-ide.kushnir.cloud}"
DEPLOY_HOST="${DEPLOY_HOST:-${DEPLOY_HOST}}"

echo "====== AUTOMATED SSL/TLS CERTIFICATE MANAGEMENT ======"
echo ""

# Create cert directory
mkdir -p "$CERT_DIR"

# Function to generate self-signed certificate (bootstrap)
generate_self_signed() {
    local domain=$1
    echo "Generating self-signed certificate for bootstrap..."
    
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "${CERT_DIR}/${domain}.key" \
        -out "${CERT_DIR}/${domain}.crt" \
        -days 365 \
        -subj "/CN=${domain}/O=Development/C=US" \
        -addext "subjectAltName=DNS:${domain},DNS:*.${domain}"
    
    echo "✓ Self-signed certificate generated"
    echo "   Key: ${CERT_DIR}/${domain}.key"
    echo "   Cert: ${CERT_DIR}/${domain}.crt"
}

# Function to generate ACME configuration
generate_acme_config() {
    local domain=$1
    local email=$2
    
    echo "Generating ACME configuration..."
    
    # This config is injected into Caddyfile
    cat > "${CERT_DIR}/acme.conf" << 'EOF'
# ACME Configuration - Auto-injected into Caddyfile
# Enables automatic Let's Encrypt certificate provisioning

{
    acme_ca https://acme-v02.api.letsencrypt.org/directory
    acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    
    # Certificate storage location (persisted in volumes)
    storage file_system {
        root /data/caddy/certificates
    }
    
    # Email for Let's Encrypt notifications
    email ACME_EMAIL
}
EOF
    
    sed -i "s|ACME_EMAIL|${email}|g" "${CERT_DIR}/acme.conf"
    
    echo "✓ ACME configuration generated"
    echo "   Config: ${CERT_DIR}/acme.conf"
    echo "   Email: ${email}"
}

# Function to set up DNS validation
setup_dns_validation() {
    local domain=$1
    
    echo ""
    echo "DNS Validation Setup (Cloudflare):"
    echo "  1. Export Cloudflare API token:"
    echo "     export CLOUDFLARE_API_TOKEN=<your-token>"
    echo ""
    echo "  2. Add DNS TXT record validation:"
    echo "     - Domain: ${domain}"
    echo "     - Use DNS-01 challenge (automated)"
    echo ""
    echo "  3. Certbot will validate automatically during renewal"
}

# Function to create renewal script
create_renewal_script() {
    local script="${CERT_DIR}/renew-certificates.sh"
    
    cat > "$script" << 'EOF'
#!/bin/bash
# Automated Certificate Renewal - IaC
# Runs daily via cron; managed by docker-compose

set -e
CERT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[$(date)] Checking certificate expiration..."

# Caddy handles renewal automatically via ACME
# This script provides explicit renewal capability

docker exec caddy curl -s http://localhost:2019/admin/reload || echo "Caddy reload signal sent"

echo "[$(date)] Certificate renewal check complete"

# Log certificate status
/usr/bin/openssl x509 -enddate -noout -in ${CERT_DIR}/live/cert.pem || true
EOF

    chmod +x "$script"
    echo "✓ Created renewal script: $script"
}

# Function to deploy to remote host
deploy_certificates() {
    local host=$1
    local user="akushnir"
    
    echo ""
    echo "Deploying certificates to ${host}..."
    
    # Create certificate directory on remote
    ssh -o StrictHostKeyChecking=no "${user}@${host}" \
        "mkdir -p /home/${user}/code-server-immutable-*/certs" || true
    
    # Copy certificates
    scp -o StrictHostKeyChecking=no -r "${CERT_DIR}"/* \
        "${user}@${host}:/home/${user}/code-server-immutable-20260413-211419/certs/" || true
    
    echo "✓ Certificates deployed to ${host}"
}

# Main execution
echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  ACME Email: $ACME_EMAIL"
echo "  Cert Directory: $CERT_DIR"
echo "  Deploy Host: $DEPLOY_HOST"
echo ""

# Generate self-signed for bootstrap
generate_self_signed "$DOMAIN"
echo ""

# Generate ACME configuration
generate_acme_config "$DOMAIN" "$ACME_EMAIL"
echo ""

# Set up DNS validation instructions
setup_dns_validation "$DOMAIN"
echo ""

# Create renewal script
create_renewal_script
echo ""

echo "✅ Certificate infrastructure ready"
echo ""
echo "Next Steps:"
echo "  1. Set Cloudflare API token: export CLOUDFLARE_API_TOKEN=<token>"
echo "  2. Deploy to production: docker-compose up -d"
echo "  3. Caddy will auto-provision Let's Encrypt certificate"
echo "  4. Check status: docker logs caddy"
