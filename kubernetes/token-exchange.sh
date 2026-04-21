#!/usr/bin/env bash
# @file        kubernetes/token-exchange.sh
# @module      kubernetes/oidc
# @description Exchange Kubernetes OIDC token for JWT access_token from OIDC issuer
#
# This script is meant to run inside a Kubernetes pod with OIDC token projection.
# It reads the projected token from the filesystem and exchanges it with the 
# OIDC issuer for a JWT access_token that can be used to authenticate API calls.
#
# Usage:
#   # Inside a pod with OIDC token projection:
#   bash token-exchange.sh \
#     --issuer-url https://ide.kushnir.cloud:4182 \
#     --token-path /var/run/secrets/tokens/oidc/token \
#     --audience kubernetes \
#     --output-file /tmp/access_token.jwt
#
#   # Or with default paths:
#   bash token-exchange.sh
#
# Environment Variables (defaults):
#   OIDC_ISSUER_URL: OIDC issuer URL (default: https://ide.kushnir.cloud:4182)
#   OIDC_TOKEN_PATH: Path to projected token (default: /var/run/secrets/tokens/oidc/token)
#   OIDC_AUDIENCE: Token audience (default: kubernetes)
#   OIDC_OUTPUT_FILE: Where to write the access_token (default: /tmp/access_token.jwt)
#   OIDC_INSECURE: Skip TLS verification (default: false)
#   DEBUG: Enable debug output (default: false)

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://ide.kushnir.cloud:4182}"
OIDC_TOKEN_PATH="${OIDC_TOKEN_PATH:-/var/run/secrets/tokens/oidc/token}"
OIDC_AUDIENCE="${OIDC_AUDIENCE:-kubernetes}"
OIDC_OUTPUT_FILE="${OIDC_OUTPUT_FILE:-/tmp/access_token.jwt}"
OIDC_INSECURE="${OIDC_INSECURE:-false}"
DEBUG="${DEBUG:-false}"

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --issuer-url)
            OIDC_ISSUER_URL="$2"
            shift 2
            ;;
        --token-path)
            OIDC_TOKEN_PATH="$2"
            shift 2
            ;;
        --audience)
            OIDC_AUDIENCE="$2"
            shift 2
            ;;
        --output-file)
            OIDC_OUTPUT_FILE="$2"
            shift 2
            ;;
        --insecure)
            OIDC_INSECURE="true"
            shift
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [options]"
            echo ""
            echo "Options:"
            echo "  --issuer-url URL          OIDC issuer URL (default: https://ide.kushnir.cloud:4182)"
            echo "  --token-path PATH         Path to projected token (default: /var/run/secrets/tokens/oidc/token)"
            echo "  --audience AUDIENCE       Token audience (default: kubernetes)"
            echo "  --output-file FILE        Output JWT file (default: /tmp/access_token.jwt)"
            echo "  --insecure                Skip TLS verification"
            echo "  --debug                   Enable debug output"
            echo "  -h, --help                Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  OIDC_ISSUER_URL, OIDC_TOKEN_PATH, OIDC_AUDIENCE, OIDC_OUTPUT_FILE"
            echo "  OIDC_INSECURE, DEBUG"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────────────────────

log_debug() {
    if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] $*" >&2
    fi
}

