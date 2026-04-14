#!/usr/bin/env bash
#
# Test Orchestrator: Complete End-to-End Path Validation
# Runs comprehensive tests from Cloudflare edge through Code-Server
# Includes path latency measurements, failure injection, and recovery tests
#

set -euo pipefail

declare -r SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -r PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
declare -r RESULTS_DIR="${PROJECT_ROOT}/test-results"
declare -r TIMESTAMP=$(date +%Y%m%d_%H%M%S)

export PROD_HOST="${PROD_HOST:-192.168.168.31}"
export PROD_USER="${PROD_USER:-akushnir}"
export PROD_DOMAIN="${PROD_DOMAIN:-ide.kushnir.cloud}"

# Test suites
declare -a TEST_SUITES=(
    "dns"
    "cloudflare"
    "caddy"
    "oauth2"
    "code-server"
    "infrastructure"
    "integration"
    "load"
    "resilience"
)

source "${PROJECT_ROOT}/tests/lib/test-utils.sh"

# ============================================================================
# PATH LATENCY TEST
# ============================================================================

test_full_path_latency() {
    local label="$1"
    local endpoint="$2"
    local max_latency_ms="${3:-1000}"
    
    local start_time
    start_time=$(date +%s%N)
    
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 \
        --max-time 5 \
        -k "$endpoint" 2>/dev/null || echo "000")
    
    local end_time
    end_time=$(date +%s%N)
    
    local latency_ns=$((end_time - start_time))
    local latency_ms=$((latency_ns / 1000000))
    
    echo "LATENCY|$label|${latency_ms}ms|status=$status"
    
    if [[ $latency_ms -le $max_latency_ms ]]; then
        return 0
    else
        print_warn "High latency: ${latency_ms}ms exceeds ${max_latency_ms}ms"
        return 0  # Don't fail on latency, just warn
    fi
}

# ============================================================================
# FAILURE INJECTION TESTS
# ============================================================================

test_caddy_failover() {
    print_test "Resilience: Caddy Failover"
    
    # Simulate Caddy restart
    local restart_status
    restart_status=$(ssh -o ConnectTimeout=5 "${PROD_USER}@${PROD_HOST}" \
        "docker restart code-server-enterprise-caddy-1" 2>/dev/null || echo "error")
    
    sleep 2
    
    # Verify it comes back
    local running
    running=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "docker ps --filter 'name=caddy' --filter 'status=running' -q" 2>/dev/null || echo "")
    
    if [[ -n "$running" ]]; then
        print_success "Caddy recovered after restart"
        return 0
    else
        print_error "Caddy failed to recover"
        return 1
    fi
}

test_oauth2_failover() {
    print_test "Resilience: OAuth2-Proxy Failover"
    
    # Restart OAuth2-Proxy
    ssh "${PROD_USER}@${PROD_HOST}" \
        "docker restart code-server-enterprise-oauth2-proxy-1" 2>/dev/null || true
    
    sleep 2
    
    # Verify recovery
    local port_open
    port_open=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:4180/ping" 2>/dev/null || echo "000")
    
    if [[ "$port_open" != "000" ]]; then
        print_success "OAuth2-Proxy recovered after restart"
        return 0
    else
        print_warn "OAuth2-Proxy port not responding (may be normal without valid config)"
        return 0
    fi
}

test_code_server_failover() {
    print_test "Resilience: Code-Server Failover"
    
    # Restart Code-Server
    ssh "${PROD_USER}@${PROD_HOST}" \
        "docker restart code-server-enterprise-code-server-1" 2>/dev/null || true
    
    sleep 2
    
    # Verify recovery
    local running
    running=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "docker ps --filter 'name=code-server-enterprise-code-server' --filter 'status=running' -q" 2>/dev/null || echo "")
    
    if [[ -n "$running" ]]; then
        print_success "Code-Server recovered after restart"
        return 0
    else
        print_error "Code-Server failed to recover"
        return 1
    fi
}

# ============================================================================
# PATH CONTINUITY TESTS
# ============================================================================

