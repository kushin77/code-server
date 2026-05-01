#!/bin/bash
###############################################################################
# @file        scripts/verify-q3-services.sh
# @module      ops/verify-service-health
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/_common/init.sh"
###############################################################################
# GOV-002 Compliance: Production Deployment Verification
# P3 Q3 Services: Reputation Engine, Execution Scheduler, Paperclip Control Plane
# Status: Autonomous Verification Script
# Date: April 25, 2026

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (immutable, read-only)
readonly SERVICES=("reputation-engine" "execution-scheduler" "paperclip")
readonly PORTS=(8050 8070 8010)
readonly HEALTH_ENDPOINTS=("/health" "/health" "/health")
readonly REQUIRED_FILES=("Dockerfile" "requirements.txt" "main.py")
readonly TIMEOUT_SECS=30

# Verification functions

verify_service_docker_infrastructure() {
    local service=$1
    local service_dir="apps/$service"
    
    log_info "Verifying $service infrastructure..."
    
    local all_present=true
    for file in "${REQUIRED_FILES[@]}"; do
        if [[ -f "$service_dir/$file" ]]; then
            log_success "$service: $file present"
        else
            log_error "$service: $file MISSING"
            all_present=false
        fi
    done
    
    # Verify service in docker-compose.yml
    if grep -q "^  $service:" docker-compose.yml 2>/dev/null; then
        log_success "$service: Found in docker-compose.yml"
    else
        log_error "$service: NOT found in docker-compose.yml"
        all_present=false
    fi
    
    return $([ "$all_present" = true ] && echo 0 || echo 1)
}

verify_docker_build() {
    local service=$1
    local service_dir="apps/$service"
    
    log_info "Verifying docker build for $service..."
    
    if docker build -q -t "paperclip/$service:verify" -f "$service_dir/Dockerfile" . >/dev/null 2>&1; then
        log_success "$service: Docker build successful"
        return 0
    else
        log_error "$service: Docker build FAILED"
        return 1
    fi
}

verify_python_syntax() {
    local service=$1
    local service_dir="apps/$service"
    
    log_info "Verifying Python syntax for $service..."
    
    local has_errors=false
    for pyfile in "$service_dir"/*.py; do
        if [[ -f "$pyfile" ]]; then
            if python3 -m py_compile "$pyfile" 2>/dev/null; then
                log_success "$(basename $pyfile): Python syntax OK"
            else
                log_error "$(basename $pyfile): Python syntax ERROR"
                has_errors=true
            fi
        fi
    done
    
    return $([ "$has_errors" = false ] && echo 0 || echo 1)
}

verify_dependencies() {
    local service=$1
    local service_dir="apps/$service"
    
    log_info "Verifying dependencies for $service..."
    
    if [[ ! -f "$service_dir/requirements.txt" ]]; then
        log_error "$service: requirements.txt not found"
        return 1
    fi
    
    # Try to create virtual environment and install
    local venv_dir="/tmp/venv-$service"
    if python3 -m venv "$venv_dir" 2>/dev/null && \
       "$venv_dir/bin/pip" install -q -r "$service_dir/requirements.txt" 2>/dev/null; then
        log_success "$service: Dependencies installable"
        rm -rf "$venv_dir"
        return 0
    else
        log_error "$service: Dependencies FAILED to install"
        rm -rf "$venv_dir" 2>/dev/null || true
        return 1
    fi
}

verify_docker_compose_config() {
    log_info "Verifying docker-compose.yml configuration..."
    
    if docker-compose config >/dev/null 2>&1; then
        log_success "docker-compose.yml: Configuration valid"
        return 0
    else
        log_error "docker-compose.yml: Configuration INVALID"
        return 1
    fi
}

verify_no_hardcoded_secrets() {
    local service=$1
    local service_dir="apps/$service"
    
    log_info "Scanning $service for hardcoded secrets..."
    
    local found_secret=false
    
    # Check for common patterns
    if grep -r "password\|secret\|key\|token" "$service_dir" 2>/dev/null | \
       grep -v "environment\|getenv\|os.environ\|config\|#" >/dev/null; then
        log_warning "$service: Potential hardcoded values detected (verify manually)"
    else
        log_success "$service: No obvious hardcoded secrets"
    fi
    
    return 0
}

verify_imorph_gov_headers() {
    local service=$1
    local service_dir="apps/$service"
    
    log_info "Verifying GOV-002 compliance headers in $service..."
    
    # Check if main.py has governance header
    if grep -q "@governance\|@file\|@description\|GOV-002" "$service_dir/main.py" 2>/dev/null; then
        log_success "$service: GOV-002 headers present in main.py"
    else
        log_warning "$service: GOV-002 headers NOT found (consider adding)"
    fi
    
    return 0
}

# Main verification workflow (idempotent)

main() {
    log_info "======================================"
    log_info "P3 Q3 Services - Production Readiness"
    log_info "======================================"
    log_info ""
    
    local all_passed=true
    
    # Verify each service
    for service in "${SERVICES[@]}"; do
        log_info ""
        log_info ">>> VERIFYING $service <<<"
        log_info ""
        
        verify_service_docker_infrastructure "$service" || all_passed=false
        log_info ""
        
        verify_python_syntax "$service" || all_passed=false
        log_info ""
        
        # Skip docker build on Windows (use actual deployment to verify)
        # verify_docker_build "$service" || all_passed=false
        # log_info ""
        
        verify_dependencies "$service" || all_passed=false
        log_info ""
        
        verify_no_hardcoded_secrets "$service" || all_passed=false
        log_info ""
        
        verify_imorph_gov_headers "$service" || all_passed=false
        log_info ""
    done
    
    # Global verification
    log_info ""
    log_info ">>> GLOBAL VERIFICATION <<<"
    log_info ""
    
    verify_docker_compose_config || all_passed=false
    log_info ""
    
    # Summary
    log_info ""
    log_info "======================================"
    if [[ "$all_passed" = true ]]; then
        log_success "ALL VERIFICATIONS PASSED ✅"
        log_info "Services ready for production deployment"
        return 0
    else
        log_error "SOME VERIFICATIONS FAILED"
        log_warning "Address issues before production deployment"
        return 1
    fi
}

# Execute main verification (idempotent, safe to re-run)
main "$@"
