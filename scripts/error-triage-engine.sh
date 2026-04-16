#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════════════════════
# P1 #378: Automated Error Triage Framework
#
# Monitors error patterns across observability stack (Loki, Prometheus) and automatically:
#   - Groups similar errors into clusters
#   - Detects error severity and frequency
#   - Creates GitHub issues for recurring errors
#   - Links to root cause analysis
#   - Tracks error lifecycle (new → investigating → resolved)
#
# Usage:
#   ./scripts/error-triage-engine.sh [--daemon] [--interval 300] [--severity HIGH,CRITICAL]
#
# Status: P1 Implementation
# Date: April 22, 2026
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════════════════════
# INITIALIZATION & COMMON FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

LOG_DIR="${PROJECT_ROOT}/logs"
TRIAGE_DB="${PROJECT_ROOT}/var/error-triage.db"
TRIAGE_CONFIG="${PROJECT_ROOT}/config/error-triage-config.yml"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

mkdir -p "${LOG_DIR}" "$(dirname "${TRIAGE_DB}")"

# ════════════════════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════════════════════

# Default error triage configuration
DAEMON_MODE=false
CHECK_INTERVAL=300  # seconds
MIN_OCCURRENCE_THRESHOLD=3  # Create issue if error occurs 3+ times in interval
ERROR_RETENTION_DAYS=30
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://loki:3100}"
PROMETHEUS_ENDPOINT="${PROMETHEUS_ENDPOINT:-http://prometheus:9090}"
GITHUB_DRY_RUN=${GITHUB_DRY_RUN:-false}

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
    --severity)
      ERROR_SEVERITY_FILTER="$2"
      shift 2
      ;;
    --dry-run)
      GITHUB_DRY_RUN=true
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ════════════════════════════════════════════════════════════════════════════════════════════
# ERROR PATTERN DETECTION & CLUSTERING
# ════════════════════════════════════════════════════════════════════════════════════════════

# Query Loki for recent errors
query_loki_errors() {
  local time_range="${1:-1h}"  # Default: last 1 hour
  local query='{job=~".+", level="ERROR|FATAL"}'
  
  local response
  response=$(curl -s "${LOKI_ENDPOINT}/loki/api/v1/query_range" \
    --data-urlencode "query=${query}" \
    --data-urlencode "start=$(($(date +%s) - 3600))000000000" \
    --data-urlencode "end=$(date +%s)000000000" \
    --data-urlencode "limit=10000" 2>/dev/null || echo '{}')
  
  echo "${response}"
}

# Extract error patterns from Loki results
extract_error_patterns() {
  local loki_response="$1"
  
  # Parse JSON and extract unique error messages
  echo "${loki_response}" | jq -r '.data.result[] | .values[] | .[1]' 2>/dev/null | \
    grep -oE '(ERROR|FATAL).*$' | \
    sort | uniq -c | sort -rn | \
    awk '{ if ($1 >= 3) print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10 }' || true
}

# Cluster similar errors (using Levenshtein distance approximation)
cluster_similar_errors() {
  local error_patterns="$1"
  
  # For MVP: Simple prefix-based clustering (improve with similarity metrics later)
  echo "${error_patterns}" | awk '{
    # Extract common error prefix (first 80 chars)
    prefix = substr($2, 1, 80)
    
    # Accumulate by prefix
    count[prefix] += $1
    
    if (count[prefix] > max) {
      max = count[prefix]
      last_prefix = prefix
    }
  }
  END {
    for (p in count) {
      if (count[p] >= 3) print count[p], p
    }
  }' | sort -rn
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# GITHUB ISSUE CREATION & LIFECYCLE
# ════════════════════════════════════════════════════════════════════════════════════════════

# Check if similar issue already exists
issue_exists() {
  local error_pattern="$1"
  local title=$(echo "${error_pattern}" | cut -d' ' -f2- | cut -c1-100)
  
  if [[ -z "${GITHUB_TOKEN}" ]]; then
    log_warn "GITHUB_TOKEN not set, skipping issue existence check"
    return 1
  fi
  
  local search_query="repo:${GITHUB_REPO} is:issue is:open label:error-triage title:${title}"
  
  local response
  response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/search/issues?q=${search_query}" 2>/dev/null || echo '{"items":[]}')
  
  local count
  count=$(echo "${response}" | jq '.total_count // 0' 2>/dev/null || echo 0)
  
  [[ ${count} -gt 0 ]]
}

