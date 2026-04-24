# @file sso_required.rego
# @module policies/identity
# @description All user-facing services must require authentication via OAuth2/OIDC SSO
# @governance GOV-003 - Identity & Authentication

package identity.sso_required

import future.keywords.if
import future.keywords.contains

# Deny unauthenticated access to user-facing services
deny[msg] {
    input.action == "access_service"
    input.service_type == "user_facing"
    not input.auth_token
    msg := "Unauthenticated access denied: user-facing service requires valid auth token"
}

# Deny if auth token is invalid or expired
deny[msg] {
    input.action == "access_service"
    input.service_type == "user_facing"
    input.auth_token
    not input.token_valid
    msg := "Access denied: authentication token is invalid or expired"
}

# Deny if auth provider is not in approved list
deny[msg] {
    input.action == "access_service"
    input.service_type == "user_facing"
    input.auth_provider
    approved_providers := ["oauth2-proxy", "keycloak", "github-oauth"]
    not input.auth_provider in approved_providers
    msg := sprintf("Access denied: auth provider '%s' not approved", [input.auth_provider])
}

# Deny if SSO claim verification fails
deny[msg] {
    input.action == "access_service"
    input.service_type == "user_facing"
    not input.sso_verified
    msg := "Access denied: SSO claim verification failed"
}

# Allow service access with valid SSO token
allow[msg] {
    input.action == "access_service"
    input.service_type == "user_facing"
    input.auth_token
    input.token_valid
    input.sso_verified
    input.user_id
    msg := sprintf("SSO authentication verified for user %s", [input.user_id])
}

# Service-to-service communication can bypass SSO with mTLS
allow[msg] {
    input.action == "access_service"
    input.service_type == "internal"
    input.caller_type == "service"
    input.mtls_verified
    msg := sprintf("Service call from %s verified via mTLS certificate", [input.caller_id])
}

# Allow local/development access without auth if in dev mode
allow[msg] {
    input.action == "access_service"
    input.environment == "development"
    input.network_source == "local"
    msg := "Development local access permitted"
}
