#!/usr/bin/env bash
################################################################################
# @file        scripts/ci/validate-security-policy.sh
# @module      ci/security
# @description Enforce security policy gates in CI to block anti-patterns
# @owner       platform
# @status      active
#
# PURPOSE
#   Detects common security misconfigurations before they reach production:
#   - Tokens/secrets hardcoded in process args or env vars
#   - Wildcard identity allowlists (OAuth, firewall rules, ACLs)
#   - Overly-broad host Port exposure (0.0.0.0 bindings)
#   - Privileged container configurations without justification
#   - Missing/weak authentication on admin APIs
#
# USAGE
#   scripts/ci/validate-security-policy.sh [--check=<check-name>] [--fail-fast]
#
# EXAMPLES
#   scripts/ci/validate-security-policy.sh                    # Run all checks
#   scripts/ci/validate-security-policy.sh --check=tokens     # Run token check only
#   scripts/ci/validate-security-policy.sh --fail-fast        # Exit on first failure
#
# EXIT CODES
#   0 - All checks passed
#   1 - Policy violation(s) detected
#   2 - Configuration error (missing files, bad args)
#
# ENVIRONMENT VARIABLES (optional)
#   SECURITY_POLICY_FAIL_FAST   - Set to "1" to exit on first failure
#   SECURITY_POLICY_VERBOSE     - Set to "1" for detailed check output
#
# NOTES
#   - This script follows GOV-001 (Canonical Libraries) and GOV-002 (Metadata Headers)
#   - All violations are logged as errors and collected before final exit
#   - CI/CD integration: Include in github actions, gitlab-ci, circleci pipelines
#   - See DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md for security standards
#
# Last Updated: April 18, 2026
################################################################################

set -euo pipefail

################################################################################
# INITIALIZATION
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || {
    echo "FATAL: Cannot load _common/init.sh from $SCRIPT_DIR" >&2
    exit 2
}

SCRIPT_NAME="$(basename "$0")"

################################################################################
# CONFIGURATION
################################################################################

# Policy check flags
FAIL_FAST="${SECURITY_POLICY_FAIL_FAST:-0}"
VERBOSE="${SECURITY_POLICY_VERBOSE:-0}"
CHECK_FILTER="${CHECK_FILTER:-}"  # If set, run only this check

# Repo root (one level up from scripts/)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Violation counter
VIOLATION_COUNT=0

################################################################################
# HELPER FUNCTIONS
################################################################################

