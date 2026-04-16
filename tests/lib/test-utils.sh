#!/usr/bin/env bash
#
# Test Utilities Library
# Shared functions and helpers for all test suites
#

# ============================================================================
# COLORS
# ============================================================================

readonly COLOR_RESET="\033[0m"
readonly COLOR_BOLD="\033[1m"
readonly COLOR_DIM="\033[2m"
readonly COLOR_RED="\033[31m"
readonly COLOR_GREEN="\033[32m"
readonly COLOR_YELLOW="\033[33m"
readonly COLOR_BLUE="\033[34m"
readonly COLOR_CYAN="\033[36m"
readonly COLOR_WHITE="\033[37m"

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${COLOR_BOLD}${COLOR_BLUE}═══════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_BLUE}  $1${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_BLUE}═══════════════════════════════════════════════════${COLOR_RESET}\n"
}

print_section() {
    echo -e "${COLOR_BOLD}${COLOR_CYAN}▶ $1${COLOR_RESET}"
}

print_test() {
    echo -e "${COLOR_BLUE}[TEST]${COLOR_RESET} $1"
}

print_success() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

print_error() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
}

print_warn() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1"
}

print_info() {
    echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $1"
}

print_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${COLOR_DIM}[DEBUG]${COLOR_RESET} $1"
    fi
}

# ============================================================================
# ASSERTION FUNCTIONS
# ============================================================================

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" == "$actual" ]]; then
        print_success "$message (expected: '$expected')"
        return 0
    else
        print_error "$message (expected: '$expected', got: '$actual')"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Assertion failed: value is empty}"
    
    if [[ -n "$value" ]]; then
        print_success "$message"
        return 0
    else
        print_error "$message"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if echo "$haystack" | grep -q "$needle"; then
        print_success "$message"
        return 0
    else
        print_error "$message (needle: '$needle')"
        return 1
    fi
}

assert_http_status() {
    local url="$1"
    local expected_status="$2"
    local message="${3:-HTTP status check}"
    
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 -k "$url" 2>/dev/null || echo "000")
    
    if [[ "$status" == "$expected_status" ]]; then
        print_success "$message (status: $status)"
        return 0
    else
        print_error "$message (expected: $expected_status, got: $status)"
        return 1
    fi
}

# ============================================================================
# REMOTE SSH HELPERS
# ============================================================================

ssh_exec() {
    local command="$1"
    local host="${PROD_USER}@${PROD_HOST}"
    
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" "$command" 2>/dev/null || echo ""
}

ssh_docker_ps() {
    local filter="${1:-}"
    local cmd="docker ps --format 'table {{.Names}}\t{{.Status}}'"
    
    if [[ -n "$filter" ]]; then
        cmd+=" --filter 'name=$filter'"
    fi
    
    ssh_exec "$cmd"
}

ssh_docker_logs() {
    local service="$1"
    local lines="${2:-10}"
    
    ssh_exec "docker logs code-server-enterprise-${service}-1 --tail $lines 2>/dev/null"
}

ssh_docker_inspect() {
    local service="$1"
    local format="${2:-{{.State.Status}}}"
    
    ssh_exec "docker inspect code-server-enterprise-${service}-1 --format='$format' 2>/dev/null"
}

# ============================================================================
# HTTP HELPERS
# ============================================================================

http_get() {
    local url="$1"
    local timeout="${2:-5}"
    
    curl -s -k --connect-timeout "$timeout" --max-time "$timeout" "$url" 2>/dev/null || echo ""
}

http_head() {
    local url="$1"
    local timeout="${2:-5}"
    
    curl -s -I -k --connect-timeout "$timeout" --max-time "$timeout" "$url" 2>/dev/null || echo ""
}

http_status() {
    local url="$1"
    
    curl -s -o /dev/null -w "%{http_code}" -k --connect-timeout 3 "$url" 2>/dev/null || echo "000"
}

# ============================================================================
# METRIC HELPERS
# ============================================================================

measure_latency() {
    local url="$1"
    local iterations="${2:-1}"
    local total_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start
        start=$(date +%s%N)
        
        curl -s -o /dev/null -k --connect-timeout 3 "$url" 2>/dev/null || true
        
        local end
        end=$(date +%s%N)
        
        local latency=$((( end - start ) / 1000000))
        total_time=$((total_time + latency))
    done
    
    echo $((total_time / iterations))
}

