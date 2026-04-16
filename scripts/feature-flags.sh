#!/bin/bash
# Feature Flag Management - Production Canary Deployment Support
# Issue #404 - Quality Gates Implementation
#
# This script provides feature flag management for gradual rollouts:
# 1% -> 10% -> 50% -> 100% user adoption
#
# Feature flags enable:
# - Canary deployments (expose to small user group first)
# - Gradual rollout (increase traffic over time)
# - Instant rollback (disable flag if issues detected)
# - A/B testing (compare behavior before/after)
#
# Usage:
#   ./feature-flags.sh list                    # List all flags
#   ./feature-flags.sh get <flag-name>         # Get flag status
#   ./feature-flags.sh enable <flag-name>      # Enable flag globally (100%)
#   ./feature-flags.sh disable <flag-name>     # Disable flag (0%)
#   ./feature-flags.sh set <flag-name> <pct>   # Set rollout percentage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

FEATURE_FLAGS_FILE="${FEATURE_FLAGS_FILE:-.env.feature-flags}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"

# ============================================================================
# Feature Flag Storage (Redis-based)
# ============================================================================
#
# Each feature flag is stored as a Redis key:
#   - Key: "feature_flag:<flag_name>:enabled_percentage"
#   - Value: 0-100 (percentage of users who see this feature)
#   - TTL: None (permanent until explicitly changed)
#
# Example usage in application code:
#   if is_feature_enabled("new_ui_redesign", user.id):
#       render_new_ui()
#   else:
#       render_legacy_ui()
#
# ============================================================================

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

# Check if Redis is available
check_redis() {
    if ! command -v redis-cli &> /dev/null; then
        error "redis-cli not found. Install redis-tools or use: docker-compose exec redis redis-cli"
    fi
}

# List all feature flags
list_flags() {
    log "Listing all feature flags..."
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" KEYS "feature_flag:*:enabled_percentage" | \
        sed 's/feature_flag://g; s/:enabled_percentage//g' || {
        log "No feature flags configured yet"
    }
}

# Get flag status (enabled percentage)
get_flag() {
    local flag_name="$1"
    local key="feature_flag:${flag_name}:enabled_percentage"
    
    local percentage=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$key" || echo "0")
    
    if [ -z "$percentage" ] || [ "$percentage" = "nil" ]; then
        percentage="0"
    fi
    
    log "Feature flag '$flag_name': ${percentage}% of users"
    
    case "$percentage" in
        0) echo "Status: DISABLED" ;;
        100) echo "Status: ENABLED (all users)" ;;
        *) echo "Status: CANARY (${percentage}% rollout)" ;;
    esac
}

# Enable flag globally (100%)
enable_flag() {
    local flag_name="$1"
    local key="feature_flag:${flag_name}:enabled_percentage"
    
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "$key" "100" || \
        error "Failed to enable flag '$flag_name'"
    
    log "✅ Feature flag '$flag_name' ENABLED (100% of users)"
    log "   This is the final stage of canary deployment"
}

# Disable flag (0%)
disable_flag() {
    local flag_name="$1"
    local key="feature_flag:${flag_name}:enabled_percentage"
    
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "$key" "0" || \
        error "Failed to disable flag '$flag_name'"
    
    log "✅ Feature flag '$flag_name' DISABLED (0% of users)"
    log "   ⚠️  INSTANT ROLLBACK - users reverted to previous behavior"
}

# Set flag to specific percentage
set_flag_percentage() {
    local flag_name="$1"
    local percentage="$2"
    local key="feature_flag:${flag_name}:enabled_percentage"
    
    # Validate percentage is 0-100
    if ! [[ "$percentage" =~ ^[0-9]+$ ]] || [ "$percentage" -lt 0 ] || [ "$percentage" -gt 100 ]; then
        error "Percentage must be between 0 and 100"
    fi
    
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "$key" "$percentage" || \
        error "Failed to set flag '$flag_name' to $percentage%"
    
    log "✅ Feature flag '$flag_name' set to ${percentage}%"
    
    case "$percentage" in
        0) log "   Status: DISABLED" ;;
        1-9) log "   Status: CANARY (testing with small user group)" ;;
        10-49) log "   Status: GRADUAL ROLLOUT (expanding to more users)" ;;
        50-99) log "   Status: APPROACHING FULL ROLLOUT" ;;
        100) log "   Status: FULL ROLLOUT (all users)" ;;
    esac
}

