#!/bin/bash
###############################################################################
# Security Testing Suite
# Issue #1537 Week 4-5: Chaos Engineering & Security Testing
#
# Purpose: Comprehensive security scanning including SAST, SCA, DAST, and secrets
# Tests: Static analysis, dependency scanning, secrets detection, container scanning
#
# Usage:
#   ./scripts/security/security-scan.sh
#   ./scripts/security/security-scan.sh --type sast
#   ./scripts/security/security-scan.sh --type sca --fail-on high
#
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

###############################################################################
# Note: logging functions provided by scripts/_common/init.sh
###############################################################################
# SAST: Static Application Security Testing
###############################################################################

run_sast() {
    log_info "Running Static Analysis (SAST)..."
    
    local issues=0
    
    # Python - Bandit
    if command -v bandit &>/dev/null; then
        log_info "Running Bandit (Python security)..."
        
        if bandit -r apps/auth-server/src/ -f json -o /tmp/bandit-report.json 2>/dev/null; then
            log_success "Bandit scan passed"
        else
            log_warning "Bandit found potential issues"
            issues+=1
        fi
        
        # Check for critical issues
        if grep -q '"severity": "HIGH"' /tmp/bandit-report.json 2>/dev/null; then
            log_warning "High-severity issues found"
        fi
    else
        log_warning "Bandit not installed"
    fi
    
    # JavaScript/TypeScript - ESLint
    if command -v eslint &>/dev/null; then
        log_info "Running ESLint (JavaScript/TypeScript security)..."
        
        if eslint apps/auth-server/src/**/*.ts --format json > /tmp/eslint-report.json 2>&1 || true; then
            local error_count=$(grep -c '"severity": 2' /tmp/eslint-report.json || echo "0")
            
            if [ "$error_count" -gt 0 ]; then
                log_warning "ESLint found $error_count errors"
                issues+=1
            else
                log_success "ESLint scan passed"
            fi
        fi
    else
        log_warning "ESLint not installed"
    fi
    
    # SQL injection pattern detection
    log_info "Checking for SQL injection patterns..."
    if grep -r "execute.*format" apps/auth-server/src/ 2>/dev/null | grep -v ".pyc"; then
        log_error "Found potential SQL injection patterns"
        issues+=1
    else
        log_success "No SQL injection patterns detected"
    fi
    
    # XSS pattern detection
    log_info "Checking for XSS patterns..."
    if grep -r "dangerouslySetInnerHTML\|innerHTML\|eval(" apps/auth-server/src/**/*.ts 2>/dev/null; then
        log_error "Found potential XSS patterns"
        issues+=1
    else
        log_success "No XSS patterns detected"
    fi
    
    # Hardcoded secret detection
    log_info "Checking for hardcoded secrets..."
    if grep -r "api.?key\|password\|secret\|token" apps/auth-server/src/ 2>/dev/null | \
       grep -i "=.*[\'\"].*[\'\"]" | \
       grep -v ".pyc" | \
       grep -v "placeholder\|example\|test\|dummy"; then
        log_warning "Found potential hardcoded values"
        issues+=1
    else
        log_success "No obvious hardcoded secrets"
    fi
    
    return $([ $issues -eq 0 ] && echo 0 || echo 1)
}

###############################################################################
# SCA: Software Composition Analysis (Dependency Scanning)
###############################################################################

run_sca() {
    log_info "Running Dependency Scanning (SCA)..."
    
    local issues=0
    
    # Python dependencies
    if command -v pip &>/dev/null; then
        log_info "Checking Python dependencies..."
        
        if command -v safety &>/dev/null; then
            if safety check --json > /tmp/safety-report.json 2>&1; then
                log_success "Python dependencies secure"
            else
                log_error "Python dependencies have known vulnerabilities"
                issues+=1
            fi
        else
            log_warning "Safety not installed for Python scanning"
        fi
    fi
    
    # JavaScript dependencies
    if command -v npm &>/dev/null; then
        log_info "Checking JavaScript dependencies..."
        
        if npm audit --json > /tmp/npm-audit-report.json 2>&1; then
            local critical=$(jq '.metadata.vulnerabilities.critical // 0' /tmp/npm-audit-report.json)
            local high=$(jq '.metadata.vulnerabilities.high // 0' /tmp/npm-audit-report.json)
            
            if [ "$critical" -gt 0 ]; then
                log_error "Found $critical critical vulnerabilities"
                issues+=1
            elif [ "$high" -gt 0 ]; then
                log_warning "Found $high high-severity vulnerabilities"
            else
                log_success "JavaScript dependencies secure"
            fi
        else
            log_warning "npm audit check failed"
        fi
    fi
    
    # Snyk integration (if available)
    if command -v snyk &>/dev/null; then
        log_info "Running Snyk scan..."
        
        if snyk test --severity-threshold=high > /tmp/snyk-report.txt 2>&1; then
            log_success "Snyk scan passed"
        else
            log_warning "Snyk found vulnerabilities"
            issues+=1
        fi
    fi
    
    return $([ $issues -eq 0 ] && echo 0 || echo 1)
}

