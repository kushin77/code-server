#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PATTERN='password=secret|replication_user_pwd|admin123|changeme-enterprise-pwd|changeme-sudo-pwd|CODE_SERVER_PASSWORD=\$\{CODE_SERVER_PASSWORD:-change-me\}'

matches=$(grep -RInE "$PATTERN" scripts \
  --include='*.sh' \
  --exclude-dir='_archive' \
  --exclude='check-no-hardcoded-credentials.sh' || true)

if [[ -n "$matches" ]]; then
  echo "FAIL: Hardcoded credential literals detected in active scripts:" >&2
  echo "$matches" >&2
  exit 1
fi

echo "OK: no hardcoded credential literals detected"
