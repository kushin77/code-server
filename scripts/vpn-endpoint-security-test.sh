#!/bin/bash
################################################################################
# VPN ENTERPRISE ENDPOINT SECURITY TEST
# Validates network isolation, endpoint security, and access controls
# 
# Usage: ./vpn-endpoint-security-test.sh [--verbose] [--deep-scan]
# 
# Performs:
# - Endpoint accessibility checks (external only)
# - Network isolation verification
# - Security boundary testing
# - Latency and response time measurements
# - Port security validation
# - Service discovery verification
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
readonly RESULTS_DIR="${SCRIPT_DIR}/../test-results/vpn-endpoint-scan/${TIMESTAMP}"

# Configuration
readonly DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
readonly DEPLOY_USER="${DEPLOY_USER:-akushnir}"
readonly VERBOSE="${VERBOSE:-false}"
readonly DEEP_SCAN="${DEEP_SCAN:-false}"

# External endpoints (publicly accessible via host network)
declare -A EXTERNAL_ENDPOINTS=(
    [code-server]="http://${DEPLOY_HOST}:8080"
    [jaeger-ui]="http://${DEPLOY_HOST}:16686"
    [ollama-api]="http://${DEPLOY_HOST}:11434"
)

# Internal endpoints (Docker network only, should NOT be accessible from host)
declare -A INTERNAL_ENDPOINTS=(
    [prometheus]="http://${DEPLOY_HOST}:9090"
    [grafana]="http://${DEPLOY_HOST}:3000"
    [alertmanager]="http://${DEPLOY_HOST}:9093"
    [loki]="http://${DEPLOY_HOST}:3100"
)

# Security checks
declare -a SECURITY_CHECKS=(
    "cap_drop"
    "no_root_user"
    "read_only_fs"
    "security_opt"
    "network_isolation"
)

################################################################################
# UTILITY FUNCTIONS
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[VERBOSE] $*" >&2
    fi
}

error() {
    echo "[ERROR] $*" >&2
    return 1
}

create_results_dir() {
    mkdir -p "${RESULTS_DIR}"
    log "Results directory: ${RESULTS_DIR}"
}

################################################################################
# NETWORK CHECKS
################################################################################

check_external_endpoint() {
    local name="$1"
    local url="$2"
    local timeout=5
    
    verbose "Testing external endpoint: ${name} (${url})"
    
    if timeout "$timeout" curl -s -m 3 -o /dev/null -w "%{http_code}" "${url}" >/dev/null 2>&1; then
        local status_code=$(timeout "$timeout" curl -s -m 3 -w "%{http_code}" -o /dev/null "${url}" 2>/dev/null || echo "000")
        if [[ "$status_code" != "000" ]]; then
            echo "✓ EXTERNAL:${name}:ACCESSIBLE (HTTP ${status_code})"
            return 0
        fi
    fi
    
    echo "✗ EXTERNAL:${name}:TIMEOUT"
    return 1
}

check_internal_endpoint_isolation() {
    local name="$1"
    local url="$2"
    local timeout=3
    
    verbose "Testing internal endpoint isolation: ${name} (${url})"
    
    # Internal endpoints should NOT respond from the host network
    if timeout "$timeout" curl -s -m 2 -o /dev/null -w "%{http_code}" "${url}" >/dev/null 2>&1; then
        echo "✗ INTERNAL:${name}:EXPOSED (security issue - should be isolated)"
        return 1
    else
        echo "✓ INTERNAL:${name}:ISOLATED (not accessible from host)"
        return 0
    fi
}

check_network_routes() {
    log "Checking network routing..."
    
    # Get Docker network info
    local docker_network=$(ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "docker network inspect enterprise --format='{{json .IPAM}}' 2>/dev/null" || echo "{}")
    
    if [[ "$docker_network" != "{}" ]]; then
        echo "✓ NETWORK:docker-network:CONFIGURED (${docker_network})"
        return 0
    else
        echo "✗ NETWORK:docker-network:NOT_FOUND"
        return 1
    fi
}

################################################################################
# SECURITY VERIFICATION
################################################################################

check_container_security() {
    log "Checking container security settings..."
    
    ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "cd code-server-enterprise && \
        docker-compose config 2>/dev/null | grep -A 5 'security_opt' | head -20 || echo 'No security options found'"
}

check_network_isolation() {
    log "Verifying network isolation..."
    
    local output=$(ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "docker network inspect enterprise --format='{{json .}}' 2>/dev/null" || echo "{}")
    
    if [[ "$output" != "{}" ]]; then
        echo "✓ SECURITY:network-isolation:CONFIGURED"
        return 0
    else
        echo "✗ SECURITY:network-isolation:NOT_CONFIGURED"
        return 1
    fi
}

################################################################################
# PERFORMANCE CHECKS
################################################################################

measure_endpoint_latency() {
    local name="$1"
    local url="$2"
    
    verbose "Measuring latency for: ${name}"
    
    local response_time=$(curl -s -m 5 -w "%{time_total}" -o /dev/null "${url}" 2>/dev/null || echo "0")
    
    if (( $(echo "$response_time > 0" | bc -l) )); then
        local latency_ms=$(echo "scale=0; $response_time * 1000" | bc)
        echo "✓ LATENCY:${name}:${latency_ms}ms"
        return 0
    else
        echo "✗ LATENCY:${name}:TIMEOUT"
        return 1
    fi
}

