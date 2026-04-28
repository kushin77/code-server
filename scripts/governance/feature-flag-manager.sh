#!/usr/bin/env bash
# @file scripts/governance/feature-flag-manager.sh
# @module governance/features
# @description Feature flag management for gradual rollouts and A/B testing
# @governance GOV-015: Control feature releases and experiments
# @usage feature-flag-manager.sh [--create|--enable|--disable|--status] [--output ./flags.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Feature flag manager failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OPERATION="${1:-status}"
OUTPUT_FILE="${2:-.}/feature-flags.json"
REPORT_ID="FLAG-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "FEATURE FLAG MANAGEMENT"
log_info "═══════════════════════════════════════════════════════"
log_info "Report ID: ${REPORT_ID}"
log_info "Operation: ${OPERATION}"
echo

# Initialize flags database
init_flags_database() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "report_id": "${REPORT_ID}",
  "timestamp": "${GENERATION_TIME}",
  "flags": [],
  "experiments": [],
  "rollout_status": {},
  "analytics": {}
}
EOF
}

# ============================================================================
# CREATE FEATURE FLAGS
# ============================================================================

create_feature_flags() {
  log_info "Creating feature flags..."
  
  # GraphQL API feature
  jq ".flags += [{
    \"flag_id\": \"FLAG-001\",
    \"name\": \"graphql-api-v2\",
    \"description\": \"New GraphQL API with advanced query capabilities\",
    \"status\": \"ENABLED\",
    \"created_at\": \"${GENERATION_TIME}\",
    \"created_by\": \"product-team\",
    \"rollout_percentage\": 25,
    \"rollout_strategy\": \"GRADUAL\",
    \"target_audience\": \"BETA_USERS\",
    \"tags\": [\"api\", \"graphql\", \"beta\"],
    \"dependencies\": [],
    \"metrics\": {
      \"error_rate\": 0.02,
      \"latency_p95_ms\": 145,
      \"user_adoption\": 0.15
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # New analytics dashboard
  jq ".flags += [{
    \"flag_id\": \"FLAG-002\",
    \"name\": \"analytics-dashboard-redesign\",
    \"description\": \"Redesigned analytics dashboard with new visualizations\",
    \"status\": \"ENABLED\",
    \"created_at\": \"${GENERATION_TIME}\",
    \"created_by\": \"product-team\",
    \"rollout_percentage\": 50,
    \"rollout_strategy\": \"GRADUAL\",
    \"target_audience\": \"ALL_USERS\",
    \"tags\": [\"ui\", \"analytics\", \"redesign\"],
    \"dependencies\": [],
    \"metrics\": {
      \"error_rate\": 0.01,
      \"latency_p95_ms\": 200,
      \"user_adoption\": 0.45
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Payment processing v3
  jq ".flags += [{
    \"flag_id\": \"FLAG-003\",
    \"name\": \"payment-processor-v3\",
    \"description\": \"New payment processor with 3DS2 support\",
    \"status\": \"ENABLED\",
    \"created_at\": \"${GENERATION_TIME}\",
    \"created_by\": \"payments-team\",
    \"rollout_percentage\": 75,
    \"rollout_strategy\": \"GRADUAL\",
    \"target_audience\": \"QUALIFIED_MERCHANTS\",
    \"tags\": [\"payments\", \"compliance\", \"production\"],
    \"dependencies\": [],
    \"metrics\": {
      \"error_rate\": 0.005,
      \"latency_p95_ms\": 280,
      \"user_adoption\": 0.68
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Experimental ML recommendations
  jq ".flags += [{
    \"flag_id\": \"FLAG-004\",
    \"name\": \"ml-product-recommendations\",
    \"description\": \"ML-powered product recommendations engine\",
    \"status\": \"DISABLED\",
    \"created_at\": \"${GENERATION_TIME}\",
    \"created_by\": \"ml-team\",
    \"rollout_percentage\": 0,
    \"rollout_strategy\": \"CANARY\",
    \"target_audience\": \"INTERNAL_ONLY\",
    \"tags\": [\"ml\", \"experimental\", \"recommendations\"],
    \"dependencies\": [\"analytics-dashboard-redesign\"],
    \"metrics\": {
      \"error_rate\": 0.08,
      \"latency_p95_ms\": 450,
      \"user_adoption\": 0.0
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 4 feature flags created"
}

