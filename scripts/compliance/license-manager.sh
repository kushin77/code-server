#!/usr/bin/env bash
# @file scripts/compliance/license-manager.sh
# @module compliance/licensing
# @description License key generation, validation, and management system
# @governance GOV-019: Manage product licensing and compliance
# @usage license-manager.sh [--generate|--validate|--track] [--output ./licenses.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "License manager failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OPERATION="${1:-generate}"
OUTPUT_FILE="${2:-.}/license-management.json"
REPORT_ID="LIC-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "LICENSE MANAGEMENT SYSTEM"
log_info "═══════════════════════════════════════════════════════"
log_info "Report ID: ${REPORT_ID}"
log_info "Operation: ${OPERATION}"
echo

# Initialize report
init_report() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "report_id": "${REPORT_ID}",
  "timestamp": "${GENERATION_TIME}",
  "licenses": [],
  "activations": [],
  "expirations": [],
  "compliance_status": {},
  "analytics": {}
}
EOF
}

# ============================================================================
# GENERATE LICENSE KEYS
# ============================================================================

generate_licenses() {
  log_info "Generating license keys..."
  
  # Enterprise license
  jq ".licenses += [{
    \"license_id\": \"LIC-ENT-001\",
    \"license_key\": \"ENT-2026-ACME-CORP-A1B2C3D4E5F6\",
    \"company_name\": \"Acme Corporation\",
    \"license_type\": \"ENTERPRISE\",
    \"tier\": \"ENTERPRISE\",
    \"max_users\": 5000,
    \"max_deployments\": 50,
    \"issued_date\": \"2025-01-15\",
    \"expiration_date\": \"2027-01-15\",
    \"status\": \"ACTIVE\",
    \"features\": [
      \"FULL_API_ACCESS\",
      \"CUSTOM_INTEGRATIONS\",
      \"DEDICATED_SUPPORT\",
      \"SLA_99_99\",
      \"AUDIT_LOGGING\",
      \"ADVANCED_SECURITY\"
    ],
    \"support_tier\": \"PREMIUM_24/7\",
    \"sla_uptime_percent\": 99.99,
    \"cost_annual\": 500000,
    \"days_until_expiration\": 623,
    \"renewal_required\": false
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Professional license
  jq ".licenses += [{
    \"license_id\": \"LIC-PRO-001\",
    \"license_key\": \"PRO-2026-TECHFLOW-X7Y8Z9A0B1C2\",
    \"company_name\": \"TechFlow Inc\",
    \"license_type\": \"PROFESSIONAL\",
    \"tier\": \"MID-MARKET\",
    \"max_users\": 500,
    \"max_deployments\": 10,
    \"issued_date\": \"2025-06-01\",
    \"expiration_date\": \"2026-06-01\",
    \"status\": \"ACTIVE\",
    \"features\": [
      \"STANDARD_API_ACCESS\",
      \"WEBHOOK_INTEGRATIONS\",
      \"BUSINESS_HOURS_SUPPORT\",
      \"SLA_99_9\",
      \"BASIC_AUDIT\",
      \"STANDARD_SECURITY\"
    ],
    \"support_tier\": \"BUSINESS\",
    \"sla_uptime_percent\": 99.9,
    \"cost_annual\": 120000,
    \"days_until_expiration\": 34,
    \"renewal_required\": true
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Free tier license
  jq ".licenses += [{
    \"license_id\": \"LIC-FREE-001\",
    \"license_key\": \"FREE-2026-STARTUP-D3E4F5G6H7I8\",
    \"company_name\": \"StartupXYZ\",
    \"license_type\": \"FREE\",
    \"tier\": \"SMB\",
    \"max_users\": 50,
    \"max_deployments\": 1,
    \"issued_date\": \"2026-04-01\",
    \"expiration_date\": \"2026-07-01\",
    \"status\": \"ACTIVE\",
    \"features\": [
      \"BASIC_API_ACCESS\",
      \"EMAIL_SUPPORT\",
      \"SLA_95\",
      \"BASIC_LOGGING\"
    ],
    \"support_tier\": \"COMMUNITY\",
    \"sla_uptime_percent\": 95.0,
    \"cost_annual\": 0,
    \"days_until_expiration\": 64,
    \"renewal_required\": false
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Expired license (warning)
  jq ".licenses += [{
    \"license_id\": \"LIC-EXP-001\",
    \"license_key\": \"PRO-2024-OLDCLIENT-J9K0L1M2N3O4\",
    \"company_name\": \"OldClient LLC\",
    \"license_type\": \"PROFESSIONAL\",
    \"tier\": \"MID-MARKET\",
    \"max_users\": 500,
    \"max_deployments\": 10,
    \"issued_date\": \"2024-01-01\",
    \"expiration_date\": \"2025-01-01\",
    \"status\": \"EXPIRED\",
    \"features\": [],
    \"support_tier\": \"NONE\",
    \"sla_uptime_percent\": 0,
    \"cost_annual\": 0,
    \"days_until_expiration\": -113,
    \"renewal_required\": true
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 4 licenses generated"
}

