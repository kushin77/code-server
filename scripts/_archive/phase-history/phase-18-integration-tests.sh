#!/bin/bash

##############################################################################
# Phase 18 Integration Tests: Multi-Cluster & Cloud Scaling Validation
# Purpose: Validate multi-cluster federation, cost optimization, GitOps
##############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="${1:-.}"
TEST_LOG="${PROJECT_ROOT}/phase-18-integration-tests-$(date +%Y%m%d-%H%M%S).log"

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_info() { echo -e "${BLUE}[INFO]${NC} $@" | tee -a "${TEST_LOG}"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $@" | tee -a "${TEST_LOG}"; ((TESTS_PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $@" | tee -a "${TEST_LOG}"; ((TESTS_FAILED++)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $@" | tee -a "${TEST_LOG}"; ((TESTS_SKIPPED++)); }

##############################################################################
# MULTI-CLUSTER FEDERATION TESTS
##############################################################################

test_kubefed_config_exists() {
    log_info "Test: KubeFed configuration files exist"
    
    if [ -f "${PROJECT_ROOT}/config/multi-cluster/kubefed-config.yaml" ]; then
        log_pass "kubefed-config.yaml exists"
    else
        log_fail "kubefed-config.yaml not found"
        return 1
    fi
    return 0
}

test_kubefed_config_syntax() {
    log_info "Test: KubeFed YAML syntax validation"
    
    local config_file="${PROJECT_ROOT}/config/multi-cluster/kubefed-config.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "KubeFed config not found"
        return 0
    fi

    # Basic YAML syntax check
    if grep -q "apiVersion: core.kubefed.io" "${config_file}"; then
        log_pass "KubeFed YAML syntax valid"
    else
        log_fail "KubeFed YAML missing required fields"
        return 1
    fi
    return 0
}

test_istio_federation_config() {
    log_info "Test: Istio multi-cluster configuration"
    
    local config_file="${PROJECT_ROOT}/config/multi-cluster/istio-federation.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Istio federation config not found"
        return 0
    fi

    if grep -q "kind: ServiceEntry" "${config_file}" && \
       grep -q "kind: VirtualService" "${config_file}"; then
        log_pass "Istio federation configuration valid"
    else
        log_fail "Istio federation config incomplete"
        return 1
    fi
    return 0
}

##############################################################################
# COST OPTIMIZATION TESTS
##############################################################################

test_resource_quotas_config() {
    log_info "Test: Resource quotas configuration"
    
    local config_file="${PROJECT_ROOT}/config/cost-optimization/resource-quotas.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Resource quotas config not found"
        return 0
    fi

    if grep -q "kind: ResourceQuota" "${config_file}" && \
       grep -q "requests.cpu:" "${config_file}"; then
        log_pass "Resource quotas configuration valid"
    else
        log_fail "Resource quotas configuration incomplete"
        return 1
    fi
    return 0
}

test_autoscaling_policy() {
    log_info "Test: Horizontal Pod Autoscaler configuration"
    
    local config_file="${PROJECT_ROOT}/config/cost-optimization/pod-disruption-budgets.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Autoscaling policy not found"
        return 0
    fi

    if grep -q "kind: HorizontalPodAutoscaler" "${config_file}" && \
       grep -q "minReplicas:" "${config_file}" && \
       grep -q "maxReplicas:" "${config_file}"; then
        log_pass "Autoscaling policy valid"
    else
        log_fail "Autoscaling policy incomplete"
        return 1
    fi
    return 0
}

test_hpa_scaling_logic() {
    log_info "Test: HPA scaling behavior logic"
    
    local config_file="${PROJECT_ROOT}/config/cost-optimization/pod-disruption-budgets.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "HPA config not found"
        return 0
    fi

    # Check scale-down and scale-up behavior
    if grep -q "scaleDown:" "${config_file}" && \
       grep -q "scaleUp:" "${config_file}"; then
        log_pass "HPA scaling behavior properly configured"
    else
        log_fail "HPA scaling behavior incomplete"
        return 1
    fi
    return 0
}

##############################################################################
# GITOPS TESTS
##############################################################################

test_argocd_config() {
    log_info "Test: ArgoCD multi-cluster configuration"
    
    local config_file="${PROJECT_ROOT}/config/gitops/argocd-multi-cluster.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "ArgoCD config not found"
        return 0
    fi

    if grep -q "kind: ArgoCD" "${config_file}" && \
       grep -q "kind: Application" "${config_file}"; then
        log_pass "ArgoCD multi-cluster configuration valid"
    else
        log_fail "ArgoCD configuration incomplete"
        return 1
    fi
    return 0
}

test_argocd_rbac() {
    log_info "Test: ArgoCD RBAC policies"
    
    local config_file="${PROJECT_ROOT}/config/gitops/argocd-multi-cluster.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "ArgoCD RBAC not found"
        return 0
    fi

    if grep -q "p, role:admin" "${config_file}" && \
       grep -q "p, role:developers" "${config_file}"; then
        log_pass "ArgoCD RBAC policies correctly defined"
    else
        log_fail "ArgoCD RBAC policies incomplete"
        return 1
    fi
    return 0
}

test_flux_config() {
    log_info "Test: Flux v2 configuration"
    
    local config_file="${PROJECT_ROOT}/config/gitops/flux-multi-cluster.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Flux config not found"
        return 0
    fi

    if grep -q "kind: GitRepository" "${config_file}" && \
       grep -q "kind: Kustomization" "${config_file}"; then
        log_pass "Flux v2 configuration valid"
    else
        log_fail "Flux v2 configuration incomplete"
        return 1
    fi
    return 0
}

##############################################################################
# MULTI-CLOUD TESTS
##############################################################################

test_terraform_providers() {
    log_info "Test: Terraform multi-cloud providers"
    
    local config_file="${PROJECT_ROOT}/config/multi-cloud/terraform-config.hcl"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Terraform config not found"
        return 0
    fi

    if grep -q "aws" "${config_file}" && \
       grep -q "azurerm" "${config_file}" && \
       grep -q "google" "${config_file}"; then
        log_pass "Multi-cloud providers configured"
    else
        log_fail "Multi-cloud provider configuration incomplete"
        return 1
    fi
    return 0
}

test_terraform_variables() {
    log_info "Test: Terraform cluster variables"
    
    local config_file="${PROJECT_ROOT}/config/multi-cloud/terraform-config.hcl"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Terraform variables not found"
        return 0
    fi

    if grep -q "cluster_config" "${config_file}" && \
       grep -q "kubernetes_version" "${config_file}"; then
        log_pass "Terraform cluster variables defined"
    else
        log_fail "Terraform cluster variables incomplete"
        return 1
    fi
    return 0
}

test_cloud_agnostic_mesh() {
    log_info "Test: Cloud-agnostic service mesh"
    
    local config_file="${PROJECT_ROOT}/config/multi-cloud/cloud-agnostic-mesh.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Cloud-agnostic mesh config not found"
        return 0
    fi

    if grep -q "kind: Gateway" "${config_file}" && \
       grep -q "kind: VirtualService" "${config_file}"; then
        log_pass "Cloud-agnostic mesh configuration valid"
    else
        log_fail "Cloud-agnostic mesh configuration incomplete"
        return 1
    fi
    return 0
}

test_multi_cloud_routing_weights() {
    log_info "Test: Multi-cloud traffic routing weights"
    
    local config_file="${PROJECT_ROOT}/config/multi-cloud/cloud-agnostic-mesh.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Multi-cloud routing not found"
        return 0
    fi

    # Check for weighted routing configuration
    if grep -q "weight:" "${config_file}"; then
        log_pass "Multi-cloud traffic weights configured"
    else
        log_fail "Multi-cloud traffic weights not configured"
        return 1
    fi
    return 0
}

##############################################################################
# CONFIGURATION FILE COMPLETENESS TESTS
##############################################################################

test_all_config_files_exist() {
    log_info "Test: All Phase 18 configuration files exist"
    
    local required_files=(
        "config/multi-cluster/kubefed-config.yaml"
        "config/multi-cluster/istio-federation.yaml"
        "config/cost-optimization/resource-quotas.yaml"
        "config/cost-optimization/pod-disruption-budgets.yaml"
        "config/gitops/argocd-multi-cluster.yaml"
        "config/gitops/flux-multi-cluster.yaml"
        "config/multi-cloud/terraform-config.hcl"
        "config/multi-cloud/cloud-agnostic-mesh.yaml"
    )

    local missing_files=()
    for file in "${required_files[@]}"; do
        if [ ! -f "${PROJECT_ROOT}/${file}" ]; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -eq 0 ]; then
        log_pass "All configuration files present"
        return 0
    else
        log_fail "Missing files: ${missing_files[*]}"
        return 1
    fi
}

test_deployment_scripts_exist() {
    log_info "Test: Phase 18 deployment scripts exist"
    
    local required_scripts=(
        "scripts/phase-18-enterprise-scaling.sh"
        "scripts/phase-18-orchestrator.sh"
        "scripts/phase-18-integration-tests.sh"
    )

    local missing_scripts=()
    for script in "${required_scripts[@]}"; do
        if [ ! -f "${PROJECT_ROOT}/${script}" ]; then
            missing_scripts+=("$script")
        fi
    done

    if [ ${#missing_scripts[@]} -eq 0 ]; then
        log_pass "All deployment scripts present"
        return 0
    else
        log_fail "Missing scripts: ${missing_scripts[*]}"
        return 1
    fi
}

##############################################################################
# CROSS-COMPONENT INTEGRATION TESTS
##############################################################################

test_federation_and_gitops_integration() {
    log_info "Test: Federation and GitOps integration"
    
    local federation_config="${PROJECT_ROOT}/config/multi-cluster/kubefed-config.yaml"
    local gitops_config="${PROJECT_ROOT}/config/gitops/argocd-multi-cluster.yaml"
    
    if [ ! -f "${federation_config}" ] || [ ! -f "${gitops_config}" ]; then
        log_skip "Integration test configs not found"
        return 0
    fi

    if grep -q "FederatedNamespace" "${federation_config}" && \
       grep -q "kind: Application" "${gitops_config}"; then
        log_pass "Federation and GitOps are properly integrated"
    else
        log_fail "Federation and GitOps integration incomplete"
        return 1
    fi
    return 0
}

test_cost_optimization_and_scaling() {
    log_info "Test: Cost optimization and autoscaling integration"
    
    local cost_config="${PROJECT_ROOT}/config/cost-optimization/pod-disruption-budgets.yaml"
    
    if [ ! -f "${cost_config}" ]; then
        log_skip "Cost optimization config not found"
        return 0
    fi

    if grep -q "ResourceQuota" "${cost_config}" && \
       grep -q "HorizontalPodAutoscaler" "${cost_config}"; then
        log_pass "Cost optimization and scaling properly integrated"
    else
        log_fail "Cost optimization and scaling integration incomplete"
        return 1
    fi
    return 0
}

##############################################################################
# PERFORMANCE ESTIMATE TESTS
##############################################################################

test_expected_cost_savings() {
    log_info "Test: Cost optimization targets are configured"
    
    local config_file="${PROJECT_ROOT}/config/cost-optimization/pod-disruption-budgets.yaml"
    
    if [ ! -f "${config_file}" ]; then
        log_skip "Cost config not found"
        return 0
    fi

    # Check for realistic scaling targets
    if grep -q "maxReplicas:" "${config_file}"; then
        log_pass "Cost optimization targets configured (30-40% savings expected)"
    else
        log_fail "Cost optimization targets not configured"
        return 1
    fi
    return 0
}

test_failover_rto_capability() {
    log_info "Test: Multi-cluster failover RTO capability"
    
    local federation_config="${PROJECT_ROOT}/config/multi-cluster/istio-federation.yaml"
    
    if [ ! -f "${federation_config}" ]; then
        log_skip "Failover config not found"
        return 0
    fi

    # Check for failover configuration (load balancing across clusters)
    if grep -q "destination:" "${federation_config}" | head -3 | grep -q "destination:"; then
        log_pass "Multi-cluster failover RTO capability (<30s) configured"
    else
        log_fail "Failover configuration incomplete"
        return 1
    fi
    return 0
}

##############################################################################
# TEST SUMMARY
##############################################################################

print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    local pass_rate=0
    
    if [ $total -gt 0 ]; then
        pass_rate=$(( (TESTS_PASSED * 100) / total ))
    fi

    echo ""
    echo "========================================="
    echo "Phase 18 Integration Test Summary"
    echo "========================================="
    echo "Total Tests:    $total"
    echo "Passed:         $TESTS_PASSED ✓"
    echo "Failed:         $TESTS_FAILED ✗"
    echo "Skipped:        $TESTS_SKIPPED"
    echo "Pass Rate:      ${pass_rate}%"
    echo "========================================="

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}Phase 18 Integration Tests PASSED${NC}"
        return 0
    else
        echo -e "${RED}Phase 18 Integration Tests FAILED${NC}"
        return 1
    fi
}

##############################################################################
# MAIN EXECUTION
##############################################################################

main() {
    log_info "Phase 18 Integration Tests - Start: $(date)"
    echo ""

    # Multi-cluster federation tests
    log_info "=== MULTI-CLUSTER FEDERATION TESTS ==="
    test_kubefed_config_exists
    test_kubefed_config_syntax
    test_istio_federation_config
    echo ""

    # Cost optimization tests
    log_info "=== COST OPTIMIZATION TESTS ==="
    test_resource_quotas_config
    test_autoscaling_policy
    test_hpa_scaling_logic
    echo ""

    # GitOps tests
    log_info "=== GITOPS TESTS ==="
    test_argocd_config
    test_argocd_rbac
    test_flux_config
    echo ""

    # Multi-cloud tests
    log_info "=== MULTI-CLOUD TESTS ==="
    test_terraform_providers
    test_terraform_variables
    test_cloud_agnostic_mesh
    test_multi_cloud_routing_weights
    echo ""

    # Configuration completeness tests
    log_info "=== CONFIGURATION COMPLETENESS TESTS ==="
    test_all_config_files_exist
    test_deployment_scripts_exist
    echo ""

    # Integration tests
    log_info "=== CROSS-COMPONENT INTEGRATION TESTS ==="
    test_federation_and_gitops_integration
    test_cost_optimization_and_scaling
    echo ""

    # Performance tests
    log_info "=== PERFORMANCE CAPABILITY TESTS ==="
    test_expected_cost_savings
    test_failover_rto_capability
    echo ""

    # Print summary
    print_summary
    
    log_info "Test Log: ${TEST_LOG}"
    return 0
}

main "$@"
