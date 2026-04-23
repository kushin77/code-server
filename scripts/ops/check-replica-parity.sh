#!/usr/bin/env bash
# @file        scripts/ops/check-replica-parity.sh
# @module      operations/cluster
# @description Check configuration parity across all production replicas
# @owner       platform
# @status      active
#
# Verifies that both replicas (192.168.168.31 and 192.168.168.42) have
# identical critical configuration values. Detects configuration drift early.
#
# Usage:
#   bash scripts/ops/check-replica-parity.sh
#   bash scripts/ops/check-replica-parity.sh --fix  # Auto-fix by syncing from GSM
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR%/ops}/_common/init.sh"

readonly REPLICA_1="192.168.168.31"
readonly REPLICA_2="192.168.168.42"
readonly SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa_onprem}"
readonly SSH_USER="${SSH_USER:-akushnir}"
readonly WORK_DIR="${WORK_DIR:-code-server-enterprise}"

# Critical vars that MUST be identical across replicas (excluding host-specific vars)
declare -a PARITY_CHECK_VARS=(
    "DOMAIN"
    "APEX_DOMAIN"
    "IDE_DOMAIN"
    "COMPOSE_PROFILES"
    "POSTGRES_DB"
    "POSTGRES_USER"
    "REDIS_PASSWORD"
    "OAUTH2_PROXY_COOKIE_SECRET"
    "IDE_SESSION_LB_SECRET"
)

FIX_MODE="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)
            FIX_MODE="true"
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            return 1
            ;;
    esac
done

# Fetch env vars from a single replica
fetch_replica_config() {
    local host="$1"
    local tempfile
    tempfile=$(mktemp)
    
    log_info "Fetching config from $host..."
    
    # SSH to replica and export env vars
    ssh -i "$SSH_KEY" "${SSH_USER}@${host}" \
        "cd ${WORK_DIR} && source scripts/fetch-gsm-secrets.sh --non-interactive 2>/dev/null && env | grep -E '^(${PARITY_CHECK_VARS[*]//$'\n'/|})=' || true" \
        > "$tempfile" 2>/dev/null || {
        log_error "Failed to fetch config from $host"
        rm -f "$tempfile"
        return 1
    }
    
    echo "$tempfile"
}

# Compare two config files
compare_configs() {
    local file1="$1"
    local file2="$2"
    local diff_output
    local differences=0
    
    log_info "Comparing configurations..."
    
    diff_output=$(diff "$file1" "$file2" 2>&1 || true)
    
    if [ -z "$diff_output" ]; then
        log_info "✅ Replica configurations are IDENTICAL"
        return 0
    else
        log_warn "⚠️  Configuration differences detected:"
        echo "$diff_output" | while read -r line; do
            log_warn "  $line"
        done
        return 1
    fi
}

# Automatically fix parity by syncing from GSM
fix_replica_parity() {
    local host="$1"
    
    log_info "Syncing GSM secrets to $host..."
    
    ssh -i "$SSH_KEY" "${SSH_USER}@${host}" \
        "cd ${WORK_DIR} && \
         source scripts/fetch-gsm-secrets.sh --non-interactive > .env.tmp && \
         mv .env.tmp .env && \
         docker-compose up -d --no-recreate && \
         echo 'Replica $host configuration synchronized'" \
        2>&1 | sed 's/^/  /'
}

# Main execution
main() {
    log_info "Checking replica configuration parity..."
    log_info "Replicas: $REPLICA_1, $REPLICA_2"
    
    # Fetch configs from both replicas
    local config1 config2
    config1=$(fetch_replica_config "$REPLICA_1") || {
        log_error "Cannot proceed without Replica 1 config"
        return 1
    }
    
    config2=$(fetch_replica_config "$REPLICA_2") || {
        log_error "Cannot proceed without Replica 2 config"
        rm -f "$config1"
        return 1
    }
    
    # Compare configurations
    if ! compare_configs "$config1" "$config2"; then
        if [ "$FIX_MODE" = "true" ]; then
            log_warn "Auto-fix enabled: syncing from GSM..."
            fix_replica_parity "$REPLICA_2"
            
            # Re-fetch and verify
            local config2_fixed
            config2_fixed=$(fetch_replica_config "$REPLICA_2")
            
            if compare_configs "$config1" "$config2_fixed"; then
                log_info "✅ Parity restored after sync"
            else
                log_error "Parity still not matching after sync - manual intervention required"
            fi
            
            rm -f "$config2_fixed"
        else
            log_error "Configuration drift detected. Run with --fix to auto-sync from GSM"
            rm -f "$config1" "$config2"
            return 1
        fi
    fi
    
    # Cleanup
    rm -f "$config1" "$config2"
    
    log_info "✅ Replica parity check PASSED"
    return 0
}

main "$@"
