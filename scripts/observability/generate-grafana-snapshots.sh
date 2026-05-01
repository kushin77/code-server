#!/usr/bin/env bash
# @file scripts/observability/generate-grafana-snapshots.sh
# @module observability/grafana
# @description Automated Grafana dashboard snapshot generation for performance reporting
# @governance GOV-002: Immutable snapshots for audit trail and historical analysis
# @usage generate-grafana-snapshots.sh [--dashboard <name>] [--output-dir <path>] [--retention-days <days>]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Snapshot generation complete"; rm -f /tmp/grafana-snapshot-*.tmp 2>/dev/null || true' EXIT

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"
SNAPSHOT_OUTPUT_DIR="${1:-./.grafana-snapshots}"
RETENTION_DAYS="${2:-30}"

# Create output directory
mkdir -p "${SNAPSHOT_OUTPUT_DIR}"

log_info "═══════════════════════════════════════════════════════"
log_info "GRAFANA SNAPSHOT GENERATION"
log_info "═══════════════════════════════════════════════════════"

# Validate Grafana connectivity
check_grafana_connectivity() {
  log_info "Checking Grafana connectivity..."
  
  if ! response=$(curl -sf "${GRAFANA_URL}/api/health" 2>/dev/null); then
    log_error "Cannot connect to Grafana at ${GRAFANA_URL}"
    return 1
  fi
  
  log_success "✓ Grafana is accessible"
}

# List available dashboards
list_dashboards() {
  log_info "Fetching available dashboards..."
  
  local headers=""
  if [[ -n "${GRAFANA_API_KEY}" ]]; then
    headers="-H 'Authorization: Bearer ${GRAFANA_API_KEY}'"
  fi
  
  if dashboards=$(curl -s ${headers} "${GRAFANA_URL}/api/search?type=dash-db"); then
    echo "${dashboards}" | python3 -m json.tool 2>/dev/null || echo "${dashboards}"
  else
    log_error "Failed to fetch dashboards"
    return 1
  fi
}

# Generate snapshot for a specific dashboard
generate_dashboard_snapshot() {
  local dashboard_uid="$1"
  local dashboard_name="$2"
  
  log_info "Generating snapshot for dashboard: ${dashboard_name}..."
  
  local headers=""
  if [[ -n "${GRAFANA_API_KEY}" ]]; then
    headers="-H 'Authorization: Bearer ${GRAFANA_API_KEY}'"
  fi
  
  # Get dashboard
  local dashboard_json
  if ! dashboard_json=$(curl -s ${headers} "${GRAFANA_URL}/api/dashboards/uid/${dashboard_uid}"); then
    log_error "Failed to fetch dashboard: ${dashboard_name}"
    return 1
  fi
  
  # Create snapshot
  local snapshot_payload=$(cat <<EOF
{
  "dashboard": $(echo "${dashboard_json}" | python3 -c "import sys, json; d = json.load(sys.stdin); print(json.dumps(d.get('dashboard', {})))"),
  "name": "Snapshot - ${dashboard_name} - $(date -u +'%Y-%m-%d %H:%M:%S UTC')",
  "expires": ${RETENTION_DAYS}
}
EOF
)
  
  local snapshot_response
  if ! snapshot_response=$(curl -s -X POST ${headers} \
    -H "Content-Type: application/json" \
    -d "${snapshot_payload}" \
    "${GRAFANA_URL}/api/snapshots"); then
    log_error "Failed to create snapshot for: ${dashboard_name}"
    return 1
  fi
  
  # Extract snapshot key and URL
  local snapshot_key
  if snapshot_key=$(echo "${snapshot_response}" | python3 -c "import sys, json; d = json.load(sys.stdin); print(d.get('key', ''))" 2>/dev/null); then
    local snapshot_url="${GRAFANA_URL}/dashboard/snapshot/${snapshot_key}"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    
    # Log snapshot metadata
    {
      echo "Dashboard: ${dashboard_name}"
      echo "UID: ${dashboard_uid}"
      echo "Snapshot Key: ${snapshot_key}"
      echo "URL: ${snapshot_url}"
      echo "Generated: ${timestamp}"
      echo "Retention Days: ${RETENTION_DAYS}"
      echo "---"
    } >> "${SNAPSHOT_OUTPUT_DIR}/${dashboard_name//[\/\\]/-}-snapshot.log"
    
    log_success "✓ Snapshot created: ${snapshot_url}"
  else
    log_error "Could not parse snapshot response"
    return 1
  fi
}

