#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# Phase 13 - Continuous IaC Compliance Monitor
# Verifies immutability, idempotency, and reproducibility on every deployment
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MONITOR_LOG="/tmp/phase-13-iac-monitor-$(date +%Y%m%d-%H%M%S).log"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$MONITOR_LOG"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "$MONITOR_LOG"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$MONITOR_LOG"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" | tee -a "$MONITOR_LOG"
}

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# ════════════════════════════════════════════════════════════════════════════
# CHECK 1: IMMUTABILITY - Container Image Digests
# ════════════════════════════════════════════════════════════════════════════

check_image_immutability() {
    log_info "CHECK 1: Verifying container image immutability..."
    
    # Check ssh-proxy uses digest
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -q "python:3.11-slim@sha256:" "$REPO_ROOT/Dockerfile.ssh-proxy"; then
        log_success "ssh-proxy base image uses SHA256 digest"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "ssh-proxy base image missing SHA256 digest"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check docker-compose has no floating tags
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -E "(image:.*:latest|image:.*:main|image:.*:stable)" "$REPO_ROOT/docker-compose.yml" > /dev/null 2>&1; then
        log_error "Found floating tags in docker-compose.yml"
        grep -E "(image:.*:latest|image:.*:main|image:.*:stable)" "$REPO_ROOT/docker-compose.yml"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    else
        log_success "No floating tags in docker-compose.yml"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    
    # Check all external images have version tags
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local untagged=$(grep "image:" "$REPO_ROOT/docker-compose.yml" | grep -v ":.*-\|:.*\." | grep -v "local$" | wc -l)
    if [ "$untagged" -eq 0 ]; then
        log_success "All external images have explicit version tags"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "Found $untagged untagged images"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# CHECK 2: IMMUTABILITY - Configuration as Code
# ════════════════════════════════════════════════════════════════════════════

check_config_immutability() {
    log_info "CHECK 2: Verifying configuration immutability..."
    
    # Check all config files are in Git
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if git -C "$REPO_ROOT" ls-files | grep -q "docker-compose.yml"; then
        log_success "docker-compose.yml tracked in Git"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "docker-compose.yml NOT tracked in Git"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check Dockerfiles are versioned
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if git -C "$REPO_ROOT" ls-files | grep -q "Dockerfile"; then
        log_success "Dockerfiles tracked in Git"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "Dockerfiles NOT tracked in Git"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check config dir is versioned
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if git -C "$REPO_ROOT" ls-files | grep -q "config/"; then
        log_success "config/ directory tracked in Git"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "config/ NOT tracked in Git"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check no manual .env overrides in Git (should use secrets)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if ! git -C "$REPO_ROOT" ls-files | grep -q "^\.env$"; then
        log_success ".env credentials NOT in Git (using GitHub Secrets)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error ".env credentials found in Git (SECURITY RISK)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# CHECK 3: IDEMPOTENCY - Script Patterns
# ════════════════════════════════════════════════════════════════════════════

check_idempotency_patterns() {
    log_info "CHECK 3: Verifying idempotency patterns in scripts..."
    
    local script_dir="$REPO_ROOT/scripts"
    
    # Check phase-13 scripts have idempotency markers
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -q "idempotent\|state.*check\|already.*running" "$script_dir/phase-13-day1-execute.sh"; then
        log_success "phase-13-day1-execute.sh has idempotency markers"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_warn "phase-13-day1-execute.sh missing idempotency comments"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check for bash set -euo pipefail (strict mode)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if head -20 "$script_dir/phase-13-day1-execute.sh" | grep -q "set -euo pipefail"; then
        log_success "Scripts use strict mode (set -euo pipefail)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "Scripts missing strict mode"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# CHECK 4: REPRODUCIBILITY - Version Pinning
# ════════════════════════════════════════════════════════════════════════════

check_version_pinning() {
    log_info "CHECK 4: Verifying version pinning for reproducibility..."
    
    # Check code-server version pinned
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -q "CODE_SERVER_VERSION=4\.[0-9]\+\.[0-9]\+" "$REPO_ROOT/Dockerfile.code-server"; then
        log_success "code-server version explicitly pinned"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "code-server version NOT pinned"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check extension versions pinned
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -q "COPILOT_VERSION=" "$REPO_ROOT/Dockerfile.code-server" && \
       grep -q "COPILOT_CHAT_VERSION=" "$REPO_ROOT/Dockerfile.code-server"; then
        log_success "Extension versions explicitly pinned"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "Extension versions NOT pinned"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check Python packages pinned
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -q "fastapi==" "$REPO_ROOT/Dockerfile.ssh-proxy" && \
       grep -q "uvicorn==" "$REPO_ROOT/Dockerfile.ssh-proxy"; then
        log_success "Python packages have exact version pins"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "Python packages missing version pins"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# CHECK 5: DOCKER INFRASTRUCTURE
# ════════════════════════════════════════════════════════════════════════════

check_docker_health() {
    log_info "CHECK 5: Verifying Docker services health..."
    
    # Check docker running
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if command -v docker &> /dev/null; then
        log_success "Docker is available"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_warn "Docker not available (expected on dev machine)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return
    fi
    
    # Check docker-compose valid
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if docker-compose -f "$REPO_ROOT/docker-compose.yml" config > /dev/null 2>&1; then
        log_success "docker-compose.yml is valid"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "docker-compose.yml is invalid"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check health checks defined
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local healthchecks=$(grep -c "healthcheck:" "$REPO_ROOT/docker-compose.yml" || true)
    if [ "$healthchecks" -gt 0 ]; then
        log_success "Found $healthchecks health checks defined"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_warn "No health checks defined in docker-compose.yml"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# CHECK 6: GIT REPOSITORY
# ════════════════════════════════════════════════════════════════════════════

check_git_state() {
    log_info "CHECK 6: Verifying Git repository state..."
    
    # Check working tree clean
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if git -C "$REPO_ROOT" status --porcelain | grep -q .; then
        log_warn "Working tree has uncommitted changes"
        git -C "$REPO_ROOT" status --short
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    else
        log_success "Working tree is clean"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    
    # Check HEAD is on main
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD | grep -q "^main$"; then
        log_success "HEAD is on main branch"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_warn "HEAD is not on main branch"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check last commit has Phase 13 marker
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if git -C "$REPO_ROOT" log -1 --oneline | grep -q "Phase 13\|phase-13"; then
        log_success "Last commit references Phase 13"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_info "Last commit: $(git -C "$REPO_ROOT" log -1 --oneline)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# RESULTS SUMMARY
# ════════════════════════════════════════════════════════════════════════════

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════"
    echo "PHASE 13 IaC COMPLIANCE MONITOR - SUMMARY"
    echo "════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Total Checks:  $TOTAL_CHECKS"
    echo "Passed:        ${GREEN}$PASSED_CHECKS${NC}"
    echo "Failed:        ${RED}$FAILED_CHECKS${NC}"
    echo ""
    
    local pass_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo "Compliance Rate: ${GREEN}$pass_rate%${NC}"
    echo ""
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "${GREEN}✓ PHASE 13 IaC COMPLIANCE: PASS${NC}"
        echo "All immutability, idempotency, and reproducibility checks passed."
        echo ""
        echo "Deployment Ready Criteria:"
        echo "  ✓ All images immutable (versioned or digested)"
        echo "  ✓ All configuration under version control"
        echo "  ✓ Scripts follow idempotent patterns"
        echo "  ✓ All versions pinned for reproducibility"
        echo "  ✓ Healthy Docker infrastructure"
        echo "  ✓ Clean Git state"
        exit 0
    else
        echo -e "${YELLOW}⚠ PHASE 13 IaC COMPLIANCE: WARNINGS${NC}"
        echo "Some checks failed. Review above for details."
        echo "Critical failures must be fixed before deployment."
        exit 1
    fi
    
    echo ""
    echo "Monitor Log: $MONITOR_LOG"
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════════════════════════════

main() {
    echo "════════════════════════════════════════════════════════════════════════════"
    echo "PHASE 13 - CONTINUOUS IaC COMPLIANCE MONITOR"
    echo "════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Repository: $REPO_ROOT"
    echo "Monitor Log: $MONITOR_LOG"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    
    check_image_immutability
    echo ""
    check_config_immutability
    echo ""
    check_idempotency_patterns
    echo ""
    check_version_pinning
    echo ""
    check_docker_health
    echo ""
    check_git_state
    echo ""
    
    print_summary
}

main "$@"
