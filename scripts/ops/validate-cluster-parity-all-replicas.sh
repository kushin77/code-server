#!/usr/bin/env bash
# @file        scripts/ops/validate-cluster-parity-all-replicas.sh
# @module      ops/cluster-validation
# @description Comprehensive cluster parity validation for multi-replica deployment
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# CONFIGURATION
################################################################################

SSH_USER="${SSH_USER:-akushnir}"
SSH_TIMEOUT="${SSH_TIMEOUT:-10}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
HEALTH_SCHEME="${HEALTH_SCHEME:-https}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
HEALTH_HOST="${HEALTH_HOST:-ide.kushnir.cloud}"
PUBLIC_HEALTH_SCHEME="${PUBLIC_HEALTH_SCHEME:-https}"
PUBLIC_HEALTH_PATH="${PUBLIC_HEALTH_PATH:-/healthz}"
PUBLIC_HEALTH_HOST="${PUBLIC_HEALTH_HOST:-}"
PARITY_IGNORED_SERVICES_REGEX="${PARITY_IGNORED_SERVICES_REGEX:-^(session-broker)$}"

if [[ -z "$PUBLIC_HEALTH_HOST" && -n "${IDE_BASE_URL:-}" ]]; then
    PUBLIC_HEALTH_HOST="${IDE_BASE_URL#*://}"
    PUBLIC_HEALTH_HOST="${PUBLIC_HEALTH_HOST%%/*}"
fi

PUBLIC_HEALTH_HOST="${PUBLIC_HEALTH_HOST:-ide.kushnir.cloud}"
JSON_OUTPUT=0
STRICT_MODE=0
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/triage"

# Parity check results
declare -A GIT_COMMITS
declare -A SERVICE_COUNTS
declare -A HEALTH_STATUS
PARITY_VIOLATIONS=0

################################################################################
# ARGUMENT PARSING
################################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        --replicas) REPLICAS="${2:-}"; shift 2 ;;
        --timeout) SSH_TIMEOUT="${2:-10}"; shift 2 ;;
        --json) JSON_OUTPUT=1; shift ;;
        --strict) STRICT_MODE=1; shift ;;
        -h|--help) 
            echo "Usage: scripts/ops/validate-cluster-parity-all-replicas.sh [OPTIONS]"
            echo "Options:"
            echo "  --replicas <list>    Comma-separated replica IPs"
            echo "  --timeout <secs>     SSH connection timeout"
            echo "  --json               Output in JSON format"
            echo "  --strict             Require exact parity"
            exit 0
            ;;
        *) log_fatal "Unknown option: $1" ;;
    esac
done

if [[ -z "${REPLICAS:-}" ]]; then
    if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
        REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
    else
        log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before running cluster parity validation"
    fi
fi

if [[ ! -f "$SSH_KEY" ]]; then
    log_fatal "SSH key not found: $SSH_KEY"
fi

PARITY_SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout="${SSH_TIMEOUT}" -o StrictHostKeyChecking=no)

################################################################################
# CLUSTER PARITY VALIDATION
################################################################################

check_replica_git_commit() {
    local replica="$1"
    
    local commit
    commit=$(ssh "${PARITY_SSH_OPTS[@]}" \
        "$SSH_USER@$replica" \
        "cd code-server-enterprise && git rev-parse HEAD" 2>/dev/null || echo "ERROR")
    
    if [[ "$commit" == "ERROR" ]]; then
        log_error "Failed to get git commit from $replica"
        return 1
    fi
    
    GIT_COMMITS[$replica]="$commit"
    log_debug "[$replica] Git commit: ${commit:0:8}"
    return 0
}

check_replica_service_count() {
    local replica="$1"
    
    local count
    count=$(ssh "${PARITY_SSH_OPTS[@]}" \
        "$SSH_USER@$replica" \
        "cd code-server-enterprise && docker-compose ps --services 2>/dev/null | grep -Ev '${PARITY_IGNORED_SERVICES_REGEX}' | wc -l" 2>/dev/null || echo "0")
    
    SERVICE_COUNTS[$replica]="$count"
    log_debug "[$replica] Service count: $count"
    return 0
}

check_replica_health() {
    local replica="$1"
    
    local status
    status=$(curl -sk -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 \
        --resolve "${HEALTH_HOST}:443:${replica}" \
        "${HEALTH_SCHEME}://${HEALTH_HOST}${HEALTH_PATH}" 2>/dev/null || echo "000")
    
    HEALTH_STATUS[$replica]="$status"
    
    if [[ "$status" == "200" ]]; then
        log_debug "[$replica] Health check: OK"
        return 0
    else
        log_debug "[$replica] Health check: FAIL (HTTP $status)"
        return 1
    fi
}

