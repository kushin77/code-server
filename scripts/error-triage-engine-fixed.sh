#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://loki:3100}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"
ERROR_TRIAGE_THRESHOLD="${ERROR_TRIAGE_THRESHOLD:-100}"
ERROR_TRIAGE_INTERVAL="${ERROR_TRIAGE_INTERVAL:-300}"
ERROR_TRIAGE_WINDOW="${ERROR_TRIAGE_WINDOW:-3600}"
TRIAGE_DB="/var/lib/error-triage/error-triage.db"

init_db() {
    log_info "Initializing error triage database"
    sqlite3 "$TRIAGE_DB" << 'SQLITE_EOF'
CREATE TABLE IF NOT EXISTS error_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_hash TEXT UNIQUE NOT NULL,
    error_message TEXT,
    first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    occurrence_count INTEGER DEFAULT 1,
    github_issue_number INTEGER,
    status TEXT DEFAULT 'new'
);
CREATE INDEX IF NOT EXISTS idx_pattern_hash ON error_patterns(pattern_hash);
CREATE INDEX IF NOT EXISTS idx_last_seen ON error_patterns(last_seen);
SQLITE_EOF
}

alert_on_pattern() {
    local pattern_hash="$1"
    local error_message="$2"
    local occurrence_count="$3"
    
    local existing_issue
    existing_issue=$(sqlite3 "$TRIAGE_DB" "SELECT github_issue_number FROM error_patterns WHERE pattern_hash = '$pattern_hash';" 2>/dev/null || echo '')
    
    if [[ -n "$existing_issue" ]] && [[ "$existing_issue" != "null" ]]; then
        return 0
    fi
    
    local issue_title="[AUTO-TRIAGE] Error Pattern: $(echo "$error_message" | head -c 50)"
    local issue_body="Pattern Hash: $pattern_hash
Occurrences: $occurrence_count
Message: $error_message"
    
    log_info "Creating GitHub issue for pattern $pattern_hash"
    
    local gh_output
    gh_output=$(gh issue create --title "$issue_title" --body "$issue_body" --repo "$GITHUB_REPO" 2>&1) || {
        log_warn "Failed to create GitHub issue"
        return 1
    }
    
    local new_issue_number
    new_issue_number=$(printf '%s' "$gh_output" | grep -oE 'issues/[0-9]+' | awk -F/ '{print $NF}' || true)
    
    if [[ -n "$new_issue_number" ]]; then
        sqlite3 "$TRIAGE_DB" "UPDATE error_patterns SET github_issue_number = $new_issue_number, status = 'alerted' WHERE pattern_hash = '$pattern_hash';"
        log_info "Linked pattern $pattern_hash to issue #$new_issue_number"
    fi
}

query_loki() {
    local now_epoch
    local start_epoch
    local start
    
    now_epoch=$(date +%s)
    start_epoch=$((now_epoch - ERROR_TRIAGE_WINDOW))
    start="${start_epoch}000000000"
    
    curl -s -X GET "${LOKI_ENDPOINT}/loki/api/v1/query_range" \
        --data-urlencode 'query={level=~"ERROR|FATAL|error|fatal"}' \
        --data-urlencode "start=$start" \
        --data-urlencode "end=${now_epoch}000000000" \
        --data-urlencode "limit=1000" | jq -r '.data.result[0].values[][] | .[1]' 2>/dev/null || true
}

record_error() {
    local error_message="$1"
    local pattern_hash
    pattern_hash=$(printf '%s' "$error_message" | md5sum | awk '{print $1}')
    
    sqlite3 "$TRIAGE_DB" << 'SQLITE_EOF'
INSERT OR IGNORE INTO error_patterns (pattern_hash, error_message) VALUES ('$pattern_hash', '$error_message');
UPDATE error_patterns SET occurrence_count = occurrence_count + 1, last_seen = CURRENT_TIMESTAMP WHERE pattern_hash = '$pattern_hash';
SQLITE_EOF
    
    echo "$pattern_hash"
}

scan_once() {
    log_debug "Scanning Loki for new error patterns"
    
    local logs
    logs=$(query_loki)
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        local pattern_hash occurrence_count
        pattern_hash=$(record_error "$line")
        occurrence_count=$(sqlite3 "$TRIAGE_DB" "SELECT occurrence_count FROM error_patterns WHERE pattern_hash = '$pattern_hash';" 2>/dev/null || echo 0)
        
        if [[ $occurrence_count -ge $ERROR_TRIAGE_THRESHOLD ]]; then
            log_warn "Threshold reached ($occurrence_count occurrences)"
            alert_on_pattern "$pattern_hash" "$line" "$occurrence_count"
        fi
    done <<< "$logs"
}

run_daemon() {
    log_info "Starting error triage daemon (interval=${ERROR_TRIAGE_INTERVAL}s, threshold=${ERROR_TRIAGE_THRESHOLD})"
    
    while true; do
        scan_once || true
        sleep "$ERROR_TRIAGE_INTERVAL"
    done
}

cleanup() {
    log_info "Cleaning up error triage engine"
}

main() {
    trap cleanup EXIT
    
    init_db
    
    if [[ "${1:-}" == "--daemon" ]]; then
        run_daemon
    else
        scan_once
    fi
}

main "$@"
