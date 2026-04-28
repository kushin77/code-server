#!/usr/bin/env bash
# @file scripts/planning/capacity-planner.sh
# @module planning/capacity
# @description Long-term capacity planning with growth projections
# @governance GOV-007: Plan infrastructure growth and resource scaling
# @usage capacity-planner.sh [--projection-months 12] [--output ./capacity-plan.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Capacity planning failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
PROJECTION_MONTHS="${1:-12}"
OUTPUT_FILE="${2:-.}/capacity-plan.json"
PLAN_ID="CP-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "CAPACITY PLANNING TOOL"
log_info "═══════════════════════════════════════════════════════"
log_info "Plan ID: ${PLAN_ID}"
log_info "Projection Period: ${PROJECTION_MONTHS} months"
echo

# Initialize capacity plan
init_capacity_plan() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "plan_id": "${PLAN_ID}",
  "timestamp": "${GENERATION_TIME}",
  "projection_months": ${PROJECTION_MONTHS},
  "current_state": {},
  "growth_assumptions": {},
  "projections": [],
  "recommendations": [],
  "risk_factors": []
}
EOF
}

# ============================================================================
# CURRENT STATE ASSESSMENT
# ============================================================================

assess_current_state() {
  log_info "Assessing current infrastructure state..."
  
  # System resources
  local total_cpu=$(nproc)
  local total_mem_gb=$(free -g | awk 'NR==2 {print $2}')
  local total_disk_gb=$(df / | awk 'NR==2 {print $2/1024/1024}')
  
  # Service count
  local service_count=$(docker-compose config 2>/dev/null | grep -c "image:" || echo 0)
  
  # Data metrics
  local db_size_bytes=$(du -sb /var/lib/postgresql 2>/dev/null | awk '{print $1}' || echo 0)
  
  # User base estimate
  local estimated_users=100
  
  jq ".current_state = {
    \"cpu_cores\": ${total_cpu},
    \"memory_gb\": ${total_mem_gb},
    \"disk_gb\": $(printf "%.1f" "${total_disk_gb}"),
    \"services_deployed\": ${service_count},
    \"database_size_bytes\": ${db_size_bytes},
    \"estimated_active_users\": ${estimated_users},
    \"timestamp\": \"${GENERATION_TIME}\"
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Current state assessed"
}

# ============================================================================
# GROWTH ASSUMPTIONS
# ============================================================================

define_growth_assumptions() {
  log_info "Defining growth assumptions..."
  
  jq ".growth_assumptions = {
    \"user_growth_monthly_percent\": 5.0,
    \"data_growth_monthly_percent\": 8.0,
    \"service_expansion_quarterly\": 2,
    \"peak_to_average_ratio\": 1.5,
    \"redundancy_factor\": 1.2,
    \"headroom_percent\": 25
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Growth assumptions defined"
}

# ============================================================================
# GENERATE PROJECTIONS
# ============================================================================

generate_projections() {
  log_info "Generating capacity projections..."
  
  local current_users=100
  local current_data_gb=$(jq '.current_state.database_size_bytes / 1024 / 1024 / 1024' "${OUTPUT_FILE}")
  local user_growth=1.05
  local data_growth=1.08
  
  for month in $(seq 1 "${PROJECTION_MONTHS}"); do
    local projected_users=$(echo "scale=0; ${current_users} * (${user_growth} ^ ${month})" | bc)
    local projected_data=$(echo "scale=1; ${current_data_gb} * (${data_growth} ^ ${month})" | bc)
    
    # Memory requirement: 10MB per user + 50GB base
    local required_memory=$(echo "scale=1; 50 + (${projected_users} * 10 / 1024)" | bc)
    
    # Storage requirement: data + 50% headroom
    local required_storage=$(echo "scale=1; ${projected_data} * 1.5" | bc)
    
    # CPU requirement: 0.1 cores per 100 users
    local required_cpu=$(echo "scale=2; 4 + (${projected_users} * 0.1 / 100)" | bc)
    
    jq ".projections += [{
      \"month\": ${month},
      \"estimated_users\": ${projected_users},
      \"estimated_data_gb\": ${projected_data},
      \"required_memory_gb\": ${required_memory},
      \"required_storage_gb\": ${required_storage},
      \"required_cpu_cores\": ${required_cpu},
      \"projection_date\": \"$(date -u -d "+${month} months" +%Y-%m-%d)\"
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  done
  
  log_success "✓ Projections generated for ${PROJECTION_MONTHS} months"
}

# ============================================================================
# SCALING RECOMMENDATIONS
# ============================================================================

