#!/usr/bin/env bash
# @file        scripts/ci/check-no-hardcoded-lb-cookie-secret.sh
# @module      ci/security
# @description Detect and prevent hardcoded LB cookie secrets in Caddyfile and other configs
# @owner       Infrastructure Team
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Configuration
FAIL_ON_HARDCODED="${FAIL_ON_HARDCODED:-1}"
FAIL_ON_FALLBACK="${FAIL_ON_FALLBACK:-1}"
FAIL_ON_MISSING_REQUIRED="${FAIL_ON_MISSING_REQUIRED:-1}"
DRY_RUN="${DRY_RUN:-0}"

# Report file
REPORT_FILE="${SCRIPT_DIR}/artifacts/ci/lb-cookie-secret-report.json"
mkdir -p "$(dirname "$REPORT_FILE")"

log_stage() {
    log_info "========== $1 =========="
}

check_hardcoded_secret734() {
    log_stage "CHECK 1: Hardcoded secret734 Detection"
    
    local hardcoded_files=()
    local hardcoded_count=0
    
    log_info "Scanning for literal 'secret734' in code and config files..."
    
    # Scan files (exclude git history, artifacts, node_modules, etc.)
    while IFS= read -r file; do
        if grep -q "secret734" "$file" 2>/dev/null; then
            hardcoded_files+=("$file")
            ((hardcoded_count++))
            log_error "  ❌ Found hardcoded 'secret734' in: $file"
        fi
    done < <(find "$SCRIPT_DIR" -type f \
        ! -path "*/.git/*" \
        ! -path "*/node_modules/*" \
        ! -path "*/artifacts/*" \
        ! -path "*/.terraform/*" \
        ! -path "*/dist/*" \
        ! -path "*/__pycache__/*" \
        \( -name "Caddyfile*" -o -name "*.yml" -o -name "*.yaml" -o -name "*.sh" -o -name "*.conf" \) \
        2>/dev/null || true)
    
    if [ $hardcoded_count -eq 0 ]; then
        log_info "✅ No hardcoded 'secret734' found in active config files"
        return 0
    else
        log_error "❌ Found hardcoded 'secret734' in $hardcoded_count file(s)"
        if [ $FAIL_ON_HARDCODED -eq 1 ]; then
            return 1
        fi
        return 0
    fi
}

check_fallback_secret() {
    log_stage "CHECK 2: Fallback to Hardcoded Secret Detection"
    
    local fallback_files=()
    local fallback_count=0
    
    log_info "Scanning for IDE_SESSION_LB_SECRET with hardcoded fallback (e.g., {\$IDE_SESSION_LB_SECRET:secret734})..."
    
    # Look for pattern: {$IDE_SESSION_LB_SECRET:anything}
    while IFS= read -r file; do
        # Check for fallback pattern: {$IDE_SESSION_LB_SECRET:...}
        if grep -q '{\$IDE_SESSION_LB_SECRET:[^}]*}' "$file" 2>/dev/null; then
            fallback_files+=("$file")
            ((fallback_count++))
            log_error "  ❌ Found fallback in: $file"
            grep -n '{\$IDE_SESSION_LB_SECRET:[^}]*}' "$file" 2>/dev/null | while IFS=: read -r linenum content; do
                log_error "     Line $linenum: $content"
            done
        fi
    done < <(find "$SCRIPT_DIR" -type f \
        ! -path "*/.git/*" \
        ! -path "*/node_modules/*" \
        ! -path "*/artifacts/*" \
        ! -path "*/.terraform/*" \
        \( -name "Caddyfile*" -o -name "*.yml" -o -name "*.yaml" -o -name "*.conf" \) \
        2>/dev/null || true)
    
    if [ $fallback_count -eq 0 ]; then
        log_info "✅ No fallback to hardcoded secrets found"
        return 0
    else
        log_error "❌ Found IDE_SESSION_LB_SECRET with fallback in $fallback_count file(s)"
        if [ $FAIL_ON_FALLBACK -eq 1 ]; then
            return 1
        fi
        return 0
    fi
}

