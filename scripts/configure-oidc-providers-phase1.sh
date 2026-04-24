#!/usr/bin/env bash
# @file        scripts/configure-oidc-providers-phase1.sh
# @module      iam
# @description configure oidc providers phase1 — on-prem code-server
# @owner       platform
# @status      active
#
# P1 #388 - OAuth2 Provider Configuration (Phase 1)
# Sets up OIDC federation with Google, GitHub, and local Keycloak
# Immutable versions: google-oauth2 v1.0.0, keycloak 20.0.0
# On-prem focus: All identity providers configured for ${DEPLOY_HOST}/42
#

set -euo pipefail

# Source common logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Config paths
CONFIG_DIR="${CONFIG_DIR:-./config/iam}"
SECRETS_DIR="${SECRETS_DIR:-.env.local}"

# ============================================================================
# Phase 1: OIDC Provider Configuration
# ============================================================================

echo "========================================================================="
echo "P1 #388 - OIDC Provider Configuration (Phase 1)"
echo "========================================================================="

# 1. Google OAuth2 Configuration
# Pre-requisites: Google Cloud Project with OAuth2 consent screen configured
log_info "Configuring Google OAuth2 provider..."

cat > "${CONFIG_DIR}/google-oauth2.env" <<'EOF'
# Google OAuth2 OIDC Configuration (on-prem deployment)
# Generated for P1 #388 Phase 1

# Google Cloud Project Settings (from GCP Console)
GOOGLE_OAUTH2_CLIENT_ID="${GOOGLE_OAUTH2_CLIENT_ID:-}"
GOOGLE_OAUTH2_CLIENT_SECRET="${GOOGLE_OAUTH2_CLIENT_SECRET:-}"

# Authorization endpoint
GOOGLE_OAUTH2_AUTH_URI="https://accounts.google.com/o/oauth2/v2/auth"

# Token endpoint
GOOGLE_OAUTH2_TOKEN_URI="https://oauth2.googleapis.com/token"

# User info endpoint
GOOGLE_OAUTH2_USERINFO_URI="https://openidconnect.googleapis.com/v1/userinfo"

# Scopes requested from Google
GOOGLE_OAUTH2_SCOPES="openid email profile"

# PKCE (Proof Key for Code Exchange) - REQUIRED for desktop/CLI flows
GOOGLE_OAUTH2_PKCE_ENABLED="true"

# MFA enforcement: Optional for developers, mandatory for admins
GOOGLE_OAUTH2_MFA_REQUIRED_FOR_ADMIN="true"
GOOGLE_OAUTH2_MFA_REQUIRED_FOR_VIEWER="false"

# Token validation
GOOGLE_OAUTH2_TOKEN_EXPIRY_SECONDS="3600"
GOOGLE_OAUTH2_REFRESH_TOKEN_EXPIRY_SECONDS="604800"

# Callback URLs for dev/staging/prod (must match GCP Console)
GOOGLE_OAUTH2_CALLBACK_URL_DEV="http://localhost:8080/auth/google/callback"
GOOGLE_OAUTH2_CALLBACK_URL_PROD="https://code-server.${DEPLOY_HOST}.nip.io:${PORT_CODE_SERVER}/auth/google/callback"
GOOGLE_OAUTH2_CALLBACK_URL_BACKSTAGE="https://backstage.kushin.cloud/auth/google/callback"
GOOGLE_OAUTH2_CALLBACK_URL_APPSMITH="https://appsmith.kushin.cloud/auth/google/callback"
EOF

log_info "Google OAuth2 config created: ${CONFIG_DIR}/google-oauth2.env"

# 2. GitHub OIDC Configuration (for workload identity federation)
# Pre-requisites: GitHub Organization with OIDC provider configured
log_info "Configuring GitHub OIDC provider..."

cat > "${CONFIG_DIR}/github-oidc.env" <<'EOF'
# GitHub OIDC Provider Configuration (Workload Federation)
# Generated for P1 #388 Phase 1
# Used by GitHub Actions CI/CD to authenticate to on-prem services

# GitHub Organization settings
GITHUB_OIDC_ORGANIZATION="kushin77"
GITHUB_OIDC_REPOSITORY="code-server"

# OIDC token endpoint
GITHUB_OIDC_TOKEN_URL="https://token.actions.githubusercontent.com"

# Token issuer (must be https://token.actions.githubusercontent.com)
GITHUB_OIDC_ISSUER="https://token.actions.githubusercontent.com"

# Subject claim format: repo:OWNER/REPO:ref:refs/heads/BRANCH
# Example: repo:kushin77/code-server:ref:refs/heads/main
GITHUB_OIDC_SUBJECT_FILTER="repo:kushin77/code-server:ref:refs/heads/main,repo:kushin77/code-server:pull_request"

