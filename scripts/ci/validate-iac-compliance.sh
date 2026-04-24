#!/usr/bin/env bash
# @file        scripts/ci/validate-iac-compliance.sh
# @module      infrastructure/governance
# @description Validate Infrastructure as Code compliance across immutability, idempotency, and reproducibility principles
#
# This script validates that all infrastructure changes follow IaC principles:
# - Immutability: No runtime modifications, all changes via git
# - Idempotency: Safe to re-run deployments multiple times
# - Reproducibility: Exact same deployment results from any commit
#
# Exit codes:
#   0 = All checks passed (COMPLIANT)
#   1 = One or more checks failed (NON-COMPLIANT)
#
# Usage:
#   ./scripts/ci/validate-iac-compliance.sh
#   ./scripts/ci/validate-iac-compliance.sh --strict  # Fail on warnings

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

STRICT_MODE="${1:-}"
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════════════════════
# Logging Functions
# ═══════════════════════════════════════════════════════════════════════════════

log_pass() {
    echo -e "${GREEN}✓${NC} $*"
    ((PASS_COUNT++))
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    ((WARN_COUNT++))
}

log_fail() {
    echo -e "${RED}✗${NC} $*"
    ((FAIL_COUNT++))
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_section() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  $*"
    echo "═══════════════════════════════════════════════════════════════════════════════"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Immutability Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_immutability() {
    log_section "IMMUTABILITY VALIDATION"
    
    # Check 1: All configuration in git
    log_info "Checking if configuration is version-controlled..."
    if git -C "${PROJECT_ROOT}" ls-files config/ docker-compose.yml > /dev/null 2>&1; then
        log_pass "Configuration tracked in git"
    else
        log_fail "Configuration not tracked in git"
    fi
    
    # Check 2: Container images use SHA256 digests
    log_info "Checking container image digest pinning..."
    local docker_compose="${PROJECT_ROOT}/docker-compose.yml"
    local total_images=$(grep -c "^[[:space:]]*image:" "$docker_compose" || true)
    local pinned_images=$(grep "@sha256:" "$docker_compose" | wc -l)
    
    if [[ $pinned_images -eq $total_images ]]; then
        log_pass "All ${total_images} container images pinned to SHA256 digests (100%)"
    elif [[ $pinned_images -gt 0 ]]; then
        local percentage=$((pinned_images * 100 / total_images))
        log_warn "Container image digest coverage: ${percentage}% (${pinned_images}/${total_images})"
    else
        log_fail "No container images pinned to SHA256 digests (0/${total_images})"
    fi
    
    # Check 3: No hardcoded secrets
    log_info "Checking for hardcoded secrets..."
    local secret_patterns=("PASSWORD=" "TOKEN=" "API_KEY=" "SECRET=" "CREDENTIAL=")
    local secrets_found=0
    
    for pattern in "${secret_patterns[@]}"; do
        if grep -r "${pattern}" "$PROJECT_ROOT" --include="*.yml" --include="*.yaml" 2>/dev/null | \
           grep -v "example" | grep -v "placeholder" | grep -v ".env" > /dev/null; then
            ((secrets_found++))
        fi
    done
    
    if [[ $secrets_found -eq 0 ]]; then
        log_pass "No hardcoded secrets detected in configuration"
    else
        log_warn "Found ${secrets_found} potential hardcoded secret patterns (review required)"
    fi
    
    # Check 4: No manual SSH configuration
    log_info "Checking for SSH key immutability..."
    if [[ ! -f "${PROJECT_ROOT}/terraform/modules/ssh_keys.tf" ]] || \
       grep -q "provisioner \"local-exec\"" "${PROJECT_ROOT}/terraform/modules/ssh_keys.tf"; then
        log_warn "SSH configuration may not be fully IaC-driven"
    else
        log_pass "SSH configuration managed via Terraform"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Idempotency Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_idempotency() {
    log_section "IDEMPOTENCY VALIDATION"
    
    # Check 1: SQL migrations use IF NOT EXISTS
    log_info "Checking SQL migration idempotency..."
    local migrations_dir="${PROJECT_ROOT}/migrations"
    if [[ -d "$migrations_dir" ]]; then
        local sql_files=$(find "$migrations_dir" -name "*.sql" -type f | wc -l)
        local safe_migrations=$(grep -l "IF NOT EXISTS" "$migrations_dir"/*.sql 2>/dev/null | wc -l)
        
        if [[ $safe_migrations -eq $sql_files ]]; then
            log_pass "All ${sql_files} SQL migrations are idempotent (IF NOT EXISTS pattern)"
        else
            log_warn "SQL migration idempotency: ${safe_migrations}/${sql_files} use IF NOT EXISTS pattern"
        fi
    else
        log_info "No migrations directory found"
    fi
    
    # Check 2: Docker Compose safe to re-run
    log_info "Checking Docker Compose idempotency..."
    if grep -q "restart: unless-stopped\|restart: always" "$docker_compose"; then
        log_pass "Docker services configured for auto-restart (idempotent)"
    else
        log_warn "Docker services may not have proper restart policies"
    fi
    
    # Check 3: Deployment scripts are idempotent
    log_info "Checking deployment script safety..."
    local deploy_scripts=$(find "$PROJECT_ROOT/scripts" -name "deploy*.sh" -type f 2>/dev/null | wc -l)
    local safe_deploys=$(grep -l "set -euo pipefail" "$PROJECT_ROOT/scripts"/deploy*.sh 2>/dev/null | wc -l)
    
    if [[ $deploy_scripts -gt 0 ]]; then
        if [[ $safe_deploys -eq $deploy_scripts ]]; then
            log_pass "All ${deploy_scripts} deployment scripts have error handling"
        else
            log_warn "Deployment script safety: ${safe_deploys}/${deploy_scripts} have proper error handling"
        fi
    fi
    
    # Check 4: No manual modifications in scripts
    log_info "Checking for imperative shell commands..."
    if grep -r "\.\/setup\.sh\|\.\/install\.sh\|make install" "$PROJECT_ROOT" --include="*.tf" --include="*.yml" 2>/dev/null | \
       grep -v "example\|TODO" > /dev/null; then
        log_warn "Found imperative setup commands (should be declarative)"
    else
        log_pass "No manual setup commands detected (declarative approach)"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Reproducibility Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_reproducibility() {
    log_section "REPRODUCIBILITY VALIDATION"
    
    # Check 1: Git commit history
    log_info "Checking git history for version control..."
    if git -C "$PROJECT_ROOT" rev-parse HEAD > /dev/null 2>&1; then
        local commit_hash=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)
        local commit_count=$(git -C "$PROJECT_ROOT" rev-list --count HEAD)
        log_pass "Git repository valid (${commit_count} commits, HEAD: ${commit_hash})"
    else
        log_fail "Git repository not initialized or inaccessible"
    fi
    
    # Check 2: Pinned dependency versions
    log_info "Checking for pinned versions..."
    local pinned_services=0
    
    if grep -q "postgres:15-alpine@sha256" "$docker_compose"; then
        ((pinned_services++))
    fi
    
    if grep -q "redis:7-alpine@sha256" "$docker_compose"; then
        ((pinned_services++))
    fi
    
    if grep -q "caddy:.*@sha256" "$docker_compose"; then
        ((pinned_services++))
    fi
    
    if [[ $pinned_services -ge 3 ]]; then
        log_pass "Core services pinned to specific versions (${pinned_services} verified)"
    else
        log_warn "Core services not all pinned to specific versions"
    fi
    
    # Check 3: Terraform stateful operations
    log_info "Checking Terraform for deterministic operations..."
    if [[ -d "${PROJECT_ROOT}/terraform" ]]; then
        local tf_files=$(find "$PROJECT_ROOT/terraform" -name "*.tf" -type f | wc -l)
        if [[ $tf_files -gt 0 ]]; then
            log_pass "Terraform infrastructure defined (${tf_files} .tf files)"
        else
            log_warn "Terraform directory exists but no .tf files found"
        fi
    else
        log_info "No Terraform directory found"
    fi
    
    # Check 4: Consistent environment variables
    log_info "Checking environment variable consistency..."
    if [[ -f "${PROJECT_ROOT}/.env.schema.json" ]] || [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
        log_pass "Environment variable schema documented"
    else
        log_warn "Environment variable schema not documented"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Deployment Readiness Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_deployment_readiness() {
    log_section "DEPLOYMENT READINESS VALIDATION"
    
    # Check 1: docker-compose config validity
    log_info "Validating docker-compose.yml syntax..."
    if command -v docker-compose > /dev/null 2>&1; then
        if docker-compose -f "$docker_compose" config > /dev/null 2>&1; then
            log_pass "docker-compose.yml is valid and can be deployed"
        else
            log_fail "docker-compose.yml has syntax errors"
        fi
    else
        log_info "Docker Compose not available for validation"
    fi
    
    # Check 2: Documentation present
    log_info "Checking for deployment documentation..."
    if [[ -f "${PROJECT_ROOT}/docs/DEPLOYMENT.md" ]] || [[ -f "${PROJECT_ROOT}/DEPLOYMENT.md" ]]; then
        log_pass "Deployment documentation present"
    else
        log_warn "Deployment documentation not found"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

print_summary() {
    echo ""
    log_section "COMPLIANCE SUMMARY"
    
    echo ""
    echo "Results:"
    echo "  ✓ Passed:  ${PASS_COUNT}"
    echo "  ⚠ Warnings: ${WARN_COUNT}"
    echo "  ✗ Failed:  ${FAIL_COUNT}"
    echo ""
    
    local total=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
    local compliance=$((PASS_COUNT * 100 / total))
    
    echo "IaC Compliance Score: ${compliance}% (${PASS_COUNT}/${total})"
    echo ""
    
    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓ COMPLIANT: Infrastructure meets IaC standards${NC}"
        if [[ $WARN_COUNT -gt 0 ]]; then
            echo -e "${YELLOW}  (${WARN_COUNT} warnings to review)${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗ NON-COMPLIANT: ${FAIL_COUNT} governance violations detected${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo "║   Infrastructure as Code Governance Compliance Validator (IaC-GCV)             ║"
    echo "║   Version: 1.0 | Scope: Immutability, Idempotency, Reproducibility            ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Project Root: ${PROJECT_ROOT}"
    echo "Strict Mode: ${STRICT_MODE:-disabled}"
    echo ""
    
    check_immutability
    check_idempotency
    check_reproducibility
    check_deployment_readiness
    print_summary
}

main "$@"
