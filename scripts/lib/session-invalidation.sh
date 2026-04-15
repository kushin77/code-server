#!/usr/bin/env bash
################################################################################
# File:          scripts/lib/session-invalidation.sh
# Owner:         Platform Engineering
# Purpose:       Session invalidation utilities for emergency breach response
# Usage:         source scripts/lib/session-invalidation.sh
# Status:        production
# Depends:       redis-cli, jq
# Last Updated:  April 15, 2026
################################################################################

set -euo pipefail

# Redis connection defaults
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

################################################################################
# Session Generation Counter Management
################################################################################

# Initialize global session generation counter
session_init_global_counter() {
    local counter_key="session:gen:global"
    
    # Check if counter exists
    if redis_key_exists "$counter_key"; then
        echo "✅ Global session counter already initialized"
        return 0
    fi
    
    # Initialize to generation 1
    redis_set "$counter_key" "1"
    redis_persist "$counter_key"
    
    echo "✅ Global session counter initialized (gen=1)"
}

# Initialize user-specific session generation counter
session_init_user_counter() {
    local email="$1"
    local user_hash
    
    user_hash=$(echo -n "$email" | sha256sum | cut -c1-8)
    local counter_key="session:gen:user:$user_hash"
    
    if redis_key_exists "$counter_key"; then
        return 0
    fi
    
    redis_set "$counter_key" "1"
    redis_persist "$counter_key"
}

# Get current global session generation
session_get_global_gen() {
    redis_get "session:gen:global" || echo "0"
}

# Get current user session generation
session_get_user_gen() {
    local email="$1"
    local user_hash
    
    user_hash=$(echo -n "$email" | sha256sum | cut -c1-8)
    local counter_key="session:gen:user:$user_hash"
    
    redis_get "$counter_key" || echo "0"
}

# Invalidate all global sessions (breach response)
session_invalidate_global() {
    local current_gen
    current_gen=$(session_get_global_gen)
    local next_gen=$((current_gen + 1))
    
    redis_set "session:gen:global" "$next_gen"
    redis_persist "session:gen:global"
    
    # Log the breach response
    log_session_invalidation "global" "" "all" "admin"
    
    echo "✅ All sessions invalidated (gen: $current_gen → $next_gen)"
    return 0
}

# Invalidate user-specific sessions
session_invalidate_user() {
    local email="$1"
    local user_hash
    
    user_hash=$(echo -n "$email" | sha256sum | cut -c1-8)
    local counter_key="session:gen:user:$user_hash"
    
    local current_gen
    current_gen=$(redis_get "$counter_key" || echo "0")
    local next_gen=$((current_gen + 1))
    
    redis_set "$counter_key" "$next_gen"
    redis_persist "$counter_key"
    
    # Log the invalidation
    log_session_invalidation "user" "$email" "user" "admin"
    
    echo "✅ User sessions invalidated for $email (gen: $current_gen → $next_gen)"
    return 0
}

################################################################################
# Device Fingerprint Functions
################################################################################

# Compute fingerprint hash for a request
session_compute_fingerprint() {
    local ip="$1"
    local user_agent="$2"
    
    # Extract /24 subnet (first 3 octets)
    local ip_prefix
    ip_prefix=$(echo "$ip" | cut -d. -f1-3)
    
    # Hash user agent
    local ua_hash
    ua_hash=$(echo -n "$user_agent" | sha256sum | cut -c1-16)
    
    # Create fingerprint JSON
    jq -n \
        --arg ip "$ip_prefix" \
        --arg ua "$ua_hash" \
        '{ip_prefix: $ip, ua_hash: $ua}'
}

# Store fingerprint in session
session_store_fingerprint() {
    local session_id="$1"
    local fingerprint="$2"
    
    local fp_key="session:fp:$session_id"
    redis_set "$fp_key" "$fingerprint"
    redis_expire "$fp_key" 86400  # 24 hour TTL
}

# Verify fingerprint matches current request
session_verify_fingerprint() {
    local session_id="$1"
    local current_fp="$2"
    
    local fp_key="session:fp:$session_id"
    local stored_fp
    
    stored_fp=$(redis_get "$fp_key" 2>/dev/null || echo "")
    
    if [[ -z "$stored_fp" ]]; then
        # No fingerprint stored (first request)
        return 0
    fi
    
    # Compare fingerprints
    if [[ "$stored_fp" == "$current_fp" ]]; then
        return 0
    fi
    
    # Fingerprint mismatch - potential token theft
    return 1
}

################################################################################
# Redis Helper Functions
################################################################################

redis_key_exists() {
    local key="$1"
    
    local cmd="EXISTS $key"
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" $cmd 2>/dev/null || echo "0"
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" $cmd 2>/dev/null || echo "0"
    fi
}

redis_get() {
    local key="$1"
    
    local cmd="GET $key"
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" $cmd 2>/dev/null || return 1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" $cmd 2>/dev/null || return 1
    fi
}

redis_set() {
    local key="$1"
    local value="$2"
    
    local cmd="SET $key $value"
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" $cmd >/dev/null 2>&1 || return 1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" $cmd >/dev/null 2>&1 || return 1
    fi
}

redis_persist() {
    local key="$1"
    
    local cmd="PERSIST $key"
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" $cmd >/dev/null 2>&1 || return 1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" $cmd >/dev/null 2>&1 || return 1
    fi
}

redis_expire() {
    local key="$1"
    local ttl="$2"
    
    local cmd="EXPIRE $key $ttl"
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" $cmd >/dev/null 2>&1 || return 1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" $cmd >/dev/null 2>&1 || return 1
    fi
}

################################################################################
# Audit Logging
################################################################################

log_session_invalidation() {
    local scope="$1"        # global | user
    local email="$2"        # user email (for user scope)
    local affected="$3"     # all | user | count
    local actor="$4"        # who performed invalidation
    
    local timestamp
    timestamp=$(date -u +'%Y-%m-%dT%H:%M:%S+00:00')
    
    local audit_dir="audit"
    mkdir -p "$audit_dir"
    
    local log_entry
    log_entry=$(jq -n \
        --arg ts "$timestamp" \
        --arg scope "$scope" \
        --arg email "$email" \
        --arg affected "$affected" \
        --arg actor "$actor" \
        '{timestamp: $ts, event: "session_invalidated", scope: $scope, email: $email, affected: $affected, actor: $actor}')
    
    echo "$log_entry" >> "audit/session-invalidation.log"
}

echo "✅ Session invalidation library loaded"
