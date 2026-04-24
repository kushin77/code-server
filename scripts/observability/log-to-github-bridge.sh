#!/usr/bin/env bash
# @file        scripts/observability/log-to-github-bridge.sh
# @module      observability/github-integration
# @description Central bridge that reads from Loki and creates/updates GitHub issues.
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# Log-to-GitHub Bridge (Phase 22+)
#
# Purpose:
#   - Central aggregator for all log → GitHub issue conversions
#   - Query Loki for specific error patterns
#   - Group similar errors into issues
#   - Provide unified interface for log-based alerting
#   - Deduplicate and update existing issues
#
# Usage:
#   ./scripts/observability/log-to-github-bridge.sh --query '{job="terraform"}' --severity ERROR
#   ./scripts/observability/log-to-github-bridge.sh --daemon --interval 300
#
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${PROJECT_ROOT}/scripts/_common/init.sh" || { echo "FATAL: Cannot source init.sh"; exit 1; }

# Configuration
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://loki:3100}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
QUERY="${QUERY:-{job!=\"\"}}"  # Default: all jobs
SEVERITY="${SEVERITY:-ERROR}"
TIME_RANGE="${TIME_RANGE:-1h}"
DAEMON_MODE=false
CHECK_INTERVAL=600  # 10 minutes
DEDUP_WINDOW=86400  # 1 day
DATABASE="${PROJECT_ROOT}/var/log-to-github.db"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --daemon)
      DAEMON_MODE=true
      shift
      ;;
    --interval)
      CHECK_INTERVAL="$2"
      shift 2
      ;;
    --query)
      QUERY="$2"
      shift 2
      ;;
    --severity)
      SEVERITY="$2"
      shift 2
      ;;
    --time-range)
      TIME_RANGE="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "${DATABASE}")"

if [[ -z "${GITHUB_TOKEN}" ]]; then
  log_warn "GITHUB_TOKEN not set, GitHub issue creation disabled"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ════════════════════════════════════════════════════════════════════════════════════════════

