#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# final-validation.sh - Elite Infrastructure Transformation Final Validation
# Comprehensive production readiness validation across all systems
# Execution: Run on 192.168.168.31 before marking as production-ready
# Exit Code: 0 = production-ready | 1 = blockers found
# ═════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Logging functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

section() {
    echo ""
    echo "═════════════════════════════════════════════════════════════════════════════"
    echo "$1"
    echo "═════════════════════════════════════════════════════════════════════════════"
}

# Validation functions

# 1. Docker Services Check
validate_docker_services() {
    section "Docker Services Validation"
    
    local services=(postgres redis code-server caddy oauth2-proxy prometheus grafana alertmanager jaeger ollama)
    
    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --format "{{.Names}}" | grep -q "$service"; then
            pass "Service running: $service"
        else
            fail "Service not running: $service"
        fi
    done
}

# 2. Health Endpoints Check
validate_health_endpoints() {
    section "Health Endpoints Validation"
    
    local endpoints=(
        "http://localhost:8080/health"
        "http://localhost:9090/-/healthy"
        "http://localhost:3000/api/health"
        "http://localhost:9093/-/healthy"
        "http://localhost:16686/search"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -sf "$endpoint" > /dev/null 2>&1; then
            pass "Health endpoint responsive: $endpoint"
        else
            warn "Health endpoint not responding: $endpoint"
        fi
    done
}

# 3. Database Connectivity Check
validate_database_connectivity() {
    section "Database Connectivity Validation"
    
    # PostgreSQL
    if pg_isready -h localhost -p 5432 -U codeserver > /dev/null 2>&1; then
        pass "PostgreSQL connectivity verified"
    else
        fail "PostgreSQL connection failed"
    fi
    
    # Redis
    if redis-cli -h localhost -p 6379 ping > /dev/null 2>&1; then
        pass "Redis connectivity verified"
    else
        fail "Redis connection failed"
    fi
}

# 4. NAS Mounts Check
validate_nas_mounts() {
    section "NAS Storage Validation"
    
    if mount | grep -q "/mnt/nas-56"; then
        pass "NAS mount /mnt/nas-56 is mounted"
        local size=$(df /mnt/nas-56 | tail -1 | awk '{print $2}')
        if [ "$size" -gt 1000000 ]; then
            pass "NAS available space: $(numfmt --to=iec "$((size * 1024))" 2>/dev/null || echo "$size KB")"
        else
            warn "NAS available space low: $(numfmt --to=iec "$((size * 1024))" 2>/dev/null || echo "$size KB")"
        fi
    else
        fail "NAS mount /mnt/nas-56 not found"
    fi
}

# 5. GPU Availability Check
validate_gpu_availability() {
    section "GPU Availability Validation"
    
    if command -v nvidia-smi &> /dev/null; then
        pass "NVIDIA drivers installed"
        
        local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
        pass "GPU count: $gpu_count"
        
        local device_1_memory=$(nvidia-smi --id=1 --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
        if [ "$device_1_memory" != "N/A" ]; then
            pass "GPU device 1 memory: ${device_1_memory}MB"
        else
            warn "GPU device 1 not available (check hardware)"
        fi
    else
        warn "NVIDIA drivers not installed (GPU disabled)"
    fi
}

# 6. Configuration Consolidation Check
validate_config_consolidation() {
    section "Configuration Consolidation Validation"
    
    if [ -f "docker-compose.yml" ]; then
        pass "Single docker-compose.yml exists"
    else
        fail "Main docker-compose.yml not found"
    fi
    
    if [ -f "Caddyfile" ]; then
        pass "Single Caddyfile exists"
    else
        fail "Main Caddyfile not found"
    fi
    
    if [ -f "terraform/locals.tf" ]; then
        pass "Terraform locals.tf (SSOT) exists"
    else
        fail "terraform/locals.tf not found"
    fi
    
    # Check for orphaned variants
    orphaned=$(find . -maxdepth 1 -name "docker-compose*.yml" ! -name "docker-compose.yml" 2>/dev/null | wc -l)
    if [ "$orphaned" -eq 0 ]; then
        pass "No orphaned docker-compose files"
    else
        warn "Found $orphaned orphaned docker-compose files"
    fi
}

# 7. Security Check
validate_security() {
    section "Security Configuration Validation"
    
    if [ -f "services/gsm_client.py" ]; then
        pass "GSM Python client present"
    else
        fail "GSM Python client not found"
    fi
    
    if [ -f "scripts/load-gsm-secrets.sh" ]; then
        pass "GSM bash loader present"
    else
        fail "GSM bash loader not found"
    fi
    
    # Check for hardcoded secrets
    local hardcoded=$(grep -r "password\|secret\|token" . \
        --include="*.yml" --include="*.yaml" --include="*.js" --include="*.py" \
        | grep -v "ENV\|VAR\|\${" \
        | grep -v ".archived\|.git\|node_modules" \
        | wc -l)
    
    if [ "$hardcoded" -eq 0 ]; then
        pass "No hardcoded secrets detected"
    else
        warn "Potential hardcoded secrets found: $hardcoded lines (review required)"
    fi
}

# 8. Monitoring and Alerting Check
validate_monitoring() {
    section "Monitoring and Alerting Validation"
    
    if [ -f "alert-rules.yml" ]; then
        pass "Alert rules configured"
    else
        fail "alert-rules.yml not found"
    fi
    
    if [ -f "alertmanager-production.yml" ]; then
        pass "AlertManager production config present"
    else
        fail "alertmanager-production.yml not found"
    fi
    
    # Check Prometheus targets
    if curl -sf http://localhost:9090/api/v1/targets | grep -q "caddy\|postgres\|redis" 2>/dev/null; then
        pass "Prometheus monitoring active"
    else
        warn "Prometheus targets may not be configured correctly"
    fi
}

# 9. Deployment Artifacts Check
validate_deployment_artifacts() {
    section "Deployment Artifacts Validation"
    
    # Check git status
    if [ "$(git status --porcelain | wc -l)" -eq 0 ]; then
        pass "Clean git working tree"
    else
        warn "Uncommitted changes present"
    fi
    
    # Check commit count
    local commits=$(git rev-list --count HEAD)
    if [ "$commits" -gt 100 ]; then
        pass "Sufficient commit history ($commits commits)"
    else
        warn "Limited commit history ($commits commits)"
    fi
    
    # Check for README
    if [ -f "README.md" ]; then
        pass "README.md present"
    else
        fail "README.md not found"
    fi
    
    # Check for deployment docs
    if [ -f "DEVELOPMENT-GUIDE.md" ] || [ -f "ARCHITECTURE.md" ]; then
        pass "Deployment documentation present"
    else
        warn "Deployment documentation may be incomplete"
    fi
}

# 10. Backup Validation
validate_backups() {
    section "Backup Validation"
    
    if [ -d "/backups/postgresql" ]; then
        local recent=$(find /backups/postgresql -maxdepth 1 -type f -mtime -1 2>/dev/null | wc -l)
        if [ "$recent" -gt 0 ]; then
            pass "Recent PostgreSQL backups found"
        else
            warn "No recent PostgreSQL backups (check backup job)"
        fi
    else
        warn "PostgreSQL backup directory not found"
    fi
}

# 11. Performance Check
validate_performance() {
    section "Performance Validation"
    
    # Check system resources
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if (( $(echo "$cpu_usage < 80" | bc -l) )); then
        pass "CPU usage acceptable: $cpu_usage%"
    else
        warn "CPU usage elevated: $cpu_usage%"
    fi
    
    local mem_usage=$(free | grep Mem | awk '{printf("%.0f", ($3/$2) * 100)}')
    if (( mem_usage < 80 )); then
        pass "Memory usage acceptable: $mem_usage%"
    else
        warn "Memory usage elevated: $mem_usage%"
    fi
}

# 12. SSL/TLS Check
validate_ssl_tls() {
    section "SSL/TLS Configuration Validation"
    
    if [ -f "Caddyfile" ] && grep -q "tls" Caddyfile; then
        pass "TLS configuration present"
    else
        warn "TLS configuration may be incomplete"
    fi
}

# Main execution
main() {
    echo ""
    echo "╔═════════════════════════════════════════════════════════════════════════════╗"
    echo "║          ELITE INFRASTRUCTURE TRANSFORMATION - FINAL VALIDATION              ║"
    echo "║                      Production Readiness Assessment                         ║"
    echo "╚═════════════════════════════════════════════════════════════════════════════╝"
    
    validate_docker_services
    validate_health_endpoints
    validate_database_connectivity
    validate_nas_mounts
    validate_gpu_availability
    validate_config_consolidation
    validate_security
    validate_monitoring
    validate_deployment_artifacts
    validate_backups
    validate_performance
    validate_ssl_tls
    
    # Summary
    echo ""
    section "VALIDATION SUMMARY"
    echo -e "  ${GREEN}Passed${NC}:   $PASSED"
    echo -e "  ${RED}Failed${NC}:   $FAILED"
    echo -e "  ${YELLOW}Warnings${NC}: $WARNINGS"
    echo ""
    
    if [ "$FAILED" -eq 0 ]; then
        echo -e "${GREEN}✓ PRODUCTION READINESS: GO${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ PRODUCTION READINESS: NO-GO${NC}"
        echo "Resolve failures above before proceeding to production."
        echo ""
        return 1
    fi
}

# Run validation
main "$@"