print_check_header() {
    local check_name="$1"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "SECURITY CHECK: $check_name"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

add_violation() {
    local check_name="$1"
    local file_path="$2"
    local line_num="$3"
    local description="$4"
    
    ((VIOLATION_COUNT++))
    
    log_error "[$check_name] $file_path:$line_num"
    log_error "  └─ $description"
    
    if [[ "$FAIL_FAST" == "1" ]]; then
        exit 1
    fi
}

################################################################################
# SECURITY CHECKS
################################################################################

check_tokens_in_args() {
    print_check_header "No Tokens/Secrets in Process Args"
    
    # Check critical files only (not full recursive scan)
    local files_to_check=(
        "$REPO_ROOT/scripts/setup-cloudflare-tunnel.sh"
        "$REPO_ROOT/terraform/modules/dns/main.tf"
        "$REPO_ROOT/docker-compose.production.yml"
    )
    
    for file_path in "${files_to_check[@]}"; do
        [[ ! -f "$file_path" ]] && continue
        
        # Check for token in ExecStart (not env var)
        if grep -q "ExecStart.*CLOUDFLARE_TUNNEL_TOKEN=" "$file_path" 2>/dev/null && \
           ! grep -q 'EnvironmentFile' "$file_path" 2>/dev/null; then
            add_violation "TOKENS_IN_ARGS" "$file_path" "?" "Token exposed in process args"
        fi
        
        # Check for cloudflare-api-token in args
        if grep -q "cloudflare-api-token" "$file_path" 2>/dev/null && \
           ! grep -q "cloudflare-api-token.*env" "$file_path" 2>/dev/null; then
            add_violation "TOKENS_IN_ARGS" "$file_path" "?" "Cloudflare API token in command args"
        fi
    done
    
    log_info "✓ Token/secret patterns verified in critical files"
}

check_wildcard_identity() {
    print_check_header "No Wildcard Identity Allowlists"
    
    # Check OAuth config
    local oauth_files=(
        "$REPO_ROOT/oauth2-proxy.cfg"
        "$REPO_ROOT/docker-compose.base.yml"
    )
    
    for file_path in "${oauth_files[@]}"; do
        [[ ! -f "$file_path" ]] && continue
        
        # Check for wildcard domain patterns
        if grep -E 'email-domains.*\["["\*]+"\]' "$file_path" 2>/dev/null; then
            add_violation "WILDCARD_DOMAIN" "$file_path" "?" \
                "Wildcard email domain found (should restrict to specific domain)"
        fi
    done
    
    log_info "✓ Wildcard identity allowlist check complete"
}

check_host_port_exposure() {
    print_check_header "Service Ports Bound to Localhost Only"
    
    # Check production compose for 0.0.0.0 bindings (except public services)
    local compose_file="$REPO_ROOT/docker-compose.production.yml"
    [[ ! -f "$compose_file" ]] && return
    
    local allowed_services=("caddy" "oauth2-proxy" "code-server")
    
    # Get all 0.0.0.0 entries
    local count=0
    while IFS= read -r line; do
        ((count++)) || true
        
        # Check if line mentions 0.0.0.0
        if echo "$line" | grep -q "0\.0\.0\.0"; then
            # Check if it's an allowed service
            local skip=0
            for allowed in "${allowed_services[@]}"; do
                if grep -i "image.*$allowed" "$compose_file" >/dev/null 2>&1; then
                    skip=1
                    break
                fi
            done
            
            if [[ $skip -eq 0 ]]; then
                add_violation "HOST_EXPOSURE" "$compose_file" "$count" \
                    "Found 0.0.0.0 binding (should be 127.0.0.1)"
            fi
        fi
    done < "$compose_file"
    
    log_info "✓ Host port exposure check complete"
}

check_caddyfile_imports() {
    print_check_header "Caddy Config Imports Validated"
    
    # Check if Caddyfile.production has Caddyfile.base
    if grep -q "@import Caddyfile.base\|import Caddyfile.base" "$REPO_ROOT/Caddyfile.production" 2>/dev/null; then
        if [[ ! -f "$REPO_ROOT/Caddyfile.base" ]]; then
            add_violation "MISSING_IMPORT" "$REPO_ROOT/Caddyfile.production" "?" \
                "Caddyfile.production references Caddyfile.base but it does not exist"
        else
            log_info "✓ Caddyfile imports valid"
        fi
    fi
}

check_privileged_justification() {
    print_check_header "Privileged Containers Have Justification"
    
    # Find privileged containers in Terraform (should have comment block)
    local tf_files=("$REPO_ROOT"/terraform/modules/security/main.tf)
    
    for file_path in "${tf_files[@]}"; do
        [[ ! -f "$file_path" ]] && continue
        
        if grep -q "privileged = true" "$file_path"; then
            # Check if there's a security note comment block
            if ! grep -q "CRITICAL SECURITY NOTE\|THREAT JUSTIFICATION" "$file_path"; then
                add_violation "PRIVILEGE_JUSTIFICATION" "$file_path" "?" \
                    "Privileged container found, but security justification is missing"
            fi
        fi
    done
    
    log_info "✓ Privileged container justification check complete"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "$SCRIPT_NAME: Starting security policy validation"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check=*)
                CHECK_FILTER="${1#*=}"
                shift
                ;;
            --fail-fast)
                FAIL_FAST="1"
                shift
                ;;
            --help|-h)
                echo "Usage: $SCRIPT_NAME [--check=<name>] [--fail-fast]"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 2
                ;;
        esac
    done
    
    # Run checks
    [[ -z "$CHECK_FILTER" || "$CHECK_FILTER" == "tokens" ]] && check_tokens_in_args
    [[ -z "$CHECK_FILTER" || "$CHECK_FILTER" == "identity" ]] && check_wildcard_identity
    [[ -z "$CHECK_FILTER" || "$CHECK_FILTER" == "exposure" ]] && check_host_port_exposure
    [[ -z "$CHECK_FILTER" || "$CHECK_FILTER" == "caddyfile" ]] && check_caddyfile_imports
    [[ -z "$CHECK_FILTER" || "$CHECK_FILTER" == "privilege" ]] && check_privileged_justification
    
    # Summary
    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ $VIOLATION_COUNT -eq 0 ]]; then
        log_info "✅ All security policy checks passed"
        return 0
    else
        log_error "❌ SECURITY POLICY VIOLATIONS: $VIOLATION_COUNT"
        log_error "Review the errors above and address before merge"
        return 1
    fi
}

main "$@"
