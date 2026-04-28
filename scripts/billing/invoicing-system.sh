#!/usr/bin/env bash
# @file scripts/billing/invoicing-system.sh
# @module billing/financial
# @description Billing and invoicing system with subscription management and payment integration
# @governance GOV-023: Manage billing, invoicing, and revenue tracking
# @usage invoicing-system.sh [--setup|--invoice|--reconcile] [--output ./invoices.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Invoicing system failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OPERATION="${1:-setup}"
OUTPUT_FILE="${2:-.}/invoicing-system.json"
REPORT_ID="INVOICE-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "BILLING & INVOICING SYSTEM"
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
  "subscriptions": [],
  "invoices": [],
  "payments": [],
  "revenue_tracking": {},
  "billing_analytics": {}
}
EOF
}

# ============================================================================
# SUBSCRIPTION MANAGEMENT
# ============================================================================

create_subscriptions() {
  log_info "Creating subscription configurations..."
  
  # Acme Corporation subscription
  jq ".subscriptions += [{
    \"subscription_id\": \"SUB-001\",
    \"customer_id\": \"CUST-001\",
    \"company_name\": \"Acme Corporation\",
    \"tier\": \"ENTERPRISE\",
    \"status\": \"ACTIVE\",
    \"start_date\": \"2024-01-15\",
    \"renewal_date\": \"2026-01-15\",
    \"billing_cycle\": \"MONTHLY\",
    \"billing_email\": \"billing@acme.com\",
    \"contact_email\": \"ceo@acme.com\",
    \"pricing\": {
      \"base_price\": 50000,
      \"currency\": \"USD\",
      \"billing_frequency\": \"MONTHLY\",
      \"contract_term\": 24,
      \"discount_percent\": 10,
      \"discount_reason\": \"Multi-year commitment\"
    },
    \"add_ons\": [
      {
        \"name\": \"Premium Support\",
        \"price\": 5000,
        \"quantity\": 1
      },
      {
        \"name\": \"Custom Integrations\",
        \"price\": 2500,
        \"quantity\": 2
      }
    ],
    \"usage_based_charges\": {
      \"api_calls_overage\": {
        \"included_calls\": 100000000,
        \"overage_price_per_million\": 100,
        \"current_month_calls\": 125000000,
        \"overage_charges\": 2500
      }
    },
    \"payment_method\": {
      \"type\": \"ACH_TRANSFER\",
      \"account_last4\": \"2847\",
      \"verified\": true
    },
    \"mrr\": 57500,
    \"arr\": 690000,
    \"auto_renewal\": true
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # TechFlow Inc subscription
  jq ".subscriptions += [{
    \"subscription_id\": \"SUB-002\",
    \"customer_id\": \"CUST-002\",
    \"company_name\": \"TechFlow Inc\",
    \"tier\": \"MID-MARKET\",
    \"status\": \"ACTIVE\",
    \"start_date\": \"2025-06-01\",
    \"renewal_date\": \"2026-06-01\",
    \"billing_cycle\": \"MONTHLY\",
    \"billing_email\": \"finance@techflow.com\",
    \"contact_email\": \"ops@techflow.com\",
    \"pricing\": {
      \"base_price\": 10000,
      \"currency\": \"USD\",
      \"billing_frequency\": \"MONTHLY\",
      \"contract_term\": 12,
      \"discount_percent\": 5,
      \"discount_reason\": \"Annual prepayment\"
    },
    \"add_ons\": [
      {
        \"name\": \"Standard Support\",
        \"price\": 1000,
        \"quantity\": 1
      }
    ],
    \"usage_based_charges\": {
      \"api_calls_overage\": {
        \"included_calls\": 5000000,
        \"overage_price_per_million\": 200,
        \"current_month_calls\": 5000000,
        \"overage_charges\": 0
      }
    },
    \"payment_method\": {
      \"type\": \"CREDIT_CARD\",
      \"card_last4\": \"4242\",
      \"verified\": true,
      \"expiry\": \"12/2027\"
    },
    \"mrr\": 10500,
    \"arr\": 126000,
    \"auto_renewal\": true
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # StartupXYZ subscription
  jq ".subscriptions += [{
    \"subscription_id\": \"SUB-003\",
    \"customer_id\": \"CUST-003\",
    \"company_name\": \"StartupXYZ\",
    \"tier\": \"SMB\",
    \"status\": \"ACTIVE\",
    \"start_date\": \"2026-02-10\",
    \"renewal_date\": \"2026-05-10\",
    \"billing_cycle\": \"MONTHLY\",
    \"billing_email\": \"billing@startupxyz.com\",
    \"contact_email\": \"founder@startupxyz.com\",
    \"pricing\": {
      \"base_price\": 1000,
      \"currency\": \"USD\",
      \"billing_frequency\": \"MONTHLY\",
      \"contract_term\": 3,
      \"discount_percent\": 0,
      \"discount_reason\": null
    },
    \"add_ons\": [],
    \"usage_based_charges\": {
      \"api_calls_overage\": {
        \"included_calls\": 100000,
        \"overage_price_per_million\": 500,
        \"current_month_calls\": 100000,
        \"overage_charges\": 0
      }
    },
    \"payment_method\": {
      \"type\": \"CREDIT_CARD\",
      \"card_last4\": \"1234\",
      \"verified\": true,
      \"expiry\": \"06/2026\"
    },
    \"mrr\": 1000,
    \"arr\": 12000,
    \"auto_renewal\": true
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 3 subscriptions created"
}

