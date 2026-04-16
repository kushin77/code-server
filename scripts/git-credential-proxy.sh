#!/bin/bash
# Git Credential Helper for Cloudflare Proxy
# Phase 2 Issue #184: Enable push without SSH key access
# 
# This script intercepts git credential requests and routes them through
# the git-proxy-server instead of looking up local SSH keys.
# 
# Installation:
#   cp git-credential-proxy.sh /usr/local/bin/
#   git config --global credential.helper proxy
#   git config --global credential.useHttpPath true
# 
# Usage:
#   git push origin feature-branch
#   (automatically uses proxy instead of local SSH key)

set -euo pipefail

# Configuration
PROXY_URL="${GIT_PROXY_URL:-http://127.0.0.1:8765}"
PROXY_TOKEN="${GIT_PROXY_TOKEN:-}"
AUDIT_LOG="${GIT_PROXY_AUDIT:-$HOME/.git-proxy-audit.log}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

log_audit() {
    local operation=$1
    local host=$2
    local status=$3
    local details=${4:-}
    
    if [ -n "$AUDIT_LOG" ]; then
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local log_entry="{\"timestamp\":\"$timestamp\",\"operation\":\"$operation\",\"host\":\"$host\",\"status\":\"$status\",\"details\":\"$details\"}"
        echo "$log_entry" >> "$AUDIT_LOG" 2>/dev/null || true
    fi
}

# Parse git credential protocol input
# Format: key=value\nkey=value\n\n
parse_git_credentials() {
    local -A creds
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        IFS='=' read -r key value <<< "$line"
        creds[$key]="$value"
    done
    
    printf '%s\n' "${creds[@]}"
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    local operation=""
    local host=""
    local username=""
    local protocol=""
    
    # Read input from git
    while IFS='=' read -r key value; do
        case "$key" in
            "operation") operation="$value" ;;
            "host") host="$value" ;;
            "username") username="$value" ;;
            "protocol") protocol="$value" ;;
            "") break ;;
        esac
    done
    
    # Validate operation
    case "$operation" in
        "get")
            handle_get_credentials "$host" "$username" "$protocol"
            ;;
        "store")
            handle_store_credentials "$host" "$username"
            ;;
        "erase")
            handle_erase_credentials "$host"
            ;;
        *)
            echo -e "${RED}✗ Unknown operation: $operation${NC}" >&2
            exit 1
            ;;
    esac
}

handle_get_credentials() {
    local host="$1"
    local username="${2:-git}"
    local protocol="${3:-ssh}"
    
    # For SSH, we intercept and use the proxy
    if [ "$protocol" = "ssh" ] || [ "$host" = "github.com" ] || [ "$host" = "gitlab.com" ]; then
        # Check if proxy is available
        if ! command -v curl &> /dev/null; then
            echo -e "${RED}✗ curl required for git proxy${NC}" >&2
            exit 1
        fi
        
        # Call proxy server to authenticate
        if [ -n "$PROXY_TOKEN" ]; then
            response=$(curl -s -X POST \
                -H "Authorization: Bearer $PROXY_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"operation\":\"get\",\"host\":\"$host\",\"username\":\"$username\",\"protocol\":\"$protocol\"}" \
                "$PROXY_URL/git/credentials" 2>&1 || echo "{\"error\":\"proxy unreachable\"}")
            
            # Check for errors
            if echo "$response" | grep -q '"error"'; then
                echo -e "${YELLOW}⚠ Proxy error, using local SSH${NC}" >&2
                log_audit "get_credentials" "$host" "fallback" "proxy unavailable"
                
                # Fallback to standard SSH (should not have local key in read-only IDE)
                echo "protocol=$protocol"
                echo "host=$host"
                echo "username=$username"
            else
                # Return proxy credentials
                echo "protocol=$protocol"
                echo "host=$host"
                echo "username=$username"
                echo "password=$PROXY_TOKEN"
                log_audit "get_credentials" "$host" "success" "routed through proxy"
            fi
        else
            echo -e "${YELLOW}⚠ GIT_PROXY_TOKEN not set, cannot authenticate${NC}" >&2
            exit 1
        fi
    else
        # For HTTPS, use standard credentials
        echo "protocol=$protocol"
        echo "host=$host"
        echo "username=$username"
    fi
}

handle_store_credentials() {
    local host="$1"
    
    # In proxy mode, we don't store credentials locally
    # Just log the request
    log_audit "store_credentials" "$host" "ignored" "credentials not stored locally in proxy mode"
}

handle_erase_credentials() {
    local host="$1"
    
    # Erase operation - no-op in proxy mode
    log_audit "erase_credentials" "$host" "ignored" "no local credentials to erase"
}

# ============================================================================
# Entry Point
# ============================================================================

# Check if running in git credential helper mode
if [ $# -eq 0 ]; then
    main
else
    case "$1" in
        "get"|"store"|"erase")
            # Called with operation as first argument
            operation="$1"
            shift
            
            # Read remaining input
            while IFS='=' read -r key value; do
                case "$key" in
                    "host") host="$value" ;;
                    "username") username="$value" ;;
                    "protocol") protocol="$value" ;;
                    "") break ;;
                esac
            done
            
            case "$operation" in
                "get") handle_get_credentials "$host" "$username" "$protocol" ;;
                "store") handle_store_credentials "$host" ;;
                "erase") handle_erase_credentials "$host" ;;
            esac
            ;;
        "--help"|"-h")
            cat << EOF
Git Credential Helper for Proxy
Issue #184: Enable git operations without SSH key exposure

Usage: git credential-proxy get|store|erase < <credentials>

Environment Variables:
  GIT_PROXY_URL       URL to proxy server (default: http://127.0.0.1:8765)
  GIT_PROXY_TOKEN     Authentication token for proxy
  GIT_PROXY_AUDIT     Path to audit log (default: \$HOME/.git-proxy-audit.log)

Installation:
  sudo cp git-credential-proxy.sh /usr/local/bin/git-credential-proxy
  git config --global credential.helper proxy
  git config --global credential.useHttpPath true

This helper intercepts git credential requests and routes them through
the git-proxy-server, preventing developers from ever accessing SSH keys.

Example:
  export GIT_PROXY_URL=http://proxy.dev.internal:8765
  export GIT_PROXY_TOKEN=\$(cat ~/.git-proxy-token)
  git push origin feature-branch
EOF
            ;;
        *)
            echo -e "${RED}✗ Unknown argument: $1${NC}" >&2
            echo "Usage: git-credential-proxy [get|store|erase|--help]" >&2
            exit 1
            ;;
    esac
fi
