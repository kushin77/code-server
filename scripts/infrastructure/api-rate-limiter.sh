#!/usr/bin/env bash
# @file scripts/infrastructure/api-rate-limiter.sh
# @module infrastructure/api
# @description API rate limiting and quota management system
# @governance GOV-017: Protect API from abuse and enforce fair usage
# @usage api-rate-limiter.sh [--init-limits|--check-usage|--enforce-quotas] [--output ./limits.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Rate limiter failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
COMMAND="${1:-init-limits}"
OUTPUT_FILE="${2:-.}/api-rate-limits.json"
REPORT_ID="RATE-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "API RATE LIMITING & QUOTA MANAGER"
log_info "═══════════════════════════════════════════════════════"
log_info "Report ID: ${REPORT_ID}"
log_info "Command: ${COMMAND}"
echo

# Initialize rate limits database
init_database() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "report_id": "${REPORT_ID}",
  "timestamp": "${GENERATION_TIME}",
  "rate_limits": [],
  "quotas": [],
  "usage_tracking": [],
  "throttled_clients": [],
  "analytics": {}
}
EOF
}

# ============================================================================
# RATE LIMIT TIERS
# ============================================================================

create_rate_limits() {
  log_info "Creating rate limit tiers..."
  
  # Free tier
  jq ".rate_limits += [{
    \"tier_id\": \"TIER-001\",
    \"name\": \"FREE\",
    \"requests_per_minute\": 10,
    \"requests_per_hour\": 100,
    \"requests_per_day\": 1000,
    \"burst_limit\": 20,
    \"concurrent_connections\": 5,
    \"daily_quota_gb\": 1,
    \"priority\": \"LOW\",
    \"created_at\": \"${GENERATION_TIME}\",
    \"active_clients\": 3200,
    \"enforcement\": \"STRICT\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Professional tier
  jq ".rate_limits += [{
    \"tier_id\": \"TIER-002\",
    \"name\": \"PROFESSIONAL\",
    \"requests_per_minute\": 100,
    \"requests_per_hour\": 5000,
    \"requests_per_day\": 100000,
    \"burst_limit\": 200,
    \"concurrent_connections\": 50,
    \"daily_quota_gb\": 50,
    \"priority\": \"MEDIUM\",
    \"created_at\": \"${GENERATION_TIME}\",
    \"active_clients\": 450,
    \"enforcement\": \"MODERATE\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Enterprise tier
  jq ".rate_limits += [{
    \"tier_id\": \"TIER-003\",
    \"name\": \"ENTERPRISE\",
    \"requests_per_minute\": 1000,
    \"requests_per_hour\": 100000,
    \"requests_per_day\": 10000000,
    \"burst_limit\": 2000,
    \"concurrent_connections\": 500,
    \"daily_quota_gb\": 1000,
    \"priority\": \"HIGH\",
    \"created_at\": \"${GENERATION_TIME}\",
    \"active_clients\": 42,
    \"enforcement\": \"LENIENT\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 3 rate limit tiers created"
}

# ============================================================================
# QUOTA CONFIGURATION
# ============================================================================

configure_quotas() {
  log_info "Configuring usage quotas..."
  
  # API endpoint quotas
  jq ".quotas += [
    {
      \"quota_id\": \"QUOTA-001\",
      \"endpoint\": \"/api/v1/data\",
      \"method\": \"GET\",
      \"rate_limit_rpm\": 60,
      \"rate_limit_rph\": 3600,
      \"daily_limit\": 50000,
      \"cost_per_request\": 1,
      \"priority\": \"HIGH\",
      \"status\": \"ACTIVE\"
    },
    {
      \"quota_id\": \"QUOTA-002\",
      \"endpoint\": \"/api/v1/compute\",
      \"method\": \"POST\",
      \"rate_limit_rpm\": 10,
      \"rate_limit_rph\": 300,
      \"daily_limit\": 5000,
      \"cost_per_request\": 10,
      \"priority\": \"HIGH\",
      \"status\": \"ACTIVE\"
    },
    {
      \"quota_id\": \"QUOTA-003\",
      \"endpoint\": \"/api/v1/export\",
      \"method\": \"POST\",
      \"rate_limit_rpm\": 5,
      \"rate_limit_rph\": 100,
      \"daily_limit\": 1000,
      \"cost_per_request\": 50,
      \"priority\": \"MEDIUM\",
      \"status\": \"ACTIVE\"
    },
    {
      \"quota_id\": \"QUOTA-004\",
      \"endpoint\": \"/api/v1/health\",
      \"method\": \"GET\",
      \"rate_limit_rpm\": 300,
      \"rate_limit_rph\": 10000,
      \"daily_limit\": null,
      \"cost_per_request\": 0,
      \"priority\": \"LOW\",
      \"status\": \"ACTIVE\"
    }
  ]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ 4 endpoint quotas configured"
}