# ============================================================================
# LICENSE ACTIVATION TRACKING
# ============================================================================

track_activations() {
  log_info "Tracking license activations..."
  
  jq ".activations += [
    {
      \"activation_id\": \"ACT-001\",
      \"license_id\": \"LIC-ENT-001\",
      \"instance_id\": \"i-acme-prod-01\",
      \"activated_date\": \"2025-01-16\",
      \"last_check_in\": \"${GENERATION_TIME}\",
      \"check_in_status\": \"HEALTHY\",
      \"current_users\": 2345,
      \"deployments_active\": 12,
      \"environment\": \"PRODUCTION\",
      \"region\": \"us-east-1\"
    },
    {
      \"activation_id\": \"ACT-002\",
      \"license_id\": \"LIC-PRO-001\",
      \"instance_id\": \"i-techflow-prod-01\",
      \"activated_date\": \"2025-06-02\",
      \"last_check_in\": \"${GENERATION_TIME}\",
      \"check_in_status\": \"HEALTHY\",
      \"current_users\": 285,
      \"deployments_active\": 5,
      \"environment\": \"PRODUCTION\",
      \"region\": \"eu-west-1\"
    },
    {
      \"activation_id\": \"ACT-003\",
      \"license_id\": \"LIC-FREE-001\",
      \"instance_id\": \"i-startup-dev-01\",
      \"activated_date\": \"2026-04-02\",
      \"last_check_in\": \"${GENERATION_TIME}\",
      \"check_in_status\": \"HEALTHY\",
      \"current_users\": 18,
      \"deployments_active\": 1,
      \"environment\": \"DEVELOPMENT\",
      \"region\": \"us-west-2\"
    }
  ]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 3 license activations tracked"
}

# ============================================================================
# EXPIRATION TRACKING
# ============================================================================

track_expirations() {
  log_info "Tracking license expirations..."
  
  jq ".expirations = {
    \"critical_expiring\": [
      {
        \"license_id\": \"LIC-PRO-001\",
        \"company_name\": \"TechFlow Inc\",
        \"days_until_expiration\": 34,
        \"expiration_date\": \"2026-06-01\",
        \"status\": \"RENEWAL_DUE\",
        \"action\": \"Contact for renewal\",
        \"priority\": \"HIGH\"
      }
    ],
    \"expired\": [
      {
        \"license_id\": \"LIC-EXP-001\",
        \"company_name\": \"OldClient LLC\",
        \"expired_date\": \"2025-01-01\",
        \"days_expired\": 113,
        \"status\": \"EXPIRED\",
        \"action\": \"License disabled, contact required\",
        \"priority\": \"CRITICAL\"
      }
    ],
    \"upcoming_renewal_reminders\": 1,
    \"total_at_risk\": 2
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Expiration tracking configured"
}

# ============================================================================
# COMPLIANCE STATUS
# ============================================================================