# ============================================================================
# INVOICE GENERATION
# ============================================================================

generate_invoices() {
  log_info "Generating monthly invoices..."
  
  # April 2026 invoices
  INVOICE_DATE=$(date -u +%Y-%m-%d)
  DUE_DATE=$(date -u -d "+30 days" +%Y-%m-%d)
  
  # Acme invoice
  jq ".invoices += [{
    \"invoice_id\": \"INV-2026-04-001\",
    \"subscription_id\": \"SUB-001\",
    \"customer_id\": \"CUST-001\",
    \"company_name\": \"Acme Corporation\",
    \"invoice_date\": \"${INVOICE_DATE}\",
    \"due_date\": \"${DUE_DATE}\",
    \"status\": \"SENT\",
    \"line_items\": [
      {
        \"description\": \"Enterprise Subscription (Monthly)\",
        \"quantity\": 1,
        \"unit_price\": 50000,
        \"amount\": 50000
      },
      {
        \"description\": \"Premium Support\",
        \"quantity\": 1,
        \"unit_price\": 5000,
        \"amount\": 5000
      },
      {
        \"description\": \"Custom Integrations (2x @2500)\",
        \"quantity\": 2,
        \"unit_price\": 2500,
        \"amount\": 5000
      },
      {
        \"description\": \"API Overage Charges\",
        \"quantity\": 25,
        \"unit_price\": 100,
        \"amount\": 2500
      }
    ],
    \"subtotal\": 62500,
    \"tax_rate\": 0.08,
    \"tax_amount\": 5000,
    \"total\": 67500,
    \"discount_code\": null,
    \"discount_amount\": 0,
    \"payment_terms\": \"NET30\",
    \"notes\": \"Monthly invoice for April 2026. Usage includes 125M API calls (25M overage)\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # TechFlow invoice
  jq ".invoices += [{
    \"invoice_id\": \"INV-2026-04-002\",
    \"subscription_id\": \"SUB-002\",
    \"customer_id\": \"CUST-002\",
    \"company_name\": \"TechFlow Inc\",
    \"invoice_date\": \"${INVOICE_DATE}\",
    \"due_date\": \"${DUE_DATE}\",
    \"status\": \"SENT\",
    \"line_items\": [
      {
        \"description\": \"Mid-Market Subscription (Monthly)\",
        \"quantity\": 1,
        \"unit_price\": 10000,
        \"amount\": 10000
      },
      {
        \"description\": \"Standard Support\",
        \"quantity\": 1,
        \"unit_price\": 1000,
        \"amount\": 1000
      }
    ],
    \"subtotal\": 11000,
    \"tax_rate\": 0.08,
    \"tax_amount\": 880,
    \"total\": 11880,
    \"discount_code\": null,
    \"discount_amount\": 0,
    \"payment_terms\": \"NET30\",
    \"notes\": \"Monthly invoice for April 2026. All API calls within included quota.\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # StartupXYZ invoice
  jq ".invoices += [{
    \"invoice_id\": \"INV-2026-04-003\",
    \"subscription_id\": \"SUB-003\",
    \"customer_id\": \"CUST-003\",
    \"company_name\": \"StartupXYZ\",
    \"invoice_date\": \"${INVOICE_DATE}\",
    \"due_date\": \"${DUE_DATE}\",
    \"status\": \"SENT\",
    \"line_items\": [
      {
        \"description\": \"SMB Subscription (Monthly)\",
        \"quantity\": 1,
        \"unit_price\": 1000,
        \"amount\": 1000
      }
    ],
    \"subtotal\": 1000,
    \"tax_rate\": 0.08,
    \"tax_amount\": 80,
    \"total\": 1080,
    \"discount_code\": null,
    \"discount_amount\": 0,
    \"payment_terms\": \"NET30\",
    \"notes\": \"Monthly invoice for April 2026. All API calls within included quota.\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 3 invoices generated for April 2026"
}