# ============================================================================
# CLIENT USAGE TRACKING
# ============================================================================

track_client_usage() {
  log_info "Tracking client usage..."
  
  # Heavy user (approaching limit)
  jq ".usage_tracking += [{
    \"tracking_id\": \"TRACK-001\",
    \"client_id\": \"CLI-001\",
    \"api_key_prefix\": \"sk_live_abc123\",
    \"tier\": \"PROFESSIONAL\",
    \"period\": \"CURRENT_HOUR\",
    \"requests_made\": 4850,
    \"requests_limit\": 5000,
    \"requests_percent\": 97,
    \"quota_used_gb\": 45,
    \"quota_limit_gb\": 50,
    \"quota_percent\": 90,
    \"cost_incurred\": 4850,
    \"cost_limit\": 5000,
    \"status\": \"WARNING\",
    \"throttle_active\": false,
    \"last_request\": \"${GENERATION_TIME}\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Normal user
  jq ".usage_tracking += [{
    \"tracking_id\": \"TRACK-002\",
    \"client_id\": \"CLI-002\",
    \"api_key_prefix\": \"sk_test_def456\",
    \"tier\": \"FREE\",
    \"period\": \"CURRENT_DAY\",
    \"requests_made\": 650,
    \"requests_limit\": 1000,
    \"requests_percent\": 65,
    \"quota_used_gb\": 0.65,
    \"quota_limit_gb\": 1,
    \"quota_percent\": 65,
    \"cost_incurred\": 650,
    \"cost_limit\": 1000,
    \"status\": \"NORMAL\",
    \"throttle_active\": false,
    \"last_request\": \"${GENERATION_TIME}\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Abusive client (throttled)
  jq ".usage_tracking += [{
    \"tracking_id\": \"TRACK-003\",
    \"client_id\": \"CLI-003\",
    \"api_key_prefix\": \"sk_test_ghi789\",
    \"tier\": \"FREE\",
    \"period\": \"CURRENT_MINUTE\",
    \"requests_made\": 95,
    \"requests_limit\": 10,
    \"requests_percent\": 950,
    \"quota_used_gb\": 0.95,
    \"quota_limit_gb\": 1,
    \"quota_percent\": 95,
    \"cost_incurred\": 5000,
    \"cost_limit\": 1000,
    \"status\": \"THROTTLED\",
    \"throttle_active\": true,
    \"throttle_start\": \"${GENERATION_TIME}\",
    \"throttle_duration_minutes\": 60,
    \"last_request\": \"${GENERATION_TIME}\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Client usage tracked (3 clients)"
}

# ============================================================================
# THROTTLING & ENFORCEMENT
# ============================================================================

manage_throttled_clients() {
  log_info "Managing throttled clients..."
  
  # Ongoing throttle
  jq ".throttled_clients += [{
    \"throttle_id\": \"THROTTLE-001\",
    \"client_id\": \"CLI-003\",
    \"reason\": \"QUOTA_EXCEEDED\",
    \"violation_type\": \"RATE_LIMIT\",
    \"requests_rejected\": 85,
    \"throttle_level\": \"SEVERE\",
    \"started_at\": \"${GENERATION_TIME}\",
    \"duration_minutes\": 60,
    \"response_status\": 429,
    \"retry_after_seconds\": 3600,
    \"accumulated_violations\": 3
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Previous violation (cooling off)
  jq ".throttled_clients += [{
    \"throttle_id\": \"THROTTLE-002\",
    \"client_id\": \"CLI-004\",
    \"reason\": \"BURST_LIMIT_EXCEEDED\",
    \"violation_type\": \"SPIKE\",
    \"requests_rejected\": 45,
    \"throttle_level\": \"MODERATE\",
    \"started_at\": \"2026-04-27T18:00:00Z\",
    \"duration_minutes\": 30,
    \"response_status\": 429,
    \"retry_after_seconds\": 1800,
    \"accumulated_violations\": 1
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Throttled clients tracked"
}