log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Decode JWT claims for inspection (uses jq or falls back to base64)
decode_jwt_payload() {
    local jwt="$1"
    local payload
    
    # Extract middle part (payload)
    payload=$(echo "$jwt" | cut -d '.' -f 2)
    
    # Add padding if needed
    local padded
    padded="$payload$(printf '%.0s=' $(seq $((${#payload} % 4))))"
    
    # Decode base64
    if command -v jq &>/dev/null; then
        echo "$padded" | base64 -d 2>/dev/null | jq '.' || echo "$padded" | base64 -d 2>/dev/null
    else
        echo "$padded" | base64 -d 2>/dev/null || echo "[Could not decode payload]"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Validation
# ────────────────────────────────────────────────────────────────────────────

log_debug "Configuration:"
log_debug "  OIDC_ISSUER_URL: $OIDC_ISSUER_URL"
log_debug "  OIDC_TOKEN_PATH: $OIDC_TOKEN_PATH"
log_debug "  OIDC_AUDIENCE: $OIDC_AUDIENCE"
log_debug "  OIDC_OUTPUT_FILE: $OIDC_OUTPUT_FILE"
log_debug "  OIDC_INSECURE: $OIDC_INSECURE"

# Check token file exists
if [ ! -f "$OIDC_TOKEN_PATH" ]; then
    log_error "Token file not found: $OIDC_TOKEN_PATH"
    log_error "This script must run inside a pod with OIDC token projection enabled."
    exit 1
fi

# Read token
SUBJECT_TOKEN=$(cat "$OIDC_TOKEN_PATH")
if [ -z "$SUBJECT_TOKEN" ]; then
    log_error "Token file is empty: $OIDC_TOKEN_PATH"
    exit 1
fi

log_info "Token loaded from: $OIDC_TOKEN_PATH"
log_debug "Token (first 50 chars): ${SUBJECT_TOKEN:0:50}..."

# ────────────────────────────────────────────────────────────────────────────
# Token Exchange Request
# ────────────────────────────────────────────────────────────────────────────

log_info "Exchanging Kubernetes token for JWT access_token..."
log_debug "Requesting: POST $OIDC_ISSUER_URL/.well-known/oauth2/token"

# Build curl command with optional insecure flag
CURL_OPTS=()
if [ "$OIDC_INSECURE" = "true" ]; then
    CURL_OPTS+=("-k")  # Allow insecure connections
    log_info "⚠️  TLS verification disabled (--insecure)"
fi

# Perform token exchange via RFC 8693 (Subject Token Assertion Grant)
RESPONSE=$(curl "${CURL_OPTS[@]}" \
    -s \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
    --data-urlencode "subject_token_type=urn:ietf:params:oauth:token-type:jwt" \
    --data-urlencode "subject_token=$SUBJECT_TOKEN" \
    --data-urlencode "audience=$OIDC_AUDIENCE" \
    "$OIDC_ISSUER_URL/.well-known/oauth2/token" 2>&1 || true)

log_debug "Token exchange response: $RESPONSE"

# Check for errors
if echo "$RESPONSE" | grep -q "error"; then
    log_error "Token exchange failed!"
    log_error "Response: $RESPONSE"
    exit 1
fi

# Extract access_token from response
if ! command -v jq &>/dev/null; then
    log_error "jq is required to parse response. Please install jq."
    exit 1
fi

ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token' 2>/dev/null || true)
if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    log_error "Failed to extract access_token from response"
    log_error "Response: $RESPONSE"
    exit 1
fi

log_info "✅ Token exchange successful!"

# Save to output file
mkdir -p "$(dirname "$OIDC_OUTPUT_FILE")"
echo "$ACCESS_TOKEN" > "$OIDC_OUTPUT_FILE"
chmod 600 "$OIDC_OUTPUT_FILE"

log_info "Access token written to: $OIDC_OUTPUT_FILE"

# Display token info
log_info ""
log_info "Token Details:"
log_info "  Format: JWT (RS256)"
log_info "  Location: $OIDC_OUTPUT_FILE"

# Decode and display claims
if command -v jq &>/dev/null; then
    log_info "  Payload:"
    decode_jwt_payload "$ACCESS_TOKEN" | sed 's/^/    /' || log_info "  [Could not decode claims]"
fi

log_info ""
log_info "✨ Ready to use token in API requests:"
log_info "  curl -H 'Authorization: Bearer $(cat $OIDC_OUTPUT_FILE)' http://api:3000/api/v1/endpoint"

exit 0
