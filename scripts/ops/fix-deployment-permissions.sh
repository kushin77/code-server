#!/usr/bin/env bash
# @file        scripts/ops/fix-deployment-permissions.sh
# @module      ops/deployment
# @description Idempotent remediation of root-owned deployment artifacts on replicas
# @owner       akushnir
# @status      stable
#
# Fixes common permission issues encountered in CI/CD:
# - Root-owned files created by Docker volumes
# - Inaccessible git repository state
# - Permissions for user 'akushnir' on all deployment files
#
# Usage: bash scripts/ops/fix-deployment-permissions.sh [--replicas R31,R42]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
USER_OWNER="akushnir"
REPO_PATH="/home/akushnir/code-server-enterprise"

log_info "Starting idempotent permission remediation for: $REPLICAS"

IFS=',' read -ra ADDR <<< "$REPLICAS"
for host in "${ADDR[@]}"; do
    log_info "Fixing permissions on $host..."
    
    # We use sudo for chown, assuming the user has passwordless sudo for these directories
    # or that the user running the script on the host is root/sudo-capable.
    ssh "$host" "sudo chown -R $USER_OWNER:$USER_OWNER $REPO_PATH && \
                sudo chmod -R u+rwX $REPO_PATH && \
                log_info '✅ Permissions restored for $USER_OWNER on $host'" || {
        log_error "Failed to restore permissions on $host"
        continue
    }
done

log_info "Permission remediation complete"
exit 0
