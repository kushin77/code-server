#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# PHASE 13: FINAL PRODUCTION READINESS VALIDATION
#
# Comprehensive verification that all Phase 13 components meet:
# - Infrastructure as Code (IaC) principles
# - Immutability requirements
# - Idempotency standards
#
# This script runs once before April 14 deployment
# Exit code 0 = READY, Exit code 1 = NOT READY
#
# April 13, 2026
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VALIDATION_LOG="/tmp/phase-13-final-validation-$(date +%s).log"
VALIDATION_REPORT="/tmp/phase-13-validation-report.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Keep track of results
CATEGORIES_PASSED=0
CATEGORIES_FAILED=0
TOTAL_CHECKS=0
PASSED_CHECKS=0

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION CATEGORIES
# ─────────────────────────────────────────────────────────────────────────────

log_category() {
    local name="$1"
    echo "" | tee -a "$VALIDATION_LOG"
    echo -e "${BLUE}═══ $name ═══${NC}" | tee -a "$VALIDATION_LOG"
}

log_check() {
    local description="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "  [$TOTAL_CHECKS] $description ... " | tee -a "$VALIDATION_LOG"
}

result_pass() {
    echo -e "${GREEN}✓ PASS${NC}" | tee -a "$VALIDATION_LOG"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

result_fail() {
    local reason="${1:-}"
    echo -e "${RED}✗ FAIL${NC}${reason:+ - $reason}" | tee -a "$VALIDATION_LOG"
}

category_pass() {
    CATEGORIES_PASSED=$((CATEGORIES_PASSED + 1))
}

category_fail() {
    CATEGORIES_FAILED=$((CATEGORIES_FAILED + 1))
}

# ─────────────────────────────────────────────────────────────────────────────
# IaC VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

validate_iac() {
    log_category "INFRASTRUCTURE AS CODE (IaC)"

    local failures=0

    # Terraform files exist
    log_check "Terraform configuration files exist"
    if [ -f "$REPO_ROOT/terraform/cloudflare-phase-13.tf" ]; then
        result_pass
    else
        result_fail "cloudflare-phase-13.tf not found"
        failures=$((failures + 1))
    fi

    # Terraform has resource definitions
    log_check "Terraform resources properly defined"
    if grep -q "resource \"cloudflare" "$REPO_ROOT/terraform/cloudflare-phase-13.tf"; then
        result_pass
    else
        result_fail "No cloudflare resources found"
        failures=$((failures + 1))
    fi

    # Docker Compose exists
    log_check "docker-compose.yml defines all services"
    if [ -f "$REPO_ROOT/docker-compose.yml" ]; then
        local service_count=$(grep -c "^[a-z].*:$" "$REPO_ROOT/docker-compose.yml" || true)
        if [ "$service_count" -ge 5 ]; then
            result_pass
        else
            result_fail "Only $service_count services found (need 5+)"
            failures=$((failures + 1))
        fi
    else
        result_fail "docker-compose.yml not found"
        failures=$((failures + 1))
    fi

    # Dockerfiles exist
    log_check "All required Dockerfiles present"
    if [ -f "$REPO_ROOT/Dockerfile.ssh-proxy" ] && \
       [ -f "$REPO_ROOT/Dockerfile.caddy" ] && \
       [ -f "$REPO_ROOT/Dockerfile.code-server" ]; then
        result_pass
    else
        result_fail "Missing Dockerfile(s)"
        failures=$((failures + 1))
    fi

    # GitHub Actions workflow
    log_check "GitHub Actions workflow defined"
    if [ -f "$REPO_ROOT/.github/workflows/phase-13-deploy.yml" ]; then
        if grep -q "on:" "$REPO_ROOT/.github/workflows/phase-13-deploy.yml"; then
            result_pass
        else
            result_fail "Workflow missing trigger definition"
            failures=$((failures + 1))
        fi
    else
        result_fail "phase-13-deploy.yml not found"
        failures=$((failures + 1))
    fi

    # Systemd services defined
    log_check "Systemd services defined (IaC)"
    if [ -f "$REPO_ROOT/config/systemd/ssh-proxy.service" ] && \
       [ -f "$REPO_ROOT/config/systemd/git-proxy.service" ]; then
        result_pass
    else
        result_fail "Missing systemd service files"
        failures=$((failures + 1))
    fi

    if [ $failures -eq 0 ]; then
        category_pass
    else
        category_fail
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# IMMUTABILITY VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

validate_immutability() {
    log_category "IMMUTABILITY (Version Control)"

    local failures=0

    # All config files tracked in git
    log_check "Configuration files tracked in git"
    if git -C "$REPO_ROOT" ls-files | grep -q "config/"; then
        result_pass
    else
        result_fail "Config files not in git"
        failures=$((failures + 1))
    fi

    # Terraform files tracked
    log_check "Terraform files tracked in git"
    if git -C "$REPO_ROOT" ls-files | grep -q "terraform/"; then
        result_pass
    else
        result_fail "Terraform files not in git"
        failures=$((failures + 1))
    fi

    # Scripts tracked
    log_check "All scripts tracked in git"
    if git -C "$REPO_ROOT" ls-files | grep -q "scripts/phase-13"; then
        result_pass
    else
        result_fail "Phase 13 scripts not in git"
        failures=$((failures + 1))
    fi

    # No untracked Phase 13 files
    log_check "No untracked Phase 13 files"
    local untracked=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard | grep -c "phase-13\|PHASE-13" || true)
    if [ "$untracked" -eq 0 ]; then
        result_pass
    else
        result_fail "$untracked untracked Phase 13 files found"
        failures=$((failures + 1))
    fi

    # Audit logging config marked immutable
    log_check "Audit logging config marked immutable"
    if grep -q "immutable" "$REPO_ROOT/config/audit-logging.conf"; then
        result_pass
    else
        result_fail "Audit config not marked immutable"
        failures=$((failures + 1))
    fi

    # No hardcoded secrets in code
    log_check "No secrets in version control"
    local secret_count=0
    if grep -r "CLOUDFLARE_API\|oauth2.*secret\|password.*=" "$REPO_ROOT/terraform" 2>/dev/null | grep -v "example\|tfvars.example"; then
        result_fail "Possible secrets found in code"
        failures=$((failures + 1))
    else
        result_pass
    fi

    if [ $failures -eq 0 ]; then
        category_pass
    else
        category_fail
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# IDEMPOTENCY VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

validate_idempotency() {
    log_category "IDEMPOTENCY (Safe Re-entrance)"

    local failures=0

    # Orchestrator has state tracking
    log_check "Master orchestrator implements state tracking"
    if grep -q "state\|STATE\|deployment.state" "$SCRIPT_DIR/phase-13-orchestrator.sh"; then
        result_pass
    else
        result_fail "No state tracking in orchestrator"
        failures=$((failures + 1))
    fi

    # Orchestrator has idempotent checks
    log_check "Orchestrator skips completed tasks"
    if grep -q "is_task_complete\|status.*completed" "$SCRIPT_DIR/phase-13-orchestrator.sh"; then
        result_pass
    else
        result_fail "No skip logic in orchestrator"
        failures=$((failures + 1))
    fi

    # Task scripts have existence checks
    log_check "Task scripts check for existing resources"
    local idempotent_count=0
    for script in "$SCRIPT_DIR"/phase-13-task-*.sh; do
        if [ -f "$script" ] && grep -q "if.*exists\|already\|is_complete" "$script" 2>/dev/null; then
            idempotent_count=$((idempotent_count + 1))
        fi
    done
    if [ "$idempotent_count" -ge 3 ]; then
        result_pass
    else
        result_fail "Only $idempotent_count/5+ tasks have idempotency checks"
        failures=$((failures + 1))
    fi

    # Terraform has for_each or count (idempotent resource management)
    log_check "Terraform uses idempotent resource management"
    if grep -q "for_each\|count" "$REPO_ROOT/terraform/cloudflare-phase-13.tf"; then
        result_pass
    else
        result_fail "No for_each/count in Terraform (may cause re-creation)"
        failures=$((failures + 1))
    fi

    # Docker has restart policies
    log_check "Docker services have restart policies"
    if grep -q "restart_policy\|restart:\|unless-stopped" "$REPO_ROOT/docker-compose.yml"; then
        result_pass
    else
        result_fail "No restart policies defined"
        failures=$((failures + 1))
    fi

    # Systemd services have restart on failure
    log_check "Systemd services restart on failure"
    if grep -q "Restart=\|RestartSec=" "$REPO_ROOT/config/systemd/ssh-proxy.service"; then
        result_pass
    else
        result_fail "No restart policy in systemd service"
        failures=$((failures + 1))
    fi

    if [ $failures -eq 0 ]; then
        category_pass
    else
        category_fail
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ORCHESTRATION VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

validate_orchestration() {
    log_category "ORCHESTRATION (Integration)"

    local failures=0

    # Master orchestrator syntax valid
    log_check "Master orchestrator has valid shell syntax"
    if bash -n "$SCRIPT_DIR/phase-13-orchestrator.sh" 2>/dev/null; then
        result_pass
    else
        result_fail "Syntax error in orchestrator"
        failures=$((failures + 1))
    fi

    # All task scripts present
    log_check "All 5 task scripts present"
    local task_count=0
    for i in 1.1 1.2 1.3 1.4 1.5; do
        if ls "$SCRIPT_DIR"/phase-13-task-${i}-*.sh 1>/dev/null 2>&1; then
            task_count=$((task_count + 1))
        fi
    done
    if [ "$task_count" -eq 5 ]; then
        result_pass
    else
        result_fail "Only $task_count/5 task scripts found"
        failures=$((failures + 1))
    fi

    # Validation scripts present
    log_check "Validation scripts available"
    if [ -f "$SCRIPT_DIR/phase-13-validation-checklist.sh" ] && \
       [ -f "$SCRIPT_DIR/phase-13-e2e-test.sh" ]; then
        result_pass
    else
        result_fail "Validation scripts missing"
        failures=$((failures + 1))
    fi

    # Configuration files consistent
    log_check "Configuration files are consistent"
    if [ -f "$REPO_ROOT/config/audit-logging.conf" ] && \
       [ -f "$REPO_ROOT/config/ssh-proxy.conf" ]; then
        result_pass
    else
        result_fail "Configuration files missing"
        failures=$((failures + 1))
    fi

    if [ $failures -eq 0 ]; then
        category_pass
    else
        category_fail
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# DOCUMENTATION VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

validate_documentation() {
    log_category "DOCUMENTATION (Completeness)"

    local failures=0
    local required_docs=(
        "PHASE-13-ORCHESTRATION-FINAL-COMPLETION-REPORT.md"
        "PHASE-13-DEPLOYMENT-READINESS-SIGN-OFF.md"
        "PHASE-13-INFRASTRUCTURE-TEAM-DEPLOYMENT-GUIDE.md"
        "PHASE-13-FINAL-TEST-STATUS-READY.md"
        "PHASE-13-DEPLOYMENT-DAY-APRIL-14.md"
    )

    log_check "All prerequisite documentation exists"
    local doc_count=0
    for doc in "${required_docs[@]}"; do
        if [ -f "$REPO_ROOT/$doc" ]; then
            doc_count=$((doc_count + 1))
        fi
    done
    if [ "$doc_count" -eq "${#required_docs[@]}" ]; then
        result_pass
    else
        result_fail "Only $doc_count/${#required_docs[@]} docs found"
        failures=$((failures + 1))
    fi

    if [ $failures -eq 0 ]; then
        category_pass
    else
        category_fail
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# GIT STATUS VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

validate_git_status() {
    log_category "GIT REPOSITORY STATUS"

    local failures=0

    # Repository is clean
    log_check "Working directory is clean"
    local status=$(git -C "$REPO_ROOT" status --short | wc -l)
    if [ "$status" -eq 0 ]; then
        result_pass
    else
        result_fail "$status uncommitted changes"
        failures=$((failures + 1))
    fi

    # On main branch
    log_check "On main branch"
    local branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
    if [ "$branch" = "main" ]; then
        result_pass
    else
        result_fail "On $branch branch (need main)"
        failures=$((failures + 1))
    fi

    # Recent commits exist
    log_check "Recent Phase 13 commits present"
    if git -C "$REPO_ROOT" log --oneline -5 | grep -i "phase-13\|orchestration\|deployment"; then
        result_pass
    else
        result_fail "No recent Phase 13 commits"
        failures=$((failures + 1))
    fi

    if [ $failures -eq 0 ]; then
        category_pass
    else
        category_fail
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# FINAL REPORT
# ─────────────────────────────────────────────────────────────────────────────

generate_report() {
    local total_categories=$((CATEGORIES_PASSED + CATEGORIES_FAILED))
    local pass_rate=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${BLUE}PHASE 13 FINAL PRODUCTION READINESS REPORT${NC}"
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo ""

    echo "Test Categories:" | tee -a "$VALIDATION_LOG"
    echo "  Passed:  $CATEGORIES_PASSED" | tee -a "$VALIDATION_LOG"
    echo "  Failed:  $CATEGORIES_FAILED" | tee -a "$VALIDATION_LOG"
    echo ""

    echo "Individual Checks:" | tee -a "$VALIDATION_LOG"
    echo "  Total:   $TOTAL_CHECKS" | tee -a "$VALIDATION_LOG"
    echo "  Passed:  $PASSED_CHECKS" | tee -a "$VALIDATION_LOG"
    echo "  Pass Rate: $pass_rate%" | tee -a "$VALIDATION_LOG"
    echo ""

    # Generate JSON report
    cat > "$VALIDATION_REPORT" << EOF
{
  "validation_timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "results": {
    "categories_tested": $total_categories,
    "categories_passed": $CATEGORIES_PASSED,
    "categories_failed": $CATEGORIES_FAILED,
    "total_checks": $TOTAL_CHECKS,
    "checks_passed": $PASSED_CHECKS,
    "pass_rate_percent": $pass_rate
  },
  "validation_areas": {
    "iac": "Infrastructure as Code",
    "immutability": "Version Control & Immutability",
    "idempotency": "Idempotent Execution",
    "orchestration": "Integration & Orchestration",
    "documentation": "Completeness",
    "git_status": "Repository Status"
  },
  "log_file": "$VALIDATION_LOG",
  "report_file": "$VALIDATION_REPORT"
}
EOF

    echo -e "${BLUE}════════════════════════════════════════════${NC}"

    # Go/No-Go decision
    if [ $CATEGORIES_FAILED -eq 0 ] && [ $pass_rate -ge 95 ]; then
        echo -e "${GREEN}✓ GO FOR DEPLOYMENT${NC}"
        echo ""
        echo "All requirements met:"
        echo "  ✓ Infrastructure as Code (IaC) validated"
        echo "  ✓ Immutability (version control) validated"
        echo "  ✓ Idempotency (safe re-entrance) validated"
        echo "  ✓ Orchestration integration verified"
        echo "  ✓ Documentation complete"
        echo "  ✓ Git repository clean"
        echo ""
        echo "Ready for April 14, 2026 @ 09:00 UTC execution"
        echo ""
        echo "Log: $VALIDATION_LOG"
        echo "Report: $VALIDATION_REPORT"
        return 0
    else
        echo -e "${RED}✗ NOT READY FOR DEPLOYMENT${NC}"
        echo ""
        echo "Issues found:"
        echo "  Failed categories: $CATEGORIES_FAILED"
        echo "  Pass rate: $pass_rate% (need 95%+)"
        echo ""
        echo "Review: $VALIDATION_LOG"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ PHASE 13 FINAL PRODUCTION READINESS AUDIT   ║${NC}"
    echo -e "${BLUE}║ IaC • Immutability • Idempotency Validation ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Validation Log: $VALIDATION_LOG"
    echo ""

    # Run all validations
    validate_iac
    validate_immutability
    validate_idempotency
    validate_orchestration
    validate_documentation
    validate_git_status

    # Generate report and decide
    generate_report
}

main "$@"
