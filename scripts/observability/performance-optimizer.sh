#!/usr/bin/env bash
# @file scripts/observability/performance-optimizer.sh
# @module observability/optimization
# @description Comprehensive performance analysis and optimization recommendations
# @governance GOV-006: Maintain optimal system performance and resource efficiency
# @usage performance-optimizer.sh [--analysis-depth full|standard|quick] [--output ./performance-analysis.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Performance analysis failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
ANALYSIS_DEPTH="${1:-standard}"
OUTPUT_FILE="${2:-.}/performance-analysis.json"
ANALYSIS_ID="PERF-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "PERFORMANCE OPTIMIZATION ANALYZER"
log_info "═══════════════════════════════════════════════════════"
log_info "Analysis ID: ${ANALYSIS_ID}"
log_info "Depth: ${ANALYSIS_DEPTH}"
echo

# Initialize analysis
init_analysis() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "analysis_id": "${ANALYSIS_ID}",
  "timestamp": "${GENERATION_TIME}",
  "analysis_depth": "${ANALYSIS_DEPTH}",
  "system_metrics": {},
  "service_metrics": [],
  "bottlenecks": [],
  "recommendations": [],
  "optimization_score": 0
}
EOF
}

# ============================================================================
# SYSTEM METRICS COLLECTION
# ============================================================================

collect_system_metrics() {
  log_info "Collecting system metrics..."
  
  # CPU metrics
  local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' || echo 0)
  local cpu_cores=$(nproc)
  
  # Memory metrics
  local mem_total=$(free -b | awk 'NR==2 {print $2}')
  local mem_used=$(free -b | awk 'NR==2 {print $3}')
  local mem_available=$(free -b | awk 'NR==2 {print $7}')
  local mem_percent=$(echo "scale=2; ${mem_used} * 100 / ${mem_total}" | bc)
  
  # Disk metrics
  local disk_total=$(df / | awk 'NR==2 {print $2}')
  local disk_used=$(df / | awk 'NR==2 {print $3}')
  local disk_available=$(df / | awk 'NR==2 {print $4}')
  local disk_percent=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
  
  # Load average
  local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
  
  # Process metrics
  local process_count=$(ps aux | wc -l)
  local zombie_count=$(ps aux | grep -c '<defunct>' || echo 0)
  
  jq ".system_metrics = {
    \"cpu\": {
      \"usage_percent\": $(printf "%.2f" "${cpu_usage}"),
      \"cores\": ${cpu_cores},
      \"load_average\": \"${load_avg}\"
    },
    \"memory\": {
      \"total_bytes\": ${mem_total},
      \"used_bytes\": ${mem_used},
      \"available_bytes\": ${mem_available},
      \"usage_percent\": ${mem_percent}
    },
    \"disk\": {
      \"total_bytes\": ${disk_total},
      \"used_bytes\": ${disk_used},
      \"available_bytes\": ${disk_available},
      \"usage_percent\": ${disk_percent}
    },
    \"processes\": {
      \"total\": ${process_count},
      \"zombies\": ${zombie_count}
    },
    \"timestamp\": \"${GENERATION_TIME}\"
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ System metrics collected"
}

# ============================================================================
# SERVICE PERFORMANCE ANALYSIS
# ============================================================================

analyze_service_performance() {
  log_info "Analyzing service performance..."
  
  local services=$(docker ps --format "{{.Names}}")
  
  while IFS= read -r service; do
    [[ -z "${service}" ]] && continue
    
    # Container stats
    local cpu=$(docker stats --no-stream "${service}" 2>/dev/null | tail -1 | awk '{print $3}' | sed 's/%//' || echo "0")
    local mem=$(docker stats --no-stream "${service}" 2>/dev/null | tail -1 | awk '{print $7}' | sed 's/%//' || echo "0")
    
    # Uptime
    local created=$(docker inspect "${service}" --format='{{.State.StartedAt}}' 2>/dev/null || echo "")
    
    jq ".service_metrics += [{
      \"service_name\": \"${service}\",
      \"cpu_percent\": $(printf "%.2f" "${cpu}"),
      \"memory_percent\": $(printf "%.2f" "${mem}"),
      \"started_at\": \"${created}\",
      \"analysis_time\": \"${GENERATION_TIME}\"
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  done <<< "${services}"
  
  log_success "✓ Service performance analyzed"
}