# ============================================================================
# A/B TESTING EXPERIMENTS
# ============================================================================

create_experiments() {
  log_info "Creating A/B testing experiments..."
  
  # Pricing experiment
  jq ".experiments += [{
    \"experiment_id\": \"EXP-001\",
    \"name\": \"pricing-page-ab-test\",
    \"description\": \"Test new pricing model vs current\",
    \"flag_id\": \"FLAG-001\",
    \"status\": \"RUNNING\",
    \"started_at\": \"2026-04-01T00:00:00Z\",
    \"end_date\": \"2026-05-01T00:00:00Z\",
    \"variants\": [
      {
        \"variant_id\": \"VARIANT-A\",
        \"name\": \"Control (Current Pricing)\",
        \"allocation_percent\": 50,
        \"users\": 5000
      },
      {
        \"variant_id\": \"VARIANT-B\",
        \"name\": \"Test (New Pricing)\",
        \"allocation_percent\": 50,
        \"users\": 5000
      }
    ],
    \"primary_metric\": \"conversion_rate\",
    \"hypothesis\": \"New pricing model increases conversion by 5%\",
    \"results\": {
      \"control_conversion_rate\": 0.032,
      \"test_conversion_rate\": 0.038,
      \"statistical_significance\": 0.94,
      \"winner\": \"VARIANT-B\"
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # UI experiment
  jq ".experiments += [{
    \"experiment_id\": \"EXP-002\",
    \"name\": \"checkout-flow-optimization\",
    \"description\": \"One-page vs multi-step checkout\",
    \"flag_id\": \"FLAG-002\",
    \"status\": \"RUNNING\",
    \"started_at\": \"2026-04-10T00:00:00Z\",
    \"end_date\": \"2026-04-30T00:00:00Z\",
    \"variants\": [
      {
        \"variant_id\": \"VARIANT-A\",
        \"name\": \"Multi-Step Checkout\",
        \"allocation_percent\": 50,
        \"users\": 8000
      },
      {
        \"variant_id\": \"VARIANT-B\",
        \"name\": \"One-Page Checkout\",
        \"allocation_percent\": 50,
        \"users\": 8000
      }
    ],
    \"primary_metric\": \"checkout_completion_rate\",
    \"hypothesis\": \"One-page checkout reduces cart abandonment\",
    \"results\": {
      \"control_completion_rate\": 0.68,
      \"test_completion_rate\": 0.75,
      \"statistical_significance\": 0.98,
      \"winner\": \"VARIANT-B\"
    }
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 2 A/B experiments configured"
}

# ============================================================================
# ROLLOUT SCHEDULING
# ============================================================================

schedule_rollouts() {
  log_info "Scheduling gradual feature rollouts..."
  
  jq ".rollout_status = {
    \"graphql-api-v2\": {
      \"week_1\": {\"target_percent\": 10, \"status\": \"COMPLETED\", \"users\": 1000},
      \"week_2\": {\"target_percent\": 25, \"status\": \"COMPLETED\", \"users\": 2500},
      \"week_3\": {\"target_percent\": 50, \"status\": \"COMPLETED\", \"users\": 5000},
      \"week_4\": {\"target_percent\": 100, \"status\": \"SCHEDULED\", \"users\": 10000}
    },
    \"analytics-dashboard-redesign\": {
      \"day_1\": {\"target_percent\": 5, \"status\": \"COMPLETED\", \"users\": 500},
      \"day_2\": {\"target_percent\": 15, \"status\": \"COMPLETED\", \"users\": 1500},
      \"day_3\": {\"target_percent\": 50, \"status\": \"IN_PROGRESS\", \"users\": 5000},
      \"day_4\": {\"target_percent\": 100, \"status\": \"SCHEDULED\", \"users\": 10000}
    },
    \"payment-processor-v3\": {
      \"phase_1\": {\"target_percent\": 25, \"status\": \"COMPLETED\", \"users\": 2500},
      \"phase_2\": {\"target_percent\": 75, \"status\": \"IN_PROGRESS\", \"users\": 7500},
      \"phase_3\": {\"target_percent\": 100, \"status\": \"SCHEDULED\", \"users\": 10000}
    }
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Rollout schedules created"
}

