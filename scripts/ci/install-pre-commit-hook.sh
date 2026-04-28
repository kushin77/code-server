#!/usr/bin/env bash
# @file scripts/ci/install-pre-commit-hook.sh
# @description Install SSOT enforcement as git pre-commit hook
# @usage: bash scripts/ci/install-pre-commit-hook.sh

set -euo pipefail

HOOK_SOURCE="scripts/ci/pre-commit-ssot-enforcement.sh"
HOOK_DEST=".git/hooks/pre-commit"

if [[ ! -f "$HOOK_SOURCE" ]]; then
  echo "❌ Error: $HOOK_SOURCE not found"
  exit 1
fi

# Create hooks directory if needed
mkdir -p "$(dirname "$HOOK_DEST")"

# Copy hook and make executable
cp "$HOOK_SOURCE" "$HOOK_DEST"
chmod +x "$HOOK_DEST"

echo "✅ Pre-commit hook installed:"
echo "   Location: $HOOK_DEST"
echo "   Source:   $HOOK_SOURCE"
echo ""
echo "The hook will run automatically on: git commit"
echo "To bypass (not recommended): git commit --no-verify"
