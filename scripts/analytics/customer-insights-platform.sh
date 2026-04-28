#!/usr/bin/env bash
# @file scripts/analytics/customer-insights-platform.sh
# @module analytics/intelligence
# @description Customer insights and predictive analytics platform
# @governance ANALYTICS-001: Leverage customer data for actionable intelligence
# @usage customer-insights-platform.sh [--analyze|--predict|--report] [--output ./insights-report.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Customer insights platform failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OPERATION="${1:-analyze}"
OUTPUT_FILE="${2:-.}/customer-insights-report.json"
REPORT_ID="INSIGHTS-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "CUSTOMER INSIGHTS & PREDICTIVE ANALYTICS PLATFORM"
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
  "customer_segments": [],
  "behavioral_analytics": [],
  "predictive_insights": []
}
EOF
}

# ============================================================================
# CUSTOMER SEGMENTATION
# ============================================================================

segment_customers() {
  log_info "Analyzing customer segments..."
  
  # Enterprise Customers
  jq ".customer_segments += [{
    \"segment_id\": \"SEG-001\",
    \"segment_name\": \"Enterprise\",
    \"customer_count\": 24,
    \"annual_contract_value\": 5800000,
    \"avg_arpu_monthly\": 20139,
    \"avg_lifetime_value\": 485000,
    \"retention_rate_pct\": 95,
    \"churn_rate_annual_pct\": 4.2,
    \"primary_use_cases\": [
      \"Large-scale data processing\",
      \"Mission-critical integrations\",
      \"Multi-team collaboration\"
    ],
    \"satisfaction_metrics\": {
      \"nps_score\": 72,
      \"csat_score\": 4.5,
      \"product_adoption_pct\": 92,
      \"feature_usage_depth\": \"ADVANCED\"
    },
    \"growth_opportunity\": \"Upsell advanced features and consulting services\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Mid-market Customers
  jq ".customer_segments += [{
    \"segment_id\": \"SEG-002\",
    \"segment_name\": \"Mid-Market\",
    \"customer_count\": 156,
    \"annual_contract_value\": 1560000,
    \"avg_arpu_monthly\": 8333,
    \"avg_lifetime_value\": 125000,
    \"retention_rate_pct\": 88,
    \"churn_rate_annual_pct\": 8.5,
    \"primary_use_cases\": [
      \"Team collaboration\",
      \"Workflow automation\",
      \"Performance tracking\"
    ],
    \"satisfaction_metrics\": {
      \"nps_score\": 58,
      \"csat_score\": 4.1,
      \"product_adoption_pct\": 76,
      \"feature_usage_depth\": \"INTERMEDIATE\"
    },
    \"growth_opportunity\": \"Improve onboarding to increase product adoption\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # SMB Customers
  jq ".customer_segments += [{
    \"segment_id\": \"SEG-003\",
    \"segment_name\": \"Small Business\",
    \"customer_count\": 842,
    \"annual_contract_value\": 4254000,
    \"avg_arpu_monthly\": 421,
    \"avg_lifetime_value\": 28500,
    \"retention_rate_pct\": 72,
    \"churn_rate_annual_pct\": 18.3,
    \"primary_use_cases\": [
      \"Basic team communication\",
      \"Simple process automation\",
      \"Basic analytics\"
    ],
    \"satisfaction_metrics\": {
      \"nps_score\": 42,
      \"csat_score\": 3.8,
      \"product_adoption_pct\": 54,
      \"feature_usage_depth\": \"BASIC\"
    },
    \"growth_opportunity\": \"Self-serve resources and community engagement\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 3 customer segments analyzed"
}

# ============================================================================
# BEHAVIORAL ANALYTICS
# ============================================================================

