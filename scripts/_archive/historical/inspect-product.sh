#!/bin/bash
PROD="/usr/lib/code-server/lib/vscode/product.json"
echo "=== KEY FIELDS ==="
grep -i "defaultChatAgent\|extensionsGallery\|serviceUrl\|itemUrl\|marketplace\|chatAgent\|copilot" "$PROD" | head -40
echo ""
echo "=== trustedExtensionAuthAccess ==="
grep -A3 "trustedExtensionAuthAccess" "$PROD"
echo ""
echo "=== builtInExtensions first 10 ==="
grep "extensionId" "$PROD" | head -10
echo ""
echo "=== SERVICE_URL env ==="
echo "SERVICE_URL=$SERVICE_URL"
echo "ITEM_URL=$ITEM_URL"
echo ""
echo "=== Extensions installed ==="
/usr/bin/code-server --list-extensions --extensions-dir /home/coder/.local/share/code-server/extensions 2>/dev/null
echo ""
echo "=== VSIX files ==="
ls -la /opt/vsix/
echo ""
echo "=== github-authentication extension ==="
ls -la /usr/lib/code-server/lib/vscode/extensions/github-authentication/dist/browser/ 2>/dev/null || echo "NOT FOUND"
echo ""
echo "=== code-server version ==="
/usr/bin/code-server --version
