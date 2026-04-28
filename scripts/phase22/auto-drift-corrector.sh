#!/bin/bash

################################################################################
# Phase 22: Auto-Drift Corrector
# Purpose: Automatically detect and correct Terraform drift
# Date: April 28, 2026
################################################################################

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR%/scripts*}" && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh" || exit 1

# Configuration
TF_DIR="${REPO_ROOT}/terraform"
DRIFT_LOG="${REPO_ROOT}/logs/drift-corrections.log"
DRIFT_REPORT="${REPO_ROOT}/artifacts/phase22/drift-report-$(date +%Y%m%d-%H%M%S).json"
DRIFT_CHECK_INTERVAL=900  # 15 minutes
COOLDOWN_PERIOD=300      # 5 minutes between corrections
LAST_CORRECTION_FILE="/tmp/last-drift-correction"

mkdir -p "$(dirname "${DRIFT_LOG}")" "$(dirname "${DRIFT_REPORT}")"

log_drift() {
    local level="$1"
    local msg="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $msg" | tee -a "${DRIFT_LOG}"
}

################################################################################
# Section 1: Drift Detection
################################################################################

detect_drift() {
    log_drift "INFO" "🔍 Starting drift detection..."
    
    cd "${TF_DIR}" || exit 1
    
    # Refresh state
    log_drift "INFO" "Refreshing Terraform state..."
    terraform refresh -json > /tmp/tf-refresh.json 2>&1 || true
    
    # Run plan to detect drift
    log_drift "INFO" "Running Terraform plan to detect drift..."
    terraform plan -json -out=/tmp/tfplan > /tmp/tf-plan.json 2>&1 || true
    
    # Parse plan output
    local drift_count=0
    local drift_resources=()
    
    if [ -f /tmp/tf-plan.json ]; then
        drift_count=$(jq '[.[] | select(.type == "resource_drift")] | length' /tmp/tf-plan.json)
        drift_resources=($(jq -r '.[] | select(.type == "resource_drift") | .address' /tmp/tf-plan.json 2>/dev/null || echo ""))
    fi
    
    log_drift "INFO" "Drift detected: $drift_count resources"
    
    if [ $drift_count -gt 0 ]; then
        log_drift "WARN" "Drifted resources: ${drift_resources[*]}"
        return 0  # Drift found
    fi
    
    return 1  # No drift
}

################################################################################
# Section 2: Cooldown Check
################################################################################

check_cooldown() {
    if [ ! -f "${LAST_CORRECTION_FILE}" ]; then
        return 0  # Allow correction (no previous correction)
    fi
    
    local last_correction=$(cat "${LAST_CORRECTION_FILE}")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_correction))
    
    if [ $time_diff -lt $COOLDOWN_PERIOD ]; then
        log_drift "WARN" "Cooldown period active ($time_diff/$COOLDOWN_PERIOD sec)"
        return 1  # Still in cooldown
    fi
    
    return 0  # Cooldown expired
}

################################################################################
# Section 3: Automatic Correction
################################################################################

apply_correction() {
    log_drift "INFO" "📝 Applying Terraform corrections..."
    
    cd "${TF_DIR}" || exit 1
    
    # Pre-correction validation
    log_drift "INFO" "Pre-correction validation..."
    terraform validate > /dev/null 2>&1 || {
        log_drift "ERROR" "Terraform validation failed"
        return 1
    }
    
    # Apply with auto-approve (with audit trail)
    log_drift "INFO" "Executing terraform apply -auto-approve..."
    
    local apply_output
    apply_output=$(terraform apply -auto-approve -json 2>&1)
    
    echo "$apply_output" | tee -a "${DRIFT_REPORT}"
    
    # Check for errors
    if echo "$apply_output" | grep -q "Error"; then
        log_drift "ERROR" "Terraform apply failed"
        return 1
    fi
    
    log_drift "INFO" "✅ Corrections applied successfully"
    
    # Record correction time
    date +%s > "${LAST_CORRECTION_FILE}"
    
    return 0
}

################################################################################
# Section 4: Audit Logging
################################################################################

log_correction_event() {
    local status="$1"
    local drift_count="$2"
    
    local audit_log="/var/log/audit/drift-corrections.log"
    mkdir -p "$(dirname "$audit_log")"
    
    cat >> "$audit_log" << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "event": "drift_correction",
  "status": "$status",
  "drift_count": $drift_count,
  "corrector": "phase22-auto-drift-corrector",
  "user": "autonomous-agent"
}
EOF
    
    # Send to Prometheus push gateway (optional)
    if command -v curl &>/dev/null; then
        curl -s -X POST \
            "http://localhost:9091/metrics/job/drift-correction" \
            --data-binary @- << PROM
# TYPE drift_corrections_total counter
drift_corrections_total{status="$status"} 1
# TYPE drift_correction_timestamp gauge
drift_correction_timestamp $(date +%s)000
PROM
    fi
}

################################################################################
# Section 5: Metrics & Reporting
################################################################################

generate_report() {
    local status="$1"
    local drift_count="$2"
    
    cat > "${DRIFT_REPORT}" << EOF
# Drift Correction Report
**Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
**Status**: $status
**Drifted Resources**: $drift_count

## Drift Detection Results
$(cat /tmp/tf-plan.json 2>/dev/null | jq '.' || echo "No drift data")

## Corrections Applied
Terraform state synchronized with live infrastructure.

## Metrics
- Detection Time: $(date +%s)
- Correction Status: $status
- Resources Updated: $drift_count

## Audit Trail
See: /var/log/audit/drift-corrections.log
EOF
}

################################################################################
# Section 6: Main Execution
################################################################################

main() {
    log_drift "INFO" "═══════════════════════════════════════════════════════"
    log_drift "INFO" "Phase 22: Auto-Drift Corrector (started at $(date))"
    log_drift "INFO" "═══════════════════════════════════════════════════════"
    
    # Detect drift
    if detect_drift; then
        log_drift "INFO" "Drift detected, checking cooldown..."
        
        # Check cooldown
        if check_cooldown; then
            log_drift "INFO" "Cooldown check passed, applying corrections..."
            
            # Apply correction
            if apply_correction; then
                log_drift_event "success" "$(jq -r 'length' /tmp/tf-plan.json 2>/dev/null || echo 0)"
                log_drift "INFO" "✅ Drift correction completed successfully"
                exit 0
            else
                log_correction_event "failed" 0
                log_drift "ERROR" "❌ Drift correction failed"
                exit 1
            fi
        else
            log_drift "INFO" "Cooldown period active, skipping correction"
            exit 0
        fi
    else
        log_drift "INFO" "✅ No drift detected"
        exit 0
    fi
}

# Run main
main "$@"
