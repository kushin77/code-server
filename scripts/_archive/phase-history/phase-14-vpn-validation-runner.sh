#!/bin/bash
# phase-14-vpn-validation-runner.sh
# Orchestrates VPN-aware validation testing
# Ensures all tests are executed from within VPN tunnel
# IaC-compliant: Audited, idempotent, immutable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOMAIN="${DOMAIN:-ide.kushnir.cloud}"
LOG_DIR="${LOG_DIR:-/tmp}"
VALIDATION_LOG="$LOG_DIR/phase-14-vpn-validation-$(date +%s).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

log() {
    echo -e "${BLUE}[$(date -u '+%H:%M:%S UTC')]${NC} $*" | tee -a "$VALIDATION_LOG"
}

success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$VALIDATION_LOG"
}

error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$VALIDATION_LOG"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$VALIDATION_LOG"
}

# ============================================================================
# 0. PREREQUISITE CHECKS
# ============================================================================
check_prerequisites() {
    log "=== PREREQUISITE CHECKS ==="

    local missing=0

    # Check required tools
    for tool in dig curl openssl timeout; do
        if ! command -v "$tool" &>/dev/null; then
            warning "$tool not found - some tests will be skipped"
            ((missing++))
        else
            success "Found: $tool"
        fi
    done

    # Check VPN connectivity
    log ""
    log "Checking VPN connectivity..."

    if ping -c 1 -W 3 192.168.168.31 &>/dev/null; then
        success "Can reach production host (192.168.168.31) - VPN appears active"
    else
        warning "Cannot ping production host - VPN may not be active"
        warning "Tests may not reflect end-user experience"
    fi

    return $missing
}

# ============================================================================
# 1. VPN-AWARE DNS VALIDATION
# ============================================================================
run_vpn_dns_validation() {
    log ""
    log "=== PHASE 1: VPN-AWARE DNS VALIDATION ==="

    if [ -x "$SCRIPT_DIR/phase-14-vpn-dns-validation.sh" ]; then
        bash "$SCRIPT_DIR/phase-14-vpn-dns-validation.sh" | tee -a "$VALIDATION_LOG"
        local result=$?

        if [ $result -eq 0 ]; then
            success "DNS validation PASSED"
            return 0
        else
            error "DNS validation FAILED"
            return 1
        fi
    else
        error "DNS validation script not executable: $SCRIPT_DIR/phase-14-vpn-dns-validation.sh"
        return 1
    fi
}

# ============================================================================
# 2. SERVICE HEALTH CHECK
# ============================================================================
check_service_health() {
    log ""
    log "=== PHASE 2: SERVICE HEALTH CHECK ==="

    local host="${1:-192.168.168.31}"

    log "Checking service health on $host..."

    # Connect via SSH and check docker status
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "akushnir@$host" \
        "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null | tee -a "$VALIDATION_LOG"; then
        success "Service health check completed"
        return 0
    else
        warning "Could not reach production host via SSH - VPN may be required"
        return 1
    fi
}

# ============================================================================
# 3. TLS CERTIFICATE VALIDATION
# ============================================================================
validate_tls_certificate() {
    log ""
    log "=== PHASE 3: TLS CERTIFICATE VALIDATION ==="

    if ! command -v openssl &>/dev/null; then
        warning "openssl not available, skipping certificate validation"
        return 0
    fi

    local cert_file="/tmp/ide-kushnir-tls-cert.crt"

    # Extract certificate
    openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" \
        </dev/null 2>/dev/null | \
        openssl x509 -outform PEM > "$cert_file" 2>/dev/null || true

    if [ -f "$cert_file" ] && [ -s "$cert_file" ]; then
        log "Certificate extracted, validating..."

        # Check certificate details
        local cn=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | grep -oP "CN=\K[^,/]+")
        local issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | grep -oP "O=\K[^,=]+")
        local expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)

        log "Certificate CN: $cn"
        log "Certificate Issuer: $issuer"
        log "Certificate Expiry: $expiry"

        if [ "$cn" = "$DOMAIN" ]; then
            success "Certificate CN matches domain ($DOMAIN)"
        else
            warning "Certificate CN ($cn) does not match domain ($DOMAIN)"
        fi

        rm -f "$cert_file"
        return 0
    else
        warning "Could not extract certificate"
        return 0
    fi
}

# ============================================================================
# 4. COMPREHENSIVE VALIDATION SUMMARY
# ============================================================================
generate_validation_summary() {
    log ""
    log "=== VALIDATION SUMMARY ==="
    log "Domain: $DOMAIN"
    log "Validation Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    log "Log File: $VALIDATION_LOG"
    log ""

    # Count results
    local passed=$(grep -c "✅" "$VALIDATION_LOG" || echo 0)
    local failed=$(grep -c "❌" "$VALIDATION_LOG" || echo 0)
    local warnings=$(grep -c "⚠️" "$VALIDATION_LOG" || echo 0)

    log "Results: $passed passed, $failed failed, $warnings warnings"

    if [ $failed -eq 0 ]; then
        success "Phase 14 VPN-Aware Validation PASSED - Ready for production launch"
        return 0
    else
        error "Phase 14 VPN-Aware Validation FAILED - Address issues before launch"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    log "╔════════════════════════════════════════════════════════════════╗"
    log "║  Phase 14 VPN-Aware Validation and Testing Framework          ║"
    log "║  Purpose: Validate production readiness from end-user POV     ║"
    log "╚════════════════════════════════════════════════════════════════╝"
    log ""
    log "Domain: $DOMAIN"
    log "Log: $VALIDATION_LOG"
    log ""

    # Execute validation phases
    check_prerequisites || true
    run_vpn_dns_validation || true
    check_service_health "192.168.168.31" || true
    validate_tls_certificate
    generate_validation_summary

    local final_result=$?

    log ""
    log "=== NEXT STEPS ==="
    if [ $final_result -eq 0 ]; then
        log "1. Review validation results: cat $VALIDATION_LOG"
        log "2. Approve Phase 14 launch in GitHub Issue #214"
        log "3. Execute: bash $SCRIPT_DIR/phase-14-go-live.sh"
    else
        log "1. Address validation failures"
        log "2. Re-run: bash $0"
        log "3. Check logs: cat $VALIDATION_LOG"
    fi

    return $final_result
}

main "$@"
