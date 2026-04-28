#!/usr/bin/env bash
# @file scripts/planning/cost-analyzer.sh
# @module planning/costs
# @description Infrastructure cost analysis and optimization opportunities
# @governance GOV-008: Optimize infrastructure costs and resource utilization
# @usage cost-analyzer.sh [--include-projections] [--output ./cost-analysis.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Cost analysis failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
INCLUDE_PROJECTIONS="${1:-}"
OUTPUT_FILE="${2:-.}/cost-analysis.json"
ANALYSIS_ID="COST-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "INFRASTRUCTURE COST ANALYZER"
log_info "═══════════════════════════════════════════════════════"
log_info "Analysis ID: ${ANALYSIS_ID}"
echo

# Initialize cost analysis
init_cost_analysis() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "analysis_id": "${ANALYSIS_ID}",
  "timestamp": "${GENERATION_TIME}",
  "currency": "USD",
  "cost_breakdown": {},
  "monthly_costs": 0,
  "annual_costs": 0,
  "optimization_opportunities": [],
  "cost_drivers": [],
  "roi_analysis": {}
}
EOF
}

# ============================================================================
# COMPUTE COSTS
# ============================================================================

analyze_compute_costs() {
  log_info "Analyzing compute resource costs..."
  
  # CPU costing: $0.10 per core-hour on-demand, $0.05 with reservation
  local cpu_cores=$(nproc)
  local cpu_hourly=$((cpu_cores * 10 / 100))  # cents, converted to dollars in decimals
  local cpu_monthly=$(echo "scale=2; ${cpu_cores} * 0.10 * 24 * 30" | bc)
  local cpu_monthly_reserved=$(echo "scale=2; ${cpu_cores} * 0.05 * 24 * 30" | bc)
  
  # Memory costing: $0.012 per GB-hour on-demand, $0.006 with reservation
  local memory_gb=$(free -g | awk 'NR==2 {print $2}')
  local memory_monthly=$(echo "scale=2; ${memory_gb} * 0.012 * 24 * 30" | bc)
  local memory_monthly_reserved=$(echo "scale=2; ${memory_gb} * 0.006 * 24 * 30" | bc)
  
  local compute_total=$(echo "scale=2; ${cpu_monthly} + ${memory_monthly}" | bc)
  local compute_reserved=$(echo "scale=2; ${cpu_monthly_reserved} + ${memory_monthly_reserved}" | bc)
  local compute_savings=$(echo "scale=2; ${compute_total} - ${compute_reserved}" | bc)
  
  jq ".cost_breakdown.compute = {
    \"cpu_cores\": ${cpu_cores},
    \"memory_gb\": ${memory_gb},
    \"monthly_on_demand\": ${compute_total},
    \"monthly_reserved\": ${compute_reserved},
    \"potential_savings\": ${compute_savings},
    \"savings_percent\": $(echo "scale=1; (${compute_savings} / ${compute_total}) * 100" | bc)
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Compute costs analyzed: \$${compute_total}/month (On-demand) → \$${compute_reserved}/month (Reserved)"
}

# ============================================================================
# STORAGE COSTS
# ============================================================================

analyze_storage_costs() {
  log_info "Analyzing storage costs..."
  
  # Storage costing: $0.10 per GB-month standard, $0.05 cold storage
  local total_disk_gb=$(df / | awk 'NR==2 {print int($2/1024/1024)}')
  local db_size_gb=$(du -sb /var/lib/postgresql 2>/dev/null | awk '{print int($1/1024/1024/1024)}' || echo 0)
  
  # 70% standard storage, 30% archive
  local standard_gb=$(echo "scale=0; ${total_disk_gb} * 0.7" | bc)
  local archive_gb=$(echo "scale=0; ${total_disk_gb} * 0.3" | bc)
  
  local standard_monthly=$(echo "scale=2; ${standard_gb} * 0.10" | bc)
  local archive_monthly=$(echo "scale=2; ${archive_gb} * 0.05" | bc)
  local storage_total=$(echo "scale=2; ${standard_monthly} + ${archive_monthly}" | bc)
  
  jq ".cost_breakdown.storage = {
    \"total_gb\": ${total_disk_gb},
    \"database_gb\": ${db_size_gb},
    \"standard_tier_gb\": ${standard_gb},
    \"archive_tier_gb\": ${archive_gb},
    \"monthly_standard\": ${standard_monthly},
    \"monthly_archive\": ${archive_monthly},
    \"monthly_total\": ${storage_total}
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Storage costs analyzed: \$${storage_total}/month"
}

