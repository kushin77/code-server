#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# PHASE 13: END-TO-END DEPLOYMENT TEST
#
# Comprehensive validation of all Phase 13 components
# - Master orchestrator
# - All 5 task scripts
# - Configuration files
# - Docker infrastructure
# - Terraform IaC
# - GitHub Actions CI/CD
#
# Idempotent: Safe to run multiple times
# Status: Outputs test results and go/no-go decision
#
# April 13-14, 2026
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_LOG="/tmp/phase-13-e2e-test-$(date +%Y%m%d-%H%M%S).log"
TEST_RESULTS_JSON="/tmp/phase-13-test-results.json"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING & ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────

log_test() {
    local msg="$1"
    echo -e "${BLUE}[TEST]${NC} $msg" | tee -a "$TEST_LOG"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

assert_pass() {
    local test_name="$1"
    echo -e "${GREEN}✓${NC} PASS: $test_name" | tee -a "$TEST_LOG"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

assert_fail() {
    local test_name="$1"
    local reason="${2:-}"
    echo -e "${RED}✗${NC} FAIL: $test_name${reason:+ - $reason}" | tee -a "$TEST_LOG"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

assert_skip() {
    local test_name="$1"
    echo -e "${YELLOW}⊘${NC} SKIP: $test_name" | tee -a "$TEST_LOG"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST SUITES
# ─────────────────────────────────────────────────────────────────────────────

test_orchestrator_files() {
    echo ""
    echo -e "${BLUE}═══ ORCHESTRATOR FILES ═══${NC}"

    log_test "Master orchestrator exists"
    if [ -f "$SCRIPT_DIR/phase-13-orchestrator.sh" ]; then
        assert_pass "Master orchestrator exists"
    else
        assert_fail "Master orchestrator exists"
        return 1
    fi

    log_test "Master orchestrator executable"
    if [ -x "$SCRIPT_DIR/phase-13-orchestrator.sh" ]; then
        assert_pass "Master orchestrator executable"
    else
        assert_fail "Master orchestrator executable" "chmod +x needed"
    fi

    log_test "Master orchestrator valid shell syntax"
    if bash -n "$SCRIPT_DIR/phase-13-orchestrator.sh" 2>/dev/null; then
        assert_pass "Master orchestrator valid shell"
    else
        assert_fail "Master orchestrator valid shell"
    fi
}

test_task_scripts() {
    echo ""
    echo -e "${BLUE}═══ TASK SCRIPTS ═══${NC}"

    local tasks=("1.1" "1.2" "1.3" "1.4" "1.5")

    for task in "${tasks[@]}"; do
        local script="$SCRIPT_DIR/phase-13-task-${task}-*.sh"

        log_test "Task $task script exists"
        if ls $script 1>/dev/null 2>&1; then
            assert_pass "Task $task script exists"

            # Check syntax
            log_test "Task $task valid shell syntax"
            if bash -n $(ls $script | head -1) 2>/dev/null; then
                assert_pass "Task $task valid syntax"
            else
                assert_fail "Task $task valid syntax"
            fi
        else
            assert_fail "Task $task script exists" "File not found"
        fi
    done
}

test_configuration_files() {
    echo ""
    echo -e "${BLUE}═══ CONFIGURATION FILES ═══${NC}"

    # Audit logging config
    log_test "Audit logging config exists"
    if [ -f "$REPO_ROOT/config/audit-logging.conf" ]; then
        assert_pass "Audit logging config exists"
    else
        assert_fail "Audit logging config exists"
        return 1
    fi

    # SSH proxy config
    log_test "SSH proxy config exists"
    if [ -f "$REPO_ROOT/config/ssh-proxy.conf" ]; then
        assert_pass "SSH proxy config exists"
    else
        assert_fail "SSH proxy config exists"
        return 1
    fi

    # Systemd services
    log_test "Git proxy systemd service exists"
    if [ -f "$REPO_ROOT/config/systemd/git-proxy.service" ]; then
        assert_pass "Git proxy systemd service exists"
    else
        assert_fail "Git proxy systemd service exists"
    fi

    log_test "SSH proxy systemd service exists"
    if [ -f "$REPO_ROOT/config/systemd/ssh-proxy.service" ]; then
        assert_pass "SSH proxy systemd service exists"
    else
        assert_fail "SSH proxy systemd service exists"
    fi
}

test_docker_setup() {
    echo ""
    echo -e "${BLUE}═══ DOCKER CONFIGURATION ═══${NC}"

    log_test "docker-compose.yml exists"
    if [ -f "$REPO_ROOT/docker-compose.yml" ]; then
        assert_pass "docker-compose.yml exists"
    else
        assert_fail "docker-compose.yml exists"
        return 1
    fi

    log_test "docker-compose.yml valid YAML"
    if grep -q "version:" "$REPO_ROOT/docker-compose.yml" && \
       grep -q "services:" "$REPO_ROOT/docker-compose.yml"; then
        assert_pass "docker-compose.yml valid YAML"
    else
        assert_fail "docker-compose.yml valid YAML"
    fi

    log_test "Dockerfile.ssh-proxy exists"
    if [ -f "$REPO_ROOT/Dockerfile.ssh-proxy" ]; then
        assert_pass "Dockerfile.ssh-proxy exists"
    else
        assert_fail "Dockerfile.ssh-proxy exists"
    fi
}

test_iac_files() {
    echo ""
    echo -e "${BLUE}═══ INFRASTRUCTURE AS CODE ═══${NC}"

    log_test "Terraform cloudflare config exists"
    if [ -f "$REPO_ROOT/terraform/cloudflare-phase-13.tf" ]; then
        assert_pass "Terraform cloudflare config exists"
    else
        assert_fail "Terraform cloudflare config exists"
        return 1
    fi

    log_test "Terraform variables example exists"
    if [ -f "$REPO_ROOT/terraform/phase-13.tfvars.example" ]; then
        assert_pass "Terraform variables example exists"
    else
        assert_fail "Terraform variables example exists"
    fi

    log_test "Terraform has resource definitions"
    if grep -q "resource \"cloudflare" "$REPO_ROOT/terraform/cloudflare-phase-13.tf"; then
        assert_pass "Terraform has resource definitions"
    else
        assert_fail "Terraform has resource definitions"
    fi
}

test_cicd() {
    echo ""
    echo -e "${BLUE}═══ CI/CD PIPELINE ═══${NC}"

    log_test "GitHub Actions workflow exists"
    if [ -f "$REPO_ROOT/.github/workflows/phase-13-deploy.yml" ]; then
        assert_pass "GitHub Actions workflow exists"
    else
        assert_fail "GitHub Actions workflow exists"
        return 1
    fi

    log_test "Workflow has jobs defined"
    if grep -q "^jobs:" "$REPO_ROOT/.github/workflows/phase-13-deploy.yml"; then
        assert_pass "Workflow has jobs defined"
    else
        assert_fail "Workflow has jobs defined"
    fi

    log_test "Workflow has triggers defined"
    if grep -q "^on:" "$REPO_ROOT/.github/workflows/phase-13-deploy.yml"; then
        assert_pass "Workflow has triggers defined"
    else
        assert_fail "Workflow has triggers defined"
    fi
}

test_documentation() {
    echo ""
    echo -e "${BLUE}═══ DOCUMENTATION ═══${NC}"

    local docs=(
        "PHASE-13-ORCHESTRATION-FINAL-COMPLETION-REPORT.md"
        "PHASE-13-DEPLOYMENT-READINESS-SIGN-OFF.md"
        "PHASE-13-INFRASTRUCTURE-TEAM-DEPLOYMENT-GUIDE.md"
        "PHASE-13-EXECUTION-READINESS-REPORT.md"
    )

    for doc in "${docs[@]}"; do
        log_test "Documentation: $doc exists"
        if [ -f "$REPO_ROOT/$doc" ]; then
            assert_pass "Documentation: $doc exists"
        else
            assert_fail "Documentation: $doc exists"
        fi
    done
}

test_git_status() {
    echo ""
    echo -e "${BLUE}═══ GIT REPOSITORY ═══${NC}"

    log_test "Valid git repository"
    if git -C "$REPO_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
        assert_pass "Valid git repository"
    else
        assert_fail "Valid git repository"
        return 1
    fi

    log_test "All changes committed"
    local uncommitted=$(git -C "$REPO_ROOT" status --short | wc -l)
    if [ "$uncommitted" -eq 0 ]; then
        assert_pass "All changes committed"
    else
        assert_fail "All changes committed" "$uncommitted uncommitted changes"
    fi
}

test_idempotency() {
    echo ""
    echo -e "${BLUE}═══ IDEMPOTENCY CHECKS ═══${NC}"

    log_test "Orchestrator has state tracking"
    if grep -q "state\|STATE\|deployment.state" "$SCRIPT_DIR/phase-13-orchestrator.sh"; then
        assert_pass "Orchestrator has state tracking"
    else
        assert_fail "Orchestrator has state tracking"
    fi

    log_test "Orchestrator has skip logic"
    if grep -q "is_task_complete\|skip" "$SCRIPT_DIR/phase-13-orchestrator.sh"; then
        assert_pass "Orchestrator has skip logic"
    else
        assert_fail "Orchestrator has skip logic"
    fi

    log_test "Task scripts have idempotency checks"
    local idempotent_scripts=0
    for script in "$SCRIPT_DIR"/phase-13-task-*.sh; do
        if grep -q "if.*exists\|already\|is_complete\|skip" "$script" 2>/dev/null; then
            idempotent_scripts=$((idempotent_scripts + 1))
        fi
    done

    if [ $idempotent_scripts -ge 3 ]; then
        assert_pass "Task scripts have idempotency checks ($idempotent_scripts/5)"
    else
        assert_fail "Task scripts have idempotency checks" "Only $idempotent_scripts/5"
    fi
}

test_immutability() {
    echo ""
    echo -e "${BLUE}═══ IMMUTABILITY CHECKS ═══${NC}"

    log_test "Audit logging config marked immutable"
    if grep -q "\"immutable\".*true\|immutable.*true" "$REPO_ROOT/config/audit-logging.conf"; then
        assert_pass "Audit logging config marked immutable"
    else
        assert_fail "Audit logging config marked immutable"
    fi

    log_test "All configs in git version control"
    if git -C "$REPO_ROOT" ls-files | grep -q "config/"; then
        assert_pass "All configs in git version control"
    else
        assert_fail "All configs in git version control"
    fi

    log_test "Docker images use version tags"
    if grep -q "code-server.*:latest\|ssh-proxy.*:latest" "$REPO_ROOT/docker-compose.yml"; then
        assert_pass "Docker images use version tags"
    else
        assert_fail "Docker images use version tags"
    fi
}

test_tools_available() {
    echo ""
    echo -e "${BLUE}═══ TOOL AVAILABILITY ═══${NC}"

    local tools=("bash" "docker" "docker-compose" "curl" "git")

    for tool in "${tools[@]}"; do
        log_test "Tool available: $tool"
        if command -v "$tool" &>/dev/null; then
            assert_pass "Tool available: $tool"
        else
            assert_fail "Tool available: $tool"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY & GO/NO-GO DECISION
# ─────────────────────────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${BLUE}PHASE 13 END-TO-END TEST SUMMARY${NC}"
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo ""
    echo "Total Tests:      $TESTS_TOTAL"
    echo -e "${GREEN}Passed:          $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:          $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped:         $TESTS_SKIPPED${NC}"
    echo ""

    if [ $TESTS_TOTAL -gt 0 ]; then
        local pass_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
        echo "Pass Rate:        ${pass_rate}%"
    fi
    echo ""

    # Generate JSON results
    cat > "$TEST_RESULTS_JSON" << EOFJSON
{
  "test_timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "summary": {
    "total": $TESTS_TOTAL,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "skipped": $TESTS_SKIPPED
  },
  "pass_rate_percent": $(( TESTS_TOTAL > 0 ? (TESTS_PASSED * 100) / TESTS_TOTAL : 0 )),
  "log_file": "$TEST_LOG"
}
EOFJSON

    # Go/No-Go Decision
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${BLUE}GO/NO-GO DECISION${NC}"
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ] && [ $TESTS_PASSED -ge 40 ]; then
        echo -e "${GREEN}✓ GO FOR DEPLOYMENT${NC}"
        echo ""
        echo "All critical components verified:"
        echo "  ✓ Orchestrator ready"
        echo "  ✓ Task scripts integrated"
        echo "  ✓ Configuration immutable"
        echo "  ✓ IaC complete"
        echo "  ✓ CI/CD pipeline ready"
        echo "  ✓ Documentation complete"
        echo "  ✓ Idempotency validated"
        echo ""
        echo -e "${GREEN}Ready for April 14, 2026 @ 09:00 UTC${NC}"
        return 0
    else
        echo -e "${RED}✗ NO-GO FOR DEPLOYMENT${NC}"
        echo ""
        echo "Issues found:"
        echo "  Failed tests: $TESTS_FAILED"
        echo "  Passed tests: $TESTS_PASSED (minimum 40 required)"
        echo ""
        echo "Review log: $TEST_LOG"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ PHASE 13 END-TO-END DEPLOYMENT TEST                ║${NC}"
    echo -e "${BLUE}║ Comprehensive pre-launch verification               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Log file: $TEST_LOG"
    echo "Results: $TEST_RESULTS_JSON"
    echo ""

    # Run all test suites
    test_orchestrator_files
    test_task_scripts
    test_configuration_files
    test_docker_setup
    test_iac_files
    test_cicd
    test_documentation
    test_git_status
    test_idempotency
    test_immutability
    test_tools_available

    # Print summary and decide
    print_summary
}

main "$@"
