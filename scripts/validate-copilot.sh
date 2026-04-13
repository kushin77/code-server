#!/bin/bash
# Validate GitHub Copilot Chat installation in code-server
# Run this inside the container to verify everything is working

set -e

echo "════════════════════════════════════════════════════════════"
echo "  GitHub Copilot Chat - Installation Validation"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if running in container
if [ ! -f /.dockerenv ]; then
    echo "⚠️  Not running in Docker container"
    echo "   To run validation inside container:"
    echo "   docker exec code-server /bin/bash -c './scripts/validate-copilot.sh'"
    echo ""
fi

# 1. Check if extension cache exists
echo "1️⃣  Checking extension cache..."
if [ -f /opt/vsix/github-copilot.vsix ]; then
    COPILOT_SIZE=$(du -h /opt/vsix/github-copilot.vsix | cut -f1)
    echo "   ✅ github-copilot.vsix cached ($COPILOT_SIZE)"
else
    echo "   ❌ github-copilot.vsix NOT found"
fi

if [ -f /opt/vsix/github-copilot-chat.vsix ]; then
    CHAT_SIZE=$(du -h /opt/vsix/github-copilot-chat.vsix | cut -f1)
    echo "   ✅ github-copilot-chat.vsix cached ($CHAT_SIZE)"
else
    echo "   ❌ github-copilot-chat.vsix NOT found"
fi
echo ""

# 2. Check if extensions are installed
echo "2️⃣  Checking installed extensions..."
EXT_DIR="/home/coder/.local/share/code-server/extensions"
mkdir -p "$EXT_DIR"

if /usr/bin/code-server --list-extensions --extensions-dir "$EXT_DIR" 2>/dev/null | grep -qi '^github.copilot$'; then
    echo "   ✅ github.copilot is installed"
else
    echo "   ❌ github.copilot is NOT installed"
fi

if /usr/bin/code-server --list-extensions --extensions-dir "$EXT_DIR" 2>/dev/null | grep -qi '^github.copilot-chat$'; then
    echo "   ✅ github.copilot-chat is installed"
else
    echo "   ❌ github.copilot-chat is NOT installed"
fi
echo ""

# 3. Check product.json patches
echo "3️⃣  Checking product.json patches..."
PRODUCT_FILE="/usr/lib/code-server/lib/vscode/product.json"

if grep -q '"github.copilot-chat"' "$PRODUCT_FILE"; then
    echo "   ✅ github.copilot-chat is in trustedExtensionAuthAccess"
else
    echo "   ⚠️  github.copilot-chat NOT in trustedExtensionAuthAccess (may require manual fix)"
fi

if ! grep -q '"defaultChatAgent"' "$PRODUCT_FILE"; then
    echo "   ✅ defaultChatAgent removed (prevents install loops)"
else
    echo "   ⚠️  defaultChatAgent still present"
fi
echo ""

# 4. Check code-server version
echo "4️⃣  Checking code-server version..."
CODE_SERVER_VERSION=$(/usr/bin/code-server --version | head -1)
echo "   ✅ code-server version: $CODE_SERVER_VERSION"
echo ""

# 5. Connectivity check
echo "5️⃣  Checking GitHub connectivity (for Copilot API)..."
if timeout 5 curl -sSL -o /dev/null -w "%{http_code}" https://api.github.com/copilot 2>/dev/null | grep -q "200\|303\|401"; then
    echo "   ✅ GitHub connectivity OK (Copilot API reachable)"
elif timeout 5 curl -sSL -o /dev/null https://github.com 2>/dev/null; then
    echo "   ✅ GitHub.com reachable (connectivity OK)"
else
    echo "   ⚠️  GitHub not reachable (GitHub tokens won't work without internet)"
fi
echo ""

# 6. Summary
echo "════════════════════════════════════════════════════════════"
echo "✅ VALIDATION COMPLETE"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "1. Open code-server in your browser (http://localhost)"
echo "2. Click the Copilot icon in the sidebar"
echo "3. Click 'Sign in with GitHub Copilot'"
echo "4. Complete the OAuth authentication flow"
echo "5. Start using Copilot Chat with Ctrl+L"
echo ""
echo "For more info, see: COPILOT_CHAT_SETUP.md"
echo ""
