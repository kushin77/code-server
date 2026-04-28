#!/usr/bin/env bash
# @file scripts/support/customer-support-system.sh
# @module support/operations
# @description Customer support ticketing and case management system
# @governance SUPPORT-001: Ensure responsive and effective customer support
# @usage customer-support-system.sh [--create|--analyze|--report] [--output ./support-report.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Support system failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OPERATION="${1:-create}"
OUTPUT_FILE="${2:-.}/customer-support-report.json"
REPORT_ID="SUPPORT-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "CUSTOMER SUPPORT & CASE MANAGEMENT SYSTEM"
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
  "support_channels": [],
  "active_tickets": [],
  "support_analytics": {}
}
EOF
}

# ============================================================================
# SUPPORT CHANNELS
# ============================================================================

setup_channels() {
  log_info "Setting up support channels..."
  
  jq ".support_channels = [
    {
      \"channel_id\": \"CH-001\",
      \"name\": \"Email Support\",
      \"availability_hours\": \"24/7\",
      \"first_response_sla_hours\": 2,
      \"resolution_sla_hours\": 24,
      \"team_size\": 12,
      \"avg_volume_daily\": 450,
      \"avg_satisfaction_score\": 4.2,
      \"avg_resolution_time_hours\": 4.5
    },
    {
      \"channel_id\": \"CH-002\",
      \"name\": \"Live Chat\",
      \"availability_hours\": \"Mon-Fri 8am-6pm EST, Sat 9am-5pm EST\",
      \"first_response_sla_minutes\": 3,
      \"resolution_sla_hours\": 4,
      \"team_size\": 8,
      \"avg_volume_daily\": 280,
      \"avg_satisfaction_score\": 4.6,
      \"avg_resolution_time_minutes\": 18
    },
    {
      \"channel_id\": \"CH-003\",
      \"name\": \"Phone Support\",
      \"availability_hours\": \"Mon-Fri 8am-8pm EST, Sat 9am-5pm EST\",
      \"first_response_sla_minutes\": 1,
      \"resolution_sla_hours\": 2,
      \"team_size\": 6,
      \"avg_volume_daily\": 120,
      \"avg_satisfaction_score\": 4.4,
      \"avg_resolution_time_minutes\": 35
    },
    {
      \"channel_id\": \"CH-004\",
      \"name\": \"Community Forum\",
      \"availability_hours\": \"24/7\",
      \"first_response_sla_hours\": 8,
      \"resolution_sla_hours\": 48,
      \"team_size\": 4,
      \"avg_volume_daily\": 95,
      \"avg_satisfaction_score\": 4.1,
      \"avg_resolution_time_hours\": 6.2
    },
    {
      \"channel_id\": \"CH-005\",
      \"name\": \"Knowledge Base\",
      \"availability_hours\": \"24/7\",
      \"first_response_sla_hours\": 0,
      \"resolution_sla_hours\": 0,
      \"team_size\": 3,
      \"avg_volume_daily\": 2100,
      \"avg_satisfaction_score\": 3.9,
      \"self_resolution_rate_pct\": 28
    }
  ]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 5 support channels configured"
}

# ============================================================================
# ACTIVE TICKETS
# ============================================================================

populate_tickets() {
  log_info "Populating active support tickets..."
  
  # Critical ticket
  jq ".active_tickets += [{
    \"ticket_id\": \"TKT-2026-0892\",
    \"priority\": \"CRITICAL\",
    \"status\": \"IN_PROGRESS\",
    \"customer\": \"Enterprise Corp\",
    \"account_value_annual\": 250000,
    \"subject\": \"Production API Error - Affecting 45% of transactions\",
    \"channel\": \"Phone\",
    \"created_at\": \"2026-04-28T12:15:00Z\",
    \"assigned_to\": \"Senior Support Engineer\",
    \"time_to_respond_minutes\": 2,
    \"current_time_open_minutes\": 18,
    \"business_impact\": \"Customer revenue loss estimated at $2,500/hour\",
    \"estimated_resolution_time_minutes\": 15,
    \"escalation_level\": 2,
    \"internal_ticket_references\": [\"BUG-1234\", \"INC-2026-0045\"]
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # High priority ticket
  jq ".active_tickets += [{
    \"ticket_id\": \"TKT-2026-0891\",
    \"priority\": \"HIGH\",
    \"status\": \"WAITING_CUSTOMER\",
    \"customer\": \"TechFlow Solutions\",
    \"account_value_annual\": 85000,
    \"subject\": \"Dashboard Performance Issues - Pages Loading Slow\",
    \"channel\": \"Email\",
    \"created_at\": \"2026-04-28T08:30:00Z\",
    \"assigned_to\": \"Support Engineer\",
    \"time_to_respond_minutes\": 45,
    \"current_time_open_minutes\": 360,
    \"business_impact\": \"Customer productivity impacted\",
    \"estimated_resolution_time_hours\": 2,
    \"escalation_level\": 1,
    \"waiting_for\": \"Customer feedback on performance metrics\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Medium priority ticket
  jq ".active_tickets += [{
    \"ticket_id\": \"TKT-2026-0890\",
    \"priority\": \"MEDIUM\",
    \"status\": \"IN_PROGRESS\",
    \"customer\": \"StartupXYZ\",
    \"account_value_annual\": 12500,
    \"subject\": \"Feature Request - Export to CSV\",
    \"channel\": \"Chat\",
    \"created_at\": \"2026-04-27T14:20:00Z\",
    \"assigned_to\": \"Support Specialist\",
    \"time_to_respond_minutes\": 3,
    \"current_time_open_minutes\": 1440,
    \"business_impact\": \"Workflow enhancement\",
    \"estimated_resolution_time_hours\": 4,
    \"escalation_level\": 0,
    \"notes\": \"Feature already in backlog - provided target delivery timeline\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Active tickets populated"
}