check_replica_public_health() {
    local replica="$1"

    local status
    status=$(curl -sk -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 \
        --resolve "${PUBLIC_HEALTH_HOST}:443:${replica}" \
        "${PUBLIC_HEALTH_SCHEME}://${PUBLIC_HEALTH_HOST}${PUBLIC_HEALTH_PATH}" 2>/dev/null || echo "000")

    HEALTH_STATUS["${replica}_public"]="$status"

    if [[ "$status" == "200" ]]; then
        log_debug "[$replica] Public HTTPS health check: OK"
        return 0
    else
        log_debug "[$replica] Public HTTPS health check: FAIL (HTTP $status)"
        return 1
    fi
}

validate_cluster_parity() {
    log_info "=== Validating Cluster Parity ==="
    log_info ""
    
    # Convert replicas string to array
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    # Check each replica
    for replica in "${replica_array[@]}"; do
        log_info "Checking replica: $replica"
        
        check_replica_git_commit "$replica" || ((++PARITY_VIOLATIONS))
        check_replica_service_count "$replica"
        check_replica_health "$replica" || ((++PARITY_VIOLATIONS))
        check_replica_public_health "$replica" || ((++PARITY_VIOLATIONS))
    done
    
    log_info ""
    log_info "=== Parity Check Results ==="
    
    # Check if all replicas have same git commit
    local first_commit=""
    local commits_match=1
    for replica in "${replica_array[@]}"; do
        if [[ -z "$first_commit" ]]; then
            first_commit="${GIT_COMMITS[$replica]:-}"
        elif [[ "${GIT_COMMITS[$replica]:-}" != "$first_commit" ]]; then
            commits_match=0
            log_error "Git commit mismatch: $replica has ${GIT_COMMITS[$replica]:-UNKNOWN}"
        fi
    done
    
    if [[ $commits_match -eq 1 ]]; then
        log_info "✓ All replicas on same git commit: ${first_commit:0:8}"
    else
        log_error "✗ Git commits do not match across replicas"
        ((++PARITY_VIOLATIONS))
    fi
    
    # Check if all replicas have matching service count without hardcoding topology.
    local baseline_count=""
    local all_counts_match=1
    for replica in "${replica_array[@]}"; do
        local count="${SERVICE_COUNTS[$replica]:-0}"

        if [[ "$count" -le 0 ]]; then
            log_error "✗ Service count unavailable on $replica"
            all_counts_match=0
            continue
        fi

        if [[ -z "$baseline_count" ]]; then
            baseline_count="$count"
            continue
        fi

        if [[ "$count" -ne "$baseline_count" ]]; then
            log_error "✗ Service count mismatch on $replica: $count (expected $baseline_count from first replica)"
            all_counts_match=0
        fi
    done

    if [[ $all_counts_match -eq 1 ]]; then
        log_info "✓ All replicas have matching service count ($baseline_count)"
    else
        ((++PARITY_VIOLATIONS))
    fi
    
    # Check health status, including the public HTTPS health route.
    local all_healthy_check=1
    local all_public_healthy_check=1
    for replica in "${replica_array[@]}"; do
        if [[ "${HEALTH_STATUS[$replica]:-000}" != "200" ]]; then
            log_error "✗ Health check failed on $replica: HTTP ${HEALTH_STATUS[$replica]:-000}"
            all_healthy_check=0
        fi

        if [[ "${HEALTH_STATUS[${replica}_public]:-000}" != "200" ]]; then
            log_error "✗ Public HTTPS health check failed on $replica: HTTP ${HEALTH_STATUS[${replica}_public]:-000}"
            all_public_healthy_check=0
        fi
    done
    
    if [[ $all_healthy_check -eq 1 && $all_public_healthy_check -eq 1 ]]; then
        log_info "✓ All replicas health checks passed"
    else
        ((++PARITY_VIOLATIONS))
    fi
    
    log_info ""
    return $PARITY_VIOLATIONS
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Cluster Parity Validation Script"
    log_info "Replicas: $REPLICAS"
    log_info ""
    
    mkdir -p "$ARTIFACTS_DIR"
    
    validate_cluster_parity
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        log_info "✓ Cluster parity validation PASSED"
        return 0
    else
        log_error "✗ Cluster parity validation FAILED ($result violations)"
        return 1
    fi
}

main "$@"
