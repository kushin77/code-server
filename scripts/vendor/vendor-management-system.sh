#!/usr/bin/env bash
# @file scripts/vendor/vendor-management-system.sh
# @module vendor/procurement
# @description Vendor management and procurement system with contracts and performance tracking
# @governance VENDOR-001: Manage third-party vendor relationships
# @usage vendor-management-system.sh [--setup|--evaluate|--audit] [--output ./vendors.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Vendor management system failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OPERATION="${1:-setup}"
OUTPUT_FILE="${2:-.}/vendor-management.json"
REPORT_ID="VENDOR-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "VENDOR MANAGEMENT & PROCUREMENT SYSTEM"
log_info "═══════════════════════════════════════════════════════"
log_info "Report ID: ${REPORT_ID}"
log_info "Operation: ${OPERATION}"
echo

# Initialize configuration
init_config() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "report_id": "${REPORT_ID}",
  "timestamp": "${GENERATION_TIME}",
  "vendors": [],
  "contracts": [],
  "procurement": [],
  "vendor_performance": {},
  "vendor_analytics": {}
}
EOF
}

# ============================================================================
# VENDOR PROFILES
# ============================================================================

create_vendor_profiles() {
  log_info "Creating vendor profiles..."
  
  # Cloud infrastructure vendor
  jq ".vendors += [{
    \"vendor_id\": \"VEND-001\",
    \"company_name\": \"CloudCore Infrastructure\",
    \"category\": \"CLOUD_SERVICES\",
    \"tier\": \"STRATEGIC\",
    \"status\": \"ACTIVE\",
    \"relationship_start_date\": \"2023-01-15\",
    \"primary_contact\": {
      \"name\": \"Robert Walsh\",
      \"email\": \"r.walsh@cloudcore.com\",
      \"phone\": \"+1-555-0201\"
    },
    \"contract_manager\": \"Sarah Chen\",
    \"location\": \"Seattle, WA\",
    \"certifications\": [
      \"SOC2_TYPE2\",
      \"ISO27001\",
      \"ISO9001\"
    ],
    \"services\": [
      \"Cloud hosting\",
      \"Infrastructure management\",
      \"Security services\"
    ],
    \"annual_spend\": 450000,
    \"payment_terms\": \"NET30\",
    \"performance_rating\": 4.7,
    \"risk_profile\": \"LOW\",
    \"data_residency\": \"US_EAST_1\",
    \"sla_uptime_pct\": 99.99
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Software licensing vendor
  jq ".vendors += [{
    \"vendor_id\": \"VEND-002\",
    \"company_name\": \"SoftLicense Pro\",
    \"category\": \"SOFTWARE_LICENSING\",
    \"tier\": \"CRITICAL\",
    \"status\": \"ACTIVE\",
    \"relationship_start_date\": \"2021-06-01\",
    \"primary_contact\": {
      \"name\": \"Maria Rodriguez\",
      \"email\": \"m.rodriguez@softlicense.com\",
      \"phone\": \"+1-555-0202\"
    },
    \"contract_manager\": \"James Miller\",
    \"location\": \"San Jose, CA\",
    \"certifications\": [
      \"BSA_MEMBER\",
      \"ISO27001\"
    ],
    \"services\": [
      \"Commercial software licenses\",
      \"License management\",
      \"Compliance support\"
    ],
    \"annual_spend\": 185000,
    \"payment_terms\": \"NET45\",
    \"performance_rating\": 4.3,
    \"risk_profile\": \"LOW\",
    \"licenses_managed\": 250,
    \"license_utilization_pct\": 87
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Database services vendor
  jq ".vendors += [{
    \"vendor_id\": \"VEND-003\",
    \"company_name\": \"DataSphere Solutions\",
    \"category\": \"DATABASE_SERVICES\",
    \"tier\": \"IMPORTANT\",
    \"status\": \"ACTIVE\",
    \"relationship_start_date\": \"2022-09-01\",
    \"primary_contact\": {
      \"name\": \"Thomas Anderson\",
      \"email\": \"t.anderson@datasphere.com\",
      \"phone\": \"+1-555-0203\"
    },
    \"contract_manager\": \"Lisa Park\",
    \"location\": \"Austin, TX\",
    \"certifications\": [
      \"SOC2_TYPE2\",
      \"ISO27001\",
      \"HIPAA_COMPLIANT\"
    ],
    \"services\": [
      \"Managed database services\",
      \"Backup and recovery\",
      \"Performance optimization\"
    ],
    \"annual_spend\": 125000,
    \"payment_terms\": \"NET30\",
    \"performance_rating\": 4.5,
    \"risk_profile\": \"LOW\",
    \"database_instances\": 12,
    \"backup_frequency\": \"HOURLY\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Consulting services vendor
  jq ".vendors += [{
    \"vendor_id\": \"VEND-004\",
    \"company_name\": \"TechConsult International\",
    \"category\": \"CONSULTING_SERVICES\",
    \"tier\": \"STANDARD\",
    \"status\": \"ACTIVE\",
    \"relationship_start_date\": \"2024-01-01\",
    \"primary_contact\": {
      \"name\": \"Jessica Brown\",
      \"email\": \"j.brown@techconsult.com\",
      \"phone\": \"+1-555-0204\"
    },
    \"contract_manager\": \"Michael Torres\",
    \"location\": \"New York, NY\",
    \"certifications\": [
      \"ISO27001\",
      \"AWS_PARTNER_PREMIER\"
    ],
    \"services\": [
      \"Architecture consulting\",
      \"Strategic planning\",
      \"Training services\"
    ],
    \"annual_spend\": 75000,
    \"payment_terms\": \"NET30\",
    \"performance_rating\": 4.2,
    \"risk_profile\": \"MEDIUM\",
    \"consultants_allocated\": 3,
    \"hourly_rate\": 250
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 4 vendor profiles created"
}

