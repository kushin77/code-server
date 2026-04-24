#!/bin/bash
# Monitor Issue #983 completion and trigger Issue #984 execution
# This script polls for Issue #983 state change and signals readiness for #984

set -euo pipefail

REPO="kushin77/code-server"
ISSUE_983=983
ISSUE_984=984
CHECK_INTERVAL_SECONDS=30
MAX_CHECKS=1440  # 12 hours of monitoring

echo "🔍 Starting Issue #983 completion monitor..."
echo "📊 Check interval: $CHECK_INTERVAL_SECONDS seconds"
echo "⏱️  Max monitoring duration: $(( MAX_CHECKS * CHECK_INTERVAL_SECONDS / 3600 )) hours"
echo "🎯 Target: When #983 closes, execute #984 using ISSUE-984-QUICK-EXECUTION.md"
echo ""

check_count=0

while [ $check_count -lt $MAX_CHECKS ]; do
  check_count=$((check_count + 1))
  
  # Get Issue #983 state
  state=$(gh issue view $ISSUE_983 --repo $REPO --json state --jq '.state' 2>/dev/null || echo "OPEN")
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  echo "[$check_count/$MAX_CHECKS] [$timestamp] Issue #983 state: $state"
  
  if [ "$state" = "CLOSED" ]; then
    echo ""
    echo "✅ ==========================================================================="
    echo "✅ Issue #983 CLOSED! QA user creation complete"
    echo "✅ ==========================================================================="
    echo ""
    echo "🚀 NEXT STEPS:"
    echo "1. Obtain QA password from Issue #983 comments"
    echo "2. Execute: bash ISSUE-984-QUICK-EXECUTION.md"
    echo "3. Total time: ~40 minutes to complete #984 + E2E tests"
    echo ""
    echo "📋 Files ready:"
    echo "   - ISSUE-984-QUICK-EXECUTION.md"
    echo "   - ISSUE-984-PRODUCTION-READY-CHECKLIST.md"
    echo ""
    
    # Optional: Create notification issue
    gh issue comment $ISSUE_984 --repo $REPO \
      --body "🔔 Issue #983 COMPLETE - QA user created. Ready to execute #984 setup.

Issue #983 completion detected. Proceeding with OAuth whitelist configuration and GSM credential setup.

Timeline:
- [ ] Step 1: Extract QA password from #983
- [ ] Step 2: Execute ISSUE-984-QUICK-EXECUTION.md
- [ ] Step 3: Verify all 20 E2E tests pass
- [ ] Step 4: Comment with evidence
- [ ] Step 5: Close #984

Estimated completion: $(date -d '+40 minutes' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '40 minutes from now')" 2>/dev/null || true
    
    exit 0
  fi
  
  # Wait before next check
  sleep $CHECK_INTERVAL_SECONDS
done

echo ""
echo "⚠️  Monitoring timeout: No status change after $(( MAX_CHECKS * CHECK_INTERVAL_SECONDS / 3600 )) hours"
echo "Last status: $state"
echo ""
echo "Manual check:"
echo "  gh issue view 983 --repo kushin77/code-server"
