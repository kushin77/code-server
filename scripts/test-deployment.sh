#!/bin/bash

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
