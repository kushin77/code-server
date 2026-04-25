#!/usr/bin/env bash
# scripts/ci/run-kushnir-cloud-appsmith-login-e2e.sh
# Run the issue #1545 portal + SSO browser flow tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

APEX_DOMAIN="${APEX_DOMAIN:-}"
if [[ -z "$APEX_DOMAIN" ]]; then
        echo "ERROR: APEX_DOMAIN is not set. Domain variability is required by GOV-002." >&2
        exit 1
fi
export PORTAL_URL="${PORTAL_URL:-https://${APEX_DOMAIN}}"
export BASE_URL="${BASE_URL:-https://ide.${APEX_DOMAIN}}"
export IDE_URL="${IDE_URL:-https://ide.${APEX_DOMAIN}}"

cd "${REPO_ROOT}"

if command -v pnpm >/dev/null 2>&1; then
	pnpm exec playwright test tests/e2e/auth/login.spec.ts tests/e2e/portal/portal.spec.ts
elif command -v npx >/dev/null 2>&1; then
	npx --no-install playwright test tests/e2e/auth/login.spec.ts tests/e2e/portal/portal.spec.ts
else
	echo "Neither pnpm nor npx is available to run Playwright tests." >&2
	exit 1
fi
