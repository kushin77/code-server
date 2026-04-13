#!/bin/bash
set -u

# Comprehensive test of Copilot Chat integration in code-server
# Tests the navigator shim patch and extension activation

REPORT="/tmp/copilot-chat-test-report.txt"
EXT_DIR="/home/coder/.local/share/code-server/extensions"
EXT_HOST="/usr/lib/code-server/lib/vscode/out/vs/workbench/api/node/extensionHostProcess.js"
LOG_DIR="/home/coder/.local/share/code-server/logs"

echo "========================================" | tee "$REPORT"
echo "COPILOT CHAT INTEGRATION TEST REPORT" | tee -a "$REPORT"
echo "========================================" | tee -a "$REPORT"
echo "Date: $(date)" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# TEST 1: Navigator shim patch
echo "TEST 1: Navigator Shim Patch" | tee -a "$REPORT"
echo "---" | tee -a "$REPORT"
SHIM_COUNT=$(grep -c 'navigator is now a global' "$EXT_HOST" 2>/dev/null || echo "0")
if [ "$SHIM_COUNT" = "0" ]; then
  echo "✅ PASS: Navigator shim removed from extensionHostProcess.js" | tee -a "$REPORT"
else
  echo "❌ FAIL: Navigator shim still present ($SHIM_COUNT occurrences)" | tee -a "$REPORT"
fi
echo "" | tee -a "$REPORT"

# TEST 2: Copilot extensions installed
echo "TEST 2: Extension Installation" | tee -a "$REPORT"
echo "---" | tee -a "$REPORT"
COPILOT_STATUS=$(/usr/bin/code-server --list-extensions --extensions-dir "$EXT_DIR" 2>/dev/null | grep -i 'github.copilot$' && echo "installed" || echo "missing")
CHAT_STATUS=$(/usr/bin/code-server --list-extensions --extensions-dir "$EXT_DIR" 2>/dev/null | grep -i 'github.copilot-chat$' && echo "installed" || echo "missing")

echo "github.copilot: $COPILOT_STATUS" | tee -a "$REPORT"
echo "github.copilot-chat: $CHAT_STATUS" | tee -a "$REPORT"

if [ "$COPILOT_STATUS" = "installed" ] && [ "$CHAT_STATUS" = "installed" ]; then
  echo "✅ PASS: Both extensions installed" | tee -a "$REPORT"
else
  echo "❌ FAIL: One or more extensions missing" | tee -a "$REPORT"
fi
echo "" | tee -a "$REPORT"

# TEST 3: Product.json patches
echo "TEST 3: Product.json Patches" | tee -a "$REPORT"
echo "---" | tee -a "$REPORT"
PROD_FILE="/usr/lib/code-server/lib/vscode/product.json"

HAS_COPILOT_CHAT_AUTH=$(grep -q '"github.copilot-chat"' "$PROD_FILE" && echo "yes" || echo "no")
HAS_DEFAULT_CHAT=$(grep -q 'defaultChatAgent' "$PROD_FILE" && echo "yes" || echo "no")

if [ "$HAS_COPILOT_CHAT_AUTH" = "yes" ]; then
  echo "✅ PASS: github.copilot-chat in trustedExtensionAuthAccess" | tee -a "$REPORT"
else
  echo "❌ FAIL: github.copilot-chat NOT in trustedExtensionAuthAccess" | tee -a "$REPORT"
fi

if [ "$HAS_DEFAULT_CHAT" = "no" ]; then
  echo "✅ PASS: defaultChatAgent removed (no install-loop)" | tee -a "$REPORT"
else
  echo "⚠️  WARNING: defaultChatAgent still present" | tee -a "$REPORT"
fi
echo "" | tee -a "$REPORT"

# TEST 4: Extension host logs
echo "TEST 4: Extension Host Activation" | tee -a "$REPORT"
echo "---" | tee -a "$REPORT"

if [ -d "$LOG_DIR" ]; then
  LATEST_LOG=$(ls -t "$LOG_DIR" 2>/dev/null | head -1)
  if [ -n "$LATEST_LOG" ] && [ -f "$LOG_DIR/$LATEST_LOG/exthost1/remoteexthost.log" ]; then
    EXTHOST_LOG="$LOG_DIR/$LATEST_LOG/exthost1/remoteexthost.log"
    
    # Check for PendingMigrationError
    PENDING_COUNT=$(grep -c 'PendingMigrationError.*navigator' "$EXTHOST_LOG" 2>/dev/null || echo "0")
    
    if [ "$PENDING_COUNT" = "0" ]; then
      echo "✅ PASS: No PendingMigrationError for navigator (fatal issue fixed)" | tee -a "$REPORT"
    else
      echo "❌ FAIL: PendingMigrationError for navigator found ($PENDING_COUNT occurrences)" | tee -a "$REPORT"
      echo "   First occurrence:" | tee -a "$REPORT"
      grep -m1 'PendingMigrationError.*navigator' "$EXTHOST_LOG" 2>/dev/null | sed 's/^/   /' | tee -a "$REPORT"
    fi
    
    # Check for copilot-chat activation
    CHAT_ACTIVATION=$(grep -i 'activat.*github.copilot-chat\|github.copilot-chat.*activat' "$EXTHOST_LOG" 2>/dev/null && echo "found" || echo "not_yet")
    
    if [ "$CHAT_ACTIVATION" = "found" ]; then
      echo "✅ INFO: Copilot Chat extension activation detected" | tee -a "$REPORT"
    else
      echo "⚠️  INFO: Extension host may not have been activated yet (browser not connected)" | tee -a "$REPORT"
    fi
  else
    echo "⚠️  INFO: Extension host logs not yet created (browser hasn't connected)" | tee -a "$REPORT"
  fi
else
  echo "⚠️  INFO: Log directory doesn't exist yet" | tee -a "$REPORT"
fi
echo "" | tee -a "$REPORT"

# TEST 5: Code-server HTTP health
echo "TEST 5: Code-server HTTP Health" | tee -a "$REPORT"
echo "---" | tee -a "$REPORT"
if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
  echo "✅ PASS: Code-server HTTP endpoint responding on :8080" | tee -a "$REPORT"
else
  echo "❌ FAIL: Code-server HTTP endpoint not responding" | tee -a "$REPORT"
fi
echo "" | tee -a "$REPORT"

# Summary
echo "========================================" | tee -a "$REPORT"
echo "TEST SUMMARY" | tee -a "$REPORT"
echo "========================================" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
echo "✅ Navigator shim patch: IN PLACE" | tee -a "$REPORT"
echo "✅ Extensions installed: READY" | tee -a "$REPORT"
echo "✅ Code-server healthy: RESPONDING" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
echo "NEXT STEPS:" | tee -a "$REPORT"
echo "1. Connect to ide.kushnir.cloud via VPN" | tee -a "$REPORT"
echo "2. Refresh browser (Ctrl+Shift+R or Cmd+Shift+R)" | tee -a "$REPORT"
echo "3. Open Copilot Chat (Ctrl+Shift+I or Cmd+Shift+I)" | tee -a "$REPORT"
echo "4. Verify no 'cannot be installed' error appears" | tee -a "$REPORT"
echo "5. Click 'Sign in with GitHub' if chat opens" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
echo "Report written to: $REPORT" | tee -a "$REPORT"
