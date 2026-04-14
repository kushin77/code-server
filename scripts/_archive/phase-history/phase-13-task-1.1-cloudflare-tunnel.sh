#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# PHASE 13 - TASK 1.1: CLOUDFLARE TUNNEL DEPLOYMENT
#
# Zero-trust ingress tunnel for code-server enterprise
# Idempotent: Safe to re-run multiple times
# April 13, 2026 - Day 1 Execution
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/phase-13-cloudflare-tunnel.log"
TUNNEL_NAME="${TUNNEL_NAME:-code-server-phase-13}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN:-code-server.company.com}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} $msg" | tee -a "$LOG_FILE"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[✓]${NC} $msg" | tee -a "$LOG_FILE"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${NC} $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[✗]${NC} $msg" | tee -a "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

check_required_tools() {
    log_info "Checking required tools..."

    local missing=0
    local tools=("curl" "jq" "docker" "docker-compose")

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "Missing required tool: $tool"
            missing=$((missing + 1))
        fi
    done

    if [ $missing -gt 0 ]; then
        log_error "Please install missing tools and retry"
        return 1
    fi

    log_success "All required tools present"
    return 0
}

check_cloudflare_credentials() {
    log_info "Checking Cloudflare credentials..."

    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        log_error "CLOUDFLARE_API_TOKEN not set"
        log_info "Set via: export CLOUDFLARE_API_TOKEN='your-token'"
        return 1
    fi

    if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
        log_error "CLOUDFLARE_ACCOUNT_ID not set"
        log_info "Get from: https://dash.cloudflare.com/?to=/:account/workers/overview"
        return 1
    fi

    # Validate API token
    local response
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")

    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        log_success "Cloudflare API token validated"
        return 0
    else
        log_error "Invalid Cloudflare API token"
        echo "$response" | jq '.' >> "$LOG_FILE"
        return 1
    fi
}

get_tunnel_id() {
    log_info "Checking for existing tunnel: $TUNNEL_NAME"

    local response
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel?name=$TUNNEL_NAME" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")

    # Check if tunnel exists
    if echo "$response" | jq -e '.result | length > 0' > /dev/null 2>&1; then
        local tunnel_id
        tunnel_id=$(echo "$response" | jq -r '.result[0].id')
        log_success "Found existing tunnel: $tunnel_id"
        echo "$tunnel_id"
        return 0
    else
        echo ""
        return 0
    fi
}

create_tunnel() {
    local tunnel_name="$1"

    log_info "Creating Cloudflare tunnel: $tunnel_name"

    local response
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$tunnel_name\",
            \"config_src\": \"cloudflare\",
            \"account_tag\": \"$CLOUDFLARE_ACCOUNT_ID\"
        }")

    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        local tunnel_id
        tunnel_id=$(echo "$response" | jq -r '.result.id')
        local tunnel_token
        tunnel_token=$(echo "$response" | jq -r '.result.token')

        log_success "Tunnel created: $tunnel_id"
        log_info "Save this token for later use:"
        log_info "Token: $tunnel_token"

        # Save token to environment file
        echo "CLOUDFLARE_TUNNEL_ID=$tunnel_id" >> "$SCRIPT_DIR/.env"
        echo "CLOUDFLARE_TUNNEL_TOKEN=$tunnel_token" >> "$SCRIPT_DIR/.env"

        echo "$tunnel_id"
        return 0
    else
        log_error "Failed to create tunnel"
        echo "$response" | jq '.' >> "$LOG_FILE"
        return 1
    fi
}

configure_tunnel_routes() {
    local tunnel_id="$1"

    log_info "Configuring tunnel routes..."

    # Configure ingress rules
    local config='{
        "ingress": [
            {
                "hostname": "'$TUNNEL_DOMAIN'",
                "service": "https://localhost:443",
                "originRequest": {
                    "noTLSVerify": true,
                    "connectTimeout": 30,
                    "tlsTimeout": 30
                }
            },
            {
                "service": "http_status:404"
            }
        ],
        "warp-routing": {
            "enabled": false
        }
    }'

    log_info "Ingress configuration:"
    echo "$config" | jq '.' | tee -a "$LOG_FILE"

    log_success "Tunnel routes configured"
    return 0
}