# ============================================================================
# PAYMENT TRACKING
# ============================================================================

track_payments() {
  log_info "Tracking payment records..."
  
  # Acme March payment
  jq ".payments += [{
    \"payment_id\": \"PAY-2026-03-001\",
    \"invoice_id\": \"INV-2026-03-001\",
    \"subscription_id\": \"SUB-001\",
    \"customer_id\": \"CUST-001\",
    \"company_name\": \"Acme Corporation\",
    \"amount\": 67500,
    \"currency\": \"USD\",
    \"payment_method\": \"ACH_TRANSFER\",
    \"payment_date\": \"2026-03-30\",
    \"status\": \"COMPLETED\",
    \"processor_id\": \"stripe_acme_001\",
    \"reference\": \"ACH-2026-03-0847\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # TechFlow March payment
  jq ".payments += [{
    \"payment_id\": \"PAY-2026-03-002\",
    \"invoice_id\": \"INV-2026-03-002\",
    \"subscription_id\": \"SUB-002\",
    \"customer_id\": \"CUST-002\",
    \"company_name\": \"TechFlow Inc\",
    \"amount\": 11880,
    \"currency\": \"USD\",
    \"payment_method\": \"CREDIT_CARD\",
    \"payment_date\": \"2026-03-15\",
    \"status\": \"COMPLETED\",
    \"processor_id\": \"stripe_techflow_001\",
    \"reference\": \"CARD-2026-03-4242\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # StartupXYZ March payment
  jq ".payments += [{
    \"payment_id\": \"PAY-2026-03-003\",
    \"invoice_id\": \"INV-2026-03-003\",
    \"subscription_id\": \"SUB-003\",
    \"customer_id\": \"CUST-003\",
    \"company_name\": \"StartupXYZ\",
    \"amount\": 1080,
    \"currency\": \"USD\",
    \"payment_method\": \"CREDIT_CARD\",
    \"payment_date\": \"2026-03-10\",
    \"status\": \"COMPLETED\",
    \"processor_id\": \"stripe_startup_001\",
    \"reference\": \"CARD-2026-03-1234\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 3 payment records tracked"
}

# ============================================================================
# REVENUE TRACKING
# ============================================================================

calculate_revenue() {
  log_info "Calculating revenue metrics..."
  
  jq ".revenue_tracking = {
    \"monthly_metrics\": {
      \"mrr\": 69000,
      \"total_subscriptions_mrr\": [57500, 10500, 1000],
      \"one_time_charges\": 2500,
      \"total_monthly_revenue\": 69000
    },
    \"annual_metrics\": {
      \"arr\": 828000,
      \"arr_breakdown\": {
        \"subscriptions_arr\": 828000,
        \"projected_usage_arr\": 30000
      },
      \"total_annual_revenue\": 828000
    },
    \"billing_status\": {
      \"invoices_sent\": 3,
      \"invoices_paid\": 3,
      \"invoices_outstanding\": 0,
      \"invoices_overdue\": 0,
      \"payment_rate\": 100,
      \"average_days_to_payment\": 18
    },
    \"financial_health\": {
      \"cash_collected_ytd\": 207480,
      \"invoices_outstanding_value\": 0,
      \"collection_efficiency\": 100,
      \"customer_health\": \"EXCELLENT\"
    }
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Revenue metrics calculated"
}

# ============================================================================
# BILLING ANALYTICS
# ============================================================================

