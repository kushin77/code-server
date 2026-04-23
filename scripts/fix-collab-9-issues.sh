#!/usr/bin/env bash
# @file        scripts/fix-collab-9-issues.sh
# @module      issues/collaboration
# @description Recreate the 10 failed Collab-9 integration issues with integrations label
#

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Initialize
init_repo

# Recreate the 10 failed Collab-9 issues
log_info "Recreating 10 failed Collab-9 integration issues..."

# Issue definitions (from the failed log)
declare -a COLLAB_9_ISSUES=(
    "EPIC [Collab-9]: GitHub Issues <-> IDE bidirectional task sync"
    "[Collab-9.1]: Linear/Jira ticket linking with auto-context from workspace"
    "[Collab-9.2]: Slack slash command to launch shared IDE sessions"
    "[Collab-9.3]: CI/CD status sidebar with live pipeline visualization"
    "[Collab-9.4]: Figma design embed - view and comment on designs in IDE"
    "[Collab-9.5]: Sentry error integration - click error traces in IDE"
    "[Collab-9.6]: Feature flag management panel (LaunchDarkly integration)"
    "[Collab-9.7]: PagerDuty incident integration - alert firefighter IDE"
    "[Collab-9.8]: Documentation-as-code - edit and preview docs in IDE"
    "[Collab-9.9]: OpenTelemetry APM integration - click traces to code"
)

# Create each issue with integrations label
declare success_count=0
declare fail_count=0

for title in "${COLLAB_9_ISSUES[@]}"; do
    log_info "Creating: $title"
    
    if source "$SCRIPT_DIR/_common/issue-create-unified.sh" && \
       copilot_create_issue \
         --title "$title" \
         --priority P2 \
         --type integrations \
         --repo kushin77/code-server \
         --force-create > /dev/null 2>&1; then
        log_info "✓ Created: $title"
        ((success_count++))
    else
        log_warn "✗ Failed: $title"
        ((fail_count++))
    fi
done

log_info "================================================"
log_info "Results: $success_count created, $fail_count failed"
log_info "================================================"

if [[ $fail_count -gt 0 ]]; then
    log_fatal "Some issues failed to create. Review the log above."
else
    log_info "✓ All 10 Collab-9 integration issues created successfully!"
fi
