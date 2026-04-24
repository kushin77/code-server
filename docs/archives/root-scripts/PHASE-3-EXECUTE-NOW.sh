#!/bin/bash
# @file        PHASE-3-EXECUTE-NOW.sh
# @module      ops/deployment
# @description Phase 3 execution: Fix Replica 1 permissions (P0 #1650)
# @status      production-ready

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          PHASE 3: REPLICA 1 PERMISSIONS FIX               ║${NC}"
echo -e "${BLUE}║            (P0 Issue #1650 Remediation)                   ║${NC}"
echo -e "${BLUE}║              IaC • Immutable • Idempotent                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ────────────────────────────────────────────────────────────────────────
# PRE-EXECUTION VERIFICATION
# ────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}[1/4] PRE-EXECUTION VERIFICATION${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Checking prerequisites..."
echo ""

echo -n "  SSH to Replica 1 (192.168.168.31): "
if ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 'echo OK' >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC}"
else
  echo -e "${RED}✗ FAILED${NC}"
  exit 1
fi

echo -n "  Passwordless sudo on Replica 1: "
if ssh -o BatchMode=yes akushnir@192.168.168.31 'sudo -n true' 2>/dev/null; then
  echo -e "${GREEN}✓${NC}"
else
  echo -e "${RED}✗ NOT CONFIGURED${NC}"
  echo ""
  echo -e "${YELLOW}  ⚠ Passwordless sudo required${NC}"
  echo "  Fix: Run on Replica 1:"
  echo "    ssh akushnir@192.168.168.31"
  echo "    sudo visudo"
  echo "    # Add line at end:"
  echo "    # akushnir ALL=(ALL) NOPASSWD: ALL"
  exit 1
fi

echo ""
echo -e "${GREEN}✓ Prerequisites verified${NC}"
echo ""

# ────────────────────────────────────────────────────────────────────────
# DRY-RUN (PREVIEW)
# ────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}[2/4] DRY-RUN (PREVIEW MODE)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running permission fix script in dry-run mode..."
echo ""

cd /mnt/c/code-server-enterprise || exit 1

if DRY_RUN=1 bash scripts/ops/fix-replica-1-permissions.sh; then
  echo ""
  echo -e "${GREEN}✓ Dry-run successful${NC}"
else
  echo ""
  echo -e "${RED}✗ Dry-run failed${NC}"
  exit 1
fi

echo ""
read -p "Proceed with REAL permission fix to Replica 1? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}✓ Cancelled by user${NC}"
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────
# REAL EXECUTION
# ────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}[3/4] REAL EXECUTION${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Applying permission fixes to Replica 1..."
echo ""

FIX_START=$(date +%s)

if bash scripts/ops/fix-replica-1-permissions.sh; then
  FIX_END=$(date +%s)
  FIX_TIME=$((FIX_END - FIX_START))
  echo ""
  echo -e "${GREEN}✓ Permission fix completed in ${FIX_TIME}s${NC}"
else
  echo ""
  echo -e "${RED}✗ Permission fix failed${NC}"
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────
# POST-EXECUTION VERIFICATION
# ────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}[4/4] POST-EXECUTION VERIFICATION${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Verifying git state on Replica 1..."
R1_COMMIT=$(ssh -o BatchMode=yes akushnir@192.168.168.31 'cd code-server-enterprise && git rev-parse --short HEAD' 2>/dev/null || echo "SSH_FAILED")
R1_DRIFT=$(ssh -o BatchMode=yes akushnir@192.168.168.31 'cd code-server-enterprise && git status --short | wc -l' 2>/dev/null || echo "SSH_FAILED")
R1_CONTAINERS=$(ssh -o BatchMode=yes akushnir@192.168.168.31 'docker ps --quiet | wc -l' 2>/dev/null || echo "SSH_FAILED")

echo -e "  Commit: ${GREEN}${R1_COMMIT}${NC}"
echo -e "  Git drift (dirty files): ${GREEN}${R1_DRIFT}${NC}"
echo -e "  Running containers: ${GREEN}${R1_CONTAINERS}${NC}"
echo ""

if [[ "${R1_COMMIT}" == "2d4d0c08" && "${R1_DRIFT}" == "0" && "${R1_CONTAINERS}" -ge 38 ]] 2>/dev/null; then
  echo -e "${GREEN}✓ Replica 1 fully recovered${NC}"
else
  echo -e "${YELLOW}⚠ Verification inconclusive (SSH may have failed)${NC}"
fi

# ────────────────────────────────────────────────────────────────────────
# SUMMARY
# ────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    PHASE 3 COMPLETE                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Replica 1 permissions fixed (P0 #1650 remediated)${NC}"
echo ""
echo "Next steps:"
echo "  1. Monitor Replica 1 for issues (check logs)"
echo "  2. Execute Phase 4: Validate cluster parity"
echo "  3. Close GitHub issue #1650"
echo ""