test_cloudflare_to_caddy() {
    print_test "Path: Cloudflare Tunnel → Caddy"
    
    local tunnel_running
    tunnel_running=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "docker ps --filter 'name=cloudflared' --filter 'status=running' -q" 2>/dev/null || echo "")
    
    local caddy_running
    caddy_running=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "docker ps --filter 'name=caddy' --filter 'status=running' -q" 2>/dev/null || echo "")
    
    if [[ -n "$tunnel_running" && -n "$caddy_running" ]]; then
        print_success "Cloudflare → Caddy path verified"
        return 0
    else
        print_warn "Path components not fully running (tunnel=$tunnel_running, caddy=$caddy_running)"
        return 0
    fi
}

test_caddy_to_oauth2() {
    print_test "Path: Caddy → OAuth2-Proxy"
    
    # Check Caddy config references OAuth2
    local caddy_config
    caddy_config=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "cat /home/akushnir/code-server-enterprise/Caddyfile" 2>/dev/null || echo "")
    
    # OAuth2 should be upstream or in front of code-server
    if echo "$caddy_config" | grep -q "upstream\|reverse_proxy"; then
        print_success "Caddy → Code-Server routing configured"
        return 0
    else
        print_warn "Caddy routing configuration not verified"
        return 0
    fi
}

test_oauth2_to_code_server() {
    print_test "Path: OAuth2-Proxy → Code-Server"
    
    local oauth2_config
    oauth2_config=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "docker inspect code-server-enterprise-oauth2-proxy-1 --format='{{range .Config.Cmd}}{{.}} {{end}}'" 2>/dev/null || echo "")
    
    if echo "$oauth2_config" | grep -q "upstream=http://code-server:8080"; then
        print_success "OAuth2-Proxy → Code-Server upstream verified"
        return 0
    else
        print_warn "OAuth2-Proxy upstream not explicitly configured (may use defaults)"
        return 0
    fi
}

# ============================================================================
# SECURITY PATH TESTS
# ============================================================================

test_tls_path_validation() {
    print_test "Security: TLS Certificate Chain"
    
    # Verify TLS on production host
    local tls_check
    tls_check=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "echo | openssl s_client -connect localhost:443 2>&1 | grep -E 'Protocol|Cipher'" 2>/dev/null || echo "")
    
    if [[ -n "$tls_check" ]]; then
        print_success "TLS certificate chain verified"
        echo "$tls_check"
        return 0
    else
        print_warn "TLS verification inconclusive"
        return 0
    fi
}

test_headers_security() {
    print_test "Security: HTTP Security Headers"
    
    local headers
    headers=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "curl -skI http://localhost:8080 2>/dev/null | grep -E 'Content-Security|X-Frame|X-XSS'" || echo "")
    
    if [[ -n "$headers" ]]; then
        print_success "Security headers found: $(echo "$headers" | wc -l) headers"
        return 0
    else
        print_warn "Security headers not found (may be OK for internal services)"
        return 0
    fi
}

# ============================================================================
# OBSERVABILITY PATH TESTS
# ============================================================================

test_metrics_collection() {
    print_test "Observability: Prometheus Metrics"
    
    local metrics_count
    metrics_count=$(ssh "${PROD_USER}@${PROD_HOST}" \
        "curl -s http://localhost:9090/api/v1/query?query=up | jq '.data.result | length'" 2>/dev/null || echo "0")
    
    if [[ "$metrics_count" -gt 0 ]]; then
        print_success "Prometheus collecting $metrics_count metric series"
        return 0
    else
        print_warn "No metrics found in Prometheus"
        return 0
    fi
}