# ============================================================================
# CONTRACT MANAGEMENT
# ============================================================================

setup_contracts() {
  log_info "Setting up vendor contracts..."
  
  jq ".contracts = [
    {
      \"contract_id\": \"CONTRACT-001\",
      \"vendor_id\": \"VEND-001\",
      \"vendor_name\": \"CloudCore Infrastructure\",
      \"contract_type\": \"SERVICE_LEVEL_AGREEMENT\",
      \"start_date\": \"2023-01-15\",
      \"end_date\": \"2026-01-14\",
      \"status\": \"ACTIVE\",
      \"value_usd\": 1350000,
      \"renewal_date\": \"2025-10-14\",
      \"auto_renewal\": true,
      \"key_terms\": {
        \"minimum_commitment\": 450000,
        \"payment_terms\": \"NET30\",
        \"termination_clause\": \"30 days notice\",
        \"price_escalation\": 3.0
      },
      \"service_levels\": {
        \"uptime_sla\": 99.99,
        \"response_time_sla_minutes\": 30,
        \"penalty_per_violation_usd\": 5000
      },
      \"compliance\": {
        \"data_processing_agreement\": \"SIGNED\",
        \"security_audit_frequency\": \"ANNUAL\",
        \"last_audit_date\": \"2026-03-15\"
      }
    },
    {
      \"contract_id\": \"CONTRACT-002\",
      \"vendor_id\": \"VEND-002\",
      \"vendor_name\": \"SoftLicense Pro\",
      \"contract_type\": \"MAINTENANCE_SUPPORT\",
      \"start_date\": \"2021-06-01\",
      \"end_date\": \"2027-05-31\",
      \"status\": \"ACTIVE\",
      \"value_usd\": 555000,
      \"renewal_date\": \"2027-03-01\",
      \"auto_renewal\": true,
      \"key_terms\": {
        \"minimum_commitment\": 185000,
        \"payment_terms\": \"NET45\",
        \"termination_clause\": \"60 days notice\",
        \"price_escalation\": 2.5
      },
      \"support_hours\": \"24/7\",
      \"response_time_hours\": 1
    },
    {
      \"contract_id\": \"CONTRACT-003\",
      \"vendor_id\": \"VEND-003\",
      \"vendor_name\": \"DataSphere Solutions\",
      \"contract_type\": \"SERVICE_LEVEL_AGREEMENT\",
      \"start_date\": \"2022-09-01\",
      \"end_date\": \"2025-08-31\",
      \"status\": \"ACTIVE\",
      \"value_usd\": 375000,
      \"renewal_date\": \"2025-06-01\",
      \"auto_renewal\": false,
      \"key_terms\": {
        \"minimum_commitment\": 125000,
        \"payment_terms\": \"NET30\",
        \"termination_clause\": \"30 days notice\",
        \"price_escalation\": 4.0
      },
      \"service_levels\": {
        \"backup_rpo_minutes\": 60,
        \"recovery_rto_hours\": 1,
        \"availability_sla\": 99.95
      }
    }
  ]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 3 contracts configured"
}

# ============================================================================
# PROCUREMENT TRACKING
# ============================================================================

