#!/usr/bin/env bash
# @file scripts/ops/cluster-ssot-sync.sh
# @description Synchronizes the Single Source of Truth (SSOT) across cluster hosts
# @governance GOV-002: Configuration parity between Primary and Replica

set -euo pipefail

# Find repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# Source canonical configuration
if [ -f "${REPO_ROOT}/scripts/_common/_base-config.env" ]; then
    source "${REPO_ROOT}/scripts/_common/_base-config.env"
else
    echo "❌ ERROR: Canonical config not found at scripts/_common/_base-config.env"
    exit 1
fi

TARGET_HOSTS=("$PRIMARY_HOST" "$REPLICA_HOST")
REMOTE_REPO_PATH="~/code-server-enterprise"

echo "=== SSOT CLUSTER SYNC START ==="
echo "Primary: $PRIMARY_HOST"
echo "Replica: $REPLICA_HOST"
echo ""

# Generate a flat .env for remote use (evaluating variables and stripping bash logic)
TEMP_ENV=$(mktemp)
# 1. Export core cluster variables
# 2. Extract only export lines from base-config and clean them up for pure .env format
# Remove 'export ', removal of default value syntax, etc.
grep "^export " "${REPO_ROOT}/scripts/_common/_base-config.env" | \
    grep -v -E "PRIMARY_HOST|REPLICA_HOST|NAS_HOST|APEX_DOMAIN|ADMIN_EMAIL" | \
    sed 's/^export //g' | \
    sed 's/="\${[^:-]*:-\([^}]*\)}"$/=\1/g' | \
    sed 's/="\${[^}]*}"$/=/g' >> "$TEMP_ENV"
for host in "${TARGET_HOSTS[@]}"; do
    echo "--- Syncing $host ---"
    # 1. Sync .env
    echo "  [1/3] Syncing .env file..."
    scp -i "$HOME/.ssh/id_ed25519" "$TEMP_ENV" "akushnir@${host}:${REMOTE_REPO_PATH}/.env"
    # 3. Apply changes (Restart containers if needed)
    echo "  [3/3] Configuration deployed."
done

rm "$TEMP_ENV"
echo ""
echo "✅ SSOT SYNC COMPLETE"
