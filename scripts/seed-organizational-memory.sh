#!/bin/bash
###############################################################################
# @file        scripts/seed-organizational-memory.sh
# @module      seed-organizational-memory
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/seed-organizational-memory.sh
# @description Historical seeding of organizational memory (incidents, runbooks, PRs, sessions)
# @governance GOV-002

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
MEMORY_ENGINE_URL="${MEMORY_ENGINE_URL:-http://localhost:8001}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BATCH_SIZE="${BATCH_SIZE:-5}"

# Logging
log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"; }
log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"; }
log_error() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*"; }
log_warn() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"; }

# ============================================================================
# Helper Functions
# ============================================================================

seed_issues() {
    local collection=$1
    local label=$2
    local limit=${3:-50}
    
    log_info "Seeding issues from collection '$collection' with label '$label'"
    
    if [ -z "$GITHUB_TOKEN" ]; then
        log_warn "GITHUB_TOKEN not set, skipping GitHub issues seeding"
        return 0
    fi
    
    # Fetch issues from GitHub API
    local query="repo:kushin77/code-server label:$label is:closed"
    local page=1
    local count=0
    
    while [ $count -lt $limit ]; do
        local response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/search/issues?q=$query&per_page=30&page=$page&sort=updated&order=desc")
        
        local issue_count=$(echo "$response" | jq '.items | length')
        
        if [ "$issue_count" -eq 0 ]; then
            break
        fi
        
        # Ingest each issue without losing the count in a subshell
        while read -r issue; do
            local issue_num=$(echo "$issue" | jq -r '.number')
            local title=$(echo "$issue" | jq -r '.title' | sed 's/"/\\"/g')
            local body=$(echo "$issue" | jq -r '.body // ""' | head -c 2000 | sed 's/"/\\"/g')
            local url=$(echo "$issue" | jq -r '.html_url')
            
            local doc_json=$(cat <<EOF
{
  "title": "$title",
  "content": "$body",
  "collection": "$collection",
  "source_url": "$url",
  "tags": ["github", "$label", "issue-$issue_num"],
  "confidence_score": 0.9
}
EOF
            )
            
            # Ingest document
            local result=$(curl -s -X POST "$MEMORY_ENGINE_URL/ingest" \
                -H "Content-Type: application/json" \
                -d "$doc_json")
            
            if echo "$result" | jq -e '.success' > /dev/null 2>&1; then
                log_success "Ingested issue #$issue_num: $title"
            else
                log_warn "Failed to ingest issue #$issue_num"
            fi
            
            count=$((count + 1))
        done < <(echo "$response" | jq -c '.items[]')
        
        page=$((page + 1))
    done
    
    log_success "Seeded $count issues into '$collection'"
}


seed_runbooks() {
    local runbook_dir="${PROJECT_ROOT}/docs/runbooks"
    
    if [ ! -d "$runbook_dir" ]; then
        log_warn "Runbooks directory not found: $runbook_dir"
        return 0
    fi
    
    log_info "Seeding runbooks from $runbook_dir"
    
    local count=0
    for runbook_file in "$runbook_dir"/*.md; do
        if [ ! -f "$runbook_file" ]; then
            continue
        fi
        
        local filename=$(basename "$runbook_file")
        local title="${filename%.md}"
        local content=$(cat "$runbook_file" | head -c 8000 | sed 's/"/\\"/g')
        
        local doc_json=$(cat <<EOF
{
  "title": "$title",
  "content": "$content",
  "collection": "runbooks",
  "tags": ["runbook", "documentation"],
  "confidence_score": 0.95
}
EOF
        )
        
        local result=$(curl -s -X POST "$MEMORY_ENGINE_URL/ingest" \
            -H "Content-Type: application/json" \
            -d "$doc_json")
        
        if echo "$result" | jq -e '.success' > /dev/null 2>&1; then
            log_success "Ingested runbook: $title"
        else
            log_warn "Failed to ingest runbook: $title"
        fi
        
        count=$((count + 1))
    done
    
    log_success "Seeded $count runbooks"
}


seed_session_reports() {
    local artifacts_dir="${PROJECT_ROOT}/artifacts"
    
    if [ ! -d "$artifacts_dir" ]; then
        log_warn "Artifacts directory not found: $artifacts_dir"
        return 0
    fi
    
    log_info "Seeding session completion reports from $artifacts_dir"
    
    local count=0
    for report_file in "$artifacts_dir"/APRIL-*-SESSION*.md; do
        if [ ! -f "$report_file" ]; then
            continue
        fi
        
        local filename=$(basename "$report_file")
        local session_date=$(echo "$filename" | grep -oE '[0-9]{2}-[0-9]{4}' | head -1)
        local content=$(cat "$report_file" | head -c 8000 | sed 's/"/\\"/g')
        
        local doc_json=$(cat <<EOF
{
  "title": "Session Report: $session_date",
  "content": "$content",
  "collection": "retrospectives",
  "tags": ["session", "completion", "$session_date"],
  "confidence_score": 0.90
}
EOF
        )
        
        local result=$(curl -s -X POST "$MEMORY_ENGINE_URL/ingest" \
            -H "Content-Type: application/json" \
            -d "$doc_json")
        
        if echo "$result" | jq -e '.success' > /dev/null 2>&1; then
            log_success "Ingested session report: $filename"
        else
            log_warn "Failed to ingest session report: $filename"
        fi
        
        count=$((count + 1))
    done
    
    log_success "Seeded $count session reports"
}


check_memory_engine() {
    log_info "Checking Memory Engine health at $MEMORY_ENGINE_URL"
    
    local response=$(curl -s "$MEMORY_ENGINE_URL/health")
    
    if echo "$response" | jq -e '.status' > /dev/null 2>&1; then
        local status=$(echo "$response" | jq -r '.status')
        log_success "Memory Engine is $status"
        return 0
    else
        log_error "Memory Engine is not responding"
        return 1
    fi
}


show_stats() {
    log_info "Fetching memory statistics"
    
    local stats=$(curl -s "$MEMORY_ENGINE_URL/stats")
    
    if echo "$stats" | jq -e '.collections' > /dev/null 2>&1; then
        echo "$stats" | jq '.collections'
        log_success "Memory engine stats retrieved"
    else
        log_warn "Could not retrieve memory stats"
    fi
}


# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "Starting organizational memory seeding"
    log_info "Memory Engine URL: $MEMORY_ENGINE_URL"
    
    # Check health
    if ! check_memory_engine; then
        log_error "Memory Engine is not healthy. Exiting."
        exit 1
    fi
    
    # Seed incidents
    seed_issues "incidents" "P0" 20
    seed_issues "incidents" "incident" 30
    
    # Seed runbooks
    seed_runbooks
    
    # Seed session reports
    seed_session_reports
    
    # Show final stats
    show_stats
    
    log_success "Organizational memory seeding complete"
}

main "$@"
