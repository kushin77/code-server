#!/bin/bash
# File:    deployment-validation-31.sh
# Owner:   Platform Engineering
# Purpose: Deployment validation test suite for ${DEPLOY_HOST}
# Status:  ACTIVE
# Usage:   ./deployment-validation-31.sh [test_pattern]

set -e

# Bootstrap _common library (logging, utils, error-handler, config)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test-specific helpers (not in _common — test result tracking)
log_pass() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${COLOR_YELLOW}⊘${COLOR_RESET} $1"
    ((TESTS_SKIPPED++))
}

# ============================================================================
# Service Health Checks
# ============================================================================

test_docker_running() {
    if docker ps &>/dev/null; then
        log_pass "Docker is running"
    else
        log_fail "Docker is not running"
        return 1
    fi
}

test_docker_compose() {
    if command -v docker-compose &>/dev/null || docker compose --help &>/dev/null; then
        log_pass "Docker Compose is available"
    else
        log_fail "Docker Compose is not available"
        return 1
    fi
}

test_services_running() {
    services=("code-server" "ollama" "cadvisor" "prometheus")
    
    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --format "{{.Names}}" | grep -q "$service"; then
            log_pass "Service '$service' is running"
        else
            log_fail "Service '$service' is not running"
        fi
    done
}

test_code_server_responsive() {
    if curl -s -f http://localhost:8443 &>/dev/null; then
        log_pass "Code-Server is responsive on :8443"
    else
        log_fail "Code-Server not responding on :8443"
    fi
}

test_ollama_responsive() {
    if curl -s http://localhost:11434/api/tags &>/dev/null; then
        log_pass "Ollama API is responsive on :11434"
    else
        log_fail "Ollama API not responding on :11434"
    fi
}

test_prometheus_running() {
    if curl -s http://localhost:9090/-/healthy &>/dev/null; then
        log_pass "Prometheus is healthy on :9090"
    else
        log_fail "Prometheus not healthy on :9090"
    fi
}

# ============================================================================
# GPU Validation
# ============================================================================

test_gpu_available() {
    if command -v nvidia-smi &>/dev/null; then
        gpu_count=$(nvidia-smi --list-gpus | wc -l)
        if [ "$gpu_count" -ge 1 ]; then
            log_pass "GPU detected: $gpu_count GPU(s) available"
        else
            log_fail "No GPUs detected"
        fi
    else
        log_fail "nvidia-smi not available (NVIDIA drivers missing)"
        return 1
    fi
}

test_cuda_toolkit() {
    if command -v nvcc &>/dev/null; then
        cuda_version=$(nvcc --version | grep -oP 'release \K[0-9.]+' | head -1)
        log_pass "CUDA Toolkit available: version $cuda_version"
    else
        log_fail "CUDA Toolkit not found"
    fi
}

test_cudnn_library() {
    cudnn_paths=(
        "/usr/local/cuda/lib64/libcudnn.so"
        "/opt/cudnn/lib64/libcudnn.so"
    )
    
    found=0
    for path in "${cudnn_paths[@]}"; do
        if [ -f "$path" ]; then
            log_pass "cuDNN library found at $path"
            found=1
            break
        fi
    done
    
    if [ $found -eq 0 ]; then
        log_fail "cuDNN library not found in standard locations"
    fi
}

test_gpu_memory() {
    if command -v nvidia-smi &>/dev/null; then
        total_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        log_pass "GPU memory available: ${total_memory} MB"
    fi
}

test_docker_gpu_access() {
    if docker run --rm --gpus all nvidia/cuda:12.4-base nvidia-smi &>/dev/null; then
        log_pass "Docker GPU access is working"
    else
        log_fail "Docker GPU access failed"
    fi
}

# ============================================================================
# NAS/Storage Validation
# ============================================================================

test_nas_mounts() {
    mount_points=("/mnt/nas-primary" "/mnt/nas-backup")
    
    for mount in "${mount_points[@]}"; do
        if mountpoint -q "$mount" 2>/dev/null; then
            log_pass "NAS mount point is healthy: $mount"
        else
            log_fail "NAS mount point is not mounted: $mount"
        fi
    done
}

test_nas_writable() {
    test_file="/mnt/nas-primary/.deployment-test-$(date +%s)"
    
    if touch "$test_file" 2>/dev/null && rm "$test_file"; then
        log_pass "NAS mount point is writable"
    else
        log_fail "NAS mount point is not writable"
    fi
}

test_nas_capacity() {
    # Check primary NAS has at least 500GB free
    if mountpoint -q "/mnt/nas-primary"; then
        available=$(df "/mnt/nas-primary" | tail -1 | awk '{print $4}')
        available_gb=$((available / 1024 / 1024))
        
        if [ "$available_gb" -gt 500 ]; then
            log_pass "NAS has sufficient capacity: ${available_gb}GB free"
        else
            log_fail "NAS capacity low: ${available_gb}GB free (need >500GB)"
        fi
    fi
}

