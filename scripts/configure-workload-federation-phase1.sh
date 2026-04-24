#!/usr/bin/env bash
# @file        scripts/configure-workload-federation-phase1.sh
# @module      iam
# @description configure workload federation phase1 — on-prem code-server
# @owner       platform
# @status      active
#
# P1 #388 - Phase 1: Workload Federation Setup Script
# Configures GitHub Actions OIDC and baseline RBAC for kushin77/code-server.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"

mkdir -p "$CONFIG_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions OIDC Configuration
# ─────────────────────────────────────────────────────────────────────────────

configure_github_oidc() {
    log_info "Configuring GitHub Actions OIDC claims validation..."

    cat > "$CONFIG_DIR/github-actions-oidc.yaml" <<'EOF'
# GitHub Actions OIDC Configuration (Phase 1)
# Validates JWT claims from https://token.actions.githubusercontent.com
github_oidc:
  issuer: "https://token.actions.githubusercontent.com"
  audience: "kushin77/code-server"
  
  # Claim mappings for subject verification
  subject_claim_patterns:
    main_branch: "repo:kushin77/code-server:ref:refs/heads/main"
    pr_branch: "repo:kushin77/code-server:pull_request"
    release_tag: "repo:kushin77/code-server:ref:refs/tags/v*"
  
  # Token lifetime policies
  token_ttl:
    main_branch: 900
    pr_branch: 300
    release_tag: 600
  
  # Claim validation rules
  validation_rules:
    - claim: "iss"
      must_equal: "https://token.actions.githubusercontent.com"
    - claim: "aud"
      must_equal: "kushin77/code-server"
    - claim: "sub"
      must_match_pattern: "repo:kushin77/code-server:.*"
    - claim: "repository_owner"
      must_equal: "kushin77"
    - claim: "repository"
      must_equal: "code-server"
EOF

    log_success "Generated: $CONFIG_DIR/github-actions-oidc.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# RBAC Configuration
# ─────────────────────────────────────────────────────────────────────────────

configure_rbac_baseline() {
    log_info "Configuring RBAC baseline for workload federation..."

    cat > "$CONFIG_DIR/rbac-roles.yaml" <<'EOF'
# RBAC Role Definitions (Phase 1)
# Used to validate and control permissions for federated workloads

roles:
  automation/viewer:
    description: "Read-only access for monitoring and observability"
    permissions:
      - "prometheus:scrape"
      - "logs:read"
      - "metrics:read"
      - "deployments:view"
      - "incidents:view"
  
  automation/operator:
    description: "Full operator access for CI/CD automation"
    permissions:
      - "deployments:execute"
      - "rollbacks:execute"
      - "configuration:read"
      - "configuration:write"
      - "secrets:read"
      - "logs:write"
  
  automation/admin:
    description: "Administrative access (rarely used)"
    permissions:
      - "rbac:manage"
      - "secrets:rotate"
      - "audit:read"
      - "system:configure"

# Subject-to-role mappings
role_bindings:
  - subject: "github-actions-main"
    role: "automation/operator"
    conditions:
      - "subject_claim == 'repo:kushin77/code-server:ref:refs/heads/main'"
      - "event_name == 'push'"
  
  - subject: "github-actions-pr"
    role: "automation/viewer"
    conditions:
      - "subject_claim contains 'pull_request'"
      - "event_name == 'pull_request'"
  
  - subject: "github-actions-release"
    role: "automation/operator"
    conditions:
      - "subject_claim contains 'refs/tags/v'"
      - "event_name == 'push'"
EOF

    log_success "Generated: $CONFIG_DIR/rbac-roles.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# Audit Logging Setup
# ─────────────────────────────────────────────────────────────────────────────

configure_audit_logging() {
    log_info "Configuring audit logging for OIDC token exchanges..."

    cat > "$CONFIG_DIR/audit-logging-oidc.yaml" <<'EOF'
# Audit Logging Configuration for OIDC (Phase 1)
audit_logging:
  enabled: true
  log_level: "INFO"
  
  # Events to audit
  events:
    - event_type: "token_exchange"
      description: "OIDC token exchanged for workload identity"
      required_fields:
        - timestamp
        - subject_claim
        - audience
        - issuer
        - requesting_service
        - outcome (success|failure)
    
    - event_type: "token_validation"
      description: "Token validated for API access"
      required_fields:
        - timestamp
        - token_id (first 8 chars)
        - requesting_service
        - requested_scope
        - validation_result
    
    - event_type: "permission_check"
      description: "RBAC permission evaluated"
      required_fields:
        - timestamp
        - subject
        - requested_action
        - resource
        - decision (allow|deny)
        - reason (if denied)
  
  # Retention policy
  retention:
    hot_days: 30
    warm_days: 90
    cold_days: 365
  
  # Alerting rules
  alerts:
    - condition: "failed token exchanges > 5 in 1 minute"
      severity: "critical"
      action: "block_subject_temporarily"
    
    - condition: "unauthorized access attempts > 10 in 1 minute"
      severity: "high"
      action: "alert_security_team"
EOF

    log_success "Generated: $CONFIG_DIR/audit-logging-oidc.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# Verification and Validation
# ─────────────────────────────────────────────────────────────────────────────

validate_github_oidc_issuer() {
    log_info "Validating GitHub OIDC issuer reachability..."

    local github_oidc_issuer="https://token.actions.githubusercontent.com"
    
    if curl -fsS "$github_oidc_issuer/.well-known/openid-configuration" >/dev/null 2>&1; then
        log_success "GitHub OIDC issuer is reachable and responding"
    else
        log_error "Cannot reach GitHub OIDC issuer at $github_oidc_issuer"
        return 1
    fi
}

validate_configuration() {
    log_info "Validating Phase 1 configuration artifacts..."

    local files=(
        "$CONFIG_DIR/github-actions-oidc.yaml"
        "$CONFIG_DIR/rbac-roles.yaml"
        "$CONFIG_DIR/audit-logging-oidc.yaml"
    )

    local file
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "Found: $file"
        else
            log_error "Missing: $file"
            return 1
        fi
    done

    log_success "All Phase 1 configuration files validated"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

main() {
    log_info "Starting P1 #388 Phase 1 setup..."
    log_info "Repository: kushin77/code-server"
    
    configure_github_oidc
    configure_rbac_baseline
    configure_audit_logging
    validate_github_oidc_issuer
    validate_configuration

    cat <<'NEXT_STEPS'

✅ Phase 1 Setup Complete

Generated Configuration:
  • GitHub Actions OIDC claims validation
  • RBAC role definitions and bindings
  • Audit logging specifications

Next Steps:
  1. Review all configuration files in config/
  2. Commit to branch: p1-388-workload-federation-phase-1
  3. Open PR for review
  4. Phase 2: Deploy Kubernetes ServiceAccounts and token validation service

Documentation:
  • See WORKLOAD_FEDERATION_IMPLEMENTATION.md for complete guide
  • Run: ./scripts/configure-workload-federation-phase2.sh

NEXT_STEPS
}

main "$@"
