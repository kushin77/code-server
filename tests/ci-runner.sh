#!/usr/bin/env bash
#
# CI/CD Test Runner: GitHub Actions Integration
# Runs complete end-to-end test suite with CI-friendly formatting
#
# Environment variables (from GitHub Actions):
#   - CI: Set to "true" by GitHub Actions
#   - GITHUB_RUN_ID: Test run identifier
#   - GITHUB_SHA: Commit SHA
#   - PROD_HOST: Production host (default: 192.168.168.31)
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly RESULTS_DIR="${PROJECT_ROOT}/test-results"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# CI environment detection
readonly IS_CI="${CI:-false}"
readonly CI_RUN_ID="${GITHUB_RUN_ID:-local-run}"
readonly CI_COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'unknown')}"

# Production configuration
export PROD_HOST="${PROD_HOST:-192.168.168.31}"
export PROD_USER="${PROD_USER:-akushnir}"
export PROD_DOMAIN="${PROD_DOMAIN:-ide.kushnir.cloud}"

source "${PROJECT_ROOT}/tests/lib/test-utils.sh"

# ============================================================================
# CI LOGGING HELPERS
# ============================================================================

ci_group_start() {
    if [[ "$IS_CI" == "true" ]]; then
        echo "::group::$1"
    else
        print_header "$1"
    fi
}

ci_group_end() {
    if [[ "$IS_CI" == "true" ]]; then
        echo "::endgroup::"
    fi
}

ci_error() {
    if [[ "$IS_CI" == "true" ]]; then
        echo "::error::$1"
    else
        print_error "$1"
    fi
}

ci_warning() {
    if [[ "$IS_CI" == "true" ]]; then
        echo "::warning::$1"
    else
        print_warn "$1"
    fi
}

ci_notice() {
    if [[ "$IS_CI" == "true" ]]; then
        echo "::notice::$1"
    else
        print_info "$1"
    fi
}

ci_set_output() {
    if [[ "$IS_CI" == "true" ]]; then
        echo "$1=$2" >> "$GITHUB_OUTPUT"
    fi
}

# ============================================================================
# TEST SUITE: LAYER 1 - DNS & CONNECTIVITY
# ============================================================================

run_layer_1_dns() {
    ci_group_start "Layer 1: DNS & Connectivity"
    
    ci_notice "Testing DNS resolution for $PROD_DOMAIN"
    
    if getent hosts "$PROD_DOMAIN" &>/dev/null; then
        local ip
        ip=$(getent hosts "$PROD_DOMAIN" | awk '{print $1}')
        print_success "DNS → $ip"
    else
        ci_warning "DNS resolution failed (expected for on-prem)"
    fi
    
    ci_notice "Testing SSH connectivity to $PROD_HOST"
    if ssh -o ConnectTimeout=5 "${PROD_USER}@${PROD_HOST}" "echo ok" &>/dev/null; then
        print_success "SSH connectivity verified"
    else
        ci_error "Cannot reach production host"
        return 1
    fi
    
    ci_group_end
    return 0
}

# ============================================================================
# TEST SUITE: LAYER 2 - CLOUDFLARE TUNNEL
# ============================================================================

run_layer_2_cloudflare() {
    ci_group_start "Layer 2: Cloudflare Tunnel"
    
    ci_notice "Checking cloudflared container status"
    
    local tunnel_status
    tunnel_status=$(ssh_docker_inspect "cloudflared" "{{.State.Status}}")
    
    if [[ "$tunnel_status" == "running" ]]; then
        print_success "Cloudflare tunnel container running"
    else
        ci_warning "Cloudflare tunnel not running: $tunnel_status"
    fi
    
    ci_notice "Checking tunnel configuration"
    
    local tunnel_logs
    tunnel_logs=$(ssh_exec "docker logs code-server-enterprise-cloudflared-1 --tail 5" 2>/dev/null || echo "")
    
    if echo "$tunnel_logs" | grep -iq "token\|registered"; then
        print_success "Tunnel configuration detected"
    else
        ci_notice "Tunnel logs inconclusive (may be placeholder mode)"
    fi
    
    ci_group_end
    return 0
}

# ============================================================================
# TEST SUITE: LAYER 3 - CADDY (TLS/WAF)
# ============================================================================

run_layer_3_caddy() {
    ci_group_start "Layer 3: Caddy (TLS & WAF)"
    
    ci_notice "Checking Caddy container status"
    
    local caddy_status
    caddy_status=$(ssh_docker_inspect "caddy" "{{.State.Status}}")
    
    if [[ "$caddy_status" == "running" ]]; then
        print_success "Caddy container running"
    else
        ci_error "Caddy container not running: $caddy_status"
        ci_group_end
        return 1
    fi
    
    ci_notice "Verifying Caddyfile configuration"
    
    local caddy_config
    caddy_config=$(ssh_exec "cat /home/akushnir/code-server-enterprise/Caddyfile")
    
    [[ -n "$caddy_config" ]] && print_success "Caddyfile readable"
    
    if echo "$caddy_config" | grep -q "reverse_proxy"; then
        print_success "Reverse proxy configured"
    fi
    
    if echo "$caddy_config" | grep -q "tls internal"; then
        print_success "Internal TLS configured"
    fi
    
    ci_notice "Testing TLS endpoint"
    
    local tlstest
    tlstest=$(ssh_exec "echo | openssl s_client -connect localhost:443 2>&1 | grep -i 'protocol\|cipher' | head -1")
    if [[ -n "$tlstest" ]]; then
        print_success "TLS: $tlstest"
    fi
    
    ci_group_end
    return 0
}