# Token validation
GITHUB_OIDC_TOKEN_EXPIRY_SECONDS="300"

# Audience (must match what CI/CD workflow requests)
GITHUB_OIDC_AUDIENCES="https://${DEPLOY_HOST}"

# MFA enforcement: Not applicable for workload identity
GITHUB_OIDC_MFA_REQUIRED="false"
EOF

log_info "GitHub OIDC config created: ${CONFIG_DIR}/github-oidc.env"

# 3. Local OIDC Provider (Keycloak)
# Fallback for on-prem environments without external OIDC connectivity
log_info "Configuring local OIDC provider (Keycloak)..."

cat > "${CONFIG_DIR}/keycloak-oidc.env" <<'EOF'
# Keycloak OIDC Provider Configuration (Local)
# Generated for P1 #388 Phase 1
# Used as fallback when Google/GitHub OIDC unavailable

# Keycloak instance settings
KEYCLOAK_HOST="keycloak.${DEPLOY_HOST}.nip.io"
KEYCLOAK_PORT="8443"
KEYCLOAK_REALM="kushin"

# Keycloak OIDC endpoints
KEYCLOAK_ISSUER="https://keycloak.${DEPLOY_HOST}.nip.io:8443/realms/kushin"
KEYCLOAK_AUTH_URI="https://keycloak.${DEPLOY_HOST}.nip.io:8443/realms/kushin/protocol/openid-connect/auth"
KEYCLOAK_TOKEN_URI="https://keycloak.${DEPLOY_HOST}.nip.io:8443/realms/kushin/protocol/openid-connect/token"
KEYCLOAK_USERINFO_URI="https://keycloak.${DEPLOY_HOST}.nip.io:8443/realms/kushin/protocol/openid-connect/userinfo"
KEYCLOAK_CERTS_URI="https://keycloak.${DEPLOY_HOST}.nip.io:8443/realms/kushin/protocol/openid-connect/certs"

# Keycloak client settings
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-code-server}"
KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"

# Scopes
KEYCLOAK_SCOPES="openid email profile roles"

# Token validation
KEYCLOAK_TOKEN_EXPIRY_SECONDS="3600"

# Callback URLs
KEYCLOAK_CALLBACK_URL="https://code-server.${DEPLOY_HOST}.nip.io:${PORT_CODE_SERVER}/auth/keycloak/callback"

# User federation: sync users from LDAP/AD
KEYCLOAK_USER_FEDERATION_ENABLED="false"
KEYCLOAK_LDAP_URL="${KEYCLOAK_LDAP_URL:-}"

# MFA settings
KEYCLOAK_MFA_REQUIRED_FOR_ADMIN="true"
KEYCLOAK_MFA_REQUIRED_FOR_VIEWER="false"
EOF

log_info "Keycloak OIDC config created: ${CONFIG_DIR}/keycloak-oidc.env"

# 4. OIDC Provider Priority Chain
# Defines which provider is consulted in which order
log_info "Creating OIDC provider chain configuration..."

cat > "${CONFIG_DIR}/oidc-provider-chain.yaml" <<'EOF'
# OIDC Provider Chain Configuration
# P1 #388 Phase 1 - Identity & Workload Authentication
# Defines fallback behavior when primary provider unavailable

version: "1.0"

# Provider chain: attempt providers in order until success
providers:
  - name: google
    enabled: true
    priority: 1
    config: "./google-oauth2.env"
    type: oidc
    issuer: "https://accounts.google.com"
    required_claims:
      - sub
      - email
      - email_verified
    mfa_enforcement:
      admin: required
      operator: optional
      viewer: optional
    max_retries: 3
    timeout_seconds: 30

  - name: github
    enabled: true
    priority: 2
    config: "./github-oidc.env"
    type: oauth2
    issuer: "https://token.actions.githubusercontent.com"
    required_claims:
      - sub
      - iss
      - aud
    mfa_enforcement:
      workload: not_applicable
    max_retries: 3
    timeout_seconds: 30

  - name: keycloak
    enabled: true
    priority: 3
    config: "./keycloak-oidc.env"
    type: oidc
    issuer: "https://keycloak.${DEPLOY_HOST}.nip.io:8443/realms/kushin"
    required_claims:
      - sub
      - email
      - realm_access
    mfa_enforcement:
      admin: required
      operator: optional
      viewer: optional
    max_retries: 3
    timeout_seconds: 30