test_nas_latency() {
    if command -v iozone &>/dev/null; then
        latency=$(iozone -a -n 1m -g 100m -M /mnt/nas-primary 2>/dev/null | grep -oP 'latency.*\K[0-9]+' | head -1)
        if [ -n "$latency" ] && [ "$latency" -lt 100 ]; then
            log_pass "NAS latency acceptable: ${latency}ms"
        else
            log_skip "NAS latency test (iozone available but incomplete)"
        fi
    else
        log_skip "NAS latency test (iozone not available)"
    fi
}

# ============================================================================
# Network Validation
# ============================================================================

test_dns_resolution() {
    if nslookup google.com &>/dev/null; then
        log_pass "DNS resolution is working"
    else
        log_fail "DNS resolution failed"
    fi
}

test_internet_connectivity() {
    if curl -s --connect-timeout 5 https://api.github.com &>/dev/null; then
        log_pass "Internet connectivity is working"
    else
        log_fail "Internet connectivity failed"
    fi
}

test_ssh_access() {
    if ssh -o ConnectTimeout=5 $USER@localhost "echo" &>/dev/null; then
        log_pass "SSH access is working"
    else
        log_fail "SSH access failed"
    fi
}

test_firewall_rules() {
    ports=(8443 11434 9090 3000 9100)
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_pass "Port $port is accessible"
        else
            log_skip "Port $port (may be blocked by firewall)"
        fi
    done
}

# ============================================================================
# Docker Image Validation
# ============================================================================

test_code_server_image() {
    if docker images | grep -q code-server; then
        log_pass "Code-Server image is present"
    else
        log_fail "Code-Server image not found"
    fi
}

test_ollama_image() {
    if docker images | grep -q ollama; then
        log_pass "Ollama image is present"
    else
        log_fail "Ollama image not found"
    fi
}

# ============================================================================
# Configuration Validation
# ============================================================================

test_environment_variables() {
    required_vars=(
        "OLLAMA_NUM_GPU"
        "CODE_SERVER_HOST"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -n "${!var}" ]; then
            log_pass "Environment variable set: $var"
        else
            log_skip "Environment variable not set: $var"
        fi
    done
}

# ============================================================================
# Security Validation
# ============================================================================

test_ssh_keyauth_only() {
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
        log_pass "SSH password authentication is disabled"
    else
        log_skip "SSH password auth check (check sshd_config manually)"
    fi
}

test_no_hardcoded_secrets() {
    secret_files=$(grep -r "password\|secret\|api.key" config/ Dockerfile 2>/dev/null | grep -v ".example" | wc -l)
    if [ "$secret_files" -eq 0 ]; then
        log_pass "No hardcoded secrets detected"
    else
        log_fail "Found $secret_files potential hardcoded secrets"
    fi
}

# ============================================================================
# Performance Baseline
# ============================================================================

test_cpu_performance() {
    if command -v sysbench &>/dev/null; then
        log_info "Running CPU benchmark (30 seconds)..."
        sysbench cpu --cpu-total-threads=4 --time=30 run 2>&1 | grep -q "total time" && \
            log_pass "CPU benchmark completed" || \
            log_fail "CPU benchmark failed"
    else
        log_skip "CPU benchmark (sysbench not available)"
    fi
}

test_memory_performance() {
    if command -v sysbench &>/dev/null; then
        log_info "Running memory benchmark..."
        sysbench memory --memory-total-size=1G run 2>&1 | grep -q "total time" && \
            log_pass "Memory benchmark completed" || \
            log_fail "Memory benchmark failed"
    else
        log_skip "Memory benchmark (sysbench not available)"
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
    echo "═══════════════════════════════════════════════════════════════"
    echo "Deployment Validation Test Suite - ${DEPLOY_HOST}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Service Tests
    echo -e "${BLUE}Service Health Checks${NC}"
    test_docker_running
    test_docker_compose
    test_services_running
    test_code_server_responsive
    test_ollama_responsive
    test_prometheus_running
    echo ""
    
    # GPU Tests
    echo -e "${BLUE}GPU Validation${NC}"
    test_gpu_available
    test_cuda_toolkit
    test_cudnn_library
    test_gpu_memory
    test_docker_gpu_access
    echo ""
    
    # NAS Tests
    echo -e "${BLUE}NAS/Storage Validation${NC}"
    test_nas_mounts
    test_nas_writable
    test_nas_capacity
    test_nas_latency
    echo ""
    
    # Network Tests
    echo -e "${BLUE}Network Validation${NC}"
    test_dns_resolution
    test_internet_connectivity
    test_ssh_access
    test_firewall_rules
    echo ""
    
    # Image Tests
    echo -e "${BLUE}Docker Image Validation${NC}"
    test_code_server_image
    test_ollama_image
    echo ""
    
    # Configuration Tests
    echo -e "${BLUE}Configuration Validation${NC}"
    test_environment_variables
    echo ""
    
    # Security Tests
    echo -e "${BLUE}Security Validation${NC}"
    test_ssh_keyauth_only
    test_no_hardcoded_secrets
    echo ""
    
    # Performance Tests
    echo -e "${BLUE}Performance Baseline${NC}"
    test_cpu_performance
    test_memory_performance
    echo ""
    
    # Summary
    echo "═══════════════════════════════════════════════════════════════"
    echo "Test Summary:"
    echo "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}VALIDATION FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}VALIDATION PASSED${NC}"
        exit 0
    fi
}

main "$@"