# ============================================================================
# BOTTLENECK DETECTION
# ============================================================================

detect_bottlenecks() {
  log_info "Detecting performance bottlenecks..."
  
  local cpu_usage=$(jq '.system_metrics.cpu.usage_percent' "${OUTPUT_FILE}")
  local mem_percent=$(jq '.system_metrics.memory.usage_percent' "${OUTPUT_FILE}")
  local disk_percent=$(jq '.system_metrics.disk.usage_percent' "${OUTPUT_FILE}")
  
  # CPU bottleneck
  if (( $(echo "${cpu_usage} > 80" | bc -l) )); then
    jq ".bottlenecks += [{
      \"type\": \"CPU\",
      \"severity\": \"HIGH\",
      \"current_value\": ${cpu_usage},
      \"threshold\": 80,
      \"description\": \"CPU usage critically high\",
      \"impact\": \"Service response degradation\",
      \"timestamp\": \"${GENERATION_TIME}\"
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  elif (( $(echo "${cpu_usage} > 70" | bc -l) )); then
    jq ".bottlenecks += [{
      \"type\": \"CPU\",
      \"severity\": \"MEDIUM\",
      \"current_value\": ${cpu_usage},
      \"threshold\": 70,
      \"description\": \"CPU usage elevated\",
      \"impact\": \"Performance degradation likely\",
      \"timestamp\": \"${GENERATION_TIME}\"
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  # Memory bottleneck
  if (( $(echo "${mem_percent} > 85" | bc -l) )); then
    jq ".bottlenecks += [{
      \"type\": \"MEMORY\",
      \"severity\": \"HIGH\",
      \"current_value\": ${mem_percent},
      \"threshold\": 85,
      \"description\": \"Memory pressure critical\",
      \"impact\": \"OOM killer may trigger\",
      \"timestamp\": \"${GENERATION_TIME}\"
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  # Disk bottleneck
  if [[ ${disk_percent} -gt 90 ]]; then
    jq ".bottlenecks += [{
      \"type\": \"DISK\",
      \"severity\": \"CRITICAL\",
      \"current_value\": ${disk_percent},
      \"threshold\": 90,
      \"description\": \"Disk space critically low\",
      \"impact\": \"Service failures imminent\",
      \"timestamp\": \"${GENERATION_TIME}\"
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  log_success "✓ Bottleneck detection complete"
}

# ============================================================================
# GENERATE RECOMMENDATIONS
# ============================================================================

generate_recommendations() {
  log_info "Generating optimization recommendations..."
  
  local cpu_usage=$(jq '.system_metrics.cpu.usage_percent' "${OUTPUT_FILE}")
  local mem_percent=$(jq '.system_metrics.memory.usage_percent' "${OUTPUT_FILE}")
  local disk_percent=$(jq '.system_metrics.disk.usage_percent' "${OUTPUT_FILE}")
  
  # CPU recommendations
  if (( $(echo "${cpu_usage} > 75" | bc -l) )); then
    jq ".recommendations += [{
      \"priority\": \"HIGH\",
      \"category\": \"CPU Optimization\",
      \"recommendation\": \"Implement horizontal scaling or optimize hot code paths\",
      \"estimated_improvement_percent\": 20,
      \"implementation_complexity\": \"MEDIUM\",
      \"estimated_effort_hours\": 4
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  # Memory recommendations
  if (( $(echo "${mem_percent} > 75" | bc -l) )); then
    jq ".recommendations += [{
      \"priority\": \"HIGH\",
      \"category\": \"Memory Optimization\",
      \"recommendation\": \"Review memory limits, implement caching strategies, prune unused data\",
      \"estimated_improvement_percent\": 25,
      \"implementation_complexity\": \"MEDIUM\",
      \"estimated_effort_hours\": 6
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  # Disk recommendations
  if [[ ${disk_percent} -gt 80 ]]; then
    jq ".recommendations += [{
      \"priority\": \"CRITICAL\",
      \"category\": \"Disk Space\",
      \"recommendation\": \"Implement log rotation, prune old backups, clean temporary files\",
      \"estimated_improvement_percent\": 40,
      \"implementation_complexity\": \"LOW\",
      \"estimated_effort_hours\": 1
    }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  # General recommendations
  jq ".recommendations += [{
    \"priority\": \"MEDIUM\",
    \"category\": \"Monitoring\",
    \"recommendation\": \"Enable continuous performance monitoring with 30-second collection interval\",
    \"estimated_improvement_percent\": 15,
    \"implementation_complexity\": \"LOW\",
    \"estimated_effort_hours\": 0.5
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  log_success "✓ Recommendations generated"
}

