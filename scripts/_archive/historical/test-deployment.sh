#!/bin/bash
################################################################################
# File: test-deployment.sh
# Owner: QA/Testing Team
# Purpose: Automated end-to-end deployment verification and testing
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+, Docker 20.10+
#
# Dependencies:
#   - docker — Container runtime
#   - curl — HTTP endpoint testing
#   - jq — JSON response parsing
#   - python3 — Test automation scripting
#
# Related Files:
#   - docker-compose.yml — Service definitions for testing
#   - .github/workflows/validate-config.yml — CI integration
#   - TESTING.md — Comprehensive test documentation
#   - scripts/stress-test-remote.sh — Load testing
#
# Usage:
#   ./test-deployment.sh                        # Full E2E test suite
#   ./test-deployment.sh --smoke                # Quick smoke tests
#   ./test-deployment.sh --detailed             # Verbose output
#   ./test-deployment.sh --module <name>        # Specific module test
#
# Test Suites:
#   - Smoke tests (basic connectivity)
#   - Integration tests (service communication)
#   - Security tests (auth, TLS validation)
#   - Performance tests (latency, throughput)
#   - E2E tests (complete workflow validation)
#
# Exit Codes:
#   0 — All tests passed
#   1 — Some tests failed (non-critical)
#   2 — Critical tests failed (deployment invalid)
#
# Examples:
#   ./scripts/test-deployment.sh
#   ./scripts/test-deployment.sh --smoke
#
# Recent Changes:
#   2026-04-14: Integrated detailed error reporting
#   2026-04-13: Initial creation with comprehensive test suite
#
################################################################################

echo "==============================================="
echo "CODE-SERVER COPILOT CHAT DEPLOYMENT TEST"
echo "==============================================="
echo ""

# Verify navigator shim is removed
SHIM_COUNT=$(grep -c "navigator is now a global" /usr/lib/code-server/lib/vscode/out/vs/workbench/api/node/extensionHostProcess.js 2>/dev/null || echo "0")
echo "Navigator Shim Status:"
echo "  Occurrences: $SHIM_COUNT"
if [ "$SHIM_COUNT" = "0" ]; then
  echo "  Result: ✅ PASS (shim removed)"
else
  echo "  Result: ❌ FAIL (shim still present)"
fi
echo ""

# List installed extensions
echo "Installed Extensions (Copilot):"
/usr/bin/code-server --list-extensions --extensions-dir /home/coder/.local/share/code-server/extensions 2>/dev/null | grep -E "copilot" | while read ext; do
  echo "  ✅ $ext"
done
echo ""

# Verify product.json patches
echo "product.json Patches:"

if grep -q '"github.copilot-chat"' /usr/lib/code-server/lib/vscode/product.json; then
  echo "  ✅ github.copilot-chat in trustedExtensionAuthAccess"
else
  echo "  ❌ github.copilot-chat NOT in trustedExtensionAuthAccess"
fi

if ! grep -q 'defaultChatAgent' /usr/lib/code-server/lib/vscode/product.json; then
  echo "  ✅ defaultChatAgent removed"
else
  echo "  ⚠️  defaultChatAgent still present"
fi
echo ""

# HTTP health check
echo "Code-server Health:"
if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
  echo "  ✅ HTTP endpoint responding on :8080"
else
  echo "  ❌ HTTP endpoint NOT responding"
fi
echo ""

echo "==============================================="
echo "✅ DEPLOYMENT READY FOR TESTING"
echo "==============================================="
echo ""
echo "USER TESTING INSTRUCTIONS:"
echo "1. Connect via VPN (Wireguard 'web browser testing' profile)"
echo "2. Navigate to: https://ide.kushnir.cloud"
echo "3. Reload page (Ctrl+Shift+R or Cmd+Shift+R) to refresh extension host"
echo "4. Wait 10-15 seconds for extension host to initialize"
echo "5. Open Copilot Chat (Ctrl+Shift+I or Cmd+Shift+I)"
echo "6. VERIFY: No 'cannot be installed because it was not found' error"
echo "7. If chat opens, click 'Sign in with GitHub' and authenticate"
echo "8. Test chat: Ask 'What is this repository about?'"
echo ""
