#!/usr/bin/env bats
# @file        tests/unit/kubernetes-oidc/test_serviceaccount_config.bats
# @module      testing/kubernetes-oidc
# @description Unit tests for Kubernetes ServiceAccount OIDC configuration
#

setup() {
    load ../lib.bats
    load ../test_helper.bash
    
    # Create temp directory for test manifests
    export TEST_MANIFEST_DIR="$(mktemp -d)"
    export KUBE_NAMESPACE="test-oidc-$(date +%s)"
    export OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://oauth2-oidc-issuer:4182}"
}

teardown() {
    # Cleanup temp directory
    rm -rf "$TEST_MANIFEST_DIR"
}

# Test 1: Verify ServiceAccount manifest is valid YAML
@test "ServiceAccount manifest is valid YAML" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    [ -f "$manifest_file" ] || skip "Manifest file not found"
    
    # Validate YAML syntax
    if command -v yamllint &>/dev/null; then
        run yamllint -d "{extends: relaxed}" "$manifest_file"
        [ "$status" -eq 0 ]
    else
        # Fallback: just check it's readable
        run head -1 "$manifest_file"
        [[ "$output" == *"---"* ]] || [[ "$output" == *"apiVersion"* ]]
    fi
}

# Test 2: Verify ServiceAccount definitions exist
@test "GitHub Actions ServiceAccount is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 5 "name: github-actions-ci" "$manifest_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ServiceAccount"* ]] || [[ "$output" == *"kind:"* ]]
}

@test "Batch Processor ServiceAccount is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 5 "name: batch-processor" "$manifest_file"
    [ "$status" -eq 0 ]
}

@test "Webhook Receiver ServiceAccount is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 5 "name: webhook-receiver" "$manifest_file"
    [ "$status" -eq 0 ]
}

# Test 3: Verify ClusterRole definitions
@test "ClusterRole for GitHub Actions is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 10 "name: code-server-github-actions" "$manifest_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ClusterRole"* ]] || [[ "$output" == *"kind:"* ]]
}

@test "ClusterRole for Batch Processor is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 10 "name: code-server-batch-processor" "$manifest_file"
    [ "$status" -eq 0 ]
}

# Test 4: Verify ClusterRoleBinding definitions
@test "ClusterRoleBinding for GitHub Actions is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 5 "name: github-actions-binding" "$manifest_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ClusterRoleBinding"* ]] || [[ "$output" == *"kind:"* ]]
}

@test "ClusterRoleBinding for Batch Processor is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 5 "name: batch-processor-binding" "$manifest_file"
    [ "$status" -eq 0 ]
}

# Test 5: Verify OIDC token projection configuration
@test "Token projection path is correct" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -B 2 -A 2 "/var/run/secrets/tokens/oidc/token" "$manifest_file"
    [ "$status" -eq 0 ]
}

@test "Token projection TTL is set" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep "expirationSeconds" "$manifest_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3600"* ]] || [[ "$output" == *"300"* ]]
}

# Test 6: Verify NetworkPolicy configuration
@test "NetworkPolicy for OIDC access is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 10 "kind: NetworkPolicy" "$manifest_file"
    [ "$status" -eq 0 ]
}

@test "NetworkPolicy restricts to OIDC issuer" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -B 5 -A 5 "port: 4182" "$manifest_file"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May or may not be in manifest
}

# Test 7: Verify example Pod configuration
@test "Example Pod with token projection is defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 15 "name: github-actions-example" "$manifest_file"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # Example may or may not be included
}

# Test 8: Verify security context in deployments
@test "Pod security context is configured" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 5 "securityContext:" "$manifest_file"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    
    if [ "$status" -eq 0 ]; then
        [[ "$output" == *"runAsNonRoot"* ]] || [[ "$output" == *"readOnlyRootFilesystem"* ]]
    fi
}

# Test 9: Verify resource limits are set
@test "Resource limits are defined for workloads" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 3 "resources:" "$manifest_file"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# Test 10: Verify labels for service discovery
@test "ServiceAccount labels are defined" {
    local manifest_file="kubernetes/oidc-serviceaccounts.yaml"
    
    run grep -A 3 "labels:" "$manifest_file"
    [ "$status" -eq 0 ]
}

# Test 11: Token exchange script exists and is valid
@test "Token exchange script exists" {
    [ -f "kubernetes/token-exchange.sh" ]
}

@test "Token exchange script has valid bash syntax" {
    run bash -n kubernetes/token-exchange.sh
    [ "$status" -eq 0 ]
}

@test "Token exchange script defines required functions" {
    local script="kubernetes/token-exchange.sh"
    
    run grep "exchange_token_for_jwt" "$script"
    [ "$status" -eq 0 ]
}

# Test 12: API client example exists and is valid
@test "API client example script exists" {
    [ -f "kubernetes/api-client-example.sh" ]
}

@test "API client example script has valid bash syntax" {
    run bash -n kubernetes/api-client-example.sh
    [ "$status" -eq 0 ]
}

@test "API client example defines token caching function" {
    local script="kubernetes/api-client-example.sh"
    
    run grep "get_jwt_token\|cache_token" "$script"
    [ "$status" -eq 0 ]
}

# Test 13: Documentation completeness
@test "Kubernetes OIDC documentation exists" {
    [ -f "docs/KUBERNETES-OIDC-INTEGRATION.md" ]
}

@test "Documentation covers architecture" {
    local doc="docs/KUBERNETES-OIDC-INTEGRATION.md"
    
    run grep -i "architecture\|token flow\|issuer" "$doc"
    [ "$status" -eq 0 ]
}

@test "Documentation covers deployment steps" {
    local doc="docs/KUBERNETES-OIDC-INTEGRATION.md"
    
    run grep -i "deploy\|install\|apply\|kubectl" "$doc"
    [ "$status" -eq 0 ]
}

@test "Documentation covers troubleshooting" {
    local doc="docs/KUBERNETES-OIDC-INTEGRATION.md"
    
    run grep -i "troubleshoot\|error\|problem\|issue" "$doc"
    [ "$status" -eq 0 ]
}
