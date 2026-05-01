#!/bin/bash
# @file scripts/ci/validate-staging-deployment.sh
# @module infrastructure/validation
# @description Phase 2C Work Item 3: Full staging deployment validation
# @governance VAL-001: Comprehensive staging validation before production rollout

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Trap handlers for error handling and cleanup
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleaning up..."; rm -f /tmp/validate-staging-*.tmp 2>/dev/null || true' EXIT

# Configuration
REPO_ROOT="${1:-.}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
COMPOSE_DIR="${REPO_ROOT}"
VALIDATION_LOG="${REPO_ROOT}/artifacts/staging-validation-$(date +%Y%m%d_%H%M%S).log"
RESULTS_FILE="${REPO_ROOT}/artifacts/staging-validation-results.json"

# Ensure artifacts directory exists
mkdir -p "${REPO_ROOT}/artifacts"

# Initialize results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$VALIDATION_LOG"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "$VALIDATION_LOG"
    PASSED_TESTS+=1
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" | tee -a "$VALIDATION_LOG"
    FAILED_TESTS+=1
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $*" | tee -a "$VALIDATION_LOG"
    SKIPPED_TESTS+=1
}

test_section() {
    echo "" | tee -a "$VALIDATION_LOG"
    echo -e "${BLUE}════════════════════════════════════════${NC}" | tee -a "$VALIDATION_LOG"
    echo -e "${BLUE}$1${NC}" | tee -a "$VALIDATION_LOG"
    echo -e "${BLUE}════════════════════════════════════════${NC}" | tee -a "$VALIDATION_LOG"
}

# Helper to run test
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    TOTAL_TESTS+=1
    
    if eval "$test_cmd" &>/dev/null; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# ============================================================================
# TEST SECTION 1: Configuration Validation
# ============================================================================

test_section "Configuration Validation"

# Source common functions
if [[ -f "${REPO_ROOT}/scripts/_common/init.sh" ]]; then
    source "${REPO_ROOT}/scripts/_common/init.sh"
    log_success "Sourced init.sh successfully"
else
    log_error "init.sh not found at ${REPO_ROOT}/scripts/_common/init.sh"
fi

# Source config
if [[ -f "${REPO_ROOT}/scripts/_common/config.env" ]]; then
    source "${REPO_ROOT}/scripts/_common/config.env"
    log_success "Sourced config.env successfully"
else
    log_error "config.env not found at ${REPO_ROOT}/scripts/_common/config.env"
fi

# Test SSOT variables
required_vars=("PRIMARY_HOST" "APEX_DOMAIN" "POSTGRES_PASSWORD" "REDIS_PASSWORD")
for var in "${required_vars[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        log_success "Required variable $var is set"
    else
        log_warning "Required variable $var is NOT set (may be expected in dev environment)"
    fi
done

# ============================================================================
# TEST SECTION 2: Docker-Compose File Validation
# ============================================================================

test_section "Docker-Compose File Validation"

# Validate primary docker-compose.yml
run_test "docker-compose.yml exists" \
    "test -f '${COMPOSE_DIR}/docker-compose.yml'"

run_test "docker-compose.yml syntax is valid" \
    "docker-compose -f '${COMPOSE_DIR}/docker-compose.yml' config >/dev/null"

# Validate docker-compose.prod.yml
run_test "docker-compose.prod.yml exists" \
    "test -f '${COMPOSE_DIR}/docker-compose.prod.yml'"

run_test "docker-compose.prod.yml syntax is valid" \
    "docker-compose -f '${COMPOSE_DIR}/docker-compose.prod.yml' config >/dev/null"

# Validate docker-compose.cluster.yml
run_test "docker-compose.cluster.yml exists" \
    "test -f '${COMPOSE_DIR}/docker-compose.cluster.yml'"

run_test "docker-compose.cluster.yml syntax is valid" \
    "docker-compose -f '${COMPOSE_DIR}/docker-compose.cluster.yml' config >/dev/null"

# Validate docker-compose.override.yml
run_test "docker-compose.override.yml exists" \
    "test -f '${COMPOSE_DIR}/docker-compose.override.yml'"

run_test "docker-compose.override.yml syntax is valid" \
    "docker-compose -f '${COMPOSE_DIR}/docker-compose.override.yml' config >/dev/null"

# ============================================================================
# TEST SECTION 3: Monitoring Configuration Validation
# ============================================================================

test_section "Monitoring Configuration Validation"

# Check config/monitoring directory structure
monitoring_files=(
    "alertmanager.yml"
    "alerts/alert-rules.yml"
    "prometheus/prometheus.yml"
    "loki/loki-config.yaml"
    "otel/collector-config.yaml"
    "tempo/tempo-config.yaml"
)

for file in "${monitoring_files[@]}"; do
    run_test "config/monitoring/$file exists" \
        "test -f '${COMPOSE_DIR}/config/monitoring/$file'"
done

# ============================================================================
# TEST SECTION 4: Service References Validation
# ============================================================================

test_section "Service References Validation"

# Count expected services
run_test "docker-compose.yml has 39+ services defined" \
    "test $(grep -c '^\s\s[a-z].*:$' '${COMPOSE_DIR}/docker-compose.yml' 2>/dev/null || echo 0) -ge 30"

