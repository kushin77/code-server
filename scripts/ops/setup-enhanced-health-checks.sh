#!/usr/bin/env bash
# @file        scripts/ops/setup-enhanced-health-checks.sh
# @module      ops/health-monitoring
# @description Deploy application-aware health checks to all cluster replicas
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# CONFIGURATION
################################################################################

SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"
if [[ -z "$SSH_USER" ]]; then
    log_fatal "Set SSH_USER or DEPLOY_USER before deploying enhanced health checks"
fi

if [[ -z "${REPLICAS:-}" ]]; then
    if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
        REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
    else
        log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before deploying enhanced health checks"
    fi
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no)

################################################################################
# HEALTH CHECK IMPLEMENTATION
################################################################################

deploy_health_check() {
    local replica="$1"
    
    log_info "Deploying enhanced health check to $replica..."
    
    # Push the status-check.sh script which is used by Caddy/LoadBalancer
    local status_script="/home/$SSH_USER/scripts/cluster-health-probe.sh"
    
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$replica" "mkdir -p /home/$SSH_USER/scripts"
    
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$replica" "cat << 'EOF' > $status_script
#!/usr/bin/env bash
# Application-Aware Health Probe
# Checks Docker services, DB connectivity, and NAS mount

set -eo pipefail

CHECK_PS_COUNT=\$(docker compose -f code-server-enterprise/docker-compose.yml ps --format json | grep -c 'running' || echo \"0\")
CHECK_DB=\$(docker compose -f code-server-enterprise/docker-compose.yml exec -T db pg_isready -U postgres > /dev/null 2>&1 && echo \"OK\" || echo \"FAIL\")
CHECK_NAS=\$(mountpoint -q /mnt/nas/persistent && echo \"OK\" || echo \"FAIL\")

if [[ \$CHECK_PS_COUNT -gt 5 ]] && [[ \"\$CHECK_DB\" == \"OK\" ]] && [[ \"\$CHECK_NAS\" == \"OK\" ]]; then
    exit 0
else
    echo \"HEALTH FAILURE: Services=\$CHECK_PS_COUNT DB=\$CHECK_DB NAS=\$CHECK_NAS\" >&2
    exit 1
fi
EOF"

    ssh "${SSH_OPTS[@]}" "$SSH_USER@$replica" "chmod +x $status_script"
    log_info "✅ Health probe script deployed to $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Beginning Enhanced Health Check deployment..."
    
    # Convert replicas string to array
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        deploy_health_check "$replica"
    done
    
    log_info "✅ Enhanced health checks distributed to cluster"
}

main "$@"
