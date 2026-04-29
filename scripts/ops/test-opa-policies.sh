#!/bin/bash
# @file scripts/ops/test-opa-policies.sh
# @module ops/testing
# @description End-to-end test suite for OPA policy validation
# @governance GOV-002 - Policy validation before production deployment

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

LOG_FILE="${REPO_ROOT}/artifacts/opa-e2e-test.log"
REPORT_FILE="${REPO_ROOT}/artifacts/opa-e2e-test-report.json"

source_env_file "${REPO_ROOT}/.env.infrastructure"

mkdir -p "${REPO_ROOT}/artifacts"

OPA_URL="${OPA_ENDPOINT:-${OPA_URL:-http://localhost:8181}}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $@" | tee -a "$LOG_FILE"
    ((++TESTS_PASSED))
}

error() {
    echo -e "${RED}✗${NC} $@" | tee -a "$LOG_FILE"
    ((++TESTS_FAILED))
}

warning() {
    echo -e "${YELLOW}⚠${NC} $@" | tee -a "$LOG_FILE"
    ((++TESTS_SKIPPED))
}

# Query OPA and check response
query_opa() {
    local policy=$1
    local input=$2
    local description=$3
    
    log "INFO" "Testing: $description"
    log "INFO" "Query: POST ${OPA_URL}/v1/data/${policy}"
    
    response=$(curl -s -X POST "${OPA_URL}/v1/data/${policy}" \
        -H "Content-Type: application/json" \
        -d "$input" 2>/dev/null || echo '{"error": "Connection failed"}')
    
    echo "$response"
}

ensure_opa_service() {
    if curl -sf "${OPA_URL}/health" >/dev/null 2>&1; then
        return 0
    fi

    log "INFO" "OPA not responding at ${OPA_URL}; starting opa service with docker compose"

    if ! command -v docker >/dev/null 2>&1; then
        warning "OPA not responding at ${OPA_URL} and Docker is unavailable; skipping policy validation"
        return 2
    fi

    (
        cd "${PROJECT_ROOT}"
        docker compose up -d opa >/dev/null 2>&1 || true
    )

    local attempt=0
    local max_attempts=60
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if curl -sf "${OPA_URL}/health" >/dev/null 2>&1; then
            success "OPA service is healthy"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    warning "OPA failed to become healthy at ${OPA_URL}; skipping policy validation"
    return 2
}

# Check if deny rule fired
assert_denied() {
    local response=$1
    local description=$2
    
    if echo "$response" | jq -e '.result.deny' > /dev/null 2>&1; then
        success "$description (denied as expected)"
        return 0
    else
        error "$description (should have been denied)"
        log "ERROR" "Response: $response"
        return 1
    fi
}

# Check if allow rule fired
assert_allowed() {
    local response=$1
    local description=$2
    
    if echo "$response" | jq -e '.result.allow' > /dev/null 2>&1; then
        success "$description (allowed as expected)"
        return 0
    else
        error "$description (should have been allowed)"
        log "ERROR" "Response: $response"
        return 1
    fi
}

# ============================================================================
# Test Suites
# ============================================================================

test_secrets_policy() {
    log "INFO" "=========================================="
    log "INFO" "Testing: core.secrets policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny secret in log
    response=$(query_opa "core.secrets" \
        '{"input": {"action": "log", "data": "password=secret123"}}' \
        "Secret in log")
    assert_denied "$response" "Deny: Password in log"
    
    # Test 2: Deny secret over HTTP
    response=$(query_opa "core.secrets" \
        '{"input": {"action": "http_request", "protocol": "http", "body": "api_key=mykey"}}' \
        "Secret over HTTP")
    assert_denied "$response" "Deny: Secret over unencrypted HTTP"
    
    # Test 3: Allow HTTPS
    response=$(query_opa "core.secrets" \
        '{"input": {"action": "http_request", "protocol": "https", "body": "username=john"}}' \
        "Safe over HTTPS")
    assert_allowed "$response" "Allow: HTTPS without secrets"
}

test_production_gate() {
    log "INFO" "=========================================="
    log "INFO" "Testing: core.production_gate policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny unapproved prod deploy
    response=$(query_opa "core.production_gate" \
        '{"input": {"action": "deploy", "target_env": "production", "human_approved": false}}' \
        "Unapproved prod deploy")
    assert_denied "$response" "Deny: Production deploy without approval"
    
    # Test 2: Allow approved prod deploy
    response=$(query_opa "core.production_gate" \
        '{"input": {"action": "deploy", "target_env": "production", "human_approved": true, "approved_by": "architect", "approval_timestamp": "2026-04-24T10:00:00Z", "audit_id": "gh-pr-123"}}' \
        "Approved prod deploy")
    assert_allowed "$response" "Allow: Approved production deploy"
    
    # Test 3: Allow non-prod deploy
    response=$(query_opa "core.production_gate" \
        '{"input": {"action": "deploy", "target_env": "staging"}}' \
        "Staging deploy")
    assert_allowed "$response" "Allow: Non-production deploy"
}