# ============================================================================
# TEST SUITE: LAYER 4 - OAUTH2-PROXY (IDENTITY)
# ============================================================================

run_layer_4_oauth2() {
    ci_group_start "Layer 4: OAuth2-Proxy (Identity)"
    
    ci_notice "Checking OAuth2-Proxy container status"
    
    local oauth2_status
    oauth2_status=$(ssh_docker_inspect "oauth2-proxy" "{{.State.Status}}")
    
    if [[ "$oauth2_status" == "running" ]]; then
        print_success "OAuth2-Proxy container running"
    else
        ci_error "OAuth2-Proxy container not running: $oauth2_status"
        ci_group_end
        return 1
    fi
    
    ci_notice "Verifying OAuth2-Proxy configuration"
    
    local oauth2_cmd
    oauth2_cmd=$(ssh_exec "docker inspect code-server-enterprise-oauth2-proxy-1 --format='{{range .Config.Cmd}}{{.}} {{end}}'")
    
    if echo "$oauth2_cmd" | grep -q "upstream=http://code-server:8080"; then
        print_success "Upstream configured: code-server:8080"
    fi
    
    if echo "$oauth2_cmd" | grep -q "http-address=0.0.0.0:4180"; then
        print_success "Listen address: 0.0.0.0:4180"
    fi
    
    ci_notice "Testing OAuth2 endpoint"
    
    local oauth2_resp
    oauth2_resp=$(ssh_exec "curl -s -o /dev/null -w '%{http_code}' http://localhost:4180/ping 2>/dev/null || echo '000'")
    print_info "OAuth2 port response: $oauth2_resp"
    
    ci_group_end
    return 0
}

# ============================================================================
# TEST SUITE: LAYER 5 - CODE-SERVER (IDE)
# ============================================================================

run_layer_5_code_server() {
    ci_group_start "Layer 5: Code-Server (IDE)"
    
    ci_notice "Checking Code-Server container status"
    
    local cs_status
    cs_status=$(ssh_docker_inspect "code-server" "{{.State.Status}}")
    
    if [[ "$cs_status" == "running" ]]; then
        print_success "Code-Server container running"
    else
        ci_error "Code-Server container not running: $cs_status"
        ci_group_end
        return 1
    fi
    
    ci_notice "Testing Code-Server port 8080"
    
    local cs_response
    cs_response=$(ssh_exec "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 2>/dev/null || echo '000'")
    
    if [[ "$cs_response" != "000" ]]; then
        print_success "Code-Server responding on 8080 (status: $cs_response)"
    else
        ci_warning "Code-Server port not responding"
    fi
    
    ci_notice "Checking Code-Server health endpoint"
    
    local health
    health=$(ssh_exec "curl -s http://localhost:8080/health 2>/dev/null | head -1")
    if [[ -n "$health" ]]; then
        print_success "Health endpoint: $(echo "$health" | head -c 50)..."
    fi
    
    ci_group_end
    return 0
}

# ============================================================================
# TEST SUITE: LAYER 6 - INFRASTRUCTURE
# ============================================================================

run_layer_6_infrastructure() {
    ci_group_start "Layer 6: Infrastructure (Observability)"
    
    ci_notice "Checking PostgreSQL"
    local pg_status
    pg_status=$(ssh_docker_inspect "postgres" "{{.State.Status}}")
    [[ "$pg_status" == "running" ]] && print_success "PostgreSQL running" || ci_warning "PostgreSQL: $pg_status"
    
    ci_notice "Checking Redis"
    local redis_status
    redis_status=$(ssh_docker_inspect "redis" "{{.State.Status}}")
    [[ "$redis_status" == "running" ]] && print_success "Redis running" || ci_warning "Redis: $redis_status"
    
    ci_notice "Checking Prometheus"
    local prom_status
    prom_status=$(ssh_docker_inspect "prometheus" "{{.State.Status}}")
    [[ "$prom_status" == "running" ]] && print_success "Prometheus running" || ci_warning "Prometheus: $prom_status"
    
    ci_notice "Checking Grafana"
    local grafana_status
    grafana_status=$(ssh_docker_inspect "grafana" "{{.State.Status}}")
    [[ "$grafana_status" == "running" ]] && print_success "Grafana running" || ci_warning "Grafana: $grafana_status"
    
    ci_notice "Checking Jaeger"
    local jaeger_status
    jaeger_status=$(ssh_docker_inspect "jaeger" "{{.State.Status}}")
    [[ "$jaeger_status" == "running" ]] && print_success "Jaeger running" || ci_warning "Jaeger: $jaeger_status"
    
    ci_group_end
    return 0
}