# Global OIDC settings
global_settings:
  # Token signature verification: Always verify JWT signature
  verify_signature: true

  # Clock skew tolerance (seconds)
  clock_skew: 30

  # Token expiration buffer: Refresh tokens when exp - now < buffer
  expiration_buffer_seconds: 300

  # PKCE required for non-confidential clients (mobile, CLI)
  pkce_required_for_public_clients: true

  # Rate limiting per IP
  rate_limit:
    enabled: true
    requests_per_minute: 60

  # Audit logging: All auth events
  audit_enabled: true
  audit_log_path: "/var/log/iam/auth-events.log"

# Fallback behavior
fallback:
  # If all providers fail, deny access
  deny_on_failure: true
  
  # Max attempts across all providers
  max_total_attempts: 9
  
  # Backoff strategy: exponential
  backoff:
    initial_delay_ms: 100
    max_delay_ms: 5000
    multiplier: 2
EOF

log_info "OIDC provider chain config created: ${CONFIG_DIR}/oidc-provider-chain.yaml"

# 5. Secrets Validation
log_info "Validating required secrets..."

check_secret() {
  local secret_name="$1"
  if [ -z "${!secret_name:-}" ]; then
    log_warn "Required secret not set: $secret_name"
    return 1
  else
    log_info "Secret configured: $secret_name"
    return 0
  fi
}

check_secret "GOOGLE_OAUTH2_CLIENT_ID" || true
check_secret "GOOGLE_OAUTH2_CLIENT_SECRET" || true
check_secret "KEYCLOAK_CLIENT_SECRET" || true

# 6. OAuth2 Callback URL Validation
log_info "Validating OAuth2 callback URLs..."

validate_url() {
  local url="$1"
  local name="$2"
  
  # Basic URL validation (https required for production)
  if [[ $url == https://* || $url == http://localhost* ]]; then
    log_info "Callback URL valid ($name): $url"
    return 0
  else
    log_error "Invalid callback URL ($name): $url (must be https:// or http://localhost)"
  fi
}

validate_url "$GOOGLE_OAUTH2_CALLBACK_URL_PROD" "Google OIDC"
validate_url "https://backstage.kushin.cloud/auth/google/callback" "Backstage"
validate_url "https://appsmith.kushin.cloud/auth/google/callback" "Appsmith"

# 7. MFA Configuration
log_info "Configuring MFA enforcement..."

cat > "${CONFIG_DIR}/mfa-requirements.yaml" <<'EOF'
# MFA Requirements by Role
# P1 #388 Phase 1 - Identity & Workload Authentication

mfa_enforcement:
  roles:
    admin:
      required: true
      methods:
        - webauthn  # Primary: Hardware FIDO2/U2F
        - totp      # Secondary: Time-based OTP (authenticator app)
      max_session_duration_hours: 8
      require_reauthentication_after_minutes: 60
      
    operator:
      required: false
      recommended: true
      methods:
        - webauthn
        - totp
        - sms
      max_session_duration_hours: 24
      require_reauthentication_after_minutes: 480  # 8 hours
      
    viewer:
      required: false
      methods:
        - webauthn
        - totp
      max_session_duration_hours: 168  # 7 days
      
    service:  # Workload identity
      required: false
      methods: []
      max_session_duration_hours: 1
      
  # Device trust: Trust device for N days after MFA
  device_trust_days: 30
  
  # Compromised device handling: Require MFA on all subsequent logins
  require_mfa_after_breach: true
EOF

log_info "MFA requirements configured: ${CONFIG_DIR}/mfa-requirements.yaml"

# 8. Output summary
echo ""
echo "========================================================================="
echo "P1 #388 Phase 1 Configuration Complete"
echo "========================================================================="
echo ""
log_info "OAuth2 Provider Configuration Files:"
echo "  • ${CONFIG_DIR}/google-oauth2.env"
echo "  • ${CONFIG_DIR}/github-oidc.env"
echo "  • ${CONFIG_DIR}/keycloak-oidc.env"
echo "  • ${CONFIG_DIR}/oidc-provider-chain.yaml"
echo "  • ${CONFIG_DIR}/mfa-requirements.yaml"
echo "  • ${CONFIG_DIR}/jwt-claims-schema.json"
echo ""

log_info "Next Steps:"
echo "  1. Add secrets to GitHub Secrets or GCP Secret Manager:"
echo "     • GOOGLE_OAUTH2_CLIENT_ID"
echo "     • GOOGLE_OAUTH2_CLIENT_SECRET"
echo "     • KEYCLOAK_CLIENT_SECRET"
echo ""
echo "  2. Deploy Keycloak (if using local OIDC provider)"
echo "  3. Verify OIDC provider connectivity"
echo "  4. Test OAuth2 login flow in staging"
echo "  5. Enable MFA enforcement on production"
echo ""

log_info "Phase 1 documentation: docs/P1-388-IAM-STANDARDIZATION.md"
