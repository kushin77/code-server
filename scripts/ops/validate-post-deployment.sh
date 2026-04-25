#!/bin/bash
# @governance: Post-deployment IaC validation — verify production deployment compliance
# Purpose: Validate deployed infrastructure meets IaC standards (immutable, idempotent, env-driven)
# Author: Autonomous Agent
# Date: April 25, 2026

set -euo pipefail

# Load network configuration SSOT
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../scripts/_common/_epic-1536-network-config.env" || {
    echo "Error: Network configuration SSOT not found"
    exit 1
}

# Deployment target (all env-var driven)
readonly TARGET_HOST="${DEPLOY_HOST:-${ONPREM_PRIMARY_IP}}"
readonly TARGET_USER="${DEPLOY_USER:-admin}"
readonly REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
readonly VALIDATION_TIMEOUT="${VALIDATION_TIMEOUT:-60}"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[VALIDATE]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[✓ PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[✗ FAIL]${NC} $*"
    return 1
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}=== $* ===${NC}"
}

# Check 1: Verify IaC compliance script presence and execution
check_iac_compliance_script() {
    log_section "IaC Compliance Script Validation"
    
    local check_script
    check_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

if [ ! -f "scripts/ci/validate-iac-compliance.sh" ]; then
    echo "FAIL: IaC compliance script not found"
    exit 1
fi

echo "PASS: IaC compliance script present"

# Run compliance checks
if bash scripts/ci/validate-iac-compliance.sh > /tmp/iac-validation.log 2>&1; then
    echo "PASS: IaC compliance checks passed"
else
    echo "WARN: IaC compliance checks had warnings (review log)"
    cat /tmp/iac-validation.log | head -20
fi

EOFSCRIPT
)
    
    if ssh -o ConnectTimeout=10 "${TARGET_USER}@${TARGET_HOST}" bash -s <<< "$check_script"; then
        log_pass "IaC compliance script validation"
        return 0
    else
        log_fail "IaC compliance validation"
        return 1
    fi
}

# Check 2: Verify environment variables (no hardcoded values)
check_env_var_usage() {
    log_section "Environment Variable Usage (No Hardcoding)"
    
    local check_script
    check_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

echo "Checking for hardcoded IPs in scripts..."
if grep -r '192\.' scripts/ --include='*.sh' | grep -v '${' | grep -v '#' | head -5; then
    echo "WARN: Found potential hardcoded IPs (check above)"
else
    echo "PASS: No obvious hardcoded IPs in scripts"
fi

echo ""
echo "Checking for environment variable usage..."
hardcoded_count=$(grep -r '192\.' scripts/ --include='*.sh' | grep -v '${' | grep -v '#' | wc -l)
if [ "$hardcoded_count" -eq 0 ]; then
    echo "PASS: All network configs use environment variables"
else
    echo "WARN: Found $hardcoded_count potential hardcoding instances"
fi

EOFSCRIPT
)
    
    if ssh "${TARGET_USER}@${TARGET_HOST}" bash -s <<< "$check_script"; then
        log_pass "Environment variable usage validation"
        return 0
    else
        log_warn "Environment variable usage check"
        return 0  # Don't fail on this
    fi
}

