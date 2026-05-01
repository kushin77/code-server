#!/bin/bash
###############################################################################
# @file        scripts/metrics/collect-project-metrics.sh
# @module      metrics/collect-project-metrics
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
#
# @file scripts/metrics/collect-project-metrics.sh
# @description Collect project metrics: velocity, cycle time, burndown, issue aging
# @governance GOV-002: IaC, immutable, audit-logged
# @author GitHub Copilot
# @created 2026-04-25
#
# Usage:
#   bash scripts/metrics/collect-project-metrics.sh [--period DAYS] [--output FORMAT]
#
# Metrics Collected:
#   - Velocity: Issues closed per week
#   - Cycle time: Time from open to closed
#   - Issue aging: How long issues remain open
#   - PR review time: Time from PR open to merge
#   - PR rejection rate: % of closed unmerged PRs
#

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

readonly SCRIPT_VERSION="1.0"
readonly PERIOD="${1:-30}"  # Default 30 days
readonly OUTPUT_FORMAT="${2:-json}"
readonly METRICS_DIR="artifacts/project-metrics"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG_FILE="${METRICS_DIR}/metrics-${TIMESTAMP}.log"

mkdir -p "$METRICS_DIR"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*" | tee -a "$LOG_FILE"
}

# Calculate metrics
calculate_metrics() {
    log_info "Collecting metrics for last $PERIOD days..."
    
    local start_date=$(date -d "$PERIOD days ago" -u +%Y-%m-%dT00:00:00Z)
    local end_date=$(date -u +%Y-%m-%dT23:59:59Z)
    
    # 1. Velocity: Issues closed in period
    log_info "Calculating velocity (issues closed)..."
    local closed_issues=$(gh issue list --repo kushin77/code-server \
        --state closed \
        --search "closed:>=$start_date" \
        --limit 10000 \
        --json number | jq 'length')
    
    # 2. Cycle time: Average time to close
    log_info "Calculating cycle time..."
    local cycle_times=$(gh issue list --repo kushin77/code-server \
        --state closed \
        --search "closed:>=$start_date" \
        --limit 10000 \
        --json createdAt,closedAt)
    
    local total_cycle_time=0
    local cycle_count=0
    
    echo "$cycle_times" | jq -r '.[] | "\(.createdAt) \(.closedAt)"' | while read created closed; do
        local created_epoch=$(date -d "$created" +%s)
        local closed_epoch=$(date -d "$closed" +%s)
        local diff=$((closed_epoch - created_epoch))
        total_cycle_time=$((total_cycle_time + diff))
        cycle_count+=1
    done
    
    local avg_cycle_time=0
    if [ "$cycle_count" -gt 0 ]; then
        avg_cycle_time=$((total_cycle_time / cycle_count))
        avg_cycle_time=$((avg_cycle_time / 86400))  # Convert to days
    fi
    
    # 3. Issue aging: Current open issues
    log_info "Calculating issue aging..."
    local open_issues=$(gh issue list --repo kushin77/code-server \
        --state open \
        --json number,createdAt | jq 'length')
    
    local oldest_issue=$(gh issue list --repo kushin77/code-server \
        --state open \
        --limit 1 \
        --json createdAt | jq -r '.[0].createdAt')
    
    local oldest_age=0
    if [ -n "$oldest_issue" ] && [ "$oldest_issue" != "null" ]; then
        local oldest_epoch=$(date -d "$oldest_issue" +%s)
        local now_epoch=$(date +%s)
        oldest_age=$(( (now_epoch - oldest_epoch) / 86400 ))
    fi
    
    # 4. PR metrics
    log_info "Calculating PR metrics..."
    local prs_merged=$(gh pr list --repo kushin77/code-server \
        --state merged \
        --search "merged:>=$start_date" \
        --limit 10000 \
        --json number | jq 'length')
    
    local prs_closed=$(gh pr list --repo kushin77/code-server \
        --state closed \
        --limit 10000 \
        --json number | jq 'length')
    
    # 5. Calculate PR review time
    log_info "Calculating PR review metrics..."
    local pr_data=$(gh pr list --repo kushin77/code-server \
        --state merged \
        --search "merged:>=$start_date" \
        --limit 1000 \
        --json createdAt,mergedAt)
    
    local total_review_time=0
    local review_count=0
    
    echo "$pr_data" | jq -r '.[] | "\(.createdAt) \(.mergedAt)"' | while read created merged; do
        local created_epoch=$(date -d "$created" +%s)
        local merged_epoch=$(date -d "$merged" +%s)
        local diff=$((merged_epoch - created_epoch))
        total_review_time=$((total_review_time + diff))
        review_count+=1
    done
    
    local avg_review_time=0
    if [ "$review_count" -gt 0 ]; then
        avg_review_time=$((total_review_time / review_count))
        avg_review_time=$((avg_review_time / 3600))  # Convert to hours
    fi
    
    # Output results
    local output_file="${METRICS_DIR}/metrics-${TIMESTAMP}.${OUTPUT_FORMAT}"
    
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        jq -n \
            --arg timestamp "$TIMESTAMP" \
            --arg period "$PERIOD" \
            --arg start "$start_date" \
            --arg end "$end_date" \
            --arg velocity "$closed_issues" \
            --arg cycle_time "$avg_cycle_time" \
            --arg open_issues "$open_issues" \
            --arg oldest_age "$oldest_age" \
            --arg prs_merged "$prs_merged" \
            --arg prs_closed "$prs_closed" \
            --arg review_time "$avg_review_time" \
            '{
                timestamp: $timestamp,
                period_days: ($period | tonumber),
                start_date: $start,
                end_date: $end,
                velocity: {
                    issues_closed: ($velocity | tonumber),
                    issues_per_day: (($velocity | tonumber) / ($period | tonumber))
                },
                cycle_time: {
                    average_days: ($cycle_time | tonumber),
                    metric: "Lower is better"
                },
                issue_aging: {
                    open_issues: ($open_issues | tonumber),
                    oldest_days_open: ($oldest_age | tonumber)
                },
                pr_metrics: {
                    merged: ($prs_merged | tonumber),
                    closed_unmerged: ($prs_closed | tonumber),
                    average_review_hours: ($review_time | tonumber)
                }
            }' > "$output_file"
    fi
    
    log_success "Metrics collected and saved to $output_file"
    cat "$output_file"
}

# Main
main() {
    log_info "=== Project Metrics Collection Started ==="
    log_info "Version: $SCRIPT_VERSION"
    log_info "Period: $PERIOD days"
    log_info "Output: $OUTPUT_FORMAT"
    
    calculate_metrics
    
    log_success "=== Project Metrics Collection Complete ==="
}

main "$@"