# Initialize database for tracking
init_database() {
  if ! command -v sqlite3 &>/dev/null; then
    log_warn "sqlite3 not available, skipping database initialization"
    return 0
  fi
  
  sqlite3 "${DATABASE}" <<'EOF'
CREATE TABLE IF NOT EXISTS loki_issue_map (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  loki_query_hash TEXT UNIQUE NOT NULL,
  github_issue_number INTEGER NOT NULL,
  last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS loki_error_aggregates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  query_hash TEXT NOT NULL,
  error_pattern TEXT NOT NULL,
  count INTEGER DEFAULT 1,
  last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  github_issue_number INTEGER,
  UNIQUE(query_hash, error_pattern)
);

CREATE INDEX IF NOT EXISTS idx_last_update ON loki_issue_map(last_update DESC);
CREATE INDEX IF NOT EXISTS idx_error_aggregates ON loki_error_aggregates(query_hash);
EOF
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# LOKI QUERYING & ERROR AGGREGATION
# ════════════════════════════════════════════════════════════════════════════════════════════

# Query Loki for errors matching criteria
query_loki() {
  local query="$1"
  local time_range="$2"
  local severity="${3:-ERROR}"
  
  # Build full query with severity filter
  local full_query="${query}, level=\"${severity}\""
  
  local response
  response=$(curl -s "${LOKI_ENDPOINT}/loki/api/v1/query_range" \
    --data-urlencode "query=${full_query}" \
    --data-urlencode "start=$(($(date +%s) - 3600))000000000" \
    --data-urlencode "end=$(date +%s)000000000" \
    --data-urlencode "limit=5000" 2>/dev/null || echo '{"status":"error"}')
  
  echo "${response}"
}

# Extract and aggregate error patterns from Loki response
aggregate_errors() {
  local loki_response="$1"
  local query_hash="$2"
  
  # Extract messages and count occurrences
  echo "${loki_response}" | jq -r '.data.result[] | .values[] | .[1]' 2>/dev/null | \
    grep -v '^$' | \
    sed 's/^[^[:space:]]*[[:space:]]//' | \
    sort | uniq -c | sort -rn | \
    awk '{
      # Normalize error pattern (first 120 chars)
      pattern = substr($2, 1, 120)
      
      print pattern, $1
    }' || true
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# GITHUB ISSUE CREATION & LINKING
# ════════════════════════════════════════════════════════════════════════════════════════════

# Get or create GitHub issue for error pattern
get_or_create_issue() {
  local error_pattern="$1"
  local query_hash="$2"
  local count="$3"
  
  if [[ -z "${GITHUB_TOKEN}" ]]; then
    return 1
  fi
  
  # Check if issue already exists in database
  if command -v sqlite3 &>/dev/null; then
    local existing_issue
    existing_issue=$(sqlite3 "${DATABASE}" \
      "SELECT github_issue_number FROM loki_issue_map WHERE loki_query_hash = '${query_hash}';" \
      2>/dev/null || echo "")
    
    if [[ -n "${existing_issue}" ]]; then
      log_debug "Issue #${existing_issue} already exists for pattern"
      return 0
    fi
  fi
  
  # Search for existing issue on GitHub
  local search_query="repo:${GITHUB_REPO} is:issue is:open label:log-bridge \"${error_pattern:0:50}\""
  local search_response
  search_response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/search/issues?q=${search_query}" 2>/dev/null || echo '{"items":[]}')
  
  local existing_count
  existing_count=$(echo "${search_response}" | jq '.total_count // 0' 2>/dev/null || echo 0)
  
  if [[ ${existing_count} -gt 0 ]]; then
    log_debug "Found existing GitHub issue for pattern"
    return 0
  fi
  
  # Create new issue
  local title="[LOG-BRIDGE] ${error_pattern:0:100}"
  local body
  body=$(cat <<EOF
## Automated Log-to-GitHub Bridge Report

**Detection Source**: Loki Log Aggregation
**Pattern**: \`${error_pattern}\`
**Occurrence Count**: ${count} (in last ${TIME_RANGE})
**Detected**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Error Context
\`\`\`
${error_pattern}
\`\`\`

### Investigation Checklist
- [ ] Identify root cause from logs
- [ ] Check if this is expected behavior
- [ ] Determine if fix is needed
- [ ] Implement fix if necessary
- [ ] Add monitoring/alerting if missing
- [ ] Close issue when resolved

### Log Query
\`\`\`
${QUERY}, level="${SEVERITY}"
\`\`\`

### Next Steps
1. Review full logs in Loki dashboard
2. Correlate with other system events
3. Check recent deployments or config changes
4. Implement preventive measures

---
*Auto-generated by Log-to-GitHub Bridge*
*Source: Loki → Error Triage Engine → GitHub*
EOF
  )
  
  local payload
  payload=$(jq -n \
    --arg title "${title}" \
    --arg body "${body}" \
    '{
      title: $title,
      body: $body,
      labels: ["log-bridge", "automated", "'${SEVERITY}'"],
      assignees: ["kushin77"]
    }')
  
  local response
  response=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${GITHUB_REPO}/issues" \
    -d "${payload}" 2>/dev/null || echo '{}')
  
  local issue_number
  issue_number=$(echo "${response}" | jq '.number // empty' 2>/dev/null || echo "")
  
  if [[ -n "${issue_number}" ]]; then
    log_info "Created GitHub issue #${issue_number} for error pattern"
    
    # Store in database
    if command -v sqlite3 &>/dev/null; then
      sqlite3 "${DATABASE}" \
        "INSERT INTO loki_issue_map (loki_query_hash, github_issue_number) VALUES ('${query_hash}', ${issue_number});" \
        2>/dev/null || true
    fi
    
    return 0
  else
    log_error "Failed to create GitHub issue"
    return 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN BRIDGE LOGIC
# ════════════════════════════════════════════════════════════════════════════════════════════

run_bridge_check() {
  log_info "Running log-to-GitHub bridge check..."
  log_info "  Query: ${QUERY}"
  log_info "  Severity: ${SEVERITY}"
  log_info "  Time Range: ${TIME_RANGE}"
  
  # Hash query for database tracking
  local query_hash
  query_hash=$(echo "${QUERY}" | sha256sum | cut -d' ' -f1)
  
  # Query Loki
  local loki_response
  loki_response=$(query_loki "${QUERY}" "${TIME_RANGE}" "${SEVERITY}")
  
  if [[ -z "${loki_response}" ]] || [[ "${loki_response}" == *"error"* ]]; then
    log_warn "Loki query failed or returned no results"
    return 1
  fi
  
  # Aggregate errors
  local aggregates
  aggregates=$(aggregate_errors "${loki_response}" "${query_hash}")
  
  if [[ -z "${aggregates}" ]]; then
    log_info "No error patterns detected in Loki"
    return 0
  fi
  
  # Process each aggregated error
  local issue_count=0
  echo "${aggregates}" | while IFS=' ' read -r pattern count; do
    log_info "Creating issue for pattern (${count}x): ${pattern:0:80}"
    
    if get_or_create_issue "${pattern}" "${query_hash}" "${count}"; then
      ((issue_count++))
    fi
  done
  
  log_info "Bridge check complete (${issue_count} new issues created)"
}

run_daemon() {
  log_info "Starting log-to-GitHub bridge daemon (interval: ${CHECK_INTERVAL}s)"
  
  while true; do
    run_bridge_check || true
    sleep "${CHECK_INTERVAL}"
  done
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  log_info "Log-to-GitHub Bridge starting..."
  
  # Initialize database
  init_database
  
  if [[ "${DAEMON_MODE}" == "true" ]]; then
    run_daemon
  else
    run_bridge_check
    log_info "Bridge check complete. Use --daemon flag to run continuously"
  fi
}

main "$@"