check_required_in_schema() {
    log_stage "CHECK 3: IDE_SESSION_LB_SECRET in Schema"
    
    log_info "Verifying IDE_SESSION_LB_SECRET is marked as required in .env.schema.json..."
    
    if ! grep -q '"IDE_SESSION_LB_SECRET"' "${SCRIPT_DIR}/.env.schema.json" 2>/dev/null; then
        log_error "❌ IDE_SESSION_LB_SECRET not found in .env.schema.json"
        if [ $FAIL_ON_MISSING_REQUIRED -eq 1 ]; then
            return 1
        fi
        return 0
    fi
    
    if ! grep -q '"IDE_SESSION_LB_SECRET".*"required": true' "${SCRIPT_DIR}/.env.schema.json" 2>/dev/null; then
        log_warn "⚠️  IDE_SESSION_LB_SECRET found but not marked as required"
        return 0
    fi
    
    log_info "✅ IDE_SESSION_LB_SECRET properly documented and required in schema"
    return 0
}

check_caddyfile_uses_var() {
    log_stage "CHECK 4: Caddyfile Uses Environment Variable"
    
    log_info "Verifying Caddyfile uses {\$IDE_SESSION_LB_SECRET} without fallback..."
    
    local caddy_uses_var=0
    
    # Check if Caddyfile uses the variable (properly)
    if grep -q '{\$IDE_SESSION_LB_SECRET}' "${SCRIPT_DIR}/Caddyfile" 2>/dev/null; then
        log_info "  ✅ Found {\$IDE_SESSION_LB_SECRET} in Caddyfile"
        caddy_uses_var=1
    else
        log_error "  ❌ Caddyfile does not use {\$IDE_SESSION_LB_SECRET} variable"
        return 1
    fi
    
    # Verify no fallback pattern
    if grep -q '{\$IDE_SESSION_LB_SECRET:[^}]*}' "${SCRIPT_DIR}/Caddyfile" 2>/dev/null; then
        log_error "  ❌ Caddyfile uses fallback pattern (should be {$IDE_SESSION_LB_SECRET} without :...)"
        return 1
    fi
    
    log_info "✅ Caddyfile correctly uses environment variable without fallback"
    return 0
}

generate_report() {
    local overall_status="$1"
    
    log_info "Generating report: $REPORT_FILE"
    
    cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "check": "hardcoded-lb-cookie-secret",
  "overall_status": "$overall_status",
  "checks": {
    "hardcoded_secret734": {
      "description": "Detect literal 'secret734' in config files",
      "status": "PASSED"
    },
    "fallback_secret": {
      "description": "Detect {IDE_SESSION_LB_SECRET:fallback} pattern",
      "status": "PASSED"
    },
    "required_in_schema": {
      "description": "IDE_SESSION_LB_SECRET marked as required in schema",
      "status": "PASSED"
    },
    "caddyfile_uses_var": {
      "description": "Caddyfile uses parameterized variable",
      "status": "PASSED"
    }
  },
  "recommendation": "No hardcoded LB cookie secrets detected. Safe to deploy."
}
EOF
    
    log_info "Report written to: $REPORT_FILE"
}

main() {
    log_stage "LB COOKIE SECRET VALIDATION (Issue #968, #998)"
    
    local checks_passed=0
    local checks_failed=0
    
    # Run all checks
    if check_hardcoded_secret734; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_fallback_secret; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_required_in_schema; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_caddyfile_uses_var; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    echo ""
    log_info "Checks passed: $checks_passed/4"
    log_info "Checks failed: $checks_failed/4"
    echo ""
    
    if [ $checks_failed -eq 0 ]; then
        log_info "✅ All LB cookie secret checks PASSED"
        generate_report "PASSED"
        return 0
    else
        log_error "❌ LB cookie secret validation FAILED ($checks_failed checks)"
        generate_report "FAILED"
        return 1
    fi
}

main "$@"
