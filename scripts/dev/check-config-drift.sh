#!/usr/bin/env bash
# @file        scripts/dev/check-config-drift.sh
# @module      governance/validation
# @description Detect configuration drift - hardcoded values that should reference SSOT files
# @owner       platform
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Configuration
DRIFT_FOUND=0
WARNINGS_FOUND=0

# SSOT file locations
ENV_TEMPLATE=""
HOSTS_FILE="environments/production/hosts.yml"
TERRAFORM_VARS="terraform/variables.tf"

log_header() {
    log_info "=== Configuration Drift Detection ===" 
}

check_hardcoded_ips() {
    log_info "Checking for hardcoded IPs (should use DNS names or environments/production/hosts.yml)..."
    
    # Define hardcoded IPs that are NOT allowed (production IPs)
    local prod_ips=("192.168.168.31" "192.168.168.42" "192.168.168.30" "192.168.168.56" "192.168.168.51")
    
    # Files to check (exclude .git and vendor)
    local files_to_check=$(find . -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.sh" -o -name "*.py" -o -name "Caddyfile" \) ! -path "./.git/*" ! -path "./node_modules/*" ! -path "./vendor/*" ! -path "./ollama-*/*" 2>/dev/null | grep -v "environments/production/hosts.yml")
    
    while IFS= read -r prod_ip; do
        # Skip grep if IP is 0.0.0.0 (always allowed)
        [[ "$prod_ip" == "0.0.0.0" ]] && continue
        
        # Check for hardcoded IP in files (exclude environment-specific files that SHOULD have IPs)
        violations=$(echo "$files_to_check" | while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                if grep -l "$prod_ip" "$file" 2>/dev/null | grep -v ".env" | grep -v "environments/"; then
                    echo "$file"
                fi
            fi
        done | sort -u)
        
        if [[ -n "$violations" ]]; then
            log_error "Hardcoded IP $prod_ip found in:"
            echo "$violations" | while IFS= read -r file; do
                echo "  $file"
                DRIFT_FOUND=1
            done
        fi
    done < <(printf '%s\n' "${prod_ips[@]}")
}

check_hardcoded_dns_names() {
    log_info "Checking for hardcoded DNS names (should use .env.template)..."
    
    # Extract DNS names that should be environment variables
    local dns_patterns=("kushnir.cloud" "prod.internal")
    
    while IFS= read -r domain; do
        # Check for hardcoded domains in operational files
        violations=$(find . -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "Caddyfile" \) ! -path "./.git/*" ! -path "./node_modules/*" ! -path "./.env*" ! -path "./environments/*" 2>/dev/null | xargs grep -l "$domain" 2>/dev/null || true)
        
        if [[ -n "$violations" ]]; then
            log_warn "Hardcoded domain $domain found in operational configs:"
            echo "$violations" | while IFS= read -r file; do
                echo "  $file (verify this should reference .env or environments/)"
            done
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    done < <(printf '%s\n' "${dns_patterns[@]}")
}

check_env_template_alignment() {
    log_info "Checking .env.template alignment with operational configs..."
    
    # Verify required environment variables are defined
    local required_vars=("DEPLOY_HOST" "REPLICA_HOST" "VIP_HOST" "DOMAIN" "REGISTRY_URL")
    
    while IFS= read -r var; do
        if ! grep -q "^$var=" "$ENV_TEMPLATE"; then
            log_error "$var not defined in $ENV_TEMPLATE (but used in operational code)"
            DRIFT_FOUND=$((DRIFT_FOUND + 1))
        fi
    done < <(printf '%s\n' "${required_vars[@]}")
}

check_terraform_vs_env() {
    log_info "Checking terraform/variables.tf vs .env.template alignment..."
    
    # Extract variable names from terraform
    local tf_vars=$(grep -o 'variable "[^"]*"' "$TERRAFORM_VARS" 2>/dev/null | cut -d'"' -f2 | sort -u)
    
    while IFS= read -r tf_var; do
        # Convert terraform variable naming (snake_case) to env var (UPPER_SNAKE_CASE)
        local env_var=$(echo "$tf_var" | tr '[:lower:]' '[:upper:]')
        
        # Check if it's a sensitive variable (skip these - they may be provided via TF_VAR_* env vars)
        if [[ "$tf_var" =~ ^(password|secret|token|key) ]]; then
            continue
        fi
        
        # For public vars, verify they're documented
        if ! grep -q "$env_var" "$ENV_TEMPLATE"; then
            log_warn "terraform variable '$tf_var' not found in $ENV_TEMPLATE - verify this is intentional"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    done < <(echo "$tf_vars")
}

generate_report() {
    log_info ""
    log_info "=== Drift Detection Report ==="
    
    if [[ $DRIFT_FOUND -gt 0 ]]; then
        log_error "CRITICAL: $DRIFT_FOUND drift violations found (config not following SSOT pattern)"
        return 1
    elif [[ $WARNINGS_FOUND -gt 0 ]]; then
        log_warn "WARNINGS: $WARNINGS_FOUND drift warnings found (review recommended but not blocking)"
        return 0
    else
        log_info "✓ No configuration drift detected"
        return 0
    fi
}

main() {
    log_header

    # Resolve canonical env SSOT file in priority order.
    if [[ -f ".env.template" ]]; then
        ENV_TEMPLATE=".env.template"
    elif [[ -f ".env.example" ]]; then
        ENV_TEMPLATE=".env.example"
    elif [[ -f ".env.defaults" ]]; then
        ENV_TEMPLATE=".env.defaults"
    fi
    
    # Check if files exist
    if [[ -z "$ENV_TEMPLATE" ]]; then
        log_error "No env SSOT file found (.env.template, .env.example, .env.defaults)"
        exit 1
    fi
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        log_error "$HOSTS_FILE not found"
        exit 1
    fi
    
    check_hardcoded_ips
    check_hardcoded_dns_names
    check_env_template_alignment
    check_terraform_vs_env
    generate_report
}

main "$@"