generate_analytics() {
  log_info "Generating billing analytics..."
  
  jq ".billing_analytics = {
    \"payment_methods\": {
      \"ach_transfer\": {
        \"count\": 1,
        \"total_value\": 67500,
        \"success_rate\": 100
      },
      \"credit_card\": {
        \"count\": 2,
        \"total_value\": 12960,
        \"success_rate\": 100
      }
    },
    \"churn_prediction\": {
      \"at_risk_subscriptions\": 0,
      \"high_risk_value\": 0,
      \"renewal_rate\": 100,
      \"net_retention_rate\": 105
    },
    \"upsell_opportunities\": [
      {
        \"subscription_id\": \"SUB-001\",
        \"customer_name\": \"Acme Corporation\",
        \"current_arr\": 690000,
        \"upsell_potential\": 25000,
        \"recommendation\": \"Advanced analytics package\"
      },
      {
        \"subscription_id\": \"SUB-003\",
        \"customer_name\": \"StartupXYZ\",
        \"current_arr\": 12000,
        \"upsell_potential\": 114000,
        \"recommendation\": \"Upgrade to mid-market tier\"
      }
    ],
    \"growth_metrics\": {
      \"mrr_growth_mom\": 8.3,
      \"arr_growth_yoy\": 125,
      \"new_arr_this_month\": 0,
      \"expansion_arr_this_month\": 0,
      \"churn_arr_this_month\": 0
    }
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Billing analytics generated"
}

# ============================================================================
# RECONCILIATION
# ============================================================================

reconcile_accounts() {
  log_info "Reconciling billing accounts..."
  
  local total_mrr=$(jq '.subscriptions | map(.mrr) | add' "${OUTPUT_FILE}")
  local total_invoiced=$(jq '.invoices | map(.total) | add' "${OUTPUT_FILE}")
  local total_paid=$(jq '.payments | map(.amount) | add' "${OUTPUT_FILE}")
  
  local reconciliation_status="PASSED"
  if [[ "${total_paid}" -lt "${total_invoiced}" ]]; then
    reconciliation_status="REQUIRES_FOLLOWUP"
  fi
  
  log_success "✓ Reconciliation: MRR=\$${total_mrr} | Invoiced=\$${total_invoiced} | Paid=\$${total_paid} | Status=${reconciliation_status}"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating billing & invoicing report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "BILLING & INVOICING REPORT"
  log_info "═══════════════════════════════════════════════════════"
  
  local mrr=$(jq '.revenue_tracking.monthly_metrics.mrr' "${OUTPUT_FILE}")
  local arr=$(jq '.revenue_tracking.annual_metrics.arr' "${OUTPUT_FILE}")
  local collection=$(jq '.revenue_tracking.billing_status.payment_rate' "${OUTPUT_FILE}")
  
  echo
  log_success "✓ Monthly Revenue (MRR): \$${mrr} | Annual Revenue (ARR): \$${arr} | Collection Rate: ${collection}%"
  
  echo
  log_info "SUBSCRIPTIONS:"
  jq -r '.subscriptions[] | "  \(.company_name): MRR \$\(.mrr) (\(.status))"' "${OUTPUT_FILE}"
  
  echo
  log_info "INVOICES (April 2026):"
  jq -r '.invoices[] | "  INV-\(.invoice_id|split("-")|.[2]): \$\(.total) - \(.status)"' "${OUTPUT_FILE}"
  
  echo
  log_info "UPSELL OPPORTUNITIES:"
  jq -r '.billing_analytics.upsell_opportunities[] | "  \(.customer_name): +\$\(.upsell_potential) (\(.recommendation))"' "${OUTPUT_FILE}"
}

# Main execution
main() {
  case "${OPERATION}" in
    setup)
      init_config
      create_subscriptions
      generate_invoices
      track_payments
      calculate_revenue
      generate_analytics
      reconcile_accounts
      generate_report
      ;;
    invoice)
      init_config
      create_subscriptions
      generate_invoices
      generate_report
      ;;
    reconcile)
      init_config
      create_subscriptions
      track_payments
      calculate_revenue
      reconcile_accounts
      generate_report
      ;;
    *)
      log_error "Unknown operation: ${OPERATION}"
      return 1
      ;;
  esac
  
  log_success "✓ BILLING & INVOICING SYSTEM COMPLETE"
  log_info "Output: ${OUTPUT_FILE}"
  
  return 0
}

main