track_procurement() {
  log_info "Tracking procurement activity..."
  
  jq ".procurement = [
    {
      \"po_id\": \"PO-2026-0456\",
      \"vendor_id\": \"VEND-001\",
      \"vendor_name\": \"CloudCore Infrastructure\",
      \"po_date\": \"2026-04-15\",
      \"amount_usd\": 112500,
      \"description\": \"Q2 2026 cloud services\",
      \"status\": \"INVOICED\",
      \"invoice_date\": \"2026-04-20\",
      \"due_date\": \"2026-05-20\",
      \"payment_status\": \"PENDING\"
    },
    {
      \"po_id\": \"PO-2026-0457\",
      \"vendor_id\": \"VEND-002\",
      \"vendor_name\": \"SoftLicense Pro\",
      \"po_date\": \"2026-04-10\",
      \"amount_usd\": 46250,
      \"description\": \"Annual software license renewal\",
      \"status\": \"DELIVERED\",
      \"delivery_date\": \"2026-04-12\",
      \"due_date\": \"2026-05-25\",
      \"payment_status\": \"PENDING\"
    },
    {
      \"po_id\": \"PO-2026-0458\",
      \"vendor_id\": \"VEND-003\",
      \"vendor_name\": \"DataSphere Solutions\",
      \"po_date\": \"2026-04-01\",
      \"amount_usd\": 31250,
      \"description\": \"Database optimization services\",
      \"status\": \"IN_PROGRESS\",
      \"expected_completion\": \"2026-05-01\",
      \"due_date\": \"2026-05-01\",
      \"payment_status\": \"NOT_DUE\"
    },
    {
      \"po_id\": \"PO-2026-0459\",
      \"vendor_id\": \"VEND-004\",
      \"vendor_name\": \"TechConsult International\",
      \"po_date\": \"2026-04-05\",
      \"amount_usd\": 15000,
      \"description\": \"Architecture review consulting\",
      \"status\": \"COMPLETED\",
      \"completion_date\": \"2026-04-15\",
      \"due_date\": \"2026-05-05\",
      \"payment_status\": \"PENDING\"
    }
  ]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Procurement activity tracked"
}

# ============================================================================
# VENDOR PERFORMANCE EVALUATION
# ============================================================================

evaluate_performance() {
  log_info "Evaluating vendor performance..."
  
  jq ".vendor_performance = {
    \"evaluation_metrics\": {
      \"quality_score\": {
        \"weight\": 30,
        \"definition\": \"Deliverable quality and adherence to specs\"
      },
      \"reliability_score\": {
        \"weight\": 25,
        \"definition\": \"On-time delivery and SLA compliance\"
      },
      \"responsiveness_score\": {
        \"weight\": 20,
        \"definition\": \"Response time and issue resolution\"
      },
      \"cost_effectiveness_score\": {
        \"weight\": 15,
        \"definition\": \"Value for money and cost management\"
      },
      \"innovation_score\": {
        \"weight\": 10,
        \"definition\": \"Continuous improvement and innovation\"
      }
    },
    \"vendor_scorecards\": [
      {
        \"vendor_id\": \"VEND-001\",
        \"vendor_name\": \"CloudCore Infrastructure\",
        \"evaluation_period\": \"2026-Q1\",
        \"quality_score\": 95,
        \"reliability_score\": 99,
        \"responsiveness_score\": 92,
        \"cost_effectiveness_score\": 88,
        \"innovation_score\": 85,
        \"overall_score\": 92.0,
        \"rating\": \"EXCELLENT\",
        \"status\": \"APPROVED_FOR_RENEWAL\"
      },
      {
        \"vendor_id\": \"VEND-002\",
        \"vendor_name\": \"SoftLicense Pro\",
        \"evaluation_period\": \"2026-Q1\",
        \"quality_score\": 88,
        \"reliability_score\": 90,
        \"responsiveness_score\": 85,
        \"cost_effectiveness_score\": 80,
        \"innovation_score\": 78,
        \"overall_score\": 85.0,
        \"rating\": \"GOOD\",
        \"status\": \"APPROVED_FOR_RENEWAL\"
      },
      {
        \"vendor_id\": \"VEND-003\",
        \"vendor_name\": \"DataSphere Solutions\",
        \"evaluation_period\": \"2026-Q1\",
        \"quality_score\": 92,
        \"reliability_score\": 96,
        \"responsiveness_score\": 94,
        \"cost_effectiveness_score\": 85,
        \"innovation_score\": 88,
        \"overall_score\": 91.0,
        \"rating\": \"EXCELLENT\",
        \"status\": \"APPROVED_FOR_RENEWAL\"
      },
      {
        \"vendor_id\": \"VEND-004\",
        \"vendor_name\": \"TechConsult International\",
        \"evaluation_period\": \"2026-Q1\",
        \"quality_score\": 85,
        \"reliability_score\": 82,
        \"responsiveness_score\": 88,
        \"cost_effectiveness_score\": 90,
        \"innovation_score\": 92,
        \"overall_score\": 87.0,
        \"rating\": \"GOOD\",
        \"status\": \"APPROVED_WITH_FEEDBACK\"
      }
    ]
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Vendor performance evaluated"
}