# ============================================================================
# NETWORKING COSTS
# ============================================================================

analyze_networking_costs() {
  log_info "Analyzing network costs..."
  
  # Egress costing: $0.09 per GB to internet, $0.02 within region
  # Assume 10 GB/day egress, mostly internal (80%)
  local daily_egress_gb=10
  local monthly_egress_gb=$((daily_egress_gb * 30))
  
  local external_gb=$(echo "scale=0; ${monthly_egress_gb} * 0.2" | bc)
  local internal_gb=$(echo "scale=0; ${monthly_egress_gb} * 0.8" | bc)
  
  local external_cost=$(echo "scale=2; ${external_gb} * 0.09" | bc)
  local internal_cost=$(echo "scale=2; ${internal_gb} * 0.02" | bc)
  local networking_total=$(echo "scale=2; ${external_cost} + ${internal_cost}" | bc)
  
  jq ".cost_breakdown.networking = {
    \"monthly_egress_gb\": ${monthly_egress_gb},
    \"external_gb\": ${external_gb},
    \"internal_gb\": ${internal_gb},
    \"external_cost\": ${external_cost},
    \"internal_cost\": ${internal_cost},
    \"monthly_total\": ${networking_total}
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Network costs analyzed: \$${networking_total}/month"
}

# ============================================================================
# SOFTWARE LICENSING
# ============================================================================