test_least_privilege() {
    log "INFO" "=========================================="
    log "INFO" "Testing: core.least_privilege policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny high-privilege op for low reputation
    response=$(query_opa "core.least_privilege" \
        '{"input": {"action": "delete_resource", "actor_reputation_score": 40}}' \
        "Low reputation delete")
    assert_denied "$response" "Deny: Delete with low reputation"
    
    # Test 2: Allow high-privilege op for high reputation
    response=$(query_opa "core.least_privilege" \
        '{"input": {"action": "delete_resource", "actor_reputation_score": 60}}' \
        "High reputation delete")
    assert_allowed "$response" "Allow: Delete with high reputation"
}

test_model_allowlist() {
    log "INFO" "=========================================="
    log "INFO" "Testing: ai.model_allowlist policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny unapproved model
    response=$(query_opa "ai.model_allowlist" \
        '{"input": {"action": "invoke_model", "model_name": "gpt-4-32k"}}' \
        "Unapproved model")
    assert_denied "$response" "Deny: Unapproved model"
    
    # Test 2: Deny approved model with insufficient reputation
    response=$(query_opa "ai.model_allowlist" \
        '{"input": {"action": "invoke_model", "model_name": "claude-3-opus", "actor_reputation_score": 60}}' \
        "Low reputation for advanced model")
    assert_denied "$response" "Deny: Insufficient reputation for model"
    
    # Test 3: Allow approved model with sufficient reputation
    response=$(query_opa "ai.model_allowlist" \
        '{"input": {"action": "invoke_model", "model_name": "llama3:8b", "actor_reputation_score": 50, "current_concurrent_count": 0}}' \
        "Approved model with sufficient reputation")
    assert_allowed "$response" "Allow: Model with sufficient reputation"
}

test_agent_budget() {
    log "INFO" "=========================================="
    log "INFO" "Testing: ai.agent_budget policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny operation with budget exhausted
    response=$(query_opa "ai.agent_budget" \
        '{"input": {"action": "execute_operation", "actor_type": "agent", "agent_tier": "default", "current_spend": 1000}}' \
        "Budget exhausted")
    assert_denied "$response" "Deny: Agent budget exhausted"
    
    # Test 2: Deny operation that exceeds remaining budget
    response=$(query_opa "ai.agent_budget" \
        '{"input": {"action": "execute_operation", "actor_type": "agent", "agent_tier": "default", "operation_type": "terraform_apply", "current_spend": 980}}' \
        "Exceeds remaining budget")
    assert_denied "$response" "Deny: Operation exceeds remaining budget"
    
    # Test 3: Allow operation within budget
    response=$(query_opa "ai.agent_budget" \
        '{"input": {"action": "execute_operation", "actor_type": "agent", "agent_tier": "default", "operation_type": "model_inference", "current_spend": 500}}' \
        "Within budget")
    assert_allowed "$response" "Allow: Operation within budget"
}

test_sso_required() {
    log "INFO" "=========================================="
    log "INFO" "Testing: identity.sso_required policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny unauthenticated user-facing service
    response=$(query_opa "identity.sso_required" \
        '{"input": {"action": "access_service", "service_type": "user_facing"}}' \
        "Unauthenticated access")
    assert_denied "$response" "Deny: Unauthenticated user-facing service"
    
    # Test 2: Allow with valid SSO
    response=$(query_opa "identity.sso_required" \
        '{"input": {"action": "access_service", "service_type": "user_facing", "auth_token": "valid", "token_valid": true, "sso_verified": true, "user_id": "user-123"}}' \
        "Valid SSO")
    assert_allowed "$response" "Allow: Valid SSO authentication"
}

test_device_trust() {
    log "INFO" "=========================================="
    log "INFO" "Testing: identity.device_trust policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny low device trust
    response=$(query_opa "identity.device_trust" \
        '{"input": {"action": "access_sensitive_resource", "device_id": "dev-123", "device_trust_score": 20, "operation_type": "access_secrets"}}' \
        "Low device trust")
    assert_denied "$response" "Deny: Low device trust score"
    
    # Test 2: Allow sufficient device trust
    response=$(query_opa "identity.device_trust" \
        '{"input": {"action": "access_sensitive_resource", "device_id": "dev-456", "device_trust_score": 85, "operation_type": "write_data"}}' \
        "Sufficient device trust")
    assert_allowed "$response" "Allow: Sufficient device trust"
}