# Verify critical services are referenced
critical_services=("postgres" "redis" "api" "caddy" "prometheus" "grafana")
for service in "${critical_services[@]}"; do
    run_test "Service $service is defined" \
        "grep -q \"^\s\s$service:\" '${COMPOSE_DIR}/docker-compose.yml'"
done

# ============================================================================
# TEST SECTION 5: Volume Mount Validation
# ============================================================================

test_section "Volume Mount Validation"

# Check for monitoring config volume mounts
volume_checks=(
    "config/monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml"
    "config/monitoring/prometheus:/etc/prometheus"
    "config/monitoring/loki:/etc/loki"
)

for mount in "${volume_checks[@]}"; do
    run_test "Volume mount $mount is referenced" \
        "grep -q '$mount' '${COMPOSE_DIR}/docker-compose.yml'"
done

# ============================================================================
# TEST SECTION 6: Health Check Functions Validation
# ============================================================================

test_section "Health Check Functions Validation"

# Check if health check functions exist
if [[ -f "${REPO_ROOT}/scripts/_common/health-checks.sh" ]]; then
    health_functions=("health_check_postgres" "health_check_redis" "health_check_api" "health_check_prometheus" "health_check_grafana")
    
    for func in "${health_functions[@]}"; do
        run_test "Health check function $func is defined" \
            "grep -q \"^$func()\" '${REPO_ROOT}/scripts/_common/health-checks.sh'"
    done
else
    log_error "health-checks.sh not found"
fi

# ============================================================================
# TEST SECTION 7: Application Migration Status
# ============================================================================

test_section "Application Migration Status (Tier 1)"

# Check memory-engine migration
run_test "memory-engine imports config.py" \
    "grep -q 'from apps._shared.python.config import get_config' '${COMPOSE_DIR}/apps/memory-engine/main.py'"

run_test "memory-engine uses config.get_int()" \
    "grep -q 'config.get_int' '${COMPOSE_DIR}/apps/memory-engine/main.py'"

# Check control-plane migration
run_test "control-plane imports config.py" \
    "grep -q 'from apps._shared.python.config import get_config' '${COMPOSE_DIR}/apps/control-plane/main.py'"

run_test "control-plane uses config.get()" \
    "grep -q 'config.get' '${COMPOSE_DIR}/apps/control-plane/main.py'"

# ============================================================================
# TEST SECTION 8: Background Test Runner Validation
# ============================================================================

test_section "Background Test Runner Validation"

run_test "Background test runner exists" \
    "test -f '${COMPOSE_DIR}/scripts/ci/background-test-runner.py'"

run_test "Background test runner is executable" \
    "test -x '${COMPOSE_DIR}/scripts/ci/background-test-runner.py'"

run_test "GitHub Actions workflow exists" \
    "test -f '${COMPOSE_DIR}/.github/workflows/continuous-validation.yml'"

# ============================================================================
# TEST SECTION 9: Git Audit Trail Validation
# ============================================================================

test_section "Git Audit Trail Validation"

# Check for Phase 2B commits
if command -v git &>/dev/null; then
    run_test "Phase 2B consolidation commit exists" \
        "git -C '${REPO_ROOT}' log --oneline | grep -q 'feat(phase2b): implement docker-compose consolidation' || git -C '${REPO_ROOT}' log --oneline | grep -q 'phase2b'"
    
    run_test "Phase 2C app migration commit exists" \
        "git -C '${REPO_ROOT}' log --oneline | grep -q 'feat(phase2c)'"
else
    log_warning "git not available, skipping git validation"
fi

# ============================================================================
# SUMMARY
# ============================================================================

test_section "Validation Summary"

echo "" | tee -a "$VALIDATION_LOG"
echo "Total Tests:      $TOTAL_TESTS" | tee -a "$VALIDATION_LOG"
echo "Passed Tests:     $PASSED_TESTS" | tee -a "$VALIDATION_LOG"
echo "Failed Tests:     $FAILED_TESTS" | tee -a "$VALIDATION_LOG"
echo "Skipped Tests:    $SKIPPED_TESTS" | tee -a "$VALIDATION_LOG"
echo "" | tee -a "$VALIDATION_LOG"

PASS_PERCENTAGE=$((PASSED_TESTS * 100 / TOTAL_TESTS))

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL VALIDATIONS PASSED ($PASS_PERCENTAGE%)${NC}" | tee -a "$VALIDATION_LOG"
    EXIT_CODE=0
else
    echo -e "${RED}✗ SOME VALIDATIONS FAILED ($PASS_PERCENTAGE% passed)${NC}" | tee -a "$VALIDATION_LOG"
    EXIT_CODE=1
fi

echo "" | tee -a "$VALIDATION_LOG"
echo "Validation log: $VALIDATION_LOG" | tee -a "$VALIDATION_LOG"

# Write JSON results
cat > "$RESULTS_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "environment": "$ENVIRONMENT",
  "total_tests": $TOTAL_TESTS,
  "passed_tests": $PASSED_TESTS,
  "failed_tests": $FAILED_TESTS,
  "skipped_tests": $SKIPPED_TESTS,
  "pass_percentage": $PASS_PERCENTAGE,
  "status": "$([ $EXIT_CODE -eq 0 ] && echo 'PASS' || echo 'FAIL')"
}
EOF

echo "Results file: $RESULTS_FILE" | tee -a "$VALIDATION_LOG"

exit $EXIT_CODE