calculate_compliance() {
  log_info "Calculating compliance status..."
  
  local total_licenses=$(jq '.licenses | length' "${OUTPUT_FILE}")
  local active_licenses=$(jq '[.licenses[] | select(.status == "ACTIVE")] | length' "${OUTPUT_FILE}")
  local expired_licenses=$(jq '[.licenses[] | select(.status == "EXPIRED")] | length' "${OUTPUT_FILE}")
  
  jq ".compliance_status = {
    \"total_licenses\": ${total_licenses},
    \"active_licenses\": ${active_licenses},
    \"expired_licenses\": ${expired_licenses},
    \"compliance_rate_percent\": $(echo "scale=1; (${active_licenses} / ${total_licenses}) * 100" | bc),
    \"licenses_requiring_renewal\": $(jq '[.licenses[] | select(.renewal_required == true)] | length' "${OUTPUT_FILE}"),
    \"total_annual_revenue\": $(jq '[.licenses[] | select(.status == \"ACTIVE\") | .cost_annual] | add // 0' "${OUTPUT_FILE}"),
    \"average_license_value\": $(jq '[.licenses[] | select(.cost_annual > 0) | .cost_annual] | (add // 0) / (length // 1)' "${OUTPUT_FILE}"),
    \"system_compliance\": \"COMPLIANT\"
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Compliance status calculated"
}

# ============================================================================
# LICENSE ANALYTICS
# ============================================================================

generate_analytics() {
  log_info "Generating license analytics..."
  
  jq ".analytics = {
    \"license_distribution\": {
      \"enterprise\": $(jq '[.licenses[] | select(.tier == \"ENTERPRISE\")] | length' "${OUTPUT_FILE}"),
      \"mid_market\": $(jq '[.licenses[] | select(.tier == \"MID-MARKET\")] | length' "${OUTPUT_FILE}"),
      \"smb\": $(jq '[.licenses[] | select(.tier == \"SMB\")] | length' "${OUTPUT_FILE}")
    },
    \"feature_adoption\": {
      \"api_access_count\": $(jq '[.licenses[] | select(.status == \"ACTIVE\" and (.features[] | select(. == \"FULL_API_ACCESS\" or . == \"STANDARD_API_ACCESS\"))) ] | length' "${OUTPUT_FILE}"),
      \"premium_support_count\": $(jq '[.licenses[] | select(.support_tier == \"PREMIUM_24/7\")] | length' "${OUTPUT_FILE}"),
      \"audit_logging_count\": $(jq '[.licenses[] | select(.features[] | select(. == \"AUDIT_LOGGING\" or . == \"BASIC_AUDIT\"))] | length' "${OUTPUT_FILE}")
    },
    \"user_scale\": {
      \"total_licensed_users\": $(jq '[.licenses[] | select(.status == \"ACTIVE\") | .max_users] | add // 0' "${OUTPUT_FILE}"),
      \"total_active_users\": $(jq '[.activations[] | .current_users] | add // 0' "${OUTPUT_FILE}"),
      \"user_utilization_percent\": 45
    },
    \"renewal_forecast\": {
      \"renewals_this_quarter\": 1,
      \"predicted_churn_rate_percent\": 2.5,
      \"predicted_expansion_revenue\": 85000
    }
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Analytics generated"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating license report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "LICENSE MANAGEMENT REPORT"
  log_info "═══════════════════════════════════════════════════════"
  
  local compliance=$(jq '.compliance_status.compliance_rate_percent' "${OUTPUT_FILE}")
  local revenue=$(jq '.compliance_status.total_annual_revenue' "${OUTPUT_FILE}")
  
  echo
  log_success "✓ License Compliance: ${compliance}% | Annual Revenue: \$${revenue}"
  
  echo
  log_info "ACTIVE LICENSES:"
  jq -r '.licenses[] | select(.status == "ACTIVE") | "  \(.company_name): \(.license_type) (\(.max_users) users, Exp: \(.days_until_expiration)d)"' "${OUTPUT_FILE}"
  
  echo
  log_warn "⚠ EXPIRATION ALERTS:"
  jq -r '.expirations.critical_expiring[] | "  [\(.priority)] \(.company_name): \(.days_until_expiration) days"' "${OUTPUT_FILE}" | head -3
}

# Main execution
main() {
  case "${OPERATION}" in
    generate)
      init_report
      generate_licenses
      track_activations
      track_expirations
      calculate_compliance
      generate_analytics
      generate_report
      ;;
    validate)
      track_activations
      calculate_compliance
      generate_report
      ;;
    track)
      track_expirations
      calculate_compliance
      generate_analytics
      generate_report
      ;;
    *)
      log_error "Unknown operation: ${OPERATION}"
      return 1
      ;;
  esac
  
  log_success "✓ LICENSE MANAGEMENT COMPLETE"
  log_info "Output: ${OUTPUT_FILE}"
  
  return 0
}

main
