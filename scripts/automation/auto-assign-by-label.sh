#!/bin/bash
###############################################################################
# @file        scripts/automation/auto-assign-by-label.sh
# @module      automation/auto-assign-by-label
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"
###############################################################################
#
# @file scripts/automation/auto-assign-by-label.sh
# @description Auto-assign issues based on labels
# @governance GOV-002: Idempotent, deterministic, audit-logged
# @author GitHub Copilot
# @created 2026-04-25
#
# Usage:
#   bash scripts/automation/auto-assign-by-label.sh <issue-number> [--dry-run]
#
# Label-to-Owner Mapping:
#   team:backend     -> akushnir
#   team:frontend    -> akushnir
#   team:infrastructure -> akushnir
#   team:security    -> akushnir
#   team:devops      -> akushnir
#

set -euo pipefail

readonly SCRIPT_VERSION="1.0"
readonly ISSUE_NUMBER="${1:-}"
readonly DRY_RUN="${2:-false}"
readonly LOG_DIR="artifacts/automation-logs"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG_FILE="${LOG_DIR}/auto-assign-${TIMESTAMP}.log"

# Label-to-assignee mapping
declare -A LABEL_ASSIGNMENTS=(
    ["team:backend"]="akushnir"
    ["team:frontend"]="akushnir"
    ["team:infrastructure"]="akushnir"
    ["team:security"]="akushnir"
    ["team:devops"]="akushnir"
    ["priority:p0"]="akushnir"
    ["priority:p1"]="akushnir"
)

mkdir -p "$LOG_DIR"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*" | tee -a "$LOG_FILE"
}

if [ -z "$ISSUE_NUMBER" ]; then
    log_error "Usage: $0 <issue-number> [--dry-run]"
    exit 1
fi

log_info "Auto-assigning issue #$ISSUE_NUMBER based on labels..."

# Fetch issue details
issue_data=$(gh issue view "$ISSUE_NUMBER" --repo kushin77/code-server \
    --json labels,assignees,state)

issue_state=$(echo "$issue_data" | jq -r '.state')
current_assignees=$(echo "$issue_data" | jq -r '.assignees[].login' | tr '\n' ' ')

if [ "$issue_state" == "CLOSED" ]; then
    log_error "Issue #$ISSUE_NUMBER is already closed"
    exit 1
fi

# Extract labels
labels=$(echo "$issue_data" | jq -r '.labels[].name')

log_info "Issue #$ISSUE_NUMBER labels: $labels"
log_info "Current assignees: $current_assignees"

# Find matching assignments
declare -a assignees_to_add

while IFS= read -r label; do
    if [ -n "$label" ] && [ -v LABEL_ASSIGNMENTS["$label"] ]; then
        assignees_to_add+=("${LABEL_ASSIGNMENTS[$label]}")
        log_info "Label '$label' maps to: ${LABEL_ASSIGNMENTS[$label]}"
    fi
done <<< "$labels"

# Remove duplicates
assignees_to_add=($(printf '%s\n' "${assignees_to_add[@]}" | sort -u))

if [ ${#assignees_to_add[@]} -eq 0 ]; then
    log_error "No matching assignments found for issue #$ISSUE_NUMBER"
    exit 1
fi

log_success "Found ${#assignees_to_add[@]} assignee(s): ${assignees_to_add[*]}"

# Assign issue
for assignee in "${assignees_to_add[@]}"; do
    if echo "$current_assignees" | grep -q "$assignee"; then
        log_info "Assignee $assignee already assigned to issue #$ISSUE_NUMBER"
        continue
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would assign issue #$ISSUE_NUMBER to $assignee"
    else
        log_info "Assigning issue #$ISSUE_NUMBER to $assignee..."
        
        gh issue edit "$ISSUE_NUMBER" \
            --repo kushin77/code-server \
            --add-assignee "$assignee" \
            2>/dev/null || log_error "Failed to assign issue #$ISSUE_NUMBER to $assignee"
    fi
done

log_success "Auto-assignment complete"
