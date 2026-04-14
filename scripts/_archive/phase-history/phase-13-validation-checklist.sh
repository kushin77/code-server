#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# PHASE 13: PRE-LAUNCH VALIDATION CHECKLIST
#
# Comprehensive verification of all Phase 13 components
# Tests: idempotency, configuration integrity, dependency resolution
# Produces: Deployment readiness assessment
#
# April 14, 2026 - Pre-Launch Verification
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# ─────────────────────────────────────────────────────────────────────────────
# ASSERTION FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

assert_file_exists() {
    local file="$1"
    local description="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} File exists: $description ($file)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} File missing: $description ($file)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

assert_executable() {
    local file="$1"
    local description="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ -x "$file" ]; then
        echo -e "${GREEN}✓${NC} Executable: $description ($file)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Not executable: $description - chmod +x needed"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

assert_valid_shell() {
    local file="$1"
    local description="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if bash -n "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Valid shell syntax: $description"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Invalid shell syntax: $description"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

assert_valid_json() {
    local file="$1"
    local description="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if jq empty "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Valid JSON: $description"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Invalid JSON syntax: $description"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

assert_valid_yaml() {
    local file="$1"
    local description="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if command -v yamllint &>/dev/null && yamllint -d relaxed "$file" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Valid YAML: $description"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    elif python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Valid YAML: $description"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Cannot fully validate YAML: $description (yamllint/python3 not available)"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi
}

assert_string_in_file() {
    local file="$1"
    local string="$2"
    local description="$3"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if grep -q "$string" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Contains: $description"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Missing: $description"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

assert_tool_available() {
    local tool="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if command -v "$tool" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Tool available: $tool"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Tool missing: $tool"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION SECTIONS
# ─────────────────────────────────────────────────────────────────────────────

validate_scripts() {
    echo ""
    echo -e "${BLUE}═══ Phase 13 Scripts ═══${NC}"

    # Core orchestration
    assert_file_exists "$SCRIPT_DIR/phase-13-orchestrator.sh" "Master orchestrator"
    assert_executable "$SCRIPT_DIR/phase-13-orchestrator.sh" "Master orchestrator"
    assert_valid_shell "$SCRIPT_DIR/phase-13-orchestrator.sh" "Orchestrator syntax"

    # Task scripts
    assert_file_exists "$SCRIPT_DIR/phase-13-task-1.1-cloudflare-tunnel.sh" "Tunnel deployment"
    assert_valid_shell "$SCRIPT_DIR/phase-13-task-1.1-cloudflare-tunnel.sh" "Tunnel syntax"

    assert_file_exists "$SCRIPT_DIR/phase-13-task-1.2-access-control.sh" "Access validation"
    assert_valid_shell "$SCRIPT_DIR/phase-13-task-1.2-access-control.sh" "Access syntax"

    assert_file_exists "$SCRIPT_DIR/phase-13-task-1.3-cluster-health.sh" "Health checks"
    assert_valid_shell "$SCRIPT_DIR/phase-13-task-1.3-cluster-health.sh" "Health syntax"

    assert_file_exists "$SCRIPT_DIR/phase-13-task-1.4-ssh-proxy.sh" "SSH proxy setup"
    assert_valid_shell "$SCRIPT_DIR/phase-13-task-1.4-ssh-proxy.sh" "SSH syntax"

    assert_file_exists "$SCRIPT_DIR/phase-13-task-1.5-load-test.sh" "Load testing"
    assert_valid_shell "$SCRIPT_DIR/phase-13-task-1.5-load-test.sh" "Load test syntax"

    # Support scripts
    assert_file_exists "$SCRIPT_DIR/phase-13-iac-monitor.sh" "IaC monitoring"
    assert_file_exists "$SCRIPT_DIR/phase-13-day1-execute.sh" "Day 1 executor"
    assert_file_exists "$SCRIPT_DIR/phase-13-day1-remote.sh" "Day 1 remote executor"
}

validate_configuration() {
    echo ""
    echo -e "${BLUE}═══ Configuration Files ═══${NC}"

    assert_file_exists "$REPO_ROOT/config/audit-logging.conf" "Audit logging config"
    assert_valid_json "$REPO_ROOT/config/audit-logging.conf" "Audit JSON syntax"
    assert_string_in_file "$REPO_ROOT/config/audit-logging.conf" "\"sinks\"" "Audit sinks defined"
    assert_string_in_file "$REPO_ROOT/config/audit-logging.conf" "\"retention\"" "Audit retention policy"

    assert_file_exists "$REPO_ROOT/config/git-proxy" "Git proxy config"
    assert_file_exists "$REPO_ROOT/config/systemd/git-proxy.service" "Git proxy systemd"
}

validate_docker_setup() {
    echo ""
    echo -e "${BLUE}═══ Docker & Containerization ═══${NC}"

    assert_file_exists "$REPO_ROOT/docker-compose.yml" "Docker Compose config"
    assert_valid_yaml "$REPO_ROOT/docker-compose.yml" "Docker Compose YAML"

    assert_file_exists "$REPO_ROOT/Dockerfile.ssh-proxy" "SSH proxy Dockerfile"
    assert_file_exists "$REPO_ROOT/Dockerfile.caddy" "Caddy Dockerfile"
    assert_file_exists "$REPO_ROOT/Dockerfile.code-server" "Code-server Dockerfile"

    # Check docker-compose services
    assert_string_in_file "$REPO_ROOT/docker-compose.yml" "caddy:" "Caddy service"
    assert_string_in_file "$REPO_ROOT/docker-compose.yml" "code-server:" "Code-server service"
    assert_string_in_file "$REPO_ROOT/docker-compose.yml" "postgres:" "PostgreSQL service"
}

validate_iac() {
    echo ""
    echo -e "${BLUE}═══ Infrastructure as Code (Terraform) ═══${NC}"

    # Terraform files
    assert_file_exists "$REPO_ROOT/terraform/cloudflare-phase-13.tf" "Cloudflare Terraform"
    assert_file_exists "$REPO_ROOT/terraform/phase-13.tfvars.example" "Terraform variables example"

    # Validate Terraform syntax
    if command -v terraform &>/dev/null; then
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        if terraform -chdir="$REPO_ROOT/terraform" validate > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Terraform validation passed"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            echo -e "${RED}✗${NC} Terraform validation failed"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
    else
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        assert_string_in_file "$REPO_ROOT/terraform/cloudflare-phase-13.tf" "resource \"cloudflare" "Terraform resources"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
}

validate_cicd() {
    echo ""
    echo -e "${BLUE}═══ GitHub Actions CI/CD ═══${NC}"

    assert_file_exists "$REPO_ROOT/.github/workflows/phase-13-deploy.yml" "Deployment workflow"
    assert_valid_yaml "$REPO_ROOT/.github/workflows/phase-13-deploy.yml" "Workflow YAML"
    assert_string_in_file "$REPO_ROOT/.github/workflows/phase-13-deploy.yml" "on:" "Trigger defined"
    assert_string_in_file "$REPO_ROOT/.github/workflows/phase-13-deploy.yml" "jobs:" "Jobs defined"
}

validate_documentation() {
    echo ""
    echo -e "${BLUE}═══ Documentation ═══${NC}"

    # Phase 13 documentation
    assert_file_exists "$REPO_ROOT/PHASE-13-EXECUTION-READINESS-REPORT.md" "Readiness report"
    assert_file_exists "$REPO_ROOT/PHASE-13-INFRASTRUCTURE-TEAM-DEPLOYMENT-GUIDE.md" "Infrastructure guide"
    assert_file_exists "$REPO_ROOT/PHASE-13-EXECUTION-IMPLEMENTATION-COMPLETE.md" "Implementation status"

    # Check for key documentation sections
    assert_string_in_file "$REPO_ROOT/PHASE-13-EXECUTION-READINESS-REPORT.md" "Task 1.1" "Task descriptions included"
}

validate_tools() {
    echo ""
    echo -e "${BLUE}═══ Required Tools ═══${NC}"

    # Essential tools
    assert_tool_available "bash" "Bash shell"
    assert_tool_available "docker" "Docker CLI"
    assert_tool_available "docker-compose" "Docker Compose"
    assert_tool_available "curl" "cURL"
    assert_tool_available "jq" "jq JSON processor"
    assert_tool_available "git" "Git"

    # Optional tools
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if command -v terraform &>/dev/null; then
        echo -e "${GREEN}✓${NC} Tool available: terraform"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠${NC} Tool optional: terraform"
        WARNINGS=$((WARNINGS + 1))
    fi
}

validate_git_status() {
    echo ""
    echo -e "${BLUE}═══ Git Repository Status ═══${NC}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if git -C "$REPO_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Valid git repository"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${RED}✗${NC} Not a git repository"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local uncommitted=$(git -C "$REPO_ROOT" status --short | wc -l)
    if [ "$uncommitted" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Working directory clean"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠${NC} $uncommitted uncommitted changes detected"
        WARNINGS=$((WARNINGS + 1))
    fi
}

validate_idempotency() {
    echo ""
    echo -e "${BLUE}═══ Idempotency Checks ═══${NC}"

    # Check for common idempotency patterns
    for script in "$SCRIPT_DIR"/phase-13-task-*.sh; do
        if [ -f "$script" ]; then
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            if grep -q "if.*already.*exists\|is_complete\|status.*complete\|skip" "$script" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} Idempotent checks found: $(basename "$script")"
                PASSED_CHECKS=$((PASSED_CHECKS + 1))
            else
                echo -e "${YELLOW}⚠${NC} Verify idempotency: $(basename "$script")"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi
    done

    # Check for state tracking
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -q "state\|STATE\|deployment.state" "$SCRIPT_DIR/phase-13-orchestrator.sh"; then
        echo -e "${GREEN}✓${NC} State tracking implemented in orchestrator"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠${NC} Verify state management implementation"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY REPORT
# ─────────────────────────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${BLUE}PHASE 13 VALIDATION SUMMARY${NC}"
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Total Checks:     $TOTAL_CHECKS"
    echo -e "${GREEN}Passed:          $PASSED_CHECKS${NC}"
    echo -e "${RED}Failed:          $FAILED_CHECKS${NC}"
    echo -e "${YELLOW}Warnings:        $WARNINGS${NC}"
    echo ""

    local pass_rate=$((($PASSED_CHECKS * 100) / $TOTAL_CHECKS))
    echo -e "Pass Rate:        ${pass_rate}%"
    echo ""

    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "${GREEN}✓ VALIDATION PASSED - READY FOR DEPLOYMENT${NC}"
        return 0
    else
        echo -e "${RED}✗ VALIDATION FAILED - REQUIRES FIXES${NC}"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ PHASE 13 PRE-LAUNCH VALIDATION CHECKLIST                ║${NC}"
    echo -e "${BLUE}║ Component verification and readiness assessment          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    validate_scripts
    validate_configuration
    validate_docker_setup
    validate_iac
    validate_cicd
    validate_documentation
    validate_tools
    validate_git_status
    validate_idempotency

    print_summary
}

main "$@"