###############################################################################
# SECRETS DETECTION
###############################################################################

run_secrets_detection() {
    log_info "Running Secrets Detection..."
    
    local secrets_found=0
    
    # git-secrets
    if command -v git-secrets &>/dev/null; then
        log_info "Scanning git history with git-secrets..."
        
        if git secrets --scan; then
            log_success "No secrets found in git history"
        else
            log_error "Secrets detected in git history"
            secrets_found+=1
        fi
    else
        log_warning "git-secrets not installed"
    fi
    
    # TruffleHog (if installed)
    if command -v trufflehog &>/dev/null; then
        log_info "Scanning with TruffleHog..."
        
        if trufflehog filesystem . --json > /tmp/trufflehog-report.json 2>&1; then
            if [ -s /tmp/trufflehog-report.json ]; then
                log_warning "TruffleHog found potential secrets"
                secrets_found+=1
            else
                log_success "No secrets detected by TruffleHog"
            fi
        fi
    fi
    
    # Regex pattern scanning
    log_info "Pattern-based secret scanning..."
    
    local patterns_found=0
    
    # AWS keys
    if grep -r "AKIA\|aws_secret_access_key" . 2>/dev/null | grep -v ".git" | grep -v "node_modules"; then
        log_warning "Potential AWS keys found"
        patterns_found+=1
    fi
    
    # GitHub tokens
    if grep -r "ghp_\|gho_\|ghu_\|ghs_\|ghr_" . 2>/dev/null | grep -v ".git" | grep -v "node_modules"; then
        log_warning "Potential GitHub tokens found"
        patterns_found+=1
    fi
    
    # Private keys
    if grep -r "BEGIN RSA PRIVATE KEY\|BEGIN PRIVATE KEY" . 2>/dev/null | grep -v ".git" | grep -v "node_modules"; then
        log_error "Private keys found in repository"
        patterns_found+=1
    fi
    
    if [ $patterns_found -eq 0 ]; then
        log_success "No secret patterns detected"
    fi
    
    return $([ $secrets_found -eq 0 ] && echo 0 || echo 1)
}

###############################################################################
# CONTAINER SECURITY
###############################################################################

run_container_security() {
    log_info "Running Container Security Scanning..."
    
    local issues=0
    
    # Trivy image scanning
    if command -v trivy &>/dev/null; then
        log_info "Scanning Docker images with Trivy..."
        
        local images=("auth-server:latest" "postgres:14-alpine" "redis:7-alpine")
        
        for image in "${images[@]}"; do
            log_info "Scanning $image..."
            
            if trivy image --severity HIGH,CRITICAL "$image" 2>&1 | grep -q "Total:"; then
                log_info "Trivy scan completed for $image"
            else
                log_warning "Could not scan $image"
            fi
        done
    else
        log_warning "Trivy not installed"
    fi
    
    # Dockerfile scanning
    log_info "Scanning Dockerfile for best practices..."
    
    local dockerfile="Dockerfile"
    
    if [ -f "$dockerfile" ]; then
        # Check for root user
        if grep -q "^USER root$" "$dockerfile"; then
            log_warning "Container runs as root"
            issues+=1
        else
            log_success "Container uses non-root user"
        fi
        
        # Check for health checks
        if grep -q "HEALTHCHECK" "$dockerfile"; then
            log_success "Health checks configured"
        else
            log_warning "No health checks configured"
        fi
    fi
    
    return $([ $issues -eq 0 ] && echo 0 || echo 1)
}

###############################################################################
# DAST: Dynamic Application Security Testing
###############################################################################