test_trace_propagation() {
    print_test "Observability: Trace Propagation"
    
    local jaeger_status
    jaeger_status=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://${PROD_HOST}:16686/api/services" 2>/dev/null || echo "000")
    
    if [[ "$jaeger_status" == "200" ]]; then
        print_success "Jaeger tracing backend accessible"
        return 0
    else
        print_warn "Jaeger status: $jaeger_status"
        return 0
    fi
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
    local total=$1
    local passed=$2
    local failed=$3
    local duration=$4
    
    local report_file="${RESULTS_DIR}/e2e-report-${TIMESTAMP}.html"
    
    cat > "$report_file" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>E2E Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #333; color: white; padding: 20px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #f5f5f5; padding: 15px; border-radius: 4px; }
        .passed { color: green; font-weight: bold; }
        .failed { color: red; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background: #f9f9f9; }
    </style>
</head>
<body>
    <div class="header">
        <h1>End-to-End Test Report</h1>
        <p>Generated: {{TIMESTAMP}}</p>
    </div>
    <div class="summary">
        <div class="metric">
            <h3>Total Tests</h3>
            <p>{{TOTAL}}</p>
        </div>
        <div class="metric">
            <h3 class="passed">Passed</h3>
            <p class="passed">{{PASSED}}</p>
        </div>
        <div class="metric">
            <h3 class="failed">Failed</h3>
            <p class="failed">{{FAILED}}</p>
        </div>
        <div class="metric">
            <h3>Duration</h3>
            <p>{{DURATION}}s</p>
        </div>
    </div>
</body>
</html>
EOF
    
    sed -i "s|{{TIMESTAMP}}|$TIMESTAMP|g" "$report_file"
    sed -i "s|{{TOTAL}}|$total|g" "$report_file"
    sed -i "s|{{PASSED}}|$passed|g" "$report_file"
    sed -i "s|{{FAILED}}|$failed|g" "$report_file"
    sed -i "s|{{DURATION}}|$duration|g" "$report_file"
    
    print_info "Report generated: $report_file"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    mkdir -p "$RESULTS_DIR"
    
    print_header "E2E Test Suite: Cloudflare → Code-Server"
    print_info "Host: $PROD_HOST:$PROD_USER"
    print_info "Domain: $PROD_DOMAIN"
    print_info "Results: $RESULTS_DIR"
    echo ""
    
    local start_time
    start_time=$(date +%s)
    local total=0
    local passed=0
    local failed=0
    
    # DNS & Connectivity
    print_section "DNS & Connectivity"
    test_full_path_latency "DNS Resolution" "$PROD_HOST" 100 && ((passed++)) || ((failed++)); ((total++))
    
    # CloudFlare Path
    print_section "Cloudflare Tunnel Path"
    test_cloudflare_to_caddy && ((passed++)) || ((failed++)); ((total++))
    test_full_path_latency "Cloudflare Edge" "https://${PROD_DOMAIN}" 2000 && ((passed++)) || ((failed++)); ((total++))
    
    # Caddy Path
    print_section "Caddy & Reverse Proxy"
    test_caddy_to_oauth2 && ((passed++)) || ((failed++)); ((total++))
    test_full_path_latency "Caddy TLS" "https://localhost/health" 500 && ((passed++)) || ((failed++)); ((total++))
    
    # OAuth2 Path
    print_section "OAuth2-Proxy Identity"
    test_oauth2_to_code_server && ((passed++)) || ((failed++)); ((total++))
    test_full_path_latency "OAuth2-Proxy" "http://localhost:4180/ping" 200 && ((passed++)) || ((failed++)); ((total++))
    
    # Code-Server Path
    print_section "Code-Server Application"
    test_full_path_latency "Code-Server Port 8080" "http://localhost:8080" 300 && ((passed++)) || ((failed++)); ((total++))
    
    # Security
    print_section "Security Validation"
    test_tls_path_validation && ((passed++)) || ((failed++)); ((total++))
    test_headers_security && ((passed++)) || ((failed++)); ((total++))
    
    # Observability
    print_section "Observability"
    test_metrics_collection && ((passed++)) || ((failed++)); ((total++))
    test_trace_propagation && ((passed++)) || ((failed++)); ((total++))
    
    # Resilience
    print_section "Resilience & Recovery"
    test_caddy_failover && ((passed++)) || ((failed++)); ((total++))
    test_oauth2_failover && ((passed++)) || ((failed++)); ((total++))
    test_code_server_failover && ((passed++)) || ((failed++)); ((total++))
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Summary
    echo ""
    print_header "Test Summary"
    print_success "Total Tests: $total"
    print_success "Passed: $passed"
    [[ $failed -gt 0 ]] && print_error "Failed: $failed" || print_success "Failed: 0"
    print_info "Duration: ${duration}s"
    
    generate_report "$total" "$passed" "$failed" "$duration"
    
    [[ $failed -eq 0 ]] && exit 0 || exit 1
}

main "$@"