# ============================================================================
# SUPPORT ANALYTICS
# ============================================================================

generate_support_analytics() {
  log_info "Generating support analytics..."
  
  jq ".support_analytics = {
    \"volume_metrics\": {
      \"total_tickets_all_time\": 18234,
      \"total_tickets_ytd\": 4521,
      \"total_tickets_this_month\": 892,
      \"open_tickets_current\": 87,
      \"closed_tickets_today\": 34,
      \"avg_daily_volume\": 234,
      \"volume_trend\": \"STABLE\"
    },
    \"sla_compliance\": {
      \"first_response_sla_compliance_pct\": 94.3,
      \"resolution_sla_compliance_pct\": 87.5,
      \"critical_ticket_sla_compliance_pct\": 98.2,
      \"high_ticket_sla_compliance_pct\": 92.1,
      \"medium_ticket_sla_compliance_pct\": 85.6,
      \"sla_breaches_this_month\": 18,
      \"trend\": \"IMPROVING\"
    },
    \"satisfaction_metrics\": {
      \"average_csat_score\": 4.26,
      \"nps_score\": 62,
      \"customer_effort_score\": 2.1,
      \"ticket_satisfaction_by_channel\": {
        \"email\": 4.2,
        \"chat\": 4.6,
        \"phone\": 4.4,
        \"forum\": 4.1,
        \"knowledge_base\": 3.9
      },
      \"customers_very_satisfied_pct\": 76,
      \"satisfaction_trend\": \"IMPROVING\"
    },
    \"efficiency_metrics\": {
      \"avg_first_response_time_hours\": 0.8,
      \"avg_resolution_time_hours\": 5.2,
      \"median_resolution_time_hours\": 2.1,
      \"p95_resolution_time_hours\": 18.5,
      \"average_interactions_per_ticket\": 2.3,
      \"first_contact_resolution_rate_pct\": 58,
      \"ticket_reopening_rate_pct\": 8.2
    },
    \"agent_performance\": {
      \"total_agents\": 33,
      \"avg_tickets_per_agent_daily\": 7.1,
      \"avg_resolution_rating\": 4.31,
      \"top_performer\": {
        \"name\": \"Alice Johnson\",
        \"tickets_resolved\": 156,
        \"avg_resolution_time_hours\": 3.2,
        \"satisfaction_score\": 4.7
      },
      \"agent_utilization_pct\": 82
    },
    \"issue_analysis\": {
      \"top_issue_categories\": [
        {\"category\": \"API/Integration Issues\", \"pct_of_volume\": 28, \"trend\": \"DOWN\"},
        {\"category\": \"Feature Questions\", \"pct_of_volume\": 22, \"trend\": \"STABLE\"},
        {\"category\": \"Billing/Account\", \"pct_of_volume\": 18, \"trend\": \"UP\"},
        {\"category\": \"Technical Bugs\", \"pct_of_volume\": 16, \"trend\": \"DOWN\"},
        {\"category\": \"Performance Issues\", \"pct_of_volume\": 11, \"trend\": \"UP\"},
        {\"category\": \"Other\", \"pct_of_volume\": 5, \"trend\": \"STABLE\"}
      ],
      \"critical_issues_discovered_this_month\": 5,
      \"issues_escalated_to_engineering\": 12,
      \"issues_resolved_with_kb_article\": 45
    },
    \"key_opportunities\": [
      {
        \"priority\": \"HIGH\",
        \"opportunity\": \"Improve first contact resolution (58% → 70%)\",
        \"action\": \"Enhance agent training and knowledge base\",
        \"potential_impact\": \"Reduce resolution time by 25%, improve CSAT by 0.5 points\",
        \"owner\": \"Support Manager\",
        \"target_date\": \"2026-06-30\"
      },
      {
        \"priority\": \"HIGH\",
        \"opportunity\": \"Reduce API integration support tickets (28% → 15%)\",
        \"action\": \"Improve API documentation and provide API sandbox\",
        \"potential_impact\": \"28% reduction in support volume, 15% cost savings\",
        \"owner\": \"Product + Support\",
        \"target_date\": \"2026-07-30\"
      },
      {
        \"priority\": \"MEDIUM\",
        \"opportunity\": \"Expand knowledge base self-service coverage (28% → 40%)\",
        \"action\": \"Create 50 new KB articles for common issues\",
        \"potential_impact\": \"12% reduction in ticket volume, improved customer satisfaction\",
        \"owner\": \"Support Team\",
        \"target_date\": \"2026-06-15\"
      }
    ],
    \"resource_planning\": {
      \"current_staffing_level\": 33,
      \"recommended_staffing_level\": 36,
      \"staffing_gap\": -3,
      \"forecast_peak_season_staffing\": 42,
      \"training_investment_annual\": 125000,
      \"tool_investment_annual\": 85000,
      \"total_support_cost_annual\": 1850000,
      \"cost_per_ticket\": 410,
      \"cost_trend\": \"STABLE\"
    }
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Support analytics generated"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating customer support report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "CUSTOMER SUPPORT & CASE MANAGEMENT REPORT"
  log_info "═══════════════════════════════════════════════════════"
  
  local tickets=$(jq '.support_analytics.volume_metrics.open_tickets_current' "${OUTPUT_FILE}")
  local csat=$(jq '.support_analytics.satisfaction_metrics.average_csat_score' "${OUTPUT_FILE}")
  local resolution=$(jq '.support_analytics.efficiency_metrics.avg_resolution_time_hours' "${OUTPUT_FILE}")
  
  echo
  log_success "✓ Open Tickets: ${tickets} | CSAT: ${csat}/5.0 | Avg Resolution: ${resolution}h"
  
  echo
  log_info "SUPPORT CHANNELS PERFORMANCE:"
  jq -r '.support_channels[] | "  \(.name): \(.avg_volume_daily) daily | CSAT: \(.avg_satisfaction_score)/5 | Resolution: \(.avg_resolution_time_hours // .avg_resolution_time_minutes)"' "${OUTPUT_FILE}"
  
  echo
  log_info "ACTIVE TICKETS:"
  jq -r '.active_tickets[] | "  [\(.priority)] \(.subject) | \(.customer) | Open: \(.current_time_open_minutes)min"' "${OUTPUT_FILE}"
  
  echo
  log_info "SLA COMPLIANCE:"
  jq -r '.support_analytics.sla_compliance | "  First Response: \(.first_response_sla_compliance_pct)% | Resolution: \(.resolution_sla_compliance_pct)% | Critical: \(.critical_ticket_sla_compliance_pct)%"' "${OUTPUT_FILE}"
  
  echo
  log_info "TOP ISSUES THIS MONTH:"
  jq -r '.support_analytics.issue_analysis.top_issue_categories[] | select(.pct_of_volume >= 16) | "  \(.category): \(.pct_of_volume)% of volume (\(.trend))"' "${OUTPUT_FILE}"
  
  echo
  log_info "KEY RECOMMENDATIONS:"
  jq -r '.support_analytics.key_opportunities[] | select(.priority == "HIGH") | "  [\(.priority)] \(.opportunity)"' "${OUTPUT_FILE}"
}

# Main execution
main() {
  case "${OPERATION}" in
    create)
      init_config
      setup_channels
      populate_tickets
      generate_support_analytics
      generate_report
      ;;
    analyze)
      init_config
      setup_channels
      populate_tickets
      generate_support_analytics
      generate_report
      ;;
    report)
      init_config
      setup_channels
      populate_tickets
      generate_support_analytics
      generate_report
      ;;
    *)
      log_error "Unknown operation: ${OPERATION}"
      return 1
      ;;
  esac
  
  log_success "✓ CUSTOMER SUPPORT SYSTEM COMPLETE"
  log_info "Output: ${OUTPUT_FILE}"
  
  return 0
}

main
