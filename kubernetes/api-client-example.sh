#!/usr/bin/env bash
# @file        kubernetes/api-client-example.sh
# @module      kubernetes/integration
# @description Example: API client making authenticated requests with JWT token
#
# This script demonstrates how to:
# 1. Read a JWT token from the projected volume
# 2. Make authenticated API calls using the JWT bearer token
# 3. Handle token expiration and refresh
#
# Usage (from inside a pod with OIDC token projection):
#   # Export the token to use in curl/http requests
#   source kubernetes/api-client-example.sh
#   call_api_with_jwt GET /api/v1/sessions
#   call_api_with_jwt POST /api/v1/jobs/start --data '{"job": "backup"}'
#
# Or directly:
#   bash kubernetes/api-client-example.sh --call-api GET /api/v1/health

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────────────────

# Token configuration
OIDC_TOKEN_PATH="${OIDC_TOKEN_PATH:-/var/run/secrets/tokens/oidc/token}"
JWT_CACHE_FILE="${JWT_CACHE_FILE:-/tmp/.api_jwt_token}"
JWT_CACHE_TTL="${JWT_CACHE_TTL:-300}"  # 5 minutes

# OIDC issuer configuration
OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://ide.kushnir.cloud:4182}"
OIDC_AUDIENCE="${OIDC_AUDIENCE:-kubernetes}"

# API configuration
API_SERVER_URL="${API_SERVER_URL:-http://localhost:3000}"
API_INSECURE="${API_INSECURE:-false}"

# ────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────────────────────

# Check if JWT token needs refresh (cache expired or missing)
needs_token_refresh() {
    if [ ! -f "$JWT_CACHE_FILE" ]; then
        return 0  # Cache file doesn't exist, need refresh
    fi
    
    local age=$(($(date +%s) - $(stat -c %Y "$JWT_CACHE_FILE" 2>/dev/null || echo 0)))
    if [ "$age" -gt "$JWT_CACHE_TTL" ]; then
        return 0  # Cache expired, need refresh
    fi
    
    return 1  # Cache is still valid
}

