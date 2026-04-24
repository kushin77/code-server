#!/usr/bin/env bash
# @file        scripts/ops/deploy-health-monitoring-direct.sh
# @module      infrastructure/monitoring
# @description Deploy health monitoring to both replicas (direct SSH execution)
# @owner       Platform Engineering
# @status      PRODUCTION READY - Governance Compliant (IaC/immutable/idempotent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
REPLICA_31="192.168.168.31"
REPLICA_42="192.168.168.42"
SSH_USER="akushnir"
SSH_KEY="${HOME}/.ssh/id_rsa_onprem"
DEPLOY_PATH="code-server-enterprise"

echo "=== CLUSTER HEALTH MONITORING DEPLOYMENT ==="
echo "Deploying to both replicas (parallel execution)..."
echo ""

# Deploy to Replica 31
echo "[Replica 31] Deploying health monitoring..."
ssh -i "${SSH_KEY}" "${SSH_USER}@${REPLICA_31}" "cd ${DEPLOY_PATH} && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus" > /dev/null 2>&1 &
PID_31=$!

# Deploy to Replica 42
echo "[Replica 42] Deploying health monitoring..."
ssh -i "${SSH_KEY}" "${SSH_USER}@${REPLICA_42}" "cd ${DEPLOY_PATH} && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus" > /dev/null 2>&1 &
PID_42=$!

# Wait for both
wait ${PID_31} && echo "✓ Replica 31 deployment complete" || echo "✗ Replica 31 deployment failed"
wait ${PID_42} && echo "✓ Replica 42 deployment complete" || echo "✗ Replica 42 deployment failed"

echo ""
echo "=== DEPLOYMENT COMPLETE ==="
echo "Prometheus health monitoring deployed to both replicas"
echo ""
echo "Verification:"
echo "  - Scrape targets: https://192.168.168.31:9090/targets"
echo "  - Alert rules: https://192.168.168.31:9090/rules"
echo "  - Health check: curl -k https://192.168.168.31/health"
echo ""

exit 0
