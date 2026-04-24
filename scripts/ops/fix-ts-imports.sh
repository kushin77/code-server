#!/usr/bin/env bash
# @file        scripts/ops/fix-ts-imports.sh
# @module      backend/ts-imports
# @description Remove .js extensions from TypeScript imports to fix Vite/Vitest source map errors

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/../.."

# Find all TypeScript files and remove .js extensions from imports
echo "Fixing TypeScript imports..."

# Fix relative imports like '../service.js' -> '../service'
find apps/backend/src -name "*.ts" -type f -exec sed -i "s/from '\(\.\.\/[^']*\)\.js'/from '\1'/g" {} +
find apps/backend/src -name "*.ts" -type f -exec sed -i "s/from '\(\.[^']*\)\.js'/from '\1'/g" {} +

# Also fix double-quoted imports
find apps/backend/src -name "*.ts" -type f -exec sed -i 's/from "\(\.\.\/[^"]*\)\.js"/from "\1"/g' {} +
find apps/backend/src -name "*.ts" -type f -exec sed -i 's/from "\(\.[^"]*\)\.js"/from "\1"/g' {} +

echo "✓ Fixed all .js extensions in imports"
