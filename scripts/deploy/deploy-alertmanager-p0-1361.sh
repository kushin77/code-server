#!/usr/bin/env bash
# @file        scripts/deploy/deploy-alertmanager-p0-1361.sh
# @module      deploy/monitoring
# @description Deploy P0 #1361 AlertManager fix - severity-based routing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR%/scripts*}" && pwd)"

# Deploy to remote host
REMOTE_HOST="${REMOTE_HOST:-192.168.168.31}"
REMOTE_USER="${REMOTE_USER:-akushnir}"

echo "📋 Deploying P0 #1361 AlertManager fix to $REMOTE_HOST..."

# Copy config file
echo "📦 Copying AlertManager config..."
scp "${PROJECT_ROOT}/config/alertmanager.yml" "${REMOTE_USER}@${REMOTE_HOST}:~/code-server-enterprise/config/alertmanager.yml" || {
  echo "⚠️  SCP failed, trying via docker..."
  ssh "${REMOTE_USER}@${REMOTE_HOST}" "cd ~/code-server-enterprise && cat > /tmp/alertmanager-new.yml << 'EOF'
$(cat "${PROJECT_ROOT}/config/alertmanager.yml")
EOF
  docker rm -f alertmanager
  docker-compose up -d alertmanager
  sleep 5
  docker exec alertmanager grep -A 3 'receivers:' /etc/alertmanager/alertmanager.yml"
  exit 0
}

# Restart AlertManager container
echo "🔄 Restarting AlertManager..."
ssh "${REMOTE_USER}@${REMOTE_HOST}" "cd ~/code-server-enterprise && docker rm -f alertmanager && docker-compose up -d alertmanager && sleep 5"

# Verify deployment
echo "✅ Verifying deployment..."
ssh "${REMOTE_USER}@${REMOTE_HOST}" "docker exec alertmanager grep -A 3 'receivers:' /etc/alertmanager/alertmanager.yml" | grep -q "critical-alerts" && {
  echo "✅ P0 #1361 AlertManager fix deployed successfully!"
  echo "   Config now routes alerts by severity (critical/warning/info)"
  exit 0
} || {
  echo "❌ Deployment failed - config not updated"
  exit 1
}
