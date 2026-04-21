#!/usr/bin/env bash
# @file        scripts/ci/predeploy-gate.sh
# @module      ci/deployment
# @description Pre-deploy validation gate: docker-compose config, Caddyfile, env vars, hardcoded secrets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ────────────────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-0}"

# Report file
REPORT_FILE="${PROJECT_ROOT}/artifacts/ci/predeploy-gate-report.json"
mkdir -p "${REPORT_FILE%/*}"

# ────────────────────────────────────────────────────────────────────────────
# Initialize report
# ────────────────────────────────────────────────────────────────────────────

init_report() {
    cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dry_run": $DRY_RUN,
  "checks": {
    "docker_compose_config": null,
    "caddyfile_syntax": null,
    "env_schema_validation": null,
    "hardcoded_secrets": null,
    "hardcoded_ips": null
  },
  "summary": {
    "total_checks": 5,
    "passed": 0,
    "failed": 0,
    "errors": []
  }
}
EOF
}

update_report() {
    local check="$1"
    local status="$2"
    local message="$3"
    
    # Use jq to update report (if available), otherwise append to errors
    if command -v jq &>/dev/null; then
        jq ".checks.\"$check\" = {\"status\": \"$status\", \"message\": \"$message\"}" "$REPORT_FILE" > "${REPORT_FILE}.tmp"
        mv "${REPORT_FILE}.tmp" "$REPORT_FILE"
    else
        # Fallback: append to errors array
        log_debug "jq not available, adding error to report: $message"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# CHECK 1: docker-compose.yml syntax and config validation
# ────────────────────────────────────────────────────────────────────────────

check_docker_compose_config() {
    log_info "CHECK 1: Validating docker-compose.yml configuration..."
    
    if ! command -v docker-compose &>/dev/null && ! command -v docker &>/dev/null; then
        log_warn "⚠ docker-compose not available - skipping config validation"
        update_report "docker_compose_config" "skipped" "docker-compose not available"
        return 0
    fi
    
    local compose_file="$PROJECT_ROOT/docker-compose.yml"
    
    if [ ! -f "$compose_file" ]; then
        log_error "✗ docker-compose.yml not found at $compose_file"
        update_report "docker_compose_config" "failed" "File not found: $compose_file"
        return 1
    fi
    
    # Try to validate docker-compose config
    if docker-compose -f "$compose_file" config >/dev/null 2>&1; then
        log_info "✓ docker-compose.yml is valid"
        update_report "docker_compose_config" "passed" "Valid"
        return 0
    else
        log_error "✗ docker-compose.yml has syntax errors:"
        docker-compose -f "$compose_file" config 2>&1 | head -20
        update_report "docker_compose_config" "failed" "Invalid syntax"
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# CHECK 2: Caddyfile syntax validation
# ────────────────────────────────────────────────────────────────────────────

check_caddyfile_syntax() {
    log_info "CHECK 2: Validating Caddyfile syntax..."
    
    local caddyfile="$PROJECT_ROOT/Caddyfile"
    
    if [ ! -f "$caddyfile" ]; then
        log_error "✗ Caddyfile not found at $caddyfile"
        update_report "caddyfile_syntax" "failed" "File not found: $caddyfile"
        return 1
    fi
    
    # Check Caddyfile syntax with caddy (if available)
    if command -v caddy &>/dev/null; then
        if caddy validate --config "$caddyfile" >/dev/null 2>&1; then
            log_info "✓ Caddyfile is syntactically valid"
            update_report "caddyfile_syntax" "passed" "Valid"
            return 0
        else
            log_error "✗ Caddyfile has syntax errors:"
            caddy validate --config "$caddyfile" 2>&1 | head -20
            update_report "caddyfile_syntax" "failed" "Invalid syntax"
            return 1
        fi
    else
        # Fallback: basic syntax checks (braces matching, common patterns)
        log_info "caddy command not available - running basic syntax checks..."
        
        # Check for unclosed braces
        local open_braces
        open_braces=$(grep -o '{' "$caddyfile" | wc -l)
        local close_braces
        close_braces=$(grep -o '}' "$caddyfile" | wc -l)
        
        if [ "$open_braces" -ne "$close_braces" ]; then
            log_error "✗ Caddyfile: brace mismatch (open: $open_braces, close: $close_braces)"
            update_report "caddyfile_syntax" "failed" "Brace mismatch"
            return 1
        fi
        
        # Check for required directives
        if ! grep -q "^ *:443" "$caddyfile"; then
            log_error "✗ Caddyfile: missing HTTPS listener (:443)"
            update_report "caddyfile_syntax" "failed" "Missing HTTPS listener"
            return 1
        fi
        
        log_info "✓ Caddyfile passed basic syntax checks"
        update_report "caddyfile_syntax" "passed" "Valid (basic checks)"
        return 0
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# CHECK 3: .env schema validation
# ────────────────────────────────────────────────────────────────────────────

check_env_schema() {
    log_info "CHECK 3: Validating .env against .env.schema.json..."
    
    local schema_file="$PROJECT_ROOT/.env.schema.json"
    local env_file="$PROJECT_ROOT/.env"
    
    if [ ! -f "$schema_file" ]; then
        log_warn "⚠ .env.schema.json not found - skipping schema validation"
        update_report "env_schema_validation" "skipped" "Schema file not found"
        return 0
    fi
    
    if [ ! -f "$env_file" ]; then
        log_warn "⚠ .env file not found - skipping validation (will be generated on deploy)"
        update_report "env_schema_validation" "skipped" ".env file not found"
        return 0
    fi
    
    # Check for required variables from schema
    if ! command -v jq &>/dev/null; then
        log_warn "⚠ jq not available - skipping detailed schema validation"
        update_report "env_schema_validation" "skipped" "jq not available"
        return 0
    fi
    
    local required_vars
    required_vars=$(jq -r '.groups[].variables | to_entries[] | select(.value.required == true) | .key' "$schema_file" | sort -u)
    local missing_vars=()
    
    while IFS= read -r var; do
        if ! grep -q "^${var}=" "$env_file"; then
            missing_vars+=("$var")
        fi
    done <<< "$required_vars"
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "✗ Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        update_report "env_schema_validation" "failed" "Missing: ${missing_vars[*]}"
        return 1
    fi
    
    log_info "✓ .env has all required schema variables"
    update_report "env_schema_validation" "passed" "Valid"
    return 0
}

# ────────────────────────────────────────────────────────────────────────────
# CHECK 4: Hardcoded secrets detection
# ────────────────────────────────────────────────────────────────────────────

check_hardcoded_secrets() {
    log_info "CHECK 4: Scanning for hardcoded secrets..."
    
    local secret_patterns=(
        'password\s*[:=]'
        'secret\s*[:=]'
        'api[_-]?key\s*[:=]'
        'token\s*[:=]'
        'Bearer\s+ey'
        'private[_-]?key'
        'api[_-]?secret'
    )
    
    local secret_files_found=0
    
    for pattern in "${secret_patterns[@]}"; do
        # Search in modified/staged files (if running in CI)
        if git -C "$PROJECT_ROOT" status --short &>/dev/null; then
            local files
            files=$(git -C "$PROJECT_ROOT" status --short | awk '{print $2}' | grep -v '^.')
        else
            local files="docker-compose.yml Caddyfile .env.schema.json"
        fi
        
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            
            if grep -iE "$pattern" "$PROJECT_ROOT/$file" 2>/dev/null | grep -vE '^\s*#' | grep -vE '(vault_path|env_var|password_auth)' >/dev/null; then
                log_error "✗ Possible hardcoded secret in $file:"
                grep -niE "$pattern" "$PROJECT_ROOT/$file" | head -3
                ((secret_files_found++))
            fi
        done <<< "$files"
    done
    
    if [ "$secret_files_found" -gt 0 ]; then
        update_report "hardcoded_secrets" "failed" "Found $secret_files_found potential secrets"
        return 1
    fi
    
    log_info "✓ No hardcoded secrets detected"
    update_report "hardcoded_secrets" "passed" "Clean"
    return 0
}

# ────────────────────────────────────────────────────────────────────────────
# CHECK 5: Hardcoded IPs detection
# ────────────────────────────────────────────────────────────────────────────

check_hardcoded_ips() {
    log_info "CHECK 5: Scanning for hardcoded IP addresses..."
    
    # Run the dedicated IP check script if available
    if [ -f "$SCRIPT_DIR/check-hardcoded-ips.sh" ]; then
        if bash "$SCRIPT_DIR/check-hardcoded-ips.sh" &>/dev/null; then
            log_info "✓ No hardcoded IPs detected"
            update_report "hardcoded_ips" "passed" "Clean"
            return 0
        else
            log_error "✗ Hardcoded IPs found - run: bash $SCRIPT_DIR/check-hardcoded-ips.sh"
            update_report "hardcoded_ips" "failed" "IPs found"
            return 1
        fi
    else
        # Fallback: basic check
        local ip_pattern='\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
        local files_with_ips
        files_with_ips=$(grep -rE "$ip_pattern" "$PROJECT_ROOT" \
            --include="*.yml" --include="*.yaml" --include="Caddyfile" \
            --exclude-dir=node_modules --exclude-dir=.git \
            2>/dev/null | wc -l)
        
        if [ "$files_with_ips" -gt 5 ]; then
            log_warn "⚠ Multiple IPs found in config files (may be legitimate in documentation)"
            log_info "  Run: bash $SCRIPT_DIR/check-hardcoded-ips.sh for detailed analysis"
            update_report "hardcoded_ips" "warning" "Found IPs in configs"
            return 0  # Warning, not failure
        fi
        
        log_info "✓ No suspicious hardcoded IPs detected"
        update_report "hardcoded_ips" "passed" "Clean"
        return 0
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Main execution
# ────────────────────────────────────────────────────────────────────────────

main() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Pre-Deploy Gate - Production Deployment Validation"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info ""
    log_info "Project root: $PROJECT_ROOT"
    log_info "Report file: $REPORT_FILE"
    log_info ""
    
    init_report
    
    local failed_checks=0
    
    if ! check_docker_compose_config; then
        ((failed_checks++))
    fi
    
    if ! check_caddyfile_syntax; then
        ((failed_checks++))
    fi
    
    if ! check_env_schema; then
        ((failed_checks++))
    fi
    
    if ! check_hardcoded_secrets; then
        ((failed_checks++))
    fi
    
    if ! check_hardcoded_ips; then
        ((failed_checks++))
    fi
    
    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "$failed_checks" -eq 0 ]; then
        log_info "✓ All pre-deploy checks passed - ready for deployment"
        log_info ""
        log_info "Next steps:"
        log_info "  • Review deployment plan"
        log_info "  • Create backup snapshot (scripts/ops/backup-verify.sh)"
        log_info "  • Execute redeploy with: bash scripts/ops/redeploy.sh"
        log_info ""
        log_info "Report: $REPORT_FILE"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
    else
        log_error "✗ $failed_checks pre-deploy check(s) failed - deployment blocked"
        log_error ""
        log_error "BLOCKING ISSUES:"
        log_error "  • Fix all failed checks before attempting deployment"
        log_error "  • Review $REPORT_FILE for details"
        log_error ""
        log_error "Report: $REPORT_FILE"
        log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 1
    fi
}

main "$@"