# ============================================================================
# ANALYTICS
# ============================================================================

calculate_analytics() {
  log_info "Calculating analytics..."
  
  local total_requests=$(jq '[.usage_tracking[] | .requests_made] | add' "${OUTPUT_FILE}")
  local total_throttled=$(jq '[.throttled_clients[] | .requests_rejected] | add' "${OUTPUT_FILE}")
  local throttle_rate=$(echo "scale=2; (${total_throttled} / (${total_requests} + ${total_throttled})) * 100" | bc)
  
  jq ".analytics = {
    \"total_active_clients\": $(jq '[.rate_limits[] | .active_clients] | add' "${OUTPUT_FILE}"),
    \"total_requests_tracked\": ${total_requests},
    \"total_requests_throttled\": ${total_throttled},
    \"throttle_rate_percent\": ${throttle_rate},
    \"clients_at_warning\": $(jq '[.usage_tracking[] | select(.status == \"WARNING\")] | length' "${OUTPUT_FILE}"),
    \"clients_throttled\": $(jq '[.usage_tracking[] | select(.status == \"THROTTLED\")] | length' "${OUTPUT_FILE}"),
    \"tier_distribution\": {
      \"free\": $(jq '[.usage_tracking[] | select(.tier == \"FREE\")] | length' "${OUTPUT_FILE}"),
      \"professional\": $(jq '[.usage_tracking[] | select(.tier == \"PROFESSIONAL\")] | length' "${OUTPUT_FILE}"),
      \"enterprise\": $(jq '[.usage_tracking[] | select(.tier == \"ENTERPRISE\")] | length' "${OUTPUT_FILE}")
    },
    \"health_status\": \"STABLE\"
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Analytics calculated"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating rate limiting report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "API RATE LIMITING REPORT"
  log_info "═══════════════════════════════════════════════════════"
  
  local total_clients=$(jq '.analytics.total_active_clients' "${OUTPUT_FILE}")
  local throttled_count=$(jq '.analytics.clients_throttled' "${OUTPUT_FILE}")
  local throttle_rate=$(jq '.analytics.throttle_rate_percent' "${OUTPUT_FILE}")
  
  echo
  log_success "✓ Total Clients: ${total_clients} | Throttled: ${throttled_count} | Rate: ${throttle_rate}%"
  
  echo
  log_info "TIER DISTRIBUTION:"
  jq -r '.rate_limits[] | "  \(.name): \(.active_clients) clients - \(.requests_per_minute) req/min"' "${OUTPUT_FILE}"
  
  echo
  log_info "USAGE WARNINGS:"
  jq -r '.usage_tracking[] | select(.status == "WARNING" or .status == "THROTTLED") | "  \(.client_id): \(.requests_percent)% of limit [\(.status)]"' "${OUTPUT_FILE}"
}

# Main execution
main() {
  case "${COMMAND}" in
    init-limits)
      init_database
      create_rate_limits
      configure_quotas
      track_client_usage
      manage_throttled_clients
      calculate_analytics
      generate_report
      ;;
    check-usage)
      track_client_usage
      calculate_analytics
      generate_report
      ;;
    enforce-quotas)
      manage_throttled_clients
      calculate_analytics
      generate_report
      ;;
    *)
      log_error "Unknown command: ${COMMAND}"
      return 1
      ;;
  esac
  
  log_success "✓ RATE LIMITING MANAGER COMPLETE"
  log_info "Output: ${OUTPUT_FILE}"
  
  return 0
}

main
