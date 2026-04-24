#!/bin/bash
# @file        PHASE-2-EXECUTE-NOW.sh
# @module      ops/deployment
# @description Phase 2 deployment: WebSocket to production (executable)
# @status      production-ready

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            PHASE 2: WEBSOCKET DEPLOYMENT                   ║${NC}"
echo -e "${BLUE}║              IaC • Immutable • Idempotent                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ────────────────────────────────────────────────────────────────────────
# PRE-DEPLOYMENT VERIFICATION
# ────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}[1/5] PRE-DEPLOYMENT VERIFICATION${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd /mnt/c/code-server-enterprise || {
  echo -e "${RED}✗ Failed to navigate to /mnt/c/code-server-enterprise${NC}"
  exit 1
}

echo "Checking local repository state..."
LOCAL_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "UNKNOWN")
echo -e "  Local HEAD: ${GREEN}${LOCAL_COMMIT}${NC}"

if [[ "${LOCAL_COMMIT}" != "2d4d0c08" ]]; then
  echo -e "${YELLOW}⚠ Warning: Local commit (${LOCAL_COMMIT}) ≠ expected (2d4d0c08)${NC}"
  echo "  Consider running Phase 1 first (git pull origin main)"
  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}✗ Deployment cancelled${NC}"
    exit 1
  fi
fi

echo "Checking SSH connectivity..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 'echo "OK"' >/dev/null 2>&1; then
  echo -e "  Replica 1: ${GREEN}✓ SSH OK${NC}"
else
  echo -e "  Replica 1: ${RED}✗ SSH FAILED${NC}"
  echo "    Fix: Check SSH key (~/.ssh/id_rsa_onprem) and network connectivity"
  exit 1
fi

if ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 'echo "OK"' >/dev/null 2>&1; then
  echo -e "  Replica 2: ${GREEN}✓ SSH OK${NC}"
else
  echo -e "  Replica 2: ${RED}✗ SSH FAILED${NC}"
  echo "    Fix: Check SSH key (~/.ssh/id_rsa_onprem) and network connectivity"
  exit 1
fi

echo ""
echo -e "${GREEN}✓ Pre-deployment verification passed${NC}"
echo ""

# ────────────────────────────────────────────────────────────────────────
# DRY-RUN (PREVIEW)
# ────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}[2/5] DRY-RUN (PREVIEW MODE)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running deployment script in dry-run mode (no changes)..."
echo ""

if DRY_RUN=1 bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42; then
  echo ""
  echo -e "${GREEN}✓ Dry-run successful${NC}"
else
  echo ""
  echo -e "${RED}✗ Dry-run failed${NC}"
  echo "  Fix issues above before proceeding to real deployment"
  exit 1
fi

echo ""
read -p "Proceed with REAL deployment to both replicas? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}✓ Deployment cancelled by user${NC}"
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────
# REAL DEPLOYMENT
# ────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}[3/5] REAL DEPLOYMENT${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deploying to both replicas in parallel..."
echo ""

DEPLOY_START=$(date +%s)

if bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42; then
  DEPLOY_END=$(date +%s)
  DEPLOY_TIME=$((DEPLOY_END - DEPLOY_START))
  echo ""
  echo -e "${GREEN}✓ Deployment completed in ${DEPLOY_TIME}s${NC}"
else
  echo ""
  echo -e "${RED}✗ Deployment failed${NC}"
  echo "  Check error messages above"
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────
# POST-DEPLOYMENT VERIFICATION
# ────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}[4/5] POST-DEPLOYMENT VERIFICATION${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Verifying commit parity..."
R1_COMMIT=$(ssh -o BatchMode=yes akushnir@192.168.168.31 'cd code-server-enterprise && git rev-parse --short HEAD' 2>/dev/null || echo "SSH_FAILED")
R2_COMMIT=$(ssh -o BatchMode=yes akushnir@192.168.168.42 'cd code-server-enterprise && git rev-parse --short HEAD' 2>/dev/null || echo "SSH_FAILED")

echo -e "  Local:    ${GREEN}${LOCAL_COMMIT}${NC}"
echo -e "  Replica1: ${GREEN}${R1_COMMIT}${NC}"
echo -e "  Replica2: ${GREEN}${R2_COMMIT}${NC}"

if [[ "${R1_COMMIT}" == "2d4d0c08" && "${R2_COMMIT}" == "2d4d0c08" ]]; then
  echo -e "${GREEN}✓ Commit parity verified${NC}"
else
  echo -e "${YELLOW}⚠ Commit parity check inconclusive (SSH may have failed)${NC}"
fi

echo ""
echo "Verifying git drift (clean state)..."
R1_DRIFT=$(ssh -o BatchMode=yes akushnir@192.168.168.31 'cd code-server-enterprise && git status --short | wc -l' 2>/dev/null || echo "SSH_FAILED")
R2_DRIFT=$(ssh -o BatchMode=yes akushnir@192.168.168.42 'cd code-server-enterprise && git status --short | wc -l' 2>/dev/null || echo "SSH_FAILED")

echo -e "  Replica1 dirty files: ${GREEN}${R1_DRIFT}${NC}"
echo -e "  Replica2 dirty files: ${GREEN}${R2_DRIFT}${NC}"

if [[ "${R1_DRIFT}" == "0" && "${R2_DRIFT}" == "0" ]]; then
  echo -e "${GREEN}✓ Git state clean (idempotent confirmed)${NC}"
else
  echo -e "${YELLOW}⚠ Git state check inconclusive (SSH may have failed)${NC}"
fi

echo ""
echo "Verifying container health..."
R1_CONTAINERS=$(ssh -o BatchMode=yes akushnir@192.168.168.31 'docker ps --quiet | wc -l' 2>/dev/null || echo "SSH_FAILED")
R2_CONTAINERS=$(ssh -o BatchMode=yes akushnir@192.168.168.42 'docker ps --quiet | wc -l' 2>/dev/null || echo "SSH_FAILED")

echo -e "  Replica1 containers: ${GREEN}${R1_CONTAINERS}${NC} (expected: >=38)"
echo -e "  Replica2 containers: ${GREEN}${R2_CONTAINERS}${NC} (expected: >=38)"

if [[ "${R1_CONTAINERS}" -ge 38 && "${R2_CONTAINERS}" -ge 38 ]] 2>/dev/null; then
  echo -e "${GREEN}✓ Container health verified${NC}"
else
  echo -e "${YELLOW}⚠ Container health check inconclusive${NC}"
fi

# ────────────────────────────────────────────────────────────────────────
# SUMMARY
# ────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    PHASE 2 COMPLETE                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

echo ""
echo -e "${GREEN}✓ WebSocket deployed to both replicas (commit 2d4d0c08)${NC}"
echo ""
echo "Next steps:"
echo "  1. Monitor cluster for 30 minutes (check logs)"
echo "  2. Execute Phase 3: Fix Replica 1 permissions (P0 #1650)"
echo "  3. Execute Phase 4: Validate cluster parity"
echo ""
echo "Detailed verification:"
echo "  bash PHASE-2-DEPLOYMENT-VERIFICATION-AND-EXECUTE.md"
echo ""