analyze_licensing_costs() {
  log_info "Analyzing software licensing costs..."
  
  # Assume 50 users, $20/month per user for enterprise features
  local estimated_users=50
  local cost_per_user=20
  local licensing_total=$(echo "scale=2; ${estimated_users} * ${cost_per_user}" | bc)
  
  jq ".cost_breakdown.licensing = {
    \"estimated_users\": ${estimated_users},
    \"cost_per_user_monthly\": ${cost_per_user},
    \"monthly_total\": ${licensing_total},
    \"components\": [
      {\"name\": \"PostgreSQL Enterprise\", \"monthly_cost\": 100},
      {\"name\": \"Monitoring/Observability\", \"monthly_cost\": 200},
      {\"name\": \"Security/Compliance\", \"monthly_cost\": 150}
    ]
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Licensing costs analyzed: \$${licensing_total}/month"
}

# ============================================================================
# OPERATIONS & SUPPORT
# ============================================================================

analyze_operations_costs() {
  log_info "Analyzing operations and support costs..."
  
  # Staff: 1 DevOps engineer ($80k/year = $6667/month)
  # Support: 2 support engineers ($70k/year = $5833/month each)
  local devops_monthly=6667
  local support_monthly=$((5833 * 2))
  local tools_monitoring=500
  local training_development=1000
  local contingency=1000
  
  local operations_total=$(echo "scale=2; ${devops_monthly} + ${support_monthly} + ${tools_monitoring} + ${training_development} + ${contingency}" | bc)
  
  jq ".cost_breakdown.operations = {
    \"devops_engineering\": ${devops_monthly},
    \"support_staff\": ${support_monthly},
    \"tools_and_monitoring\": ${tools_monitoring},
    \"training_and_development\": ${training_development},
    \"contingency_reserve\": ${contingency},
    \"monthly_total\": ${operations_total}
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Operations costs analyzed: \$${operations_total}/month"
}

# ============================================================================
# TOTAL COST CALCULATION
# ============================================================================

calculate_total_costs() {
  log_info "Calculating total costs..."
  
  local compute=$(jq '.cost_breakdown.compute.monthly_on_demand' "${OUTPUT_FILE}")
  local storage=$(jq '.cost_breakdown.storage.monthly_total' "${OUTPUT_FILE}")
  local networking=$(jq '.cost_breakdown.networking.monthly_total' "${OUTPUT_FILE}")
  local licensing=$(jq '.cost_breakdown.licensing.monthly_total' "${OUTPUT_FILE}")
  local operations=$(jq '.cost_breakdown.operations.monthly_total' "${OUTPUT_FILE}")
  
  local monthly_total=$(echo "scale=2; ${compute} + ${storage} + ${networking} + ${licensing} + ${operations}" | bc)
  local annual_total=$(echo "scale=2; ${monthly_total} * 12" | bc)
  
  jq ".monthly_costs = ${monthly_total}" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp"
  mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  jq ".annual_costs = ${annual_total}" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp"
  mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Total costs calculated: \$${monthly_total}/month (\$${annual_total}/year)"
}

# ============================================================================
# OPTIMIZATION OPPORTUNITIES
# ============================================================================

identify_optimizations() {
  log_info "Identifying cost optimization opportunities..."
  
  # Reserved instances
  jq ".optimization_opportunities += [{
    \"opportunity\": \"Reserved Instances\",
    \"current_cost\": \"Compute (on-demand)\",
    \"potential_savings_monthly\": $(jq '.cost_breakdown.compute.potential_savings' "${OUTPUT_FILE}"),
    \"implementation_effort\": \"LOW\",
    \"timeline\": \"1 month\",
    \"roi_months\": 0
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Storage optimization
  jq ".optimization_opportunities += [{
    \"opportunity\": \"Storage Tiering\",
    \"current_cost\": \"All standard tier\",
    \"potential_savings_monthly\": 150,
    \"implementation_effort\": \"MEDIUM\",
    \"timeline\": \"3 months\",
    \"roi_months\": 2
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Auto-scaling
  jq ".optimization_opportunities += [{
    \"opportunity\": \"Auto-Scaling Implementation\",
    \"current_cost\": \"Fixed over-provisioning\",
    \"potential_savings_monthly\": 500,
    \"implementation_effort\": \"HIGH\",
    \"timeline\": \"6 months\",
    \"roi_months\": 4
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# ============================================================================
# ROI ANALYSIS
# ============================================================================

analyze_roi() {
  log_info "Analyzing ROI for cost optimization..."
  
  local monthly_cost=$(jq '.monthly_costs' "${OUTPUT_FILE}")
  local annual_cost=$(jq '.annual_costs' "${OUTPUT_FILE}")
  local potential_savings=650  # Sum of optimizations
  
  jq ".roi_analysis = {
    \"current_monthly_cost\": ${monthly_cost},
    \"current_annual_cost\": ${annual_cost},
    \"potential_monthly_savings\": ${potential_savings},
    \"potential_annual_savings\": $(echo "scale=2; ${potential_savings} * 12" | bc),
    \"cost_reduction_percent\": $(echo "scale=1; (${potential_savings} / ${monthly_cost}) * 100" | bc),
    \"payback_period_months\": \"2-6 (depending on optimization)\"
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating cost analysis report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "COST ANALYSIS SUMMARY"
  log_info "═══════════════════════════════════════════════════════"
  
  local monthly=$(jq '.monthly_costs' "${OUTPUT_FILE}")
  local annual=$(jq '.annual_costs' "${OUTPUT_FILE}")
  
  echo
  log_info "TOTAL INFRASTRUCTURE COSTS:"
  echo "  Monthly: \$${monthly}"
  echo "  Annual: \$${annual}"
  
  echo
  log_info "COST BREAKDOWN:"
  jq -r '.cost_breakdown | to_entries[] | "  \(.key): $\(.value | if type == \"object\" then .monthly_total else . end)"' "${OUTPUT_FILE}"
  
  echo
  log_info "TOP OPTIMIZATION OPPORTUNITIES:"
  jq -r '.optimization_opportunities[] | "  \(.opportunity): Save $\(.potential_savings_monthly)/month (ROI: \(.roi_months) months)"' "${OUTPUT_FILE}" | head -3
}

# Main execution
main() {
  init_cost_analysis
  analyze_compute_costs
  analyze_storage_costs
  analyze_networking_costs
  analyze_licensing_costs
  analyze_operations_costs
  calculate_total_costs
  identify_optimizations
  analyze_roi
  generate_report
  
  log_success "✓ COST ANALYSIS COMPLETE"
  log_info "Analysis: ${OUTPUT_FILE}"
  
  return 0
}

main