# Get or acquire JWT token
get_jwt_token() {
    # Check if we can use cached token
    if ! needs_token_refresh && [ -f "$JWT_CACHE_FILE" ]; then
        cat "$JWT_CACHE_FILE"
        return 0
    fi
    
    # Need to acquire token
    echo "Acquiring JWT token from OIDC issuer..." >&2
    
    # Read projected token
    if [ ! -f "$OIDC_TOKEN_PATH" ]; then
        echo "ERROR: OIDC token not found at $OIDC_TOKEN_PATH" >&2
        return 1
    fi
    
    local subject_token
    subject_token=$(cat "$OIDC_TOKEN_PATH")
    
    # Exchange with OIDC issuer
    local curl_opts=()
    if [ "$API_INSECURE" = "true" ]; then
        curl_opts+=("-k")
    fi
    
    local response
    response=$(curl "${curl_opts[@]}" \
        -s \
        -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
        --data-urlencode "subject_token_type=urn:ietf:params:oauth:token-type:jwt" \
        --data-urlencode "subject_token=$subject_token" \
        --data-urlencode "audience=$OIDC_AUDIENCE" \
        "$OIDC_ISSUER_URL/.well-known/oauth2/token" 2>&1)
    
    # Extract access_token
    if echo "$response" | grep -q '"access_token"'; then
        local access_token
        access_token=$(echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
        
        # Cache the token
        mkdir -p "$(dirname "$JWT_CACHE_FILE")"
        echo "$access_token" > "$JWT_CACHE_FILE"
        chmod 600 "$JWT_CACHE_FILE"
        
        echo "$access_token"
        return 0
    else
        echo "ERROR: Failed to acquire JWT token" >&2
        echo "Response: $response" >&2
        return 1
    fi
}

# Make API call with JWT authentication
call_api_with_jwt() {
    local method="${1:-GET}"
    local endpoint="${2:-/api/v1/health}"
    shift 2
    
    # Get JWT token
    local jwt_token
    jwt_token=$(get_jwt_token) || {
        echo "Failed to obtain JWT token" >&2
        return 1
    }
    
    # Build curl command
    local curl_opts=()
    if [ "$API_INSECURE" = "true" ]; then
        curl_opts+=("-k")
    fi
    
    curl_opts+=("-X" "$method")
    curl_opts+=("-H" "Authorization: Bearer $jwt_token")
    curl_opts+=("-H" "Content-Type: application/json")
    
    # Add any additional curl options passed as arguments
    curl_opts+=("$@")
    
    # Make the API call
    echo "Making $method request to $API_SERVER_URL$endpoint" >&2
    curl "${curl_opts[@]}" "$API_SERVER_URL$endpoint"
}

# ────────────────────────────────────────────────────────────────────────────
# Example Functions
# ────────────────────────────────────────────────────────────────────────────

# Example 1: Health check (no auth required, but including JWT)
example_health_check() {
    echo "Example 1: Health Check with JWT"
    echo "=================================="
    call_api_with_jwt GET "/api/v1/health" \
        -w "\nHTTP Status: %{http_code}\n"
    echo ""
}

# Example 2: Get current user/session info (requires auth)
example_get_session() {
    echo "Example 2: Get Current Session (requires auth)"
    echo "=============================================="
    call_api_with_jwt GET "/api/v1/sessions/current" \
        -w "\nHTTP Status: %{http_code}\n"
    echo ""
}

# Example 3: Create a resource (requires auth + RBAC)
example_create_job() {
    echo "Example 3: Create Job (requires auth + RBAC)"
    echo "==========================================="
    local job_data
    job_data=$(cat <<'EOF'
{
  "name": "batch-process",
  "type": "data-import",
  "config": {
    "source": "s3://bucket/data.csv",
    "destination": "postgres://db/table"
  }
}
EOF
)
    
    call_api_with_jwt POST "/api/v1/jobs" \
        -H "Content-Type: application/json" \
        -d "$job_data" \
        -w "\nHTTP Status: %{http_code}\n"
    echo ""
}

# Example 4: Bearer token inspection (show JWT claims)
example_inspect_token() {
    echo "Example 4: Inspect JWT Token Claims"
    echo "===================================="
    
    local jwt_token
    jwt_token=$(get_jwt_token) || return 1
    
    echo "Token (first 50 chars): ${jwt_token:0:50}..."
    echo ""
    
    # Decode and display payload
    local payload
    payload=$(echo "$jwt_token" | cut -d '.' -f 2)
    payload="$payload$(printf '%.0s=' $(seq $((${#payload} % 4))))"
    
    echo "Decoded Claims:"
    echo "$payload" | base64 -d 2>/dev/null | jq '.' 2>/dev/null || {
        echo "Could not decode claims (jq required for pretty-print)"
        echo "$payload" | base64 -d 2>/dev/null
    }
    echo ""
}

# ────────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────────

main() {
    # Parse command line arguments
    case "${1:-help}" in
        --call-api)
            # Direct API call: --call-api METHOD ENDPOINT [curl-args]
            shift
            call_api_with_jwt "$@"
            ;;
        --inspect-token)
            # Inspect JWT token
            example_inspect_token
            ;;
        --health-check)
            # Run health check example
            example_health_check
            ;;
        --get-session)
            # Get session example
            example_get_session
            ;;
        --create-job)
            # Create job example
            example_create_job
            ;;
        help|--help|-h)
            cat <<'EOF'
API Client Example - Make authenticated API calls with JWT tokens

Usage:
  bash api-client-example.sh [command] [options]

Commands:
  --call-api METHOD ENDPOINT [curl-args]
    Make an API call with JWT authentication
    Example: --call-api GET /api/v1/health
    Example: --call-api POST /api/v1/jobs -d '{"name":"job1"}'

  --inspect-token
    Display JWT token claims for debugging

  --health-check
    Run example: Health check with JWT

  --get-session
    Run example: Get current session info

  --create-job
    Run example: Create a new job

  help
    Show this help message

Environment Variables:
  OIDC_TOKEN_PATH:      Path to projected Kubernetes token
  OIDC_ISSUER_URL:      OIDC issuer URL
  API_SERVER_URL:       API server URL
  JWT_CACHE_FILE:       Where to cache JWT token
  JWT_CACHE_TTL:        Token cache lifetime (seconds, default: 300)
  API_INSECURE:         Skip TLS verification (true/false)

Examples (from inside a pod with OIDC token projection):
  # Source this script and use functions directly
  source kubernetes/api-client-example.sh
  call_api_with_jwt GET /api/v1/health
  
  # Or use directly
  bash kubernetes/api-client-example.sh --health-check
  bash kubernetes/api-client-example.sh --inspect-token
  bash kubernetes/api-client-example.sh --call-api GET /api/v1/sessions

EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Use 'help' for usage information"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
