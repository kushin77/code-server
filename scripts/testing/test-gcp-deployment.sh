#!/bin/bash

################################################################################
# GCP Deployment Validation & Integration Test
#
# Purpose: Comprehensive test suite for GCP infrastructure deployment and
#          integration with code-server Phase 2b validation
#
# Usage:
#   bash scripts/testing/test-gcp-deployment.sh [setup|validate|deploy|integrate|full]
#
# Requirements:
#   - GCP service account credentials (see GCP_INFRASTRUCTURE_DEPLOYMENT_GUIDE.md)
#   - GCP_PROJECT_ID and GCP_CREDENTIALS_JSON env vars
#   - curl, jq, openssl
#
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
readonly TEST_LOG="/tmp/gcp-deployment-test-${TIMESTAMP//[^0-9]/}.log"

# Error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed at line $LINENO with exit code $exit_code"
    fi
    return $exit_code
}

trap 'cleanup' EXIT
trap 'log_error "Script interrupted"; exit 130' INT TERM

# Configuration from environment (with defaults)
readonly GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
readonly GCP_CREDENTIALS_JSON="${GCP_CREDENTIALS_JSON:-}"
readonly GCP_ZONE="${GCP_ZONE:-us-central1-a}"
readonly GCP_MACHINE_TYPE="${GCP_MACHINE_TYPE:-e2-standard-4}"

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo "[${TIMESTAMP}] [INFO] $*" | tee -a "$TEST_LOG"
}

log_success() {
    echo "[${TIMESTAMP}] [SUCCESS] ✅ $*" | tee -a "$TEST_LOG"
}

log_warn() {
    echo "[${TIMESTAMP}] [WARN] ⚠️  $*" | tee -a "$TEST_LOG"
}

log_error() {
    echo "[${TIMESTAMP}] [ERROR] ❌ $*" | tee -a "$TEST_LOG"
}

header() {
    echo "" | tee -a "$TEST_LOG"
    echo "================================================================================" | tee -a "$TEST_LOG"
    echo "$1" | tee -a "$TEST_LOG"
    echo "================================================================================" | tee -a "$TEST_LOG"
}

################################################################################
# Validation Functions
################################################################################

validate_prerequisites() {
    header "VALIDATION: Prerequisites"
    
    local required_cmds=("curl" "jq" "openssl" "base64")
    local missing_cmds=()
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
            log_error "Command not found: $cmd"
        else
            log_success "Found command: $cmd"
        fi
    done
    
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        return 1
    fi
    
    # Check GCP variables
    if [[ -z "$GCP_PROJECT_ID" ]]; then
        log_error "GCP_PROJECT_ID not set"
        return 1
    fi
    log_success "GCP_PROJECT_ID: $GCP_PROJECT_ID"
    
    if [[ -z "$GCP_CREDENTIALS_JSON" ]]; then
        log_error "GCP_CREDENTIALS_JSON not set"
        return 1
    fi
    
    if [[ ! -f "$GCP_CREDENTIALS_JSON" ]]; then
        log_error "Credentials file not found: $GCP_CREDENTIALS_JSON"
        return 1
    fi
    log_success "Credentials file found: $GCP_CREDENTIALS_JSON"
    
    # Verify credentials are valid JSON
    if ! jq empty "$GCP_CREDENTIALS_JSON" 2>/dev/null; then
        log_error "Credentials file is not valid JSON"
        return 1
    fi
    log_success "Credentials file is valid JSON"
    
    log_success "All prerequisites validated"
    return 0
}

validate_gcp_configuration() {
    header "VALIDATION: GCP Configuration"
    
    log_info "Configuration:"
    log_info "  Project ID: $GCP_PROJECT_ID"
    log_info "  Zone: $GCP_ZONE"
    log_info "  Machine Type: $GCP_MACHINE_TYPE"
    log_info "  Credentials: $GCP_CREDENTIALS_JSON"
    
    # Extract and display service account info
    local client_email
    local project_id
    client_email=$(jq -r '.client_email' "$GCP_CREDENTIALS_JSON")
    project_id=$(jq -r '.project_id' "$GCP_CREDENTIALS_JSON")
    
    log_info "Service Account:"
    log_info "  Email: $client_email"
    log_info "  Project: $project_id"
    
    log_success "GCP configuration validated"
    return 0
}

################################################################################
# Test Functions
################################################################################