# Generate snapshots for critical dashboards
generate_critical_snapshots() {
  log_info "Generating snapshots for critical monitoring dashboards..."
  
  local critical_dashboards=(
    "deployment:Deployment Status"
    "services:Service Health"
    "infrastructure:Infrastructure Metrics"
    "performance:Performance Overview"
    "security:Security Posture"
  )
  
  for dashboard_spec in "${critical_dashboards[@]}"; do
    IFS=':' read -r dashboard_uid dashboard_name <<< "${dashboard_spec}"
    
    if ! generate_dashboard_snapshot "${dashboard_uid}" "${dashboard_name}"; then
      log_warn "⚠ Skipping snapshot for ${dashboard_name} (may not exist)"
    fi
  done
}

# Cleanup old snapshots
cleanup_old_snapshots() {
  log_info "Cleaning up snapshots older than ${RETENTION_DAYS} days..."
  
  local headers=""
  if [[ -n "${GRAFANA_API_KEY}" ]]; then
    headers="-H 'Authorization: Bearer ${GRAFANA_API_KEY}'"
  fi
  
  # Fetch all snapshots
  if snapshots=$(curl -s ${headers} "${GRAFANA_URL}/api/snapshots"); then
    local deleted_count=0
    
    echo "${snapshots}" | python3 -c "
import sys, json, time
from datetime import datetime, timedelta

snapshots = json.load(sys.stdin)
retention_days = ${RETENTION_DAYS}
now = time.time()
threshold = now - (retention_days * 86400)

for snapshot in snapshots:
    created_timestamp = snapshot.get('created', 0)
    if isinstance(created_timestamp, str):
        try:
            created_dt = datetime.fromisoformat(created_timestamp.replace('Z', '+00:00'))
            created_timestamp = created_dt.timestamp()
        except:
            continue
    
    if created_timestamp < threshold:
        print(snapshot.get('key', ''))
" | while read -r snapshot_key; do
      if [[ -n "${snapshot_key}" ]]; then
        if curl -s -X DELETE ${headers} "${GRAFANA_URL}/api/snapshots/${snapshot_key}" >/dev/null 2>&1; then
          deleted_count+=1
        fi
      fi
    done
    
    if [[ ${deleted_count} -gt 0 ]]; then
      log_success "✓ Deleted ${deleted_count} expired snapshots"
    fi
  fi
}

# Generate summary report
generate_summary_report() {
  log_info "Generating snapshot summary report..."
  
  local summary_file="${SNAPSHOT_OUTPUT_DIR}/snapshot-summary-$(date -u +'%Y-%m-%d').txt"
  
  {
    echo "GRAFANA SNAPSHOT GENERATION REPORT"
    echo "Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Configuration:"
    echo "  Grafana URL: ${GRAFANA_URL}"
    echo "  Output Directory: ${SNAPSHOT_OUTPUT_DIR}"
    echo "  Retention Days: ${RETENTION_DAYS}"
    echo ""
    echo "Snapshots Created:"
    wc -l "${SNAPSHOT_OUTPUT_DIR}"/*.log 2>/dev/null | tail -1 || echo "  None"
    echo ""
    echo "═══════════════════════════════════════════════════════"
  } > "${summary_file}"
  
  log_success "✓ Summary report: ${summary_file}"
}

# Main execution
main() {
  log_info "Snapshot generation started at $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  
  if ! check_grafana_connectivity; then
    log_error "Cannot proceed without Grafana connectivity"
    return 1
  fi
  
  generate_critical_snapshots
  cleanup_old_snapshots
  generate_summary_report
  
  log_success "✓ Snapshot generation completed successfully"
  log_info "Snapshots saved to: ${SNAPSHOT_OUTPUT_DIR}"
}

# Execute main
main