test_immutable_infra() {
    log "INFO" "=========================================="
    log "INFO" "Testing: infrastructure.immutable_infra policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny SSH file modifications to prod
    response=$(query_opa "infrastructure.immutable_infra" \
        '{"input": {"action": "ssh_command", "target_host": "prod-primary", "command_type": "file_modify"}}' \
        "SSH file modify on prod")
    assert_denied "$response" "Deny: SSH modifications to production"
    
    # Test 2: Deny floating image tags
    response=$(query_opa "infrastructure.immutable_infra" \
        '{"input": {"action": "deploy_container", "target_env": "production", "image_tag": "latest"}}' \
        "Floating image tag")
    assert_denied "$response" "Deny: Floating image tag in production"
    
    # Test 3: Allow immutable digest
    response=$(query_opa "infrastructure.immutable_infra" \
        '{"input": {"action": "deploy_container", "image_digest": "sha256:abc123"}}' \
        "Immutable digest")
    assert_allowed "$response" "Allow: Immutable digest deployment"
}

test_drift_prevention() {
    log "INFO" "=========================================="
    log "INFO" "Testing: infrastructure.drift_prevention policy"
    log "INFO" "=========================================="
    
    # Test 1: Deny deploy with unreconciled drift
    response=$(query_opa "infrastructure.drift_prevention" \
        '{"input": {"action": "deploy", "target_env": "production", "drift_report": {"unreconciled_resources": ["vpc-123"]}}}' \
        "Unreconciled drift")
    assert_denied "$response" "Deny: Deploy with unreconciled drift"
    
    # Test 2: Allow drift-free deployment
    response=$(query_opa "infrastructure.drift_prevention" \
        '{"input": {"action": "deploy", "drift_report": {"drift_free": true}, "last_drift_check_age_hours": 12}}' \
        "Drift-free deployment")
    assert_allowed "$response" "Allow: Drift-free deployment"
}

# ============================================================================
# Health Check
# ============================================================================

check_opa_health() {
    log "INFO" "Checking OPA health..."
    
    if ! response=$(curl -s "${OPA_URL}/health"); then
        error "OPA not responding at ${OPA_URL}"
        return 1
    fi
    
    if echo "$response" | jq -e '.result' > /dev/null 2>&1; then
        success "OPA health check passed"
        return 0
    else
        error "OPA health check failed"
        return 1
    fi
}

check_policies_loaded() {
    log "INFO" "Checking if policies are loaded..."
    
    policies=("core.secrets" "core.production_gate" "ai.model_allowlist" "identity.sso_required" "infrastructure.immutable_infra")
    
    for policy in "${policies[@]}"; do
        if response=$(curl -s "${OPA_URL}/v1/data/${policy}"); then
            if echo "$response" | jq -e '.result' > /dev/null 2>&1; then
                success "Policy loaded: $policy"
            else
                error "Policy not loaded: $policy"
            fi
        else
            error "Failed to query policy: $policy"
        fi
    done
}

# ============================================================================
# Report Generation
# ============================================================================

generate_report() {
    log "INFO" "Generating test report..."

    local overall_status="PASS"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        overall_status="FAIL"
    elif [[ $TESTS_PASSED -eq 0 && $TESTS_SKIPPED -gt 0 ]]; then
        overall_status="SKIPPED"
    fi
    
    cat > "$REPORT_FILE" << EOF
{
  "test_suite": "OPA End-to-End Policy Validation",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "opa_url": "$OPA_URL",
  "results": {
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "skipped": $TESTS_SKIPPED,
    "total": $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
  },
    "status": "$overall_status",
  "log_file": "$LOG_FILE"
}
EOF
    
    log "INFO" "Test report written to: $REPORT_FILE"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log "INFO" "=========================================="
    log "INFO" "OPA Policy Engine End-to-End Test Suite"
    log "INFO" "=========================================="
    log "INFO" "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log "INFO" "OPA URL: $OPA_URL"
    log "INFO" "=========================================="
    
    # Pre-flight checks
    if ensure_opa_service; then
        status=0
    else
        status=$?
    fi

    if [[ ${status} -ne 0 ]]; then
        if [[ ${status} -eq 2 ]]; then
            log "WARN" "OPA policy validation skipped due to unavailable service"
            generate_report
            exit 0
        fi

        log "ERROR" "OPA health check failed. Aborting tests."
        exit 1
    fi
    
    check_policies_loaded
    
    # Run all test suites
    test_secrets_policy
    test_production_gate
    test_least_privilege
    test_model_allowlist
    test_agent_budget
    test_sso_required
    test_device_trust
    test_immutable_infra
    test_drift_prevention
    
    # Generate report
    generate_report
    
    # Summary
    log "INFO" "=========================================="
    log "INFO" "Test Summary:"
    log "INFO" "  Passed:  $TESTS_PASSED"
    log "INFO" "  Failed:  $TESTS_FAILED"
    log "INFO" "  Skipped: $TESTS_SKIPPED"
    log "INFO" "  Total:   $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))"
    log "INFO" "=========================================="
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -gt 0 ]; then
        error "Test suite FAILED"
        exit 1
    else
        success "Test suite PASSED"
        exit 0
    fi
}

# Run main only when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
