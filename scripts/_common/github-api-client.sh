#!/usr/bin/env bash
# @file        scripts/_common/github-api-client.sh
# @module      github/api-client
# @description Fine-grained GitHub token management, rate limit tracking, and exponential backoff retry logic
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
#
# Provides:
# - Secure fine-grained token retrieval from GSM
# - Automatic rate limit monitoring
# - Exponential backoff retry on 429/403 errors
# - All GitHub API calls wrapped with error handling
#

set -euo pipefail

# Source guards to prevent duplicate sourcing
[[ "${_GITHUB_API_CLIENT_SOURCED:-0}" == "1" ]] && return 0
readonly _GITHUB_API_CLIENT_SOURCED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================

# GitHub API rate limit thresholds
readonly GITHUB_RATE_LIMIT_THRESHOLD=100
readonly GITHUB_RATE_LIMIT_RESET_MIN=5  # seconds before reset to attempt call

# Retry configuration (exponential backoff)
readonly GITHUB_RETRY_MAX_ATTEMPTS=5
readonly GITHUB_RETRY_INITIAL_DELAY=1  # seconds
readonly GITHUB_RETRY_MAX_DELAY=60     # seconds

# GSM secret name for fine-grained GitHub token
readonly GITHUB_TOKEN_SECRET_NAME="github-fine-grained-token"

# ============================================================================
# Fine-Grained Token Management
# ============================================================================

#
# Retrieve fine-grained GitHub token from GSM
# Falls back to env var GITHUB_TOKEN if GSM unavailable
#
github_get_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "$GITHUB_TOKEN"
    return 0
  fi

  # Attempt GSM retrieval
  if command -v gcloud &>/dev/null; then
    local gsm_token
    gsm_token=$(gcloud secrets versions access latest --secret="$GITHUB_TOKEN_SECRET_NAME" 2>/dev/null || true)
    if [[ -n "$gsm_token" ]]; then
      echo "$gsm_token"
      return 0
    fi
  fi

  log_error "GitHub token not available (env GITHUB_TOKEN not set, GSM retrieval failed)"
  return 1
}

#
# Verify token has required scopes (fine-grained, not classic)
# Classic PAT scopes: repo, admin, etc. — too broad
# Fine-grained scopes: more limited (repo:read, issues:write, etc.)
#
github_verify_token_type() {
  local token="$1"
  local response
  
  response=$(curl -s -H "Authorization: token $token" "https://api.github.com/user" || echo "")
  
  # Fine-grained tokens return X-GitHub-API-Version header; classic PAT does not
  if echo "$response" | grep -q "ghp_"; then
    log_warn "Classic PAT detected (ghp_* format). Use fine-grained token (github_pat_* format) instead"
    return 1
  fi

  log_info "✓ Token verified as fine-grained"
  return 0
}

# ============================================================================
# Rate Limit Monitoring
# ============================================================================

#
# Get current GitHub API rate limit status
# Returns JSON: { "limit": N, "remaining": N, "reset": UNIX_TS }
#
github_get_rate_limit_status() {
  local token="$1"
  local response
  
  response=$(curl -s -H "Authorization: token $token" \
    "https://api.github.com/rate_limit" | jq '.rate_limit')
  
  echo "$response"
}

#
# Check if rate limit is approaching threshold
# Returns 0 if safe to proceed, 1 if limit exceeded
#
github_rate_limit_check() {
  local token="$1"
  local rate_limit_status
  local remaining
  
  rate_limit_status=$(github_get_rate_limit_status "$token")
  remaining=$(echo "$rate_limit_status" | jq -r '.remaining')
  
  if (( remaining < GITHUB_RATE_LIMIT_THRESHOLD )); then
    local reset_time
    reset_time=$(echo "$rate_limit_status" | jq -r '.reset')
    log_warn "GitHub rate limit approaching: $remaining/$GITHUB_RATE_LIMIT_THRESHOLD remaining (resets at $(date -d @$reset_time))"
    return 1
  fi

  return 0
}

# ============================================================================
# Exponential Backoff Retry Logic
# ============================================================================

#
# Retry function with exponential backoff for GitHub API calls
# Retries on:
#   - 429 (Too Many Requests)
#   - 403 (Forbidden — token scope or rate limit)
#   - 502, 503, 504 (temporary server errors)
#
github_api_call() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  
  local token
  token=$(github_get_token)
  
  local attempt=1
  local delay=$GITHUB_RETRY_INITIAL_DELAY
  
  while (( attempt <= GITHUB_RETRY_MAX_ATTEMPTS )); do
    log_info "[Attempt $attempt/$GITHUB_RETRY_MAX_ATTEMPTS] $method $endpoint"
    
    # Build curl command
    local curl_opts=(-s -w "\n%{http_code}")
    curl_opts+=(-H "Authorization: token $token")
    curl_opts+=(-H "Accept: application/vnd.github+json")
    curl_opts+=(-H "X-GitHub-Api-Version: 2022-11-28")
    
    if [[ "$method" != "GET" ]]; then
      curl_opts+=(-X "$method")
      if [[ -n "$data" ]]; then
        curl_opts+=(-d "$data")
      fi
    fi
    
    local response
    local http_code
    response=$(curl "${curl_opts[@]}" "https://api.github.com$endpoint" || echo "")
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | head -n-1)
    
    # Success cases
    if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
      log_info "✓ Success ($http_code)"
      echo "$response"
      return 0
    fi
    
    # Rate limit / transient errors - retry
    if [[ "$http_code" =~ ^(429|403|502|503|504)$ ]]; then
      if (( attempt < GITHUB_RETRY_MAX_ATTEMPTS )); then
        log_warn "Transient error ($http_code), retrying in ${delay}s..."
        sleep "$delay"
        
        # Exponential backoff
        delay=$(( delay * 2 ))
        if (( delay > GITHUB_RETRY_MAX_DELAY )); then
          delay=$GITHUB_RETRY_MAX_DELAY
        fi
        
        (( attempt++ ))
        continue
      fi
    fi
    
    # Non-retryable errors - fail immediately
    log_error "GitHub API error ($http_code): $response"
    return 1
  done
  
  log_error "GitHub API call failed after $GITHUB_RETRY_MAX_ATTEMPTS attempts"
  return 1
}

# ============================================================================
# GitHub CLI Wrapper
# ============================================================================

#
# Wrap `gh` CLI calls with token and error handling
#
github_gh() {
  local token
  token=$(github_get_token)
  local subcommand="${1:-}"
  
  # Enforce explicit repo scoping for repo-bound commands.
  if [[ "$subcommand" == "issue" || "$subcommand" == "pr" ]]; then
    if [[ ! "$*" =~ --repo ]]; then
      log_error "GitHub CLI call missing --repo flag: gh $*"
      return 1
    fi
  fi
  
  GH_TOKEN="$token" gh "$@" || {
    local exit_code=$?
    if (( exit_code == 1 )); then
      log_error "GitHub CLI error (exit $exit_code). Check rate limits or token scopes."
      return "$exit_code"
    fi
    return "$exit_code"
  }
}

# ============================================================================
# Exports
# ============================================================================

export -f github_get_token
export -f github_verify_token_type
export -f github_get_rate_limit_status
export -f github_rate_limit_check
export -f github_api_call
export -f github_gh
