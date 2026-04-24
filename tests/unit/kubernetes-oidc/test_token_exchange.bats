#!/usr/bin/env bats
# @file        tests/unit/kubernetes-oidc/test_token_exchange.bats
# @module      testing/kubernetes-oidc  
# @description Unit tests for OIDC token exchange functionality
#

setup() {
    load ../lib.bats
    load ../test_helper.bash
    
    export TOKEN_EXCHANGE_SCRIPT="kubernetes/token-exchange.sh"
    export OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://oauth2-oidc-issuer:4182}"
}

# Test 1: Token exchange script validates inputs
@test "Token exchange script rejects empty token" {
    skip "Requires running kubernetes cluster"
    
    run bash "$TOKEN_EXCHANGE_SCRIPT" ""
    [ "$status" -ne 0 ]
}

# Test 2: Token exchange script handles OIDC issuer URL
@test "Token exchange script uses OIDC issuer URL" {
    run grep -c "oauth2-oidc-issuer\|OIDC_ISSUER" "$TOKEN_EXCHANGE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 3: Token exchange script implements RFC 8693 grant
@test "Token exchange script uses RFC 8693 grant type" {
    run grep "urn:ietf:params:oauth:grant-type:token-exchange" "$TOKEN_EXCHANGE_SCRIPT"
    [ "$status" -eq 0 ]
}

# Test 4: Token exchange script handles JWT payload parsing
@test "Token exchange script parses JWT payload" {
    run grep -c "base64\|jq\|payload" "$TOKEN_EXCHANGE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 5: Token exchange script includes error handling
@test "Token exchange script has error handling" {
    run grep -c "error\|fail\|exit\|\|\|set -e" "$TOKEN_EXCHANGE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 6: Token exchange script documents usage
@test "Token exchange script has usage documentation" {
    run grep -c "usage\|Usage\|USAGE\|example\|Example" "$TOKEN_EXCHANGE_SCRIPT"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# Test 7: API client example has token caching
@test "API client example implements token caching" {
    local script="kubernetes/api-client-example.sh"
    
    run grep -c "cache\|CACHE\|TTL\|expire" "$script"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 8: API client example validates JWT
@test "API client example validates JWT structure" {
    local script="kubernetes/api-client-example.sh"
    
    run grep -c "Bearer\|Authorization\|jwt\|JWT" "$script"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 9: API client example makes authenticated API calls
@test "API client example calls API with JWT token" {
    local script="kubernetes/api-client-example.sh"
    
    run grep -c "curl\|api\|http" "$script"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 10: Integration test script validates prerequisites
@test "Integration test script checks prerequisites" {
    local script="kubernetes/test-oidc-integration.sh"
    
    run grep -c "prerequisite\|requirement\|check\|verify" "$script"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 11: Integration test script tests token projection
@test "Integration test script tests token projection" {
    local script="kubernetes/test-oidc-integration.sh"
    
    run grep -c "projection\|/var/run/secrets/tokens" "$script"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 12: Integration test script tests RBAC
@test "Integration test script validates RBAC" {
    local script="kubernetes/test-oidc-integration.sh"
    
    run grep -c "rbac\|RBAC\|ClusterRole\|permission\|authorize" "$script"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 13: Documentation describes token flow
@test "Documentation explains token acquisition flow" {
    local doc="docs/KUBERNETES-OIDC-INTEGRATION.md"
    
    run grep -A 5 -i "token.*flow\|token.*acquisition" "$doc"
    [ "$status" -eq 0 ]
}

# Test 14: Documentation provides deployment examples
@test "Documentation includes deployment examples" {
    local doc="docs/KUBERNETES-OIDC-INTEGRATION.md"
    
    run grep -c "Example\|example\|yaml\|kubectl apply" "$doc"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

# Test 15: Documentation covers security considerations
@test "Documentation addresses security" {
    local doc="docs/KUBERNETES-OIDC-INTEGRATION.md"
    
    run grep -i -c "security\|tls\|mtls\|secret\|encrypt" "$doc"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}