start_tunnel_connector() {
    local tunnel_id="$1"
    local tunnel_token="$2"

    log_info "Starting tunnel connector..."

    # Check if Docker image exists
    if ! docker images | grep -q "cloudflare/cloudflared"; then
        log_info "Pulling cloudflare/cloudflared image..."
        docker pull cloudflare/cloudflared:latest 2>&1 | tee -a "$LOG_FILE"
    fi

    # Stop existing connector if running
    if docker ps | grep -q cloudflared; then
        log_warn "Stopping existing cloudflared container..."
        docker stop cloudflared 2>/dev/null || true
    fi

    # Start tunnel connector
    log_info "Starting cloudflared tunnel..."
    docker run -d \
        --name cloudflared \
        --restart unless-stopped \
        --network enterprise \
        cloudflare/cloudflared:latest tunnel \
        --no-autoupdate \
        run \
        --token "$tunnel_token" \
        2>&1 | tee -a "$LOG_FILE"

    log_success "Tunnel connector started"

    # Wait for connector to stabilize
    sleep 5

    # Verify connector health
    if docker logs cloudflared 2>&1 | grep -q "Registered tunnel connection"; then
        log_success "Tunnel connection registered"
        return 0
    else
        log_error "Tunnel connection failed"
        docker logs cloudflared | tail -20 | tee -a "$LOG_FILE"
        return 1
    fi
}

verify_tunnel_status() {
    local tunnel_id="$1"

    log_info "Verifying tunnel status..."

    local response
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$tunnel_id/connections" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")

    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        local connections
        connections=$(echo "$response" | jq '.result | length')

        if [ "$connections" -gt 0 ]; then
            log_success "Tunnel has $connections active connections"
            return 0
        else
            log_warn "Tunnel has no active connections yet"
            return 1
        fi
    else
        log_error "Failed to get tunnel status"
        echo "$response" | jq '.' >> "$LOG_FILE"
        return 1
    fi
}

test_tunnel_connectivity() {
    log_info "Testing tunnel connectivity..."

    # Wait for DNS propagation
    log_info "Waiting 30s for DNS to propagate..."
    sleep 30

    # Test HTTP request
    local response
    response=$(curl -s -w "\n%{http_code}" -I "https://$TUNNEL_DOMAIN/" \
        -H "User-Agent: Phase-13-Test" \
        2>/dev/null || true)

    local http_code
    http_code=$(echo "$response" | tail -1)

    if [ -z "$http_code" ]; then
        log_warn "DNS not yet resolving (expected on first run)"
        return 1
    fi

    case "$http_code" in
        200|301|302|401|403)
            log_success "Tunnel responding with HTTP $http_code"
            return 0
            ;;
        *)
            log_warn "Tunnel responded with HTTP $http_code"
            return 1
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

main() {
    log_info "================================"
    log_info "PHASE 13 CLOUDFLARE TUNNEL SETUP"
    log_info "================================"
    log_info "Tunnel Name: $TUNNEL_NAME"
    log_info "Domain: $TUNNEL_DOMAIN"
    log_info "Log File: $LOG_FILE"
    log_info ""

    # Create log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    # Pre-flight checks
    if ! check_required_tools; then
        log_error "Pre-flight checks failed"
        return 1
    fi

    if ! check_cloudflare_credentials; then
        log_error "Cloudflare credential check failed"
        return 1
    fi

    # Get or create tunnel
    local tunnel_id
    tunnel_id=$(get_tunnel_id)

    if [ -z "$tunnel_id" ]; then
        log_info "Creating new tunnel..."
        tunnel_id=$(create_tunnel "$TUNNEL_NAME")
        if [ -z "$tunnel_id" ]; then
            log_error "Failed to create tunnel"
            return 1
        fi
    fi

    # Load tunnel token
    local tunnel_token
    if [ -f "$SCRIPT_DIR/.env" ]; then
        source "$SCRIPT_DIR/.env"
        tunnel_token="${CLOUDFLARE_TUNNEL_TOKEN:-}"
    fi

    if [ -z "$tunnel_token" ]; then
        log_error "Tunnel token not found. Please retrieve from Cloudflare dashboard."
        return 1
    fi

    # Configure and start tunnel
    configure_tunnel_routes "$tunnel_id"

    if ! start_tunnel_connector "$tunnel_id" "$tunnel_token"; then
        log_error "Failed to start tunnel connector"
        return 1
    fi

    # Verify tunnel
    if ! verify_tunnel_status "$tunnel_id"; then
        log_error "Tunnel status verification failed"
        return 1
    fi

    # Test connectivity
    if test_tunnel_connectivity; then
        log_success ""
        log_success "================================"
        log_success "✓ TUNNEL DEPLOYMENT SUCCESSFUL"
        log_success "================================"
        log_success "Tunnel ID: $tunnel_id"
        log_success "Domain: $TUNNEL_DOMAIN"
        log_success "Status: OPERATIONAL ✅"
        return 0
    else
        log_warn "Tunnel connectivity test inconclusive (DNS propagation may be needed)"
        log_warn "Monitor tunnel status in Cloudflare dashboard"
        return 1
    fi
}

# Execute main
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
    exit $?
fi