generate_recommendations() {
  log_info "Generating scaling recommendations..."
  
  local current_mem=$(jq '.current_state.memory_gb' "${OUTPUT_FILE}")
  local current_disk=$(jq '.current_state.disk_gb' "${OUTPUT_FILE}")
  local final_mem=$(jq '.projections[-1].required_memory_gb' "${OUTPUT_FILE}")
  local final_storage=$(jq '.projections[-1].required_storage_gb' "${OUTPUT_FILE}")
  
  # Memory scaling
  if (( $(echo "${final_mem} > ${current_mem}" | bc -l) )); then
    local mem_increase=$(echo "scale=0; ${final_mem} - ${current_mem}" | bc)
    jq ".recommendations += [{
      \"type\": \"MEMORY_SCALING\",
      \"priority\": \"HIGH\",
      \"current_gb\": ${current_mem},
      \"required_gb\": $(printf "%.1f" "${final_mem}"),
      \"increase_gb\": ${mem_increase},
      \"timeline\": \"Phased over 12 months\",
      \"estimated_cost\": \"\$$(echo \"scale=0; ${mem_increase} * 25\" | bc) USD\",
      \"implementation_effort\": \"MEDIUM\"
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  # Storage scaling
  if (( $(echo "${final_storage} > ${current_disk}" | bc -l) )); then
    local storage_increase=$(echo "scale=0; ${final_storage} - ${current_disk}" | bc)
    jq ".recommendations += [{
      \"type\": \"STORAGE_SCALING\",
      \"priority\": \"CRITICAL\",
      \"current_gb\": $(printf "%.1f" "${current_disk}"),
      \"required_gb\": $(printf "%.1f" "${final_storage}"),
      \"increase_gb\": ${storage_increase},
      \"timeline\": \"Immediate planning required\",
      \"estimated_cost\": \"\$$(echo \"scale=0; ${storage_increase} * 5\" | bc) USD\",
      \"implementation_effort\": \"LOW\"
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  # Service expansion
  jq ".recommendations += [{
    \"type\": \"SERVICE_EXPANSION\",
    \"priority\": \"MEDIUM\",
    \"recommended_services_to_add\": 6,
    \"timeline\": \"Q2-Q3 next year\",
    \"estimated_cost\": \"\$50000 USD\",
    \"implementation_effort\": \"HIGH\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Recommendations generated"
}

# ============================================================================
# RISK ANALYSIS
# ============================================================================

analyze_risks() {
  log_info "Analyzing capacity risks..."
  
  local final_mem=$(jq '.projections[-1].required_memory_gb' "${OUTPUT_FILE}")
  local current_mem=$(jq '.current_state.memory_gb' "${OUTPUT_FILE}")
  
  # Rapid growth risk
  jq ".risk_factors += [{
    \"risk_type\": \"RAPID_GROWTH\",
    \"probability\": \"MEDIUM\",
    \"impact\": \"HIGH\",
    \"description\": \"If user adoption exceeds 5% monthly growth\",
    \"mitigation\": \"Maintain 50% capacity buffer, auto-scaling setup\",
    \"cost_if_unmitigated\": \"\$500000 USD\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Infrastructure failure risk
  jq ".risk_factors += [{
    \"risk_type\": \"INFRASTRUCTURE_FAILURE\",
    \"probability\": \"LOW\",
    \"impact\": \"CRITICAL\",
    \"description\": \"Single point of failure if redundancy not implemented\",
    \"mitigation\": \"Multi-region setup, automated failover\",
    \"cost_if_unmitigated\": \"\$2000000 USD\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Budget overrun risk
  jq ".risk_factors += [{
    \"risk_type\": \"BUDGET_OVERRUN\",
    \"probability\": \"MEDIUM\",
    \"impact\": \"MEDIUM\",
    \"description\": \"Cost scaling faster than anticipated\",
    \"mitigation\": \"Cost optimization, reserved capacity planning\",
    \"cost_if_unmitigated\": \"\$300000 USD\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Risk analysis complete"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating capacity plan report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "CAPACITY PLAN SUMMARY"
  log_info "═══════════════════════════════════════════════════════"
  
  local current_mem=$(jq '.current_state.memory_gb' "${OUTPUT_FILE}")
  local final_mem=$(jq '.projections[-1].required_memory_gb' "${OUTPUT_FILE}")
  local current_disk=$(jq '.current_state.disk_gb' "${OUTPUT_FILE}")
  local final_storage=$(jq '.projections[-1].required_storage_gb' "${OUTPUT_FILE}")
  
  echo
  log_info "CURRENT STATE:"
  echo "  Memory: ${current_mem} GB"
  echo "  Disk: $(printf "%.1f" "${current_disk}") GB"
  
  echo
  log_info "PROJECTED IN ${PROJECTION_MONTHS} MONTHS:"
  echo "  Memory: $(printf "%.1f" "${final_mem}") GB ($(echo "scale=0; (${final_mem} / ${current_mem} - 1) * 100" | bc)% increase)"
  echo "  Disk: $(printf "%.1f" "${final_storage}") GB ($(echo "scale=0; (${final_storage} / ${current_disk} - 1) * 100" | bc)% increase)"
  
  echo
  log_info "RECOMMENDATIONS:"
  jq -r '.recommendations[] | "  [\(.priority)] \(.type): \(.estimated_cost)"' "${OUTPUT_FILE}" | head -5
  
  echo
  log_info "KEY RISKS:"
  jq -r '.risk_factors[] | "  [\(.probability)] \(.risk_type) - \(.mitigation | split(", ")[0])"' "${OUTPUT_FILE}" | head -3
}

# Main execution
main() {
  init_capacity_plan
  assess_current_state
  define_growth_assumptions
  generate_projections
  generate_recommendations
  analyze_risks
  generate_report
  
  log_success "✓ CAPACITY PLAN GENERATION COMPLETE"
  log_info "Plan: ${OUTPUT_FILE}"
  
  return 0
}

main