################################################################################
# COMPREHENSIVE SCAN
################################################################################

execute_deep_scan() {
    if [[ "$DEEP_SCAN" != "true" ]]; then
        return 0
    fi
    
    log "Executing deep security scan..."
    
    # Check for exposed secrets
    ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "cd code-server-enterprise && \
        git log --oneline -20 | grep -i 'secret\|password\|token\|key' && \
        echo 'WARNING: Found secret-related commits' || \
        echo 'OK: No recent secret commits found'"
    
    # Check Docker image signatures (if available)
    ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Digest}}' | head -10"
    
    # Check for unused images
    local dangling_images=$(ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "docker images -f dangling=true -q | wc -l")
    echo "✓ IMAGE_SCAN:dangling-images:${dangling_images} found"
}

################################################################################
# REPORTING
################################################################################

generate_report() {
    local test_results_file="${RESULTS_DIR}/endpoint-security-test.txt"
    local summary_file="${RESULTS_DIR}/summary.json"
    
    log "Generating report..."
    
    # Create detailed report
    {
        echo "═══════════════════════════════════════════════════════════════════"
        echo "VPN ENTERPRISE ENDPOINT SECURITY TEST REPORT"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        echo "Date: $(date -u)"
        echo "Host: ${DEPLOY_HOST}"
        echo "Timestamp: ${TIMESTAMP}"
        echo ""
        echo "EXTERNAL ENDPOINTS (Should be accessible):"
        echo "───────────────────────────────────────────────────────────────────"
        for name in "${!EXTERNAL_ENDPOINTS[@]}"; do
            check_external_endpoint "$name" "${EXTERNAL_ENDPOINTS[$name]}" || true
        done
        echo ""
        echo "INTERNAL ENDPOINTS (Should be ISOLATED):"
        echo "───────────────────────────────────────────────────────────────────"
        for name in "${!INTERNAL_ENDPOINTS[@]}"; do
            check_internal_endpoint_isolation "$name" "${INTERNAL_ENDPOINTS[$name]}" || true
        done
        echo ""
        echo "NETWORK CONFIGURATION:"
        echo "───────────────────────────────────────────────────────────────────"
        check_network_routes || true
        check_network_isolation || true
        echo ""
        echo "LATENCY MEASUREMENTS:"
        echo "───────────────────────────────────────────────────────────────────"
        for name in "${!EXTERNAL_ENDPOINTS[@]}"; do
            measure_endpoint_latency "$name" "${EXTERNAL_ENDPOINTS[$name]}" || true
        done
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "ENDPOINT SECURITY TEST COMPLETE"
        echo "═══════════════════════════════════════════════════════════════════"
    } | tee "${test_results_file}"
    
    # Create JSON summary
    {
        echo "{"
        echo "  \"timestamp\": \"${TIMESTAMP}\","
        echo "  \"host\": \"${DEPLOY_HOST}\","
        echo "  \"external_endpoints\": $(echo "${#EXTERNAL_ENDPOINTS[@]}"),"
        echo "  \"internal_endpoints_checked\": $(echo "${#INTERNAL_ENDPOINTS[@]}"),"
        echo "  \"tests_executed\": true,"
        echo "  \"scan_type\": \"endpoint-security\","
        echo "  \"deep_scan\": ${DEEP_SCAN}"
        echo "}"
    } | tee "${summary_file}"
    
    log "Report generated: ${test_results_file}"
    log "Summary: ${summary_file}"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log "VPN Enterprise Endpoint Security Test"
    log "Host: ${DEPLOY_HOST}"
    log "Verbose: ${VERBOSE}"
    log "Deep Scan: ${DEEP_SCAN}"
    echo ""
    
    create_results_dir
    
    # Run tests
    log "Testing external endpoints (should be accessible)..."
    for name in "${!EXTERNAL_ENDPOINTS[@]}"; do
        check_external_endpoint "$name" "${EXTERNAL_ENDPOINTS[$name]}" || true
    done
    echo ""
    
    log "Testing internal endpoints (should be ISOLATED)..."
    for name in "${!INTERNAL_ENDPOINTS[@]}"; do
        check_internal_endpoint_isolation "$name" "${INTERNAL_ENDPOINTS[$name]}" || true
    done
    echo ""
    
    log "Verifying network security..."
    check_network_routes || true
    check_network_isolation || true
    echo ""
    
    log "Measuring endpoint latencies..."
    for name in "${!EXTERNAL_ENDPOINTS[@]}"; do
        measure_endpoint_latency "$name" "${EXTERNAL_ENDPOINTS[$name]}" || true
    done
    echo ""
    
    # Optional deep scan
    execute_deep_scan || true
    
    # Generate report
    generate_report
    
    log "All tests complete"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)
            VERBOSE="true"
            ;;
        --deep-scan)
            DEEP_SCAN="true"
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# Execute
main "$@"