# ============================================================================
# CALCULATE OPTIMIZATION SCORE
# ============================================================================

calculate_optimization_score() {
  log_info "Calculating optimization score..."
  
  local cpu_usage=$(jq '.system_metrics.cpu.usage_percent' "${OUTPUT_FILE}")
  local mem_percent=$(jq '.system_metrics.memory.usage_percent' "${OUTPUT_FILE}")
  local disk_percent=$(jq '.system_metrics.disk.usage_percent' "${OUTPUT_FILE}")
  
  # Score based on utilization efficiency
  local cpu_score=$(echo "100 - ${cpu_usage}" | bc)
  local mem_score=$(echo "100 - ${mem_percent}" | bc)
  local disk_score=$(echo "100 - ${disk_percent}" | bc)
  
  # Weighted average: CPU 40%, Memory 40%, Disk 20%
  local total_score=$(echo "scale=2; (${cpu_score} * 0.4) + (${mem_score} * 0.4) + (${disk_score} * 0.2)" | bc)
  
  # Ensure score is in 0-100 range
  [[ $(echo "${total_score} < 0" | bc) -eq 1 ]] && total_score=0
  [[ $(echo "${total_score} > 100" | bc) -eq 1 ]] && total_score=100
  
  jq ".optimization_score = $(printf "%.1f" "${total_score}")" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp"
  mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
  log_info "Generating performance report..."
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "PERFORMANCE ANALYSIS REPORT"
  log_info "═══════════════════════════════════════════════════════"
  echo
  
  log_info "SYSTEM METRICS:"
  jq '.system_metrics' "${OUTPUT_FILE}" | jq '.cpu, .memory, .disk'
  
  echo
  log_info "OPTIMIZATION SCORE: $(jq '.optimization_score' "${OUTPUT_FILE}")/100"
  
  local bottleneck_count=$(jq '.bottlenecks | length' "${OUTPUT_FILE}")
  if [[ ${bottleneck_count} -gt 0 ]]; then
    echo
    log_warn "⚠ BOTTLENECKS DETECTED (${bottleneck_count}):"
    jq '.bottlenecks[] | "\(.type): \(.severity) - \(.description)"' "${OUTPUT_FILE}" | head -5
  fi
  
  local rec_count=$(jq '.recommendations | length' "${OUTPUT_FILE}")
  if [[ ${rec_count} -gt 0 ]]; then
    echo
    log_info "TOP RECOMMENDATIONS:"
    jq -r '.recommendations | sort_by(.priority) | reverse | .[] | "\(.priority): \(.recommendation)"' "${OUTPUT_FILE}" | head -3
  fi
}

# Main execution
main() {
  init_analysis
  collect_system_metrics
  
  if [[ "${ANALYSIS_DEPTH}" != "quick" ]]; then
    analyze_service_performance
  fi
  
  detect_bottlenecks
  generate_recommendations
  calculate_optimization_score
  generate_report
  
  log_success "✓ PERFORMANCE ANALYSIS COMPLETE"
  log_info "Report: ${OUTPUT_FILE}"
  
  return 0
}

main
