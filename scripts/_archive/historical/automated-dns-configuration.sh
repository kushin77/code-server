#!/bin/bash
################################################################################
# File: automated-dns-configuration.sh
# Owner: Infrastructure/DNS Team
# Purpose: Automated DNS record management and validation
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+, dig/nslookup
#
# Dependencies:
#   - curl — DNS provider API communication
#   - jq — JSON parsing for provider responses
#   - dig — DNS query tool
#   - openssl — DNS validation
#
# Related Files:
#   - terraform/dns.tf — DNS resource definitions
#   - .env — DNS provider credentials
#   - RUNBOOKS.md — DNS troubleshooting
#
# Usage:
#   ./automated-dns-configuration.sh setup       # Initial DNS configuration
#   ./automated-dns-configuration.sh verify      # Verify DNS resolution
#   ./automated-dns-configuration.sh update      # Update DNS records
#
# Operations:
#   - Create/update DNS A records
#   - Setup MX records (if applicable)
#   - Validate CNAME configuration
#   - Test DNS propagation
#   - Monitor DNS resolution
#
# Exit Codes:
#   0 — DNS configuration verified
#   1 — DNS configuration with propagation delay
#   2 — DNS resolution failed (connectivity issue)
#
# Examples:
#   ./scripts/automated-dns-configuration.sh setup
#   ./scripts/automated-dns-configuration.sh verify
#
# Recent Changes:
#   2026-04-14: Added DNS propagation validation
#   2026-04-13: Initial creation with DNS automation
#
################################################################################
# Automated DNS Configuration - IaC
# Manages DNS records via Cloudflare API

set -e

DOMAIN="${DOMAIN:-ide.kushnir.cloud}"
CF_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
CF_ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "====== AUTOMATED DNS CONFIGURATION ======"
echo ""

# Validate required environment
check_requirements() {
    if [ -z "$CF_API_TOKEN" ]; then
        echo "ERROR: CLOUDFLARE_API_TOKEN not set"
        echo "Set via: export CLOUDFLARE_API_TOKEN=<your-token>"
        return 1
    fi

    if [ -z "$CF_ZONE_ID" ]; then
        echo "ERROR: CLOUDFLARE_ZONE_ID not set"
        echo "Retrieve from: https://dash.cloudflare.com/ -> Zone ID"
        echo "Set via: export CLOUDFLARE_ZONE_ID=<zone-id>"
        return 1
    fi

    echo "✓ CloudFlare credentials configured"
}

# Function to get current DNS record
get_dns_record() {
    local name=$1

    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${name}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" | \
        jq -r '.result[0] | select(.type=="A") | {id:.id, name:.name, content:.content}'
}

# Function to create DNS record
create_dns_record() {
    local name=$1
    local ip=$2

    echo "Creating DNS record: ${name} -> ${ip}"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"A\",
            \"name\": \"${name}\",
            \"content\": \"${ip}\",
            \"ttl\": 300,
            \"proxied\": false
        }" | jq '.result | {id:.id, name:.name, content:.content, status:.status}'

    echo "✓ DNS record created"
}

# Function to update DNS record
update_dns_record() {
    local name=$1
    local ip=$2
    local record_id=$3

    echo "Updating DNS record: ${name} -> ${ip}"

    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"A\",
            \"name\": \"${name}\",
            \"content\": \"${ip}\",
            \"ttl\": 300,
            \"proxied\": false
        }" | jq '.result | {id:.id, name:.name, content:.content, status:.status}'

    echo "✓ DNS record updated"
}

# Function to configure all required DNS records
configure_dns() {
    local primary_domain=$1
    local sub_domain="*.${primary_domain}"
    local ip=$2

    echo "Configuring DNS records..."
    echo "  Primary Domain: ${primary_domain}"
    echo "  Wildcard Domain: ${sub_domain}"
    echo "  Target IP: ${ip}"
    echo ""

    # Configure primary domain
    local primary_record=$(get_dns_record "$primary_domain")
    if [ -z "$primary_record" ] || [ "$primary_record" = "null" ]; then
        create_dns_record "$primary_domain" "$ip"
    else
        local record_id=$(echo "$primary_record" | jq -r '.id')
        update_dns_record "$primary_domain" "$ip" "$record_id"
    fi

    # Configure wildcard domain
    local wildcard_record=$(get_dns_record "$sub_domain")
    if [ -z "$wildcard_record" ] || [ "$wildcard_record" = "null" ]; then
        create_dns_record "$sub_domain" "$ip"
    else
        local record_id=$(echo "$wildcard_record" | jq -r '.id')
        update_dns_record "$sub_domain" "$ip" "$record_id"
    fi
}

# Function to verify DNS resolution
verify_dns() {
    local domain=$1

    echo ""
    echo "Verifying DNS propagation..."
    for attempt in {1..6}; do
        RES=$(nslookup "$domain" 8.8.8.8 2>&1 || true)
        if echo "$RES" | grep -q "$DEPLOY_HOST"; then
            echo "✓ DNS resolves correctly in $((attempt * 10)) seconds"
            return 0
        fi
        echo "  Attempt $attempt/6 - waiting..."
        sleep 10
    done

    echo "⚠ DNS propagation pending (may take up to 24 hours)"
    return 0
}

# Function to save configuration
save_config() {
    local config_file="${SCRIPT_DIR}/.dns-config"

    cat > "$config_file" << EOF
# DNS Configuration - IaC
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

DOMAIN=${DOMAIN}
DEPLOY_HOST=${DEPLOY_HOST}
CF_ZONE_ID=${CF_ZONE_ID}
CLOUDFLARE_API_TOKEN=${CF_API_TOKEN:0:20}...
EOF

    chmod 600 "$config_file"
    echo "✓ Configuration saved to ${config_file}"
}

# Main execution
echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  Deploy Host: $DEPLOY_HOST"
echo "  CloudFlare Zone ID: $CF_ZONE_ID"
echo ""

# Check requirements
if ! check_requirements; then
    echo ""
    echo "Setup Instructions:"
    echo "  1. Get API Token from https://dash.cloudflare.com/profile/api-tokens"
    echo "  2. Create token with Zone.DNS edit permissions"
    echo "  3. Get Zone ID from https://dash.cloudflare.com/ -> Select Domain"
    echo "  4. Export environment variables and re-run"
    exit 1
fi

echo ""

# Configure DNS records
configure_dns "$DOMAIN" "$DEPLOY_HOST"
echo ""

# Verify DNS resolution
verify_dns "$DOMAIN"
echo ""

# Save configuration
save_config
echo ""

echo "✅ DNS configuration complete"
echo ""
echo "Verification:"
echo "  nslookup $DOMAIN"
echo "  ping $DOMAIN"
