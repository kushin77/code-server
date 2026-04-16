#!/usr/bin/env bash
################################################################################
# File:          scripts/admin-sessions-invalidate.sh
# Owner:         Platform Engineering
# Purpose:       Session invalidation API endpoint for breach response
# Endpoint:      POST /admin/sessions/invalidate
# Auth:          Admin token (separate from user sessions)
# Rate Limit:    10 requests/minute
# Status:        production
# Last Updated:  April 15, 2026
################################################################################

set -euo pipefail

# Source session invalidation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/session-invalidation.sh"

################################################################################
# Configuration
################################################################################

# API configuration
ADMIN_TOKEN_HEADER="${ADMIN_TOKEN_HEADER:-X-Admin-Token}"
RATE_LIMIT_REQUESTS="${RATE_LIMIT_REQUESTS:-10}"
RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-60}"

# Redis prefix for rate limiting
RATE_LIMIT_PREFIX="admin:rate-limit:sessions-invalidate"

################################################################################
# Rate Limiting
################################################################################

# Check if admin has exceeded rate limit
rate_limit_check() {
    local admin_id="$1"
    local limit_key="$RATE_LIMIT_PREFIX:$admin_id"
    
    local current
    current=$(redis_get "$limit_key" 2>/dev/null || echo "0")
    
    if [[ $current -ge $RATE_LIMIT_REQUESTS ]]; then
        return 1  # Rate limited
    fi
    
    # Increment counter
    local next=$((current + 1))
    redis_set "$limit_key" "$next"
    redis_expire "$limit_key" "$RATE_LIMIT_WINDOW"
    
    return 0  # OK
}

################################################################################
# Admin Token Validation
################################################################################

# Validate admin token
validate_admin_token() {
    local token="$1"
    
    # Verify token format (must be 32+ chars)
    if [[ ${#token} -lt 32 ]]; then
        return 1
    fi
    
    # Check token in Redis (admin tokens stored separately from user sessions)
    local token_key="admin:token:$token"
    local admin_id
    admin_id=$(redis_get "$token_key" 2>/dev/null || echo "")
    
    if [[ -z "$admin_id" ]]; then
        return 1
    fi
    
    # Return admin ID for audit logging
    echo "$admin_id"
    return 0
}

################################################################################
# Invalidation Handlers
################################################################################

# Handle global session invalidation
invalidate_global() {
    local admin_id="$1"
    
    # Check rate limit
    if ! rate_limit_check "$admin_id"; then
        echo "ERROR: Rate limit exceeded (max $RATE_LIMIT_REQUESTS requests per $RATE_LIMIT_WINDOW seconds)"
        return 1
    fi
    
    # Perform invalidation
    session_invalidate_global
    
    # Send alert (PagerDuty P0 for global breach)
    send_breach_alert "global" "" "$admin_id" || true
    
    echo '{"status": "ok", "scope": "global", "message": "All sessions invalidated"}'
}

# Handle user-specific invalidation
invalidate_user() {
    local admin_id="$1"
    local email="$2"
    
    # Validate email
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "ERROR: Invalid email format"
        return 1
    fi
    
    # Check rate limit
    if ! rate_limit_check "$admin_id"; then
        echo "ERROR: Rate limit exceeded"
        return 1
    fi
    
    # Perform invalidation
    session_invalidate_user "$email"
    
    echo "{\"status\": \"ok\", \"scope\": \"user\", \"email\": \"$email\", \"message\": \"User sessions invalidated\"}"
}

################################################################################
# Breach Alert
################################################################################

# Send PagerDuty P0 alert for global breach
send_breach_alert() {
    local scope="$1"
    local email="$2"
    local admin_id="$3"
    
    local pagerduty_token="${PAGERDUTY_TOKEN:-}"
    
    if [[ -z "$pagerduty_token" ]]; then
        echo "WARNING: PAGERDUTY_TOKEN not configured, skipping alert"
        return 0
    fi
    
    if [[ "$scope" != "global" ]]; then
        return 0  # Only send P0 for global
    fi
    
    local timestamp
    timestamp=$(date -u +'%Y-%m-%dT%H:%M:%S+00:00')
    
    # Prepare alert payload
    local alert_payload
    alert_payload=$(jq -n \
        --arg ts "$timestamp" \
        --arg admin "$admin_id" \
        '{
            routing_key: "'$pagerduty_token'",
            event_action: "trigger",
            payload: {
                summary: "🚨 SECURITY BREACH: Global session invalidation triggered",
                severity: "critical",
                source: "code-server-admin-api",
                timestamp: $ts,
                custom_details: {
                    event: "global_session_invalidation",
                    actor: $admin,
                    scope: "all_users",
                    remediation: "Check breach runbook at docs/runbooks/session-breach-response.md"
                }
            }
        }')
    
    # Send alert (best effort, don't fail if PagerDuty is down)
    curl -s -X POST "https://events.pagerduty.com/v2/enqueue" \
        -H "Content-Type: application/json" \
        -d "$alert_payload" >/dev/null 2>&1 || true
}

################################################################################
# Request Handler
################################################################################

# Main request handler
handle_request() {
    local method="$1"
    local body="$2"
    local admin_token="$3"
    
    # Validate HTTP method
    if [[ "$method" != "POST" ]]; then
        echo '{"error": "Method not allowed", "allowed": ["POST"]}'
        return 1
    fi
    
    # Validate authorization
    if [[ -z "$admin_token" ]]; then
        echo '{"error": "Unauthorized", "message": "Missing admin token"}'
        return 1
    fi
    
    local admin_id
    if ! admin_id=$(validate_admin_token "$admin_token"); then
        echo '{"error": "Unauthorized", "message": "Invalid admin token"}'
        return 1
    fi
    
    # Parse request body
    local scope
    scope=$(echo "$body" | jq -r '.scope // empty' 2>/dev/null || echo "")
    
    if [[ -z "$scope" ]]; then
        echo '{"error": "Bad request", "message": "Missing scope field"}'
        return 1
    fi
    
    # Route to handler
    case "$scope" in
        "global")
            invalidate_global "$admin_id"
            ;;
        "user")
            local email
            email=$(echo "$body" | jq -r '.email // empty' 2>/dev/null || echo "")
            if [[ -z "$email" ]]; then
                echo '{"error": "Bad request", "message": "Missing email field for user scope"}'
                return 1
            fi
            invalidate_user "$admin_id" "$email"
            ;;
        *)
            echo '{"error": "Bad request", "message": "Invalid scope (must be global or user)"}'
            return 1
            ;;
    esac
}

################################################################################
# CLI Usage (for testing)
################################################################################

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script called directly
    METHOD="${1:-POST}"
    BODY="${2:-}"
    TOKEN="${ADMIN_TOKEN:-}"
    
    if [[ -z "$TOKEN" ]]; then
        echo "ERROR: ADMIN_TOKEN environment variable required"
        exit 1
    fi
    
    handle_request "$METHOD" "$BODY" "$TOKEN"
fi