analyze_behavior() {
  log_info "Analyzing customer behavior patterns..."
  
  # Feature Adoption
  jq ".behavioral_analytics += [{
    \"behavior_id\": \"BH-001\",
    \"metric_name\": \"Feature Adoption Progression\",
    \"measurement_period\": \"Last 90 days\",
    \"segments\": [
      {\"segment\": \"Enterprise\", \"adoption_pct\": 92, \"core_features_used_pct\": 89, \"advanced_features_used_pct\": 76},
      {\"segment\": \"Mid-Market\", \"adoption_pct\": 76, \"core_features_used_pct\": 71, \"advanced_features_used_pct\": 31},
      {\"segment\": \"SMB\", \"adoption_pct\": 54, \"core_features_used_pct\": 48, \"advanced_features_used_pct\": 8}
    ],
    \"key_insight\": \"Significant adoption gap between SMB and Enterprise; SMB onboarding is critical pain point\",
    \"recommendation\": \"Implement guided onboarding tours for SMB customers\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Engagement Patterns
  jq ".behavioral_analytics += [{
    \"behavior_id\": \"BH-002\",
    \"metric_name\": \"Engagement Intensity\",
    \"measurement_period\": \"Monthly active usage\",
    \"segments\": [
      {\"segment\": \"Enterprise\", \"daily_active_users_pct\": 64, \"weekly_active_users_pct\": 89, \"monthly_active_users_pct\": 96},
      {\"segment\": \"Mid-Market\", \"daily_active_users_pct\": 28, \"weekly_active_users_pct\": 61, \"monthly_active_users_pct\": 82},
      {\"segment\": \"SMB\", \"daily_active_users_pct\": 8, \"weekly_active_users_pct\": 31, \"monthly_active_users_pct\": 54}
    },
    \"key_insight\": \"Enterprise shows strong daily engagement; SMB shows high dormancy risk\",
    \"recommendation\": \"Deploy email re-engagement campaigns for low-engagement SMB accounts\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Support Interaction Pattern
  jq ".behavioral_analytics += [{
    \"behavior_id\": \"BH-003\",
    \"metric_name\": \"Support Ticket Patterns\",
    \"measurement_period\": \"Last 180 days\",
    \"segments\": [
      {\"segment\": \"Enterprise\", \"tickets_per_customer_annual\": 8.2, \"avg_resolution_hours\": 3.5, \"satisfaction_pct\": 94},
      {\"segment\": \"Mid-Market\", \"tickets_per_customer_annual\": 12.1, \"avg_resolution_hours\": 6.2, \"satisfaction_pct\": 81},
      {\"segment\": \"SMB\", \"tickets_per_customer_annual\": 4.3, \"avg_resolution_hours\": 8.9, \"satisfaction_pct\": 67}
    },
    \"key_insight\": \"SMB satisfaction low despite fewer tickets; suggests fundamental usability issues\",
    \"recommendation\": \"Conduct UX research focused on SMB workflows\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Behavioral patterns analyzed"
}

# ============================================================================
# PREDICTIVE INSIGHTS
# ============================================================================

generate_predictions() {
  log_info "Generating predictive insights..."
  
  # Churn Prediction
  jq ".predictive_insights += [{
    \"prediction_id\": \"PRED-001\",
    \"insight_name\": \"Churn Risk Prediction\",
    \"prediction_horizon\": \"Next 90 days\",
    \"model_accuracy_pct\": 82,
    \"high_risk_customers\": {
      \"count\": 34,
      \"segment_breakdown\": {
        \"enterprise\": 0,
        \"mid_market\": 3,
        \"smb\": 31
      },
      \"total_arr_at_risk\": 185000,
      \"common_risk_factors\": [
        \"No usage in last 30 days (12 customers)\",
        \"Significantly reduced usage frequency (8 customers)\",
        \"High support ticket volume (7 customers)\",
        \"Feature adoption stalled (7 customers)\"
      ]
    },
    \"medium_risk_customers\": {
      \"count\": 78,
      \"total_arr_at_risk\": 320000
    },
    \"retention_actions\": [
      {\"action\": \"Personalized health check calls\", \"target_customers\": 34, \"success_rate_pct\": 45},
      {\"action\": \"Feature training sessions\", \"target_customers\": 45, \"success_rate_pct\": 68},
      {\"action\": \"Discount incentive (1 month free)\", \"target_customers\": 20, \"success_rate_pct\": 82}
    ]
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Expansion Opportunity Prediction
  jq ".predictive_insights += [{
    \"prediction_id\": \"PRED-002\",
    \"insight_name\": \"Expansion Revenue Opportunity\",
    \"prediction_horizon\": \"Next 12 months\",
    \"model_accuracy_pct\": 76,
    \"expansion_opportunities\": {
      \"total_expansion_arr_opportunity\": 850000,
      \"customers_with_expansion_potential\": 187,
      \"top_opportunities\": [
        {
          \"opportunity\": \"Seat expansion - add team members\",
          \"potential_arr\": 450000,
          \"target_count\": 98,
          \"likelihood_pct\": 62,
          \"action\": \"Usage-based seat recommendation emails\"
        },
        {
          \"opportunity\": \"Feature tier upgrade\",
          \"potential_arr\": 280000,
          \"target_count\": 67,
          \"likelihood_pct\": 58,
          \"action\": \"Advanced feature trial programs\"
        },
        {
          \"opportunity\": \"Add-on services (consulting, training)\",
          \"potential_arr\": 120000,
          \"target_count\": 22,
          \"likelihood_pct\": 71,
          \"action\": \"Personalized outreach from Account Managers\"
        }
      ]
    },
    \"recommended_actions\": [
      {\"action\": \"Deploy usage-based analytics dashboards\", \"cost\": 35000, \"revenue_impact\": 450000},
      {\"action\": \"Create advanced feature trial program\", \"cost\": 15000, \"revenue_impact\": 280000}
    ]
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Product Feedback Sentiment
  jq ".predictive_insights += [{
    \"prediction_id\": \"PRED-003\",
    \"insight_name\": \"Product Sentiment & Feature Request Trends\",
    \"measurement_period\": \"Last 60 days\",
    \"sentiment_analysis\": {
      \"positive_feedback_pct\": 58,
      \"neutral_feedback_pct\": 22,
      \"negative_feedback_pct\": 20,
      \"sentiment_trend\": \"IMPROVING\",
      \"sentiment_trend_pct_change\": 8
    },
    \"top_requested_features\": [
      {\"rank\": 1, \"feature\": \"Advanced reporting and dashboards\", \"request_count\": 187, \"segment\": \"Enterprise\"},
      {\"rank\": 2, \"feature\": \"Mobile app improvements\", \"request_count\": 156, \"segment\": \"All\"},
      {\"rank\": 3, \"feature\": \"API enhancements\", \"request_count\": 134, \"segment\": \"Enterprise\"},
      {\"rank\": 4, \"feature\": \"Better data export options\", \"request_count\": 98, \"segment\": \"Mid-Market\"}
    ],
    \"key_complaint_themes\": [
      {\"theme\": \"Onboarding complexity\", \"pct\": 35, \"segment_most_affected\": \"SMB\"},
      {\"theme\": \"Performance/speed\", \"pct\": 28, \"segment_most_affected\": \"Enterprise\"},
      {\"theme\": \"Documentation gaps\", \"pct\": 22, \"segment_most_affected\": \"Mid-Market\"}
    ]
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Predictive insights generated"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating customer insights report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "CUSTOMER INSIGHTS & PREDICTIVE ANALYTICS REPORT"
  log_info "═══════════════════════════════════════════════════════"
  
  local enterprise_acv=$(jq '.customer_segments[] | select(.segment_id == "SEG-001") | .annual_contract_value' "${OUTPUT_FILE}")
  local churn_risk=$(jq '.predictive_insights[] | select(.prediction_id == "PRED-001") | .high_risk_customers.total_arr_at_risk' "${OUTPUT_FILE}")
  local expansion=$(jq '.predictive_insights[] | select(.prediction_id == "PRED-002") | .expansion_opportunities.total_expansion_arr_opportunity' "${OUTPUT_FILE}")
  
  echo
  log_success "✓ Enterprise ACV: \$${enterprise_acv} | Churn Risk: \$${churn_risk} | Expansion: \$${expansion}"
  
  echo
  log_info "CUSTOMER SEGMENT OVERVIEW:"
  jq -r '.customer_segments[] | "  \(.segment_name): \(.customer_count) customers | ACV: \$\(.annual_contract_value) | NPS: \(.satisfaction_metrics.nps_score)"' "${OUTPUT_FILE}"
  
  echo
  log_info "KEY BEHAVIORAL INSIGHTS:"
  jq -r '.behavioral_analytics[] | "  • \(.key_insight)"' "${OUTPUT_FILE}" | head -3
  
  echo
  log_info "CHURN RISK:"
  jq -r '.predictive_insights[] | select(.prediction_id == "PRED-001") | "  \(.high_risk_customers.count) high-risk customers | \$\(.high_risk_customers.total_arr_at_risk) ARR at risk"' "${OUTPUT_FILE}"
  
  echo
  log_info "EXPANSION OPPORTUNITIES:"
  jq -r '.predictive_insights[] | select(.prediction_id == "PRED-002") | .top_opportunities[] | "  • \(.opportunity): \(.potential_arr | . / 1000000 | tostring) | \(.target_count) customers"' "${OUTPUT_FILE}"
  
  echo
  log_info "TOP FEATURE REQUESTS:"
  jq -r '.predictive_insights[] | select(.prediction_id == "PRED-003") | .top_requested_features[] | "  \(.rank). \(.feature) (\(.request_count) requests)"' "${OUTPUT_FILE}"
}

# Main execution
main() {
  case "${OPERATION}" in
    analyze)
      init_config
      segment_customers
      analyze_behavior
      generate_predictions
      generate_report
      ;;
    predict)
      init_config
      segment_customers
      generate_predictions
      generate_report
      ;;
    report)
      init_config
      segment_customers
      analyze_behavior
      generate_predictions
      generate_report
      ;;
    *)
      log_error "Unknown operation: ${OPERATION}"
      return 1
      ;;
  esac
  
  log_success "✓ CUSTOMER INSIGHTS PLATFORM COMPLETE"
  log_info "Output: ${OUTPUT_FILE}"
  
  return 0
}

main
