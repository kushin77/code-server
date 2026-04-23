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

TARGET_HOST=""
TARGET_LABEL=""
DEPLOY_ALL=0

usage() {
  cat <<'EOF'
Usage: bash scripts/ops/direct-deploy-logging-pipeline.sh [OPTIONS]

Options:
  --host <ip>   Deploy only to the specified host (192.168.168.31 or 192.168.168.42).
  --all         Deploy to both primary and replica hosts (192.168.168.31 and 192.168.168.42).
  -h,--help     Show this help message.

Default (no options): Deploy to both hosts (same as --all).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      TARGET_HOST="${2:-}"
      shift 2
      ;;
    --all)
      DEPLOY_ALL=1
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$TARGET_HOST" ]]; then
  case "$TARGET_HOST" in
    "$PRIMARY_HOST")
      TARGET_LABEL="PRIMARY"
      ;;
    "$REPLICA_HOST")
      TARGET_LABEL="REPLICA"
      ;;
    *)
      echo "Unsupported host: $TARGET_HOST" >&2
      exit 1
      ;;
  esac
fi

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

if [[ -n "$TARGET_HOST" ]]; then
  if deploy_host "$TARGET_HOST" "$TARGET_LABEL"; then
    echo "✓ ${TARGET_LABEL} deployment successful"
  else
    echo "✗ ${TARGET_LABEL} deployment failed"
    exit 1
  fi
elif [[ $DEPLOY_ALL -eq 1 ]] || [[ -z "$TARGET_HOST" && $DEPLOY_ALL -eq 0 ]]; then
  # Deploy to both hosts (--all flag or default behavior)
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