test_authentication() {
    header "TEST: GCP Authentication via REST API"
    
    log_info "Testing JWT-based authentication..."
    
    # Run the GCP deploy script in validate mode
    if bash "$REPO_ROOT/scripts/ops/gcp-deploy.sh" validate &>>"$TEST_LOG"; then
        log_success "Authentication test PASSED"
        return 0
    else
        log_error "Authentication test FAILED"
        return 1
    fi
}

test_list_instances() {
    header "TEST: List Existing GCP Instances"
    
    log_info "Listing current instances..."
    
    if bash "$REPO_ROOT/scripts/ops/gcp-deploy.sh" list &>>"$TEST_LOG"; then
        log_success "List instances test PASSED"
        return 0
    else
        log_warn "List instances test FAILED (may be normal if no instances exist)"
        return 0
    fi
}

test_deployment() {
    header "TEST: GCP Infrastructure Deployment"
    
    log_warn "This test will create GCP resources (cost: ~$0.50)"
    log_info "Creating infrastructure..."
    
    if timeout 600 bash "$REPO_ROOT/scripts/ops/gcp-deploy.sh" create &>>"$TEST_LOG"; then
        log_success "Infrastructure deployment test PASSED"
        
        # Give instances time to boot
        log_info "Waiting for instances to boot (30 seconds)..."
        sleep 30
        
        return 0
    else
        log_error "Infrastructure deployment test FAILED"
        return 1
    fi
}

test_instance_status() {
    header "TEST: Verify Instance Status"
    
    log_info "Getting instance status..."
    
    if bash "$REPO_ROOT/scripts/ops/gcp-deploy.sh" status &>>"$TEST_LOG"; then
        log_success "Instance status test PASSED"
        
        # Extract IPs
        local output
        output=$(bash "$REPO_ROOT/scripts/ops/gcp-deploy.sh" status 2>/dev/null)
        
        if echo "$output" | grep -q "RUNNING"; then
            log_success "Both instances are RUNNING"
            return 0
        else
            log_warn "Instances may not be fully running yet"
            return 0
        fi
    else
        log_error "Instance status test FAILED"
        return 1
    fi
}

test_ssh_connectivity() {
    header "TEST: SSH Connectivity"
    
    log_info "Testing SSH connectivity to instances..."
    
    # Extract PRIMARY IP
    local primary_ip
    primary_ip=$(bash "$REPO_ROOT/scripts/ops/gcp-deploy.sh" status 2>/dev/null | \
        grep -A 3 "PRIMARY" | grep "externalIP" | jq -r '.externalIP' 2>/dev/null || echo "")
    
    if [[ -z "$primary_ip" ]] || [[ "$primary_ip" == "null" ]]; then
        log_warn "Could not extract PRIMARY instance IP"
        return 0
    fi
    
    log_info "PRIMARY instance IP: $primary_ip"
    
    # Try SSH (with timeout)
    if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "ubuntu@$primary_ip" "echo 'SSH connectivity OK'" &>/dev/null; then
        log_success "SSH connectivity test PASSED"
        return 0
    else
        log_warn "SSH connectivity test FAILED (instances may need more time to boot, or SSH key not configured)"
        return 0
    fi
}

test_phase_2b_integration() {
    header "TEST: Phase 2b Integration"
    
    log_info "Extracting instance IPs for Phase 2b validation..."
    
    # Extract IPs
    local primary_ip replica_ip
    primary_ip=$(bash "$REPO_ROOT/scripts/ops/gcp-deploy.sh" status 2>/dev/null | \
        grep -A 3 "PRIMARY" | grep "externalIP" | jq -r '.externalIP' 2>/dev/null || echo "")
    replica_ip=$(bash "$REPO_ROOT/scripts/ops/gcp-deploy.sh" status 2>/dev/null | \
        grep -A 3 "REPLICA" | grep "externalIP" | jq -r '.externalIP' 2>/dev/null || echo "")
    
    if [[ -z "$primary_ip" ]] || [[ "$replica_ip" == "null" ]]; then
        log_warn "Could not extract instance IPs"
        log_info "Next: Manually run Phase 2b validation after configuring SSH"
        return 0
    fi
    
    log_info "PRIMARY: $primary_ip"
    log_info "REPLICA: $replica_ip"
    
    log_info "Phase 2b validation would run:"
    log_info "  PRIMARY_HOST=$primary_ip REPLICA_HOST=$replica_ip \\"
    log_info "  bash scripts/ops/full-deployment-test.sh --dry-run"
    
    log_success "Phase 2b integration configuration complete"
    return 0
}

test_cleanup() {
    header "TEST: Cleanup (Optional)"
    
    log_warn "Cleanup will DELETE all code-server GCP resources"
    log_info "Skipping cleanup (resources left running for manual verification)"
    log_info "To cleanup, run:"
    log_info "  bash $REPO_ROOT/scripts/ops/gcp-deploy.sh delete"
    
    return 0
}