run_dast() {
    log_info "Running Dynamic Application Security Testing (DAST)..."
    
    if ! command -v curl &>/dev/null; then
        log_error "curl not found"
        return 1
    fi
    
    local base_url="http://localhost:3100"
    local issues=0
    
    # Check if service is running
    if ! curl -sf "$base_url/health" >/dev/null 2>&1; then
        log_error "Service not running at $base_url"
        return 1
    fi
    
    log_info "Testing common vulnerabilities..."
    
    # SQL Injection tests
    log_info "Testing for SQL Injection vulnerability..."
    local response=$(curl -s "$base_url/api/users/me?id=1' OR '1'='1" \
        -H "Authorization: Bearer test" 2>&1 || echo "")
    
    if echo "$response" | grep -qi "sql\|syntax error\|database"; then
        log_warning "Potential SQL injection error message exposed"
        issues+=1
    else
        log_success "SQL injection test passed"
    fi
    
    # XSS tests
    log_info "Testing for XSS vulnerability..."
    local xss_payload="<script>alert('xss')</script>"
    local response=$(curl -s "$base_url/api/users/me" \
        -H "Authorization: Bearer test" \
        -H "User-Agent: $xss_payload" 2>&1 || echo "")
    
    if echo "$response" | grep -q "<script>"; then
        log_warning "Potential XSS vulnerability"
        issues+=1
    else
        log_success "XSS test passed"
    fi
    
    # CSRF tests
    log_info "Testing CSRF protection..."
    local csrf_test=$(curl -s -X POST "$base_url/api/teams" \
        -H "Content-Type: application/json" \
        -d '{}' 2>&1 || echo "")
    
    if echo "$csrf_test" | grep -q "403\|CSRF\|Forbidden"; then
        log_success "CSRF protection enabled"
    else
        log_warning "CSRF protection might be missing"
    fi
    
    # Authentication bypass tests
    log_info "Testing authentication..."
    
    # Test without credentials
    local no_auth=$(curl -s "$base_url/api/users/me" 2>&1)
    if echo "$no_auth" | grep -q "401\|Unauthorized"; then
        log_success "Authentication required"
    else
        log_error "Unauthenticated access allowed"
        issues+=1
    fi
    
    # Test with invalid token
    local invalid_token=$(curl -s "$base_url/api/users/me" \
        -H "Authorization: Bearer invalid.token.here" 2>&1)
    
    if echo "$invalid_token" | grep -q "401\|Unauthorized\|Invalid"; then
        log_success "Invalid token rejected"
    else
        log_warning "Invalid token handling unclear"
    fi
    
    # Security header tests
    log_info "Testing security headers..."
    
    local headers=$(curl -sI "$base_url/health")
    
    if echo "$headers" | grep -q "X-Content-Type-Options"; then
        log_success "X-Content-Type-Options header present"
    else
        log_warning "X-Content-Type-Options header missing"
        issues+=1
    fi
    
    if echo "$headers" | grep -q "X-Frame-Options"; then
        log_success "X-Frame-Options header present"
    else
        log_warning "X-Frame-Options header missing"
        issues+=1
    fi
    
    if echo "$headers" | grep -q "Strict-Transport-Security"; then
        log_success "HSTS header present"
    else
        log_warning "HSTS header missing"
    fi
    
    return $([ $issues -eq 0 ] && echo 0 || echo 1)
}

###############################################################################
# INFRASTRUCTURE SECURITY
###############################################################################

run_infrastructure_security() {
    log_info "Running Infrastructure Security Scanning..."
    
    local issues=0
    
    # Check terraform files
    if command -v terraform &>/dev/null && [ -d terraform/ ]; then
        log_info "Validating Terraform files..."
        
        if cd terraform && terraform validate >/dev/null 2>&1; then
            log_success "Terraform validation passed"
            cd - >/dev/null
        else
            log_error "Terraform validation failed"
            issues+=1
            cd - >/dev/null || true
        fi
    fi
    
    # Docker Compose validation
    if command -v docker-compose &>/dev/null; then
        log_info "Validating docker-compose configuration..."
        
        if docker-compose config >/dev/null 2>&1; then
            log_success "Docker Compose configuration valid"
        else
            log_error "Docker Compose validation failed"
            issues+=1
        fi
    fi
    
    return $([ $issues -eq 0 ] && echo 0 || echo 1)
}

###############################################################################
# COMPREHENSIVE SCAN
###############################################################################

run_comprehensive_scan() {
    log_info ""
    log_info "====== COMPREHENSIVE SECURITY SCAN ======"
    log_info "Starting at $(date)"
    log_info ""
    
    local total_passed=0
    local total_failed=0
    
    # SAST
    if run_sast; then
        total_passed+=1
    else
        total_failed+=1
    fi
    
    log_info ""
    
    # SCA
    if run_sca; then
        total_passed+=1
    else
        total_failed+=1
    fi
    
    log_info ""
    
    # Secrets
    if run_secrets_detection; then
        total_passed+=1
    else
        total_failed+=1
    fi
    
    log_info ""
    
    # Container
    if run_container_security; then
        total_passed+=1
    else
        total_failed+=1
    fi
    
    log_info ""
    
    # Infrastructure
    if run_infrastructure_security; then
        total_passed+=1
    else
        total_failed+=1
    fi
    
    # DAST (optional - requires running service)
    if curl -sf "http://localhost:3100/health" >/dev/null 2>&1; then
        log_info ""
        if run_dast; then
            total_passed+=1
        else
            total_failed+=1
        fi
    else
        log_warning "Skipping DAST - service not available"
    fi
    
    log_info ""
    log_info "====== SECURITY SCAN SUMMARY ======"
    log_success "Passed: $total_passed"
    if [ $total_failed -gt 0 ]; then
        log_warning "Failed: $total_failed"
    fi
    log_info "Completed at $(date)"
    
    return $([ $total_failed -eq 0 ] && echo 0 || echo 1)
}

###############################################################################
# MAIN
###############################################################################

main() {
    local scan_type="${1:-comprehensive}"
    local fail_on_severity="${2:-critical}"
    
    case "$scan_type" in
        sast)
            run_sast
            ;;
        sca)
            run_sca
            ;;
        secrets)
            run_secrets_detection
            ;;
        container)
            run_container_security
            ;;
        infrastructure)
            run_infrastructure_security
            ;;
        dast)
            run_dast
            ;;
        comprehensive|all)
            run_comprehensive_scan
            ;;
        *)
            log_error "Unknown scan type: $scan_type"
            echo "Available types: sast, sca, secrets, container, infrastructure, dast, comprehensive"
            exit 1
            ;;
    esac
}

main "$@"
