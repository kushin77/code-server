import subprocess
import tempfile
import os

# Read the clean script
clean_script = '''#!/usr/bin/env bash
# @file        scripts/error-triage-engine.sh
# @module      observability/error-triage
# @description Automated error pattern detection and GitHub issue creation from Loki logs
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://loki:3100}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"
ERROR_TRIAGE_THRESHOLD="${ERROR_TRIAGE_THRESHOLD:-100}"
ERROR_TRIAGE_INTERVAL="${ERROR_TRIAGE_INTERVAL:-300}"
ERROR_TRIAGE_WINDOW="${ERROR_TRIAGE_WINDOW:-3600}"
TRIAGE_DB="/var/lib/error-triage/error-triage.db"
SQLITE3="sqlite3"

init_db() {
    log_info "Initializing error triage database"
    "$SQLITE3" "$TRIAGE_DB" << 'SQLITE_EOF'
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
CREATE INDEX IF NOT EXISTS idx_status ON error_patterns(status);

CREATE TABLE IF NOT EXISTS error_occurrences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_id INTEGER NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(pattern_id) REFERENCES error_patterns(id)
);

CREATE INDEX IF NOT EXISTS idx_pattern_id ON error_occurrences(pattern_id);
SQLITE_EOF
}

alert_on_pattern() {
    local pattern_hash="$1"
    local error_message="$2"
    local occurrence_count="$3"
    
    # Check if already alerted
    local existing_issue
    existing_issue=$("$SQLITE3" "$TRIAGE_DB" "SELECT github_issue_number FROM error_patterns WHERE pattern_hash = '$pattern_hash';" 2>/dev/null || echo '')
    
    if [[ -n "$existing_issue" ]] && [[ "$existing_issue" != "null" ]]; then
        return 0
    fi
    
    # Prepare issue title and body
    local issue_title="[AUTO-TRIAGE] Error Pattern Detected: $(echo "$error_message" | head -c 60)..."
    local issue_body="**Pattern Hash:** \`$pattern_hash\`\\n"
    issue_body+="**Occurrences (1h):** $occurrence_count\\n"
    issue_body+="**Error Message:**\\n\`\`\`\\n$error_message\\n\`\`\`\\n"
    issue_body+="\\n_Auto-created by Error Triage Engine_"
    
    # Create GitHub issue using valid gh CLI flags only
    log_info "Creating GitHub issue for pattern $pattern_hash with $occurrence_count occurrences"
    
    local gh_output
    gh_output=$(gh issue create --title "$issue_title" --body "$issue_body" --repo "$GITHUB_REPO" 2>&1) || {
        log_warn "Failed to create GitHub issue for pattern $pattern_hash"
        return 1
    }
    
    # Extract issue number from output (URL format: https://github.com/kushin77/code-server/issues/1234)
    local new_issue_number
    new_issue_number=$(printf '%s' "$gh_output" | grep -oE 'issues/([0-9]+)' | awk -F'/' '{print $NF}' || true)
    
    if [[ -n "$new_issue_number" ]]; then
        "$SQLITE3" "$TRIAGE_DB" "UPDATE error_patterns SET github_issue_number = $new_issue_number, status = 'alerted' WHERE pattern_hash = '$pattern_hash';"
        log_info "✓ Linked error pattern $pattern_hash to GitHub Issue #$new_issue_number"
    else
        log_warn "Could not extract issue number from gh output: $gh_output"
    fi
}

query_loki() {
    local query='{level=~"ERROR|FATAL|error|fatal"}'
    local now_epoch
    local start_epoch
    local start
    
    now_epoch=$(date +%s)
    start_epoch=$((now_epoch - ERROR_TRIAGE_WINDOW))
    start="${start_epoch}000000000"
    
    curl -s -X GET "${LOKI_ENDPOINT}/loki/api/v1/query_range" \\
        --data-urlencode "query=$query" \\
        --data-urlencode "start=$start" \\
        --data-urlencode "end=${now_epoch}000000000" \\
        --data-urlencode "limit=1000" | jq -r '.data.result[0].values[][] | .[1]' 2>/dev/null || true
}

record_error() {
    local error_message="$1"
    local pattern_hash
    pattern_hash=$(printf '%s' "$error_message" | md5sum | awk '{print $1}')
    
    "$SQLITE3" "$TRIAGE_DB" << SQLITE_EOF
INSERT OR IGNORE INTO error_patterns (pattern_hash, error_message) VALUES ('$pattern_hash', '$error_message');
UPDATE error_patterns SET occurrence_count = occurrence_count + 1, last_seen = CURRENT_TIMESTAMP WHERE pattern_hash = '$pattern_hash';
INSERT INTO error_occurrences (pattern_id) SELECT id FROM error_patterns WHERE pattern_hash = '$pattern_hash';
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
        occurrence_count=$("$SQLITE3" "$TRIAGE_DB" "SELECT occurrence_count FROM error_patterns WHERE pattern_hash = '$pattern_hash';" 2>/dev/null || echo 0)
        
        if [[ $occurrence_count -ge $ERROR_TRIAGE_THRESHOLD ]]; then
            log_warn "Threshold reached for new error pattern ($occurrence_count occurrences). Creating GitHub issue..."
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
'''

with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as tmp:
    tmp.write(clean_script)
    tmp_path = tmp.name

try:
    # Copy file to remote host
    result = subprocess.run(['scp', tmp_path, 'akushnir@192.168.168.31:/tmp/error_triage_engine_fixed.sh'], 
                          capture_output=True, text=True, timeout=10)
    
    if result.returncode == 0:
        # Move it to the correct location
        result2 = subprocess.run(['ssh', 'akushnir@192.168.168.31', 
                               'mv /tmp/error_triage_engine_fixed.sh /home/akushnir/code-server-enterprise/scripts/error-triage-engine.sh && chmod +x /home/akushnir/code-server-enterprise/scripts/error-triage-engine.sh && echo "Script deployed"'],
                              capture_output=True, text=True, timeout=10)
        if result2.returncode == 0:
            print("SUCCESS: Script successfully updated and deployed")
            print(result2.stdout)
        else:
            print(f"Move failed: {result2.stderr}")
    else:
        print(f"SCP failed: {result.stderr}")
finally:
    os.unlink(tmp_path)