# Canary deployment workflow (1% -> 10% -> 50% -> 100%)
canary_rollout() {
    local flag_name="$1"
    local stage="${2:-1}"  # Stage 1, 2, 3, or 4
    
    case "$stage" in
        1)
            log "Canary Stage 1: Deploy to 1% of users..."
            set_flag_percentage "$flag_name" "1"
            log "Monitor: Check logs, error rate, latency for 5-10 minutes"
            log "Next: ./scripts/feature-flags.sh canary <flag-name> 2"
            ;;
        2)
            log "Canary Stage 2: Expand to 10% of users..."
            set_flag_percentage "$flag_name" "10"
            log "Monitor: Check metrics, user feedback for 15-30 minutes"
            log "Next: ./scripts/feature-flags.sh canary <flag-name> 3"
            ;;
        3)
            log "Canary Stage 3: Expand to 50% of users..."
            set_flag_percentage "$flag_name" "50"
            log "Monitor: Full production metrics for 30-60 minutes"
            log "Next: ./scripts/feature-flags.sh canary <flag-name> 4"
            ;;
        4)
            log "Canary Stage 4: Full rollout (100% of users)"
            enable_flag "$flag_name"
            log "✅ Feature fully deployed to production"
            ;;
        *)
            error "Stage must be 1, 2, 3, or 4"
            ;;
    esac
}

# ============================================================================
# Main Command Handler
# ============================================================================

main() {
    check_redis
    
    case "${1:-}" in
        list)
            list_flags
            ;;
        get)
            [ -z "${2:-}" ] && error "Usage: $0 get <flag-name>"
            get_flag "$2"
            ;;
        enable)
            [ -z "${2:-}" ] && error "Usage: $0 enable <flag-name>"
            enable_flag "$2"
            ;;
        disable)
            [ -z "${2:-}" ] && error "Usage: $0 disable <flag-name>"
            disable_flag "$2"
            ;;
        set)
            [ -z "${2:-}" ] || [ -z "${3:-}" ] && \
                error "Usage: $0 set <flag-name> <percentage>"
            set_flag_percentage "$2" "$3"
            ;;
        canary)
            [ -z "${2:-}" ] && error "Usage: $0 canary <flag-name> [stage 1-4]"
            canary_rollout "$2" "${3:-1}"
            ;;
        *)
            cat << EOF
Feature Flag Management - Production Canary Deployments

Usage:
  $0 list                           List all feature flags
  $0 get <flag-name>                Get flag status
  $0 enable <flag-name>             Enable flag for all users (100%)
  $0 disable <flag-name>            Disable flag (instant rollback)
  $0 set <flag-name> <percentage>   Set specific percentage (0-100)
  $0 canary <flag-name> [stage]     Canary deployment stages (1-4)

Examples:
  # Deploy new feature to 1% of users
  $0 canary new_dashboard 1
  
  # Expand to 10% after monitoring
  $0 canary new_dashboard 2
  
  # Issues detected? Instant rollback
  $0 disable new_dashboard
  
  # All clear? Full rollout
  $0 enable new_dashboard

Architecture:
  - Flags stored in Redis (key: feature_flag:<name>:enabled_percentage)
  - Percentage: 0-100 (% of users who see feature)
  - Application code checks flag before rendering feature
  - TTL: None (permanent until explicitly changed)
  - Monitoring: Track feature usage, error rate, latency per flag

Related Documentation:
  - Issue #404: Quality Gates Implementation
  - PRODUCTION-READINESS-FRAMEWORK.md: Phase 3 Operational Readiness
  - DEPLOYMENT-EXECUTION-PROCEDURE.md: Canary Deployment Workflow
EOF
            ;;
    esac
}

main "$@"
