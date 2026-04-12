#!/usr/bin/env bash
# fix-product-json.sh
# Removes defaultChatAgent from code-server's product.json
# This prevents the "Finish Setup" button and Copilot Chat auto-install error.
# Run once after installing or upgrading code-server.

set -euo pipefail

PRODUCT_JSON="$HOME/code-server/lib/vscode/product.json"

if [ ! -f "$PRODUCT_JSON" ]; then
  echo "ERROR: product.json not found at $PRODUCT_JSON"
  exit 1
fi

if python3 -c "import json; d=json.load(open('$PRODUCT_JSON')); exit(0 if 'defaultChatAgent' in d else 1)" 2>/dev/null; then
  cp "$PRODUCT_JSON" "$PRODUCT_JSON.bak"
  python3 -c "
import json
path = '$PRODUCT_JSON'
with open(path) as f:
    data = json.load(f)
data.pop('defaultChatAgent', None)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
print('✓ Removed defaultChatAgent from product.json')
print('✓ Backup saved to product.json.bak')
"
else
  echo "✓ defaultChatAgent already removed — nothing to do"
fi