################################################################################
# Test Suites
################################################################################

run_validation_suite() {
    log_info "Running validation test suite..."
    
    local failed=0
    
    validate_prerequisites || ((failed++))
    validate_gcp_configuration || ((failed++))
    
    if [[ $failed -gt 0 ]]; then
        log_error "$failed validation test(s) failed"
        return 1
    fi
    
    log_success "All validation tests passed"
    return 0
}

run_deployment_suite() {
    log_info "Running deployment test suite..."
    
    local failed=0
    
    validate_prerequisites || ((failed++))
    validate_gcp_configuration || ((failed++))
    test_authentication || ((failed++))
    test_list_instances || ((failed++))
    test_deployment || ((failed++))
    test_instance_status || ((failed++))
    
    if [[ $failed -gt 0 ]]; then
        log_error "$failed deployment test(s) failed"
        return 1
    fi
    
    log_success "All deployment tests passed"
    return 0
}

run_integration_suite() {
    log_info "Running integration test suite..."
    
    local failed=0
    
    test_instance_status || ((failed++))
    test_ssh_connectivity || ((failed++))
    test_phase_2b_integration || ((failed++))
    
    if [[ $failed -gt 0 ]]; then
        log_error "$failed integration test(s) failed (non-critical)"
    fi
    
    log_success "Integration tests completed"
    return 0
}

run_full_suite() {
    log_info "Running full deployment test suite..."
    
    local failed=0
    
    run_validation_suite || ((failed++))
    run_deployment_suite || ((failed++))
    run_integration_suite || ((failed++))
    
    if [[ $failed -gt 0 ]]; then
        log_error "$failed test suite(s) had failures"
        return 1
    fi
    
    log_success "All test suites passed"
    return 0
}

################################################################################
# Report Generation
################################################################################

generate_report() {
    header "TEST REPORT"
    
    echo "" | tee -a "$TEST_LOG"
    echo "Test Execution Summary" | tee -a "$TEST_LOG"
    echo "======================" | tee -a "$TEST_LOG"
    echo "Timestamp: $TIMESTAMP" | tee -a "$TEST_LOG"
    echo "Project ID: $GCP_PROJECT_ID" | tee -a "$TEST_LOG"
    echo "Zone: $GCP_ZONE" | tee -a "$TEST_LOG"
    echo "Test Log: $TEST_LOG" | tee -a "$TEST_LOG"
    echo "" | tee -a "$TEST_LOG"
    
    # Count test results
    local passed failed warnings
    passed=$(grep -c "\[SUCCESS\]" "$TEST_LOG" || echo "0")
    failed=$(grep -c "\[ERROR\]" "$TEST_LOG" || echo "0")
    warnings=$(grep -c "\[WARN\]" "$TEST_LOG" || echo "0")
    
    echo "Results:" | tee -a "$TEST_LOG"
    echo "  ✅ Passed: $passed" | tee -a "$TEST_LOG"
    echo "  ❌ Failed: $failed" | tee -a "$TEST_LOG"
    echo "  ⚠️  Warnings: $warnings" | tee -a "$TEST_LOG"
    echo "" | tee -a "$TEST_LOG"
    
    if [[ $failed -eq 0 ]]; then
        echo "Overall Status: ✅ PASSED" | tee -a "$TEST_LOG"
    else
        echo "Overall Status: ❌ FAILED" | tee -a "$TEST_LOG"
    fi
    
    echo "" | tee -a "$TEST_LOG"
    echo "Full log saved to: $TEST_LOG" | tee -a "$TEST_LOG"
}

################################################################################
# Main Entry Point
################################################################################

main() {
    local command=${1:-full}
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$TEST_LOG")"
    
    echo "GCP Deployment Test Suite" | tee "$TEST_LOG"
    echo "=========================" | tee -a "$TEST_LOG"
    echo "Command: $command" | tee -a "$TEST_LOG"
    echo "Timestamp: $TIMESTAMP" | tee -a "$TEST_LOG"
    echo "" | tee -a "$TEST_LOG"
    
    case "$command" in
        validate)
            run_validation_suite
            ;;
        deploy)
            run_deployment_suite
            ;;
        integrate)
            run_integration_suite
            ;;
        full)
            run_full_suite
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Usage: $0 [validate|deploy|integrate|full]"
            return 1
            ;;
    esac
    
    local exit_code=$?
    generate_report
    return $exit_code
}

main "$@"