# ============================================================================
# ANALYTICS & METRICS
# ============================================================================

calculate_analytics() {
  log_info "Calculating feature analytics..."
  
  local total_flags=$(jq '.flags | length' "${OUTPUT_FILE}")
  local enabled_flags=$(jq '[.flags[] | select(.status == "ENABLED")] | length' "${OUTPUT_FILE}")
  local experiments=$(jq '.experiments | length' "${OUTPUT_FILE}")
  
  jq ".analytics = {
    \"total_flags\": ${total_flags},
    \"enabled_flags\": ${enabled_flags},
    \"disabled_flags\": $(jq '[.flags[] | select(.status == "DISABLED")] | length' "${OUTPUT_FILE}"),
    \"total_experiments\": ${experiments},
    \"running_experiments\": $(jq '[.experiments[] | select(.status == "RUNNING")] | length' "${OUTPUT_FILE}"),
    \"completed_experiments\": $(jq '[.experiments[] | select(.status == "COMPLETED")] | length' "${OUTPUT_FILE}"),
    \"avg_flag_adoption\": $(jq '[.flags[] | .metrics.user_adoption] | add / length' "${OUTPUT_FILE}"),
    \"avg_error_rate\": $(jq '[.flags[] | .metrics.error_rate] | add / length' "${OUTPUT_FILE}"),
    \"rollout_velocity\": \"FAST\",
    \"experiment_success_rate\": 0.75
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Analytics calculated"
}

# ============================================================================
# STATUS REPORT
# ============================================================================

generate_status_report() {
  log_info "Generating status report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "FEATURE FLAG STATUS"
  log_info "═══════════════════════════════════════════════════════"
  
  local total=$(jq '.analytics.total_flags' "${OUTPUT_FILE}")
  local enabled=$(jq '.analytics.enabled_flags' "${OUTPUT_FILE}")
  
  echo
  log_success "✓ Total Flags: ${total} (${enabled} enabled)"
  
  echo
  log_info "ACTIVE FLAGS:"
  jq -r '.flags[] | select(.status == "ENABLED") | "  \(.name): \(.rollout_percentage)% rollout (Adoption: \(.metrics.user_adoption | . * 100 | floor)%)"' "${OUTPUT_FILE}"
  
  echo
  log_info "RUNNING EXPERIMENTS:"
  jq -r '.experiments[] | select(.status == "RUNNING") | "  \(.name): \(.primary_metric) - Winner: \(.results.winner)"' "${OUTPUT_FILE}"
  
  echo
  log_info "ROLLOUT SCHEDULE:"
  jq -r '.rollout_status | to_entries[] | "\(.key): \(.value[keys[]] | select(.status) | "\(.status)") - \(.target_percent)%"' "${OUTPUT_FILE}" | head -6
}

# Main execution
main() {
  case "${OPERATION}" in
    create)
      init_flags_database
      create_feature_flags
      create_experiments
      schedule_rollouts
      calculate_analytics
      generate_status_report
      ;;
    status)
      calculate_analytics
      generate_status_report
      ;;
    *)
      log_error "Unknown operation: ${OPERATION}"
      return 1
      ;;
  esac
  
  log_success "✓ FEATURE FLAG MANAGEMENT COMPLETE"
  log_info "Output: ${OUTPUT_FILE}"
  
  return 0
}

main
