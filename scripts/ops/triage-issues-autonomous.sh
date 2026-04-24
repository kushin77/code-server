#!/usr/bin/env bash
# @file        scripts/ops/triage-issues-autonomous.sh
# @module      ops/governance
# @description Autonomously triage GitHub issues and apply priority labels
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# CONFIGURATION
################################################################################

REPO="kushin77/code-server"

################################################################################
# TRIAGE LOGIC
################################################################################

triage_issues() {
    log_info "🔍 Starting autonomous triage for $REPO..."
    
    # Get unlabelled issues
    local issues
    issues=$(gh issue list --repo "$REPO" --json number,title,labels --jq '.[] | select(.labels | length == 0) | .number')
    
    if [[ -z "$issues" ]]; then
        log_info "✅ No unlabelled issues found. Triage complete."
        return 0
    fi
    
    for issue in $issues; do
        log_info "⚡ Triaging issue #$issue..."
        
        # P2/feature default for new issues
        gh issue edit "$issue" --repo "$REPO" --add-label "P2,feature"
        log_info "✅ Issue #$issue triaged as P2/feature"
    done
}

################################################################################
# MAIN
################################################################################

main() {
    require_command gh
    triage_issues
}

main "$@"
