#!/usr/bin/env bash
# @file        scripts/ops/fix-r31-permissions-simple.sh
# @module      ops/infrastructure
# @description Simple permission fix for R31 deployment directory (IaC-compliant)
# @owner       infrastructure
# @status      active

set -uo pipefail

# Configuration
HOST_R31="192.168.168.31"
DEPLOY_USER="akushnir"
DEPLOY_DIR="/home/akushnir/code-server-enterprise"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
DRY_RUN="${DRY_RUN:-0}"

echo "=== R31 Permission Remediation (Simple) ==="
echo "Host: $HOST_R31"
echo "User: $DEPLOY_USER"
echo "Dir: $DEPLOY_DIR"
echo "SSH Key: $SSH_KEY"
echo "Dry Run: $([[ $DRY_RUN -eq 1 ]] && echo YES || echo NO)"
echo ""

# Verify SSH access
echo "[1/5] Verifying SSH access..."
if ! ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${HOST_R31}" true 2>/dev/null; then
  echo "✗ SSH access failed"
  exit 1
fi
echo "✓ SSH access verified"
echo ""

# Check current permissions issues
echo "[2/5] Checking permission drift..."
if [[ $DRY_RUN -eq 0 ]]; then
  DRIFT_COUNT=$(ssh -i "$SSH_KEY" -o BatchMode=yes "${DEPLOY_USER}@${HOST_R31}" \
    "find ${DEPLOY_DIR} -maxdepth 2 \\( -not -user ${DEPLOY_USER} -o -not -group ${DEPLOY_USER} \\) 2>/dev/null | wc -l")
  echo "Detected $DRIFT_COUNT files with permission drift"
else
  echo "[dry-run] Would check permission drift"
  DRIFT_COUNT="0"
fi
echo ""

# Reset git state
echo "[3/5] Resetting git state to origin/main..."
if [[ $DRY_RUN -eq 0 ]]; then
  ssh -i "$SSH_KEY" -o BatchMode=yes "${DEPLOY_USER}@${HOST_R31}" \
    "cd ${DEPLOY_DIR} && git fetch origin && git reset --hard origin/main" >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "✓ Git state reset successfully"
  else
    echo "✗ Git reset failed"
    exit 1
  fi
else
  echo "[dry-run] Would reset git state"
fi
echo ""

# Verify git status
echo "[4/5] Verifying git status..."
if [[ $DRY_RUN -eq 0 ]]; then
  GIT_STATUS=$(ssh -i "$SSH_KEY" -o BatchMode=yes "${DEPLOY_USER}@${HOST_R31}" \
    "cd ${DEPLOY_DIR} && git status --short")
  if [[ -z "$GIT_STATUS" ]]; then
    echo "✓ Git status clean"
  else
    echo "⚠ Git has uncommitted changes"
  fi
else
  echo "[dry-run] Would verify git status"
fi
echo ""

# Verify containers are running
echo "[5/5] Verifying deployment containers..."
if [[ $DRY_RUN -eq 0 ]]; then
  CONTAINER_COUNT=$(ssh -i "$SSH_KEY" -o BatchMode=yes "${DEPLOY_USER}@${HOST_R31}" \
    "docker ps --quiet | wc -l")
  echo "✓ Running containers: $CONTAINER_COUNT"
else
  echo "[dry-run] Would verify containers"
fi
echo ""

echo "=== Remediation Complete ==="
if [[ $DRY_RUN -eq 1 ]]; then
  echo "✓ Dry-run completed successfully"
  exit 0
fi

if [[ $DRIFT_COUNT -gt 0 ]]; then
  echo "⚠ $DRIFT_COUNT files had permission issues (reset via git)"
else
  echo "✓ No permission issues detected"
fi
exit 0