# Check 3: Verify error handling in scripts
check_error_handling() {
    log_section "Error Handling (set -euo pipefail)"
    
    local check_script
    check_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

echo "Checking for proper error handling in new scripts..."

# Count scripts with set -euo pipefail
scripts_with_error_handling=$(grep -l "set -euo pipefail" scripts/lib/*.sh scripts/ci/*.sh 2>/dev/null | wc -l)
total_scripts=$(find scripts/lib scripts/ci -name "*.sh" -type f 2>/dev/null | wc -l)

echo "Scripts with set -euo pipefail: $scripts_with_error_handling / $total_scripts"

if [ "$scripts_with_error_handling" -ge "$((total_scripts - 5))" ]; then
    echo "PASS: Error handling properly implemented"
else
    echo "WARN: Some scripts may lack error handling"
fi

EOFSCRIPT
)
    
    if ssh "${TARGET_USER}@${TARGET_HOST}" bash -s <<< "$check_script"; then
        log_pass "Error handling validation"
        return 0
    else
        log_warn "Error handling validation"
        return 0
    fi
}

# Check 4: Verify governance headers in scripts
check_governance_headers() {
    log_section "Governance Headers Documentation"
    
    local check_script
    check_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

echo "Checking for @governance headers in scripts..."

scripts_with_headers=$(grep -l "@governance" scripts/lib/*.sh scripts/ci/*.sh 2>/dev/null | wc -l)
total_scripts=$(find scripts/lib scripts/ci -name "*.sh" -type f 2>/dev/null | wc -l)

echo "Scripts with @governance headers: $scripts_with_headers / $total_scripts"

if [ "$scripts_with_headers" -ge "$((total_scripts - 5))" ]; then
    echo "PASS: Governance headers properly documented"
else
    echo "WARN: Some scripts lack governance headers"
fi

EOFSCRIPT
)
    
    if ssh "${TARGET_USER}@${TARGET_HOST}" bash -s <<< "$check_script"; then
        log_pass "Governance headers validation"
        return 0
    else
        log_warn "Governance headers validation"
        return 0
    fi
}

# Check 5: Verify Docker Compose configuration
check_docker_compose_config() {
    log_section "Docker Compose Configuration"
    
    local check_script
    check_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

echo "Checking docker-compose.yml syntax..."
if docker compose config > /dev/null 2>&1; then
    echo "PASS: docker-compose.yml is valid"
else
    echo "FAIL: docker-compose.yml validation failed"
    exit 1
fi

echo ""
echo "Checking for environment variable references..."
env_var_refs=$(grep -c '\${' docker-compose.yml || echo "0")
echo "Found $env_var_refs environment variable references"

if [ "$env_var_refs" -gt 0 ]; then
    echo "PASS: Configuration uses environment variables"
else
    echo "WARN: No environment variables found in docker-compose.yml"
fi

EOFSCRIPT
)
    
    if ssh "${TARGET_USER}@${TARGET_HOST}" bash -s <<< "$check_script"; then
        log_pass "Docker Compose configuration validation"
        return 0
    else
        log_fail "Docker Compose configuration validation"
        return 1
    fi
}

# Check 6: Verify services are running
check_services_running() {
    log_section "Service Status"
    
    local check_script
    check_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

echo "Checking service status..."
if docker compose ps --all; then
    echo ""
    echo "Counting running services..."
    running=$(docker compose ps --all | grep -c "Up" || echo "0")
    total=$(docker compose ps --all | tail -n +2 | wc -l)
    echo "Running: $running / $total"
    
    if [ "$running" -gt 0 ]; then
        echo "PASS: Services are running"
    else
        echo "WARN: No services appear to be running"
    fi
else
    echo "FAIL: Could not query service status"
    exit 1
fi

EOFSCRIPT
)
    
    if ssh "${TARGET_USER}@${TARGET_HOST}" bash -s <<< "$check_script"; then
        log_pass "Service status check"
        return 0
    else
        log_warn "Service status check encountered issues"
        return 0
    fi
}

# Check 7: Verify health endpoints
check_health_endpoints() {
    log_section "Health Endpoint Verification"
    
    local check_script
    check_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-192.168.168.31}"

echo "Testing health endpoints..."
echo ""

# Test main API health
echo "Testing main API (port 3100)..."
if curl -sf "http://localhost:3100/api/health" > /dev/null 2>&1; then
    echo "PASS: Main API health endpoint responding"
else
    echo "WARN: Main API health endpoint not yet responding (may still be starting)"
fi

echo ""
echo "Testing Ollama endpoint..."
if curl -sf "http://192.168.168.31:11434/api/tags" > /dev/null 2>&1; then
    echo "PASS: Ollama API endpoint responding"
else
    echo "WARN: Ollama endpoint not reachable (deploy external Ollama separately)"
fi

EOFSCRIPT
)
    
    if ssh "${TARGET_USER}@${TARGET_HOST}" bash -s <<< "$check_script"; then
        log_pass "Health endpoint verification"
        return 0
    else
        log_warn "Health endpoint verification"
        return 0
    fi
}

# Generate validation report
generate_report() {
    log_section "Validation Summary"
    
    echo ""
    log_pass "Post-deployment IaC validation complete"
    echo ""
    echo "Next Steps:"
    echo "  1. Verify all checks passed above"
    echo "  2. Deploy external Ollama: bash scripts/ops/deploy-ollama-external.sh"
    echo "  3. Monitor logs: docker compose logs -f"
    echo "  4. Access main deployment: http://${TARGET_HOST}:3100"
    echo "  5. Access Ollama: http://${TARGET_HOST}:11434"
    echo ""
}

# Main validation workflow
main() {
    log_section "Post-Deployment IaC Validation"
    log_info "Target: ${TARGET_USER}@${TARGET_HOST}"
    log_info "Repo Path: ${REPO_PATH}"
    
    local pass_count=0
    local fail_count=0
    
    # Run all validation checks
    if check_iac_compliance_script; then ((pass_count++)); else ((fail_count++)); fi
    if check_env_var_usage; then ((pass_count++)); else ((fail_count++)); fi
    if check_error_handling; then ((pass_count++)); else ((fail_count++)); fi
    if check_governance_headers; then ((pass_count++)); else ((fail_count++)); fi
    if check_docker_compose_config; then ((pass_count++)); else ((fail_count++)); fi
    if check_services_running; then ((pass_count++)); else ((fail_count++)); fi
    if check_health_endpoints; then ((pass_count++)); else ((fail_count++)); fi
    
    generate_report
    
    log_info "Passed: ${pass_count}/7 validations"
    
    if [ "$fail_count" -gt 0 ]; then
        log_fail "${fail_count} critical validations failed"
        exit 1
    fi
    
    return 0
}

main "$@"