# ============================================================================
# VENDOR ANALYTICS
# ============================================================================

generate_vendor_analytics() {
  log_info "Generating vendor analytics..."
  
  jq ".vendor_analytics = {
    \"spending_overview\": {
      \"total_annual_vendor_spend\": 835000,
      \"ytd_vendor_spend\": 205000,
      \"by_category\": {
        \"cloud_services\": 450000,
        \"software_licensing\": 185000,
        \"database_services\": 125000,
        \"consulting_services\": 75000
      },
      \"spending_trend\": \"STABLE\"
    },
    \"vendor_concentration\": {
      \"top_3_vendors_pct\": 82,
      \"vendor_count\": 4,
      \"risk_level\": \"MEDIUM\",
      \"contingency_plan\": \"REQUIRED_FOR_CRITICAL_SERVICES\"
    },
    \"contract_expiration\": {
      \"contracts_expiring_next_90_days\": 1,
      \"contracts_requiring_renewal\": [
        {
          \"vendor_name\": \"DataSphere Solutions\",
          \"expiration_date\": \"2025-08-31\",
          \"renewal_required_by\": \"2025-06-01\",
          \"status\": \"REQUIRES_ATTENTION\"
        }
      ]
    },
    \"risk_assessment\": {
      \"critical_vendors_with_backup\": 3,
      \"critical_vendors_without_backup\": 0,
      \"compliance_violations\": 0,
      \"security_incidents\": 0,
      \"overall_risk_score\": 2,
      \"risk_rating\": \"LOW\"
    },
    \"cost_optimization\": {
      \"potential_savings_identified\": 45000,
      \"optimization_initiatives\": [
        {
          \"vendor\": \"SoftLicense Pro\",
          \"initiative\": \"License audit and optimization\",
          \"potential_savings\": 25000,
          \"implementation_effort\": \"MEDIUM\"
        },
        {
          \"vendor\": \"CloudCore Infrastructure\",
          \"initiative\": \"Reserved capacity commitment\",
          \"potential_savings\": 20000,
          \"implementation_effort\": \"LOW\"
        }
      ]
    }
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Vendor analytics generated"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating vendor management report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "VENDOR MANAGEMENT & PROCUREMENT REPORT"
  log_info "═══════════════════════════════════════════════════════"
  
  local total_spend=$(jq '.vendor_analytics.spending_overview.total_annual_vendor_spend' "${OUTPUT_FILE}")
  local vendor_count=$(jq '.vendor_analytics.vendor_concentration.vendor_count' "${OUTPUT_FILE}")
  local risk=$(jq -r '.vendor_analytics.risk_assessment.risk_rating' "${OUTPUT_FILE}")
  
  echo
  log_success "✓ Total Annual Spend: \$${total_spend} | Active Vendors: ${vendor_count} | Risk Rating: ${risk}"
  
  echo
  log_info "ACTIVE VENDORS:"
  jq -r '.vendors[] | "  \(.company_name): \(.category) | Tier: \(.tier) | Rating: \(.performance_rating)"' "${OUTPUT_FILE}"
  
  echo
  log_info "VENDOR PERFORMANCE SCORECARDS:"
  jq -r '.vendor_performance.vendor_scorecards[] | "  \(.vendor_name): \(.overall_score) (\(.rating))"' "${OUTPUT_FILE}"
  
  echo
  log_info "PROCUREMENT ACTIVITY:"
  jq -r '.procurement[] | "  PO-\(.po_id|split("-")|.[1]): \$\(.amount_usd) | Status: \(.status)"' "${OUTPUT_FILE}"
}

# Main execution
main() {
  case "${OPERATION}" in
    setup)
      init_config
      create_vendor_profiles
      setup_contracts
      track_procurement
      evaluate_performance
      generate_vendor_analytics
      generate_report
      ;;
    evaluate)
      init_config
      create_vendor_profiles
      evaluate_performance
      generate_vendor_analytics
      generate_report
      ;;
    audit)
      init_config
      create_vendor_profiles
      setup_contracts
      generate_vendor_analytics
      generate_report
      ;;
    *)
      log_error "Unknown operation: ${OPERATION}"
      return 1
      ;;
  esac
  
  log_success "✓ VENDOR MANAGEMENT SYSTEM COMPLETE"
  log_info "Output: ${OUTPUT_FILE}"
  
  return 0
}

main
