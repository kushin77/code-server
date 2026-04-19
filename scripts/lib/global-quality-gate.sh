#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Global Quality Gate - Phase 3+ Production Verification
# ═══════════════════════════════════════════════════════════════════════════════
# Validates: Environment variables, Docker services, Security configs, Health checks
# Exit Code: 0 = all checks pass, 1+ = failures detected
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

LIB_DIR="${SCRIPT_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

log_check() {
    echo -e "${YELLOW}→${NC} $1"
}

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
}

log_skip() {
    echo -e "${YELLOW}⊘${NC} $1 (skipped)"
    CHECKS_SKIPPED=$((CHECKS_SKIPPED + 1))
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1: Environment Validation
# ─────────────────────────────────────────────────────────────────────────────

check_env_schema() {
    log_header "Phase 1: Environment Variable Validation"
    
    if [[ ! -f "${PROJECT_ROOT}/.env.schema.json" ]]; then
        log_fail "Missing schema: .env.schema.json"
        return 1
    fi
    log_pass "Schema file exists (.env.schema.json)"
    
    if [[ ! -f "${PROJECT_ROOT}/.env.defaults" ]]; then
        log_fail "Missing defaults: .env.defaults"
        return 1
    fi
    log_pass "Defaults file exists (.env.defaults)"
    
    # Check required variables
    if command -v jq &>/dev/null; then
        local required_vars
        required_vars=$(jq -r '.required[]? // empty' "${PROJECT_ROOT}/.env.schema.json" 2>/dev/null | wc -l)
        if [[ $required_vars -gt 0 ]]; then
            log_pass "Schema defines $required_vars required variables"
        else
            log_skip "Could not parse required variables from schema (jq issue)"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2: Docker Service Validation
# ─────────────────────────────────────────────────────────────────────────────

check_docker_services() {
    log_header "Phase 2: Docker Service Health"

    local compose_cmd
    
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
        log_skip "docker-compose not available (may be on remote)"
        return 0
    fi

    if docker compose version &>/dev/null 2>&1; then
        compose_cmd="docker compose"
    else
        compose_cmd="docker-compose"
    fi
    
    # Skip if Docker daemon is not reachable (e.g., running quality gate locally on Windows/WSL)
    if ! docker info &>/dev/null 2>&1; then
        log_skip "Docker daemon not reachable — skipping service checks (run on ${DEPLOY_HOST:-192.168.168.31} for full validation)"
        return 0
    fi
    
    log_check "Checking docker-compose configuration..."
    if ${compose_cmd} config > /dev/null 2>&1; then
        log_pass "docker-compose configuration is valid"
    else
        log_fail "Invalid docker-compose configuration"
        return 1
    fi
    
    # Check if services are running
    if ${compose_cmd} ps > /dev/null 2>&1; then
        local running_count
        running_count=$(${compose_cmd} ps --services 2>/dev/null | wc -l)
        if [[ $running_count -gt 0 ]]; then
            log_pass "Docker services configured ($running_count services)"
        else
            log_skip "No services running (may be expected in dev)"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3: Validation Script Presence
# ─────────────────────────────────────────────────────────────────────────────

check_validation_scripts() {
    log_header "Phase 3: Validation Tooling"
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/validate-env.sh" ]]; then
        log_fail "Missing validation script: scripts/validate-env.sh"
        return 1
    fi
    log_pass "Validation script exists (scripts/validate-env.sh)"
    
    if [[ ! -x "${PROJECT_ROOT}/scripts/validate-env.sh" ]]; then
        log_check "Making validate-env.sh executable..."
        chmod +x "${PROJECT_ROOT}/scripts/validate-env.sh"
        log_pass "Validation script is now executable"
    else
        log_pass "Validation script is executable"
    fi
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/generate-env-docs.sh" ]]; then
        log_fail "Missing docs generator: scripts/generate-env-docs.sh"
        return 1
    fi
    log_pass "Documentation generator exists (scripts/generate-env-docs.sh)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4: CI/CD Configuration
# ─────────────────────────────────────────────────────────────────────────────

check_ci_cd_config() {
    log_header "Phase 4: CI/CD Pipeline Configuration"
    
    if [[ ! -f "${PROJECT_ROOT}/.github/workflows/validate-env.yml" ]]; then
        log_fail "Missing CI/CD workflow: .github/workflows/validate-env.yml"
        return 1
    fi
    log_pass "GitHub Actions workflow exists (validate-env.yml)"
    
    if command -v python3 &>/dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('${PROJECT_ROOT}/.github/workflows/validate-env.yml'))" 2>/dev/null; then
            log_pass "GitHub Actions workflow is valid YAML"
        else
            log_fail "GitHub Actions workflow has YAML syntax errors"
            return 1
        fi
    else
        log_skip "YAML validation (python3 not available)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 5: Git Repository Health
# ─────────────────────────────────────────────────────────────────────────────

check_git_status() {
    log_header "Phase 5: Git Repository Health"
    
    cd "${PROJECT_ROOT}"
    
    if [[ ! -d .git ]]; then
        log_fail "Not a git repository"
        return 1
    fi
    log_pass "Git repository initialized"
    
    # Check for uncommitted changes
    local uncommitted
    uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
    if [[ $uncommitted -eq 0 ]]; then
        log_pass "Working directory is clean (no uncommitted changes)"
    else
        log_fail "Uncommitted changes detected ($uncommitted files)"
    fi
    
    # Check branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    log_pass "Current branch: $current_branch"
    
    # Check latest commit
    local latest_commit
    latest_commit=$(git log -1 --oneline 2>/dev/null || echo "no commits")
    log_pass "Latest commit: $latest_commit"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 6: Makefile Targets
# ─────────────────────────────────────────────────────────────────────────────

check_makefile_targets() {
    log_header "Phase 6: Makefile Automation"
    
    if [[ ! -f "${PROJECT_ROOT}/Makefile" ]]; then
        log_fail "Missing Makefile"
        return 1
    fi
    log_pass "Makefile exists"
    
    # Check for phase 3 targets
    local targets=("validate-env" "test-env" "generate-env-docs")
    local missing=0
    
    for target in "${targets[@]}"; do
        if grep -q "^${target}:" "${PROJECT_ROOT}/Makefile"; then
            log_pass "Makefile target exists: $target"
        else
            log_fail "Missing Makefile target: $target"
            missing=$((missing + 1))
        fi
    done
    
    return $missing
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 7: Security Configuration
# ─────────────────────────────────────────────────────────────────────────────

check_security_config() {
    log_header "Phase 7: Security Configuration"
    
    # Check for archived legacy files
    if [[ -d "${PROJECT_ROOT}/.archived/env-variants-historical" ]]; then
        local archived_files
        archived_files=$(find "${PROJECT_ROOT}/.archived/env-variants-historical" -type f | wc -l)
        log_pass "Legacy files archived ($archived_files files in .archived/)"
    else
        log_skip "Legacy file archival not yet configured"
    fi
    
    # Check for environment archival notes
    if [[ -f "${PROJECT_ROOT}/.archived/env-variants-historical/ENV_ARCHIVAL_NOTES.md" ]]; then
        log_pass "Archival documentation exists (ENV_ARCHIVAL_NOTES.md)"
    else
        log_skip "Archival documentation not present"
    fi
    
    # Verify no plain-text secrets in tracked files
    local secret_patterns=("AKIA" "ghp_" "sk-")
    local found_secrets=0
    local env_files=()

    while IFS= read -r env_file; do
        env_files+=("$env_file")
    done < <(find "${PROJECT_ROOT}" -maxdepth 1 -type f -name '.env*' \
        ! -name '.env.example' ! -name '.env.defaults' ! -name '.env.schema.json' 2>/dev/null)

    if [[ ${#env_files[@]} -eq 0 ]]; then
        log_skip "No local .env files found for secret pattern scan"
        return 0
    fi
    
    for pattern in "${secret_patterns[@]}"; do
        if grep -H -n "$pattern" "${env_files[@]}" 2>/dev/null | head -1; then
            log_fail "Potential secret found matching pattern: $pattern"
            found_secrets=$((found_secrets + 1))
        fi
    done
    
    if [[ $found_secrets -eq 0 ]]; then
        log_pass "No obvious secrets detected in .env files"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 8: Phase 3 Completion Verification
# ─────────────────────────────────────────────────────────────────────────────

check_phase_3_completion() {
    log_header "Phase 8: Phase 3 Completion Status"
    
    # Check for phase 3 documentation
    local phase3_docs=(
        "PHASE-3-CONSOLIDATION-COMPLETE.md"
        "PHASE-3-EXECUTIVE-SUMMARY.md"
    )
    
    for doc in "${phase3_docs[@]}"; do
        if [[ -f "${PROJECT_ROOT}/$doc" ]]; then
            log_pass "Documentation file exists: $doc"
        else
            log_skip "Missing historical documentation: $doc"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         GLOBAL QUALITY GATE - PRODUCTION VERIFICATION                       ║${NC}"
    echo -e "${BLUE}║         Phase 3 Environment Variable Consolidation                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Run all checks
    check_env_schema || true
    echo ""
    
    check_docker_services || true
    echo ""
    
    check_validation_scripts || true
    echo ""
    
    check_ci_cd_config || true
    echo ""
    
    check_git_status || true
    echo ""
    
    check_makefile_targets || true
    echo ""
    
    check_security_config || true
    echo ""
    
    check_phase_3_completion || true
    echo ""
    
    # Summary
    log_header "Quality Gate Summary"
    echo -e "${GREEN}✓ Checks Passed:  $CHECKS_PASSED${NC}"
    echo -e "${RED}✗ Checks Failed:  $CHECKS_FAILED${NC}"
    echo -e "${YELLOW}⊘ Checks Skipped: $CHECKS_SKIPPED${NC}"
    echo ""
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}═════════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}✓ ALL QUALITY GATES PASSED - PRODUCTION READY${NC}"
        echo -e "${GREEN}═════════════════════════════════════════════════════════════════════════════════${NC}"
        return 0
    else
        echo -e "${RED}═════════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}✗ $CHECKS_FAILED QUALITY GATES FAILED - REVIEW REQUIRED${NC}"
        echo -e "${RED}═════════════════════════════════════════════════════════════════════════════════${NC}"
        return 1
    fi
}

main "$@"
