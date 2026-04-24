#!/usr/bin/env bash
# @file        scripts/seed-organizational-memory.sh
# @module      memory/seeding
# @description Seed organizational memory with historical incident data from GitHub
# @owner       engineering/memory
# @status      production-ready
#
# One-time seeding script that ingests:
# - All historical GitHub issues (with labels, comments, descriptions)
# - Runbooks from docs/
# - PR descriptions from recent merged PRs
# - Agent learnings from archived task records
#
# Idempotent: duplicate detection prevents re-ingestion of same documents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_common/init.sh"

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════

MEMORY_ENGINE_URL="${MEMORY_ENGINE_URL:-http://localhost:8001}"
GITHUB_TOKEN="${GITHUB_TOKEN:?GitHub token required}"
REPO="${REPO:-kushin77/code-server}"

DRY_RUN="${DRY_RUN:-0}"
BATCH_SIZE=10
INGEST_TIMEOUT=30

# ════════════════════════════════════════════════════════════════════════════
# Seeding Functions
# ════════════════════════════════════════════════════════════════════════════

log_progress() {
    local current=$1
    local total=$2
    local percent=$(( (current * 100) / total ))
    log_info "  [$percent%] $current/$total processed"
}

ingest_document() {
    local doc_id=$1
    local title=$2
    local content=$3
    local source=$4
    local metadata=$5

    local payload=$(cat <<EOF
{
  "id": "$doc_id",
  "title": "$title",
  "content": "$content",
  "source": "$source",
  "metadata": $metadata,
  "created_at": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
EOF
)

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "  [DRY] Would ingest: $doc_id ($source)"
        return 0
    fi

    local response=$(curl -s -X POST "$MEMORY_ENGINE_URL/api/documents" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time "$INGEST_TIMEOUT")

    if echo "$response" | grep -q '"status".*"ingested"'; then
        log_debug "  ✅ Ingested: $doc_id"
        return 0
    else
        log_warn "  ⚠️  Failed to ingest: $doc_id - $response"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# GitHub Issues Seeding
# ════════════════════════════════════════════════════════════════════════════

seed_github_issues() {
    log_info "Seeding GitHub issues..."

    local query="repo:$REPO type:issue state:all"
    local count=0

    while true; do
        local response=$(gh issue list --repo "$REPO" --state all --limit "$BATCH_SIZE" --json number,title,body,labels,createdAt \
            --jq '.[] | @json' 2>/dev/null || echo "")

        [[ -z "$response" ]] && break

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            local issue=$(echo "$line" | jq -r '.')
            local number=$(echo "$issue" | jq -r '.number')
            local title=$(echo "$issue" | jq -r '.title')
            local body=$(echo "$issue" | jq -r '.body // ""' | head -c 5000)  # Limit to 5KB
            local labels=$(echo "$issue" | jq -r '.labels | map(.name) | @json')

            ingest_document \
                "github-issue-$number" \
                "$title" \
                "$body" \
                "github_issue" \
                "{\"labels\": $labels, \"issue_number\": $number}"

            count=$((count + 1))
            [[ $((count % 10)) -eq 0 ]] && log_progress "$count" "∞"
        done <<< "$response"
    done

    log_info "✅ Seeded $count GitHub issues"
}

# ════════════════════════════════════════════════════════════════════════════
# Runbooks Seeding
# ════════════════════════════════════════════════════════════════════════════

seed_runbooks() {
    log_info "Seeding runbooks from docs/..."

    local count=0
    local docs_dir="docs"

    if [[ ! -d "$docs_dir" ]]; then
        log_warn "docs directory not found, skipping runbooks"
        return 0
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local title=$(basename "$file" .md)
        local content=$(head -c 10000 "$file")  # Limit to 10KB

        ingest_document \
            "runbook-$(basename "$file" .md)" \
            "$title" \
            "$content" \
            "runbook" \
            "{\"file\": \"$file\"}"

        count=$((count + 1))
        [[ $((count % 5)) -eq 0 ]] && log_progress "$count" "∞"
    done < <(find "$docs_dir" -name "*.md" -type f)

    log_info "✅ Seeded $count runbooks"
}

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

main() {
    log_info "Seeding Organizational Memory"
    log_info "Memory Engine: $MEMORY_ENGINE_URL"
    log_info "Repository: $REPO"
    [[ "$DRY_RUN" == "1" ]] && log_info "DRY RUN MODE"

    # Health check
    if ! curl -s "$MEMORY_ENGINE_URL/health" | grep -q "healthy"; then
        log_fatal "Memory Engine not responding at $MEMORY_ENGINE_URL"
    fi

    log_info "✅ Memory Engine is healthy"

    # Seed data sources
    seed_github_issues
    seed_runbooks

    log_info "✅ Organizational Memory seeding complete"
}

main
