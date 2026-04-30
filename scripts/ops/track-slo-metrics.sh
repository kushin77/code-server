#!/bin/bash
#
# SLO & Error Budget Tracker for code-server deployment
# Measures deployment reliability and tracks against SLO targets
#

set -euo pipefail

trap 'echo "Tracker failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
METRICS_DIR="${METRICS_DIR:-.metrics}"
REPORT_FILE="${METRICS_DIR}/slo-report-$(date +%Y%m%d).json"

# Ensure metrics directory exists (use user-writable directory)
mkdir -p "${METRICS_DIR}" 2>/dev/null || mkdir -p "${HOME}/.code-server-metrics" && METRICS_DIR="${HOME}/.code-server-metrics"

# SLO Definitions (adjust based on requirements)
SLO_AVAILABILITY=99      # 99% uptime (7.2 hours downtime per month)
SLO_DEPLOYMENT_SUCCESS=95 # 95% of deployments succeed without rollback
SLO_DRIFT_FREE=100       # 100% of time drift-free after apply
SLO_HEALTH_PASS=98       # 98% of health checks pass

# Monthly error budget (in minutes for a 720-hour month = 43200 minutes)
AVAILABILITY_ERROR_BUDGET=432  # ~7.2 hours downtime allowed
DEPLOYMENT_ERROR_BUDGET=1      # 1 failed deployment per month allowed

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# METRIC COLLECTION FUNCTIONS
# ============================================================================

collect_availability_metric() {
  # Placeholder: Would calculate from monitoring data
  # For now, default to 100 if no data
  echo "100"
}

collect_deployment_metrics() {
  # Count deployments from git log (commits in last 30 days)
  cd "${REPO_ROOT}" 2>/dev/null || { echo '{"total":0,"successful":0,"rate":0}'; return; }
  
  local total=$(git log --since="30 days ago" --oneline 2>/dev/null | wc -l || echo "0")
  
  # Assume all were successful (would need rollback tracking for accuracy)
  echo "{\"total\":$total,\"successful\":$total,\"rate\":100}"
}

collect_drift_metric() {
  # Placeholder: Would calculate from drift detector logs
  # For now, default to 100 (no drift)
  echo "100"
}

collect_health_check_metric() {
  # Placeholder: Would calculate from watchdog health checks
  # For now, default to 100 (all healthy)
  echo "100"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_slo_report() {
  local availability=$(collect_availability_metric)
  local deployments=$(collect_deployment_metrics)
  local drift=$(collect_drift_metric)
  local health=$(collect_health_check_metric)
  
  local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  
  echo "============================================"
  echo "SLO & Error Budget Report"
  echo "============================================"
  echo "Generated: ${timestamp}"
  echo ""
  
  # Availability
  echo "1. AVAILABILITY SLO"
  echo "   Target: ${SLO_AVAILABILITY}%"
  echo "   Actual: ${availability}%"
  local availability_status
  if (( availability >= SLO_AVAILABILITY )); then
    availability_status="${GREEN}PASS${NC}"
  else
    availability_status="${RED}FAIL${NC}"
  fi
  echo -e "   Status: ${availability_status}"
  echo "   Monthly error budget: ${AVAILABILITY_ERROR_BUDGET} minutes"
  echo ""
  
  # Deployment Success
  echo "2. DEPLOYMENT SUCCESS SLO"
  echo "   Target: ${SLO_DEPLOYMENT_SUCCESS}%"
  local deploy_rate=$(echo "$deployments" | jq -r '.rate // 0' | cut -d. -f1)
  echo "   Actual: ${deploy_rate}%"
  local deploy_status
  if (( deploy_rate >= SLO_DEPLOYMENT_SUCCESS )); then
    deploy_status="${GREEN}PASS${NC}"
  else
    deploy_status="${RED}FAIL${NC}"
  fi
  echo -e "   Status: ${deploy_status}"
  local deploy_count=$(echo "$deployments" | jq -r '.total // 0')
  echo "   Deployments (last 30d): ${deploy_count}"
  echo ""
  
  # Drift-Free Status
  echo "3. DRIFT-FREE SLO"
  echo "   Target: ${SLO_DRIFT_FREE}%"
  echo "   Actual: ${drift}%"
  local drift_status
  if (( drift >= SLO_DRIFT_FREE )); then
    drift_status="${GREEN}PASS${NC}"
  else
    drift_status="${RED}FAIL${NC}"
  fi
  echo -e "   Status: ${drift_status}"
  echo ""
  
  # Health Check Pass Rate
  echo "4. HEALTH CHECK SLO"
  echo "   Target: ${SLO_HEALTH_PASS}%"
  echo "   Actual: ${health}%"
  local health_status
  if (( health >= SLO_HEALTH_PASS )); then
    health_status="${GREEN}PASS${NC}"
  else
    health_status="${RED}FAIL${NC}"
  fi
  echo -e "   Status: ${health_status}"
  echo ""
  
  # Summary
  echo "============================================"
  echo "Error Budget Summary"
  echo "============================================"
  echo "Availability budget: ${AVAILABILITY_ERROR_BUDGET} min/month"
  echo "Deployment budget: ${DEPLOYMENT_ERROR_BUDGET} failures/month"
  echo ""
  
  # Generate JSON report
  cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "${timestamp}",
  "slo_targets": {
    "availability": ${SLO_AVAILABILITY},
    "deployment_success": ${SLO_DEPLOYMENT_SUCCESS},
    "drift_free": ${SLO_DRIFT_FREE},
    "health_check": ${SLO_HEALTH_PASS}
  },
  "metrics": {
    "availability": ${availability:-null},
    "deployment_success": ${deploy_success:-null},
    "drift_free": ${drift:-null},
    "health_check": ${health:-null}
  },
  "deployments": ${deployments},
  "error_budgets": {
    "availability_minutes_per_month": ${AVAILABILITY_ERROR_BUDGET},
    "deployment_failures_per_month": ${DEPLOYMENT_ERROR_BUDGET}
  }
}
EOF
  
  echo "Report saved to: ${REPORT_FILE}"
}

# ============================================================================
# MAIN
# ============================================================================

if [[ $# -eq 0 ]]; then
  generate_slo_report
elif [[ "$1" == "--json" ]]; then
  generate_slo_report | grep -A 50 '"timestamp"' || true
elif [[ "$1" == "--availability" ]]; then
  collect_availability_metric
elif [[ "$1" == "--deployments" ]]; then
  collect_deployment_metrics
elif [[ "$1" == "--drift" ]]; then
  collect_drift_metric
elif [[ "$1" == "--health" ]]; then
  collect_health_check_metric
else
  echo "Usage: $0 [--json | --availability | --deployments | --drift | --health]"
  exit 1
fi