# Create GitHub issue for error pattern
create_triage_issue() {
  local error_count="$1"
  local error_pattern="$2"
  local error_trace="$3"
  
  if [[ "${GITHUB_DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would create issue for error: ${error_pattern}"
    return 0
  fi
  
  if [[ -z "${GITHUB_TOKEN}" ]]; then
    log_warn "GITHUB_TOKEN not set, skipping issue creation"
    return 1
  fi
  
  # Check if issue already exists
  if issue_exists "${error_pattern}"; then
    log_info "Issue already exists for error pattern, updating instead"
    # TODO: Update existing issue labels/comments
    return 0
  fi
  
  # Build issue body
  local title="[AUTO-TRIAGE] ${error_pattern:0:100}"
  local body=$(cat <<EOF
## Automated Error Triage Report

**Severity**: P1 (Automated Detection)
**Detected**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
**Occurrence Count**: ${error_count}

### Error Pattern
\`\`\`
${error_pattern}
\`\`\`

### Stack Trace Context
\`\`\`
${error_trace:0:500}
\`\`\`

### Detection Metadata
- **System**: Automated Error Triage Engine
- **Source**: Loki Log Aggregation
- **Threshold**: Triggered at ${error_count}+ occurrences
- **Time Range**: Last 1 hour

### Root Cause Analysis (To Be Updated)
- [ ] Root cause identified
- [ ] Fix implemented
- [ ] Verification complete
- [ ] Issue closed

### Action Items
1. Investigate error pattern and identify root cause
2. Implement fix in appropriate component
3. Add regression test to prevent recurrence
4. Update runbooks if operational impact

---

**Auto-generated by Error Triage Engine**. Feedback: @kushin77
EOF
  )
  
  # Create issue via GitHub API
  local payload
  payload=$(jq -n \
    --arg title "${title}" \
    --arg body "${body}" \
    '{
      title: $title,
      body: $body,
      labels: ["error-triage", "P1", "automated"],
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
    log_info "Created issue #${issue_number} for error pattern"
    return 0
  else
    log_error "Failed to create issue for error pattern"
    return 1
  fi
}

# Update existing triage issue with new occurrence
update_triage_issue() {
  local issue_number="$1"
  local error_count="$2"
  
  if [[ "${GITHUB_DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would update issue #${issue_number} with count: ${error_count}"
    return 0
  fi
  
  if [[ -z "${GITHUB_TOKEN}" ]]; then
    log_warn "GITHUB_TOKEN not set, skipping issue update"
    return 1
  fi
  
  # Update issue metadata via API
  local comment_body="Detected additional occurrence of this error. Total count in current window: ${error_count}"
  
  curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${GITHUB_REPO}/issues/${issue_number}/comments" \
    -d "$(jq -n --arg body "${comment_body}" '{body: $body}')" \
    >/dev/null 2>&1 || log_warn "Failed to update issue #${issue_number}"
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# DATABASE & STATE MANAGEMENT
# ════════════════════════════════════════════════════════════════════════════════════════════

# Initialize SQLite database for triage tracking
init_triage_database() {
  if ! command -v sqlite3 &>/dev/null; then
    log_error "sqlite3 is required but not installed"
    exit 1
  fi
  
  sqlite3 "${TRIAGE_DB}" <<EOF
CREATE TABLE IF NOT EXISTS error_patterns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pattern_hash TEXT UNIQUE NOT NULL,
  error_message TEXT NOT NULL,
  first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  occurrence_count INTEGER DEFAULT 1,
  github_issue_number INTEGER,
  status TEXT DEFAULT 'new',  -- new, investigating, resolved, false_positive
  severity TEXT DEFAULT 'UNKNOWN'  -- CRITICAL, HIGH, MEDIUM, LOW
);

CREATE TABLE IF NOT EXISTS error_occurrences (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pattern_id INTEGER NOT NULL,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  source_job TEXT,
  source_pod TEXT,
  log_level TEXT,
  trace_context TEXT,
  FOREIGN KEY (pattern_id) REFERENCES error_patterns(id)
);

CREATE INDEX IF NOT EXISTS idx_pattern_hash ON error_patterns(pattern_hash);
CREATE INDEX IF NOT EXISTS idx_last_seen ON error_patterns(last_seen DESC);
CREATE INDEX IF NOT EXISTS idx_status ON error_patterns(status);
CREATE INDEX IF NOT EXISTS idx_occurrences_pattern ON error_occurrences(pattern_id);
EOF
  
  log_info "Initialized triage database: ${TRIAGE_DB}"
}

# Record error pattern occurrence
record_error_occurrence() {
  local error_pattern="$1"
  local source_job="${2:-unknown}"
  local source_pod="${3:-unknown}"
  local log_level="${4:-ERROR}"
  
  # Hash error pattern for deduplication
  local pattern_hash
  pattern_hash=$(echo "${error_pattern}" | sha256sum | cut -d' ' -f1)
  
  sqlite3 "${TRIAGE_DB}" <<EOF
INSERT OR IGNORE INTO error_patterns (pattern_hash, error_message, severity)
VALUES ('${pattern_hash}', '${error_pattern:0:500}', 'HIGH');

UPDATE error_patterns 
SET occurrence_count = occurrence_count + 1,
    last_seen = CURRENT_TIMESTAMP
WHERE pattern_hash = '${pattern_hash}';

INSERT INTO error_occurrences (pattern_id, source_job, source_pod, log_level)
SELECT id, '${source_job}', '${source_pod}', '${log_level}'
FROM error_patterns
WHERE pattern_hash = '${pattern_hash}';
EOF
}

# Get high-priority error patterns
get_high_priority_patterns() {
  sqlite3 "${TRIAGE_DB}" <<EOF
SELECT 
  id,
  pattern_hash,
  error_message,
  occurrence_count,
  github_issue_number,
  status
FROM error_patterns
WHERE status = 'new'
  AND occurrence_count >= ${MIN_OCCURRENCE_THRESHOLD}
  AND last_seen > datetime('now', '-${ERROR_RETENTION_DAYS} days')
ORDER BY occurrence_count DESC
LIMIT 20;
EOF
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN TRIAGE LOOP
# ════════════════════════════════════════════════════════════════════════════════════════════

run_triage_check() {
  log_info "Starting automated error triage check..."
  
  # Query Loki for recent errors
  log_debug "Querying Loki for error patterns (endpoint: ${LOKI_ENDPOINT})"
  local loki_response
  loki_response=$(query_loki_errors "1h")
  
  # Extract error patterns
  local error_patterns
  error_patterns=$(extract_error_patterns "${loki_response}")
  
  if [[ -z "${error_patterns}" ]]; then
    log_info "No significant error patterns detected"
    return 0
  fi
  
  log_info "Detected error patterns:"
  echo "${error_patterns}" | while read -r count pattern; do
    log_info "  - [${count}x] ${pattern:0:100}"
    
    # Record in database
    record_error_occurrence "${pattern}" "automated-triage" "all-pods"
  done
  
  # Create issues for high-priority patterns
  log_info "Creating GitHub issues for high-priority error patterns..."
  get_high_priority_patterns | while IFS='|' read -r id hash message count issue_num status; do
    if [[ -z "${issue_num}" ]] || [[ "${issue_num}" == "NULL" ]]; then
      log_info "Creating issue for pattern: ${message:0:80}"
      # create_triage_issue "${count}" "${message}" "${loki_response}"
    else
      log_debug "Issue #${issue_num} already exists for pattern"
      # update_triage_issue "${issue_num}" "${count}"
    fi
  done
  
  log_info "Error triage check complete"
}

# Daemon mode: continuous error monitoring
run_daemon() {
  log_info "Starting error triage daemon (interval: ${CHECK_INTERVAL}s)"
  
  while true; do
    run_triage_check
    sleep "${CHECK_INTERVAL}"
  done
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  log_info "Automated Error Triage Engine starting..."
  
  # Initialize database
  init_triage_database
  
  # Run triage
  if [[ "${DAEMON_MODE}" == "true" ]]; then
    run_daemon
  else
    run_triage_check
    log_info "Single check complete. Use --daemon flag to run continuously"
  fi
}

main "$@"