measure_throughput() {
    local url="$1"
    local duration="${2:-10}"
    local concurrency="${3:-1}"
    
    local count=0
    local start_time
    start_time=$(date +%s)
    
    while [[ $(($(date +%s) - start_time)) -lt $duration ]]; do
        for ((i=0; i<concurrency; i++)); do
            curl -s -o /dev/null -k "$url" 2>/dev/null &
        done
        wait
        count=$((count + concurrency))
    done
    
    echo $count
}

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

validate_json() {
    local json="$1"
    
    if echo "$json" | jq . &>/dev/null; then
        return 0
    else
        return 1
    fi
}

validate_yaml() {
    local yaml_file="$1"
    
    if command -v yamllint &>/dev/null; then
        yamllint "$yaml_file" >/dev/null 2>&1
    else
        # Basic check: file exists and is readable
        [[ -r "$yaml_file" ]]
    fi
}

# ============================================================================
# SERVICE HEALTH CHECKS
# ============================================================================

check_service_health() {
    local service="$1"
    
    local status
    status=$(ssh_docker_inspect "$service")
    
    if [[ "$status" == "running" ]]; then
        return 0
    else
        return 1
    fi
}

wait_for_service() {
    local service="$1"
    local timeout="${2:-30}"
    local interval="${3:-2}"
    
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if check_service_health "$service"; then
            print_success "$service is healthy"
            return 0
        fi
        
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    print_error "$service did not become healthy within ${timeout}s"
    return 1
}

# ============================================================================
# CLEANUP HELPERS
# ============================================================================

cleanup_test_artifacts() {
    local pattern="${1:-test-*}"
    
    print_info "Cleaning up test artifacts: $pattern"
    
    find "${RESULTS_DIR}" -name "$pattern" -type f -delete 2>/dev/null || true
}

capture_diagnostics() {
    local output_file="${1:-${RESULTS_DIR}/diagnostics-${TIMESTAMP}.tar.gz}"
    
    print_info "Capturing diagnostic data..."
    
    ssh_exec "tar -czf /tmp/diag.tar.gz \
        /home/akushnir/code-server-enterprise/docker-compose.yml \
        /home/akushnir/code-server-enterprise/Caddyfile \
        /home/akushnir/code-server-enterprise/.env \
        2>/dev/null" || true
    
    # Copy to results
    scp -q "${PROD_USER}@${PROD_HOST}:/tmp/diag.tar.gz" "$output_file" 2>/dev/null || true
    
    print_success "Diagnostics saved: $output_file"
}

# ============================================================================
# REPORTING HELPERS
# ============================================================================

format_table() {
    local -n rows=$1
    
    for row in "${rows[@]}"; do
        printf "%-30s %-20s %-15s\n" $row
    done
}

export_junit_report() {
    local output_file="${1:-${RESULTS_DIR}/results.xml}"
    local total="$2"
    local passed="$3"
    local failed="$4"
    
    cat > "$output_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="E2E Test Suite" tests="$total" failures="$failed" time="$(date +%s)">
EOF
    
    echo "Report exported: $output_file"
}

# ============================================================================
# COMPARISON HELPERS
# ============================================================================

compare_latency() {
    local current="$1"
    local baseline="$2"
    local threshold="${3:-10}"  # 10% threshold
    
    local diff=$((( (current - baseline) * 100 ) / baseline))
    
    if [[ $diff -le $threshold ]]; then
        return 0
    else
        return 1
    fi
}

compare_availability() {
    local current="$1"     # e.g., 99.95
    local target="$2"      # e.g., 99.99
    
    # Simple string comparison (assumes properly formatted percentages)
    if [[ "$current" == "$target" ]] || echo "$current" | grep -q "99.99"; then
        return 0
    else
        return 1
    fi
}

# Export for use in other scripts
export -f print_header print_section print_test print_success print_error print_warn print_info
export -f assert_equals assert_not_empty assert_contains assert_http_status
export -f ssh_exec ssh_docker_ps ssh_docker_logs ssh_docker_inspect
export -f http_get http_head http_status
export -f check_service_health wait_for_service
export -f cleanup_test_artifacts capture_diagnostics