# ============================================================================
# TEST SUITE: INTEGRATION TESTS
# ============================================================================

run_integration_tests() {
    ci_group_start "Integration Tests"
    
    ci_notice "Verifying Docker network"
    
    local network
    network=$(ssh_exec "docker network ls --format='{{.Name}}' | grep enterprise")
    if [[ -n "$network" ]]; then
        print_success "Docker network 'enterprise' exists"
    else
        ci_error "Docker network 'enterprise' not found"
        ci_group_end
        return 1
    fi
    
    ci_notice "Counting running services"
    
    local running_count
    running_count=$(ssh_exec "docker ps --format '{{.Names}}' | grep code-server-enterprise | wc -l")
    print_info "Running services: $running_count"
    
    if [[ $running_count -ge 10 ]]; then
        print_success "Minimum service count met ($running_count >= 10)"
    else
        ci_warning "Low service count: $running_count (expected >= 10)"
    fi
    
    ci_group_end
    return 0
}

# ============================================================================
# TEST SUITE: PATH LATENCY
# ============================================================================

run_path_latency_tests() {
    ci_group_start "Path Latency Tests"
    
    ci_notice "Measuring Code-Server latency"
    local cs_latency
    cs_latency=$(measure_latency "http://${PROD_HOST}:8080" 3)
    print_info "Code-Server: ${cs_latency}ms avg"
    
    ci_notice "Measuring Prometheus latency"
    local prom_latency
    prom_latency=$(measure_latency "http://${PROD_HOST}:9090" 3)
    print_info "Prometheus: ${prom_latency}ms avg"
    
    ci_notice "Measuring Grafana latency"
    local grafana_latency
    grafana_latency=$(measure_latency "http://${PROD_HOST}:3000" 3)
    print_info "Grafana: ${grafana_latency}ms avg"
    
    ci_group_end
    return 0
}

# ============================================================================
# FINAL REPORT
# ============================================================================

generate_ci_summary() {
    local total_passed=$1
    local total_failed=$2
    
    local summary_file="${RESULTS_DIR}/ci-summary.md"
    
    cat > "$summary_file" <<EOF
# E2E Test Summary

**Run ID**: ${CI_RUN_ID}  
**Commit**: ${CI_COMMIT:0:7}  
**Timestamp**: ${TIMESTAMP}  
**Host**: ${PROD_HOST}  
**Domain**: ${PROD_DOMAIN}  

## Results
- ✅ Passed: $total_passed
- ❌ Failed: $total_failed
- 📊 Success Rate: $((total_passed * 100 / (total_passed + total_failed)))%

## Test Layers
- [x] Layer 1: DNS & Connectivity
- [x] Layer 2: Cloudflare Tunnel
- [x] Layer 3: Caddy (TLS/WAF)
- [x] Layer 4: OAuth2-Proxy (Identity)
- [x] Layer 5: Code-Server (IDE)
- [x] Layer 6: Infrastructure
- [x] Integration Tests
- [x] Path Latency Tests

## Environment
- Production Host: ${PROD_HOST}
- SSH User: ${PROD_USER}
- Domain: ${PROD_DOMAIN}
- Run Environment: $([ "$IS_CI" == "true" ] && echo "GitHub Actions" || echo "Local")

---
$(date)
EOF
    
    cat "$summary_file"
    ci_set_output "test-summary" "$summary_file"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    mkdir -p "$RESULTS_DIR"
    
    print_header "CI/CD Test Runner: Cloudflare → Code-Server"
    
    ci_notice "Run ID: $CI_RUN_ID"
    ci_notice "Commit: $CI_COMMIT"
    ci_notice "Host: $PROD_HOST"
    
    local total_tests=0
    local passed=0
    local failed=0
    
    # Execute all test layers
    if run_layer_1_dns; then ((passed++)); else ((failed++)); fi; ((total_tests++))
    
    if run_layer_2_cloudflare; then ((passed++)); else ((failed++)); fi; ((total_tests++))
    
    if run_layer_3_caddy; then ((passed++)); else ((failed++)); fi; ((total_tests++))
    
    if run_layer_4_oauth2; then ((passed++)); else ((failed++)); fi; ((total_tests++))
    
    if run_layer_5_code_server; then ((passed++)); else ((failed++)); fi; ((total_tests++))
    
    if run_layer_6_infrastructure; then ((passed++)); else ((failed++)); fi; ((total_tests++))
    
    if run_integration_tests; then ((passed++)); else ((failed++)); fi; ((total_tests++))
    
    if run_path_latency_tests; then ((passed++)); else ((failed++)); fi; ((total_tests++))
    
    # Generate summary
    echo ""
    print_header "Test Execution Complete"
    
    ci_notice "Tests passed: $passed/$total_tests"
    [[ $failed -gt 0 ]] && ci_error "Tests failed: $failed" || ci_notice "All tests passed!"
    
    generate_ci_summary "$passed" "$total_tests"
    
    # Exit with appropriate code
    [[ $failed -eq 0 ]] && exit 0 || exit 1
}

main "$@"
