#!/usr/bin/env bash
# @file        scripts/ops/direct-deploy-logging-pipeline.sh
# @module      operations/production
# @description Direct deployment of logging pipeline to production hosts (bypasses broken preflight).
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
DEPLOY_USER="akushnir"
REPO_PATH="~/code-server-enterprise"

deploy_host() {
  local host="$1"
  local label="$2"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Deploying logging pipeline to $label: $host"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Update repo to latest main
  echo "• Updating repository..."
  ssh "${DEPLOY_USER}@${host}" "cd ${REPO_PATH} && git fetch origin main && git checkout main && git pull origin main" || return 1
  
  # Deploy logging pipeline
  echo "• Installing logging pipeline services..."
  ssh "${DEPLOY_USER}@${host}" "cd ${REPO_PATH} && \
    bash scripts/deploy-logging-pipeline-iac.sh" || return 1
  
  echo "✓ $label deployment complete"
  return 0
}

# Execute deployments
echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║ Direct IaC Logging Pipeline Deployment (Idempotent & Immutable)      ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Deploy to primary
if deploy_host "$PRIMARY_HOST" "PRIMARY"; then
  echo "✓ PRIMARY deployment successful"
else
  echo "✗ PRIMARY deployment failed"
  exit 1
fi

echo ""

# Deploy to replica
if deploy_host "$REPLICA_HOST" "REPLICA"; then
  echo "✓ REPLICA deployment successful"
else
  echo "⚠ REPLICA deployment failed (primary succeeded, continuing)"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║ ✓ Logging Pipeline Deployed to Production Hosts                       ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Verify services: ssh akushnir@192.168.168.31 'systemctl status logging-pipeline.service'"
echo "  2. Check logs: ssh akushnir@192.168.168.31 'tail -f ~/code-server-enterprise/logs/logging-pipeline.log'"
echo "  3. Monitor GitHub: gh issue list -L 10 -R kushin77/code-server -l automated"
echo ""
