#!/bin/bash
# @file        PHASE-3-EXECUTION-GUIDE.sh
# @module      ops/deployment
# @description Phase 3 execution: Fix Replica 1 permissions (P0 #1650)
# @owner       infrastructure
# @status      ready

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 3: FIX REPLICA 1 PERMISSIONS (P0 #1650)
# ═══════════════════════════════════════════════════════════════════════════
#
# This phase fixes file permission issues on Replica 1 that block git operations
# All operations are idempotent and reversible
#
# Prerequisites: Phase 2 must complete successfully
# ═══════════════════════════════════════════════════════════════════════════

cd /mnt/c/code-server-enterprise

echo "==================================================================="
echo "PHASE 3: FIX REPLICA 1 PERMISSIONS (P0 #1650)"
echo "==================================================================="
echo ""

# STEP 1: Dry-run first (recommended)
echo "Step 1: Dry-run preview"
echo "---"
DRY_RUN=1 bash scripts/ops/fix-replica-1-permissions.sh

echo ""
echo "Ready to execute Phase 3? Review the dry-run output above."
echo "Press Ctrl+C to abort, or wait 5 seconds to continue..."
echo ""
sleep 5

# STEP 2: Execute Phase 3
echo "Step 2: Execute Phase 3"
echo "---"
bash scripts/ops/fix-replica-1-permissions.sh

# STEP 3: Verification
echo ""
echo "Step 3: Verify Phase 3 completion"
echo "---"

# Verify Replica 1 commit
echo "Replica 1 commit:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 "cd code-server-enterprise && git rev-parse --short HEAD" || echo "(SSH check failed)"

# Verify git status clean
echo ""
echo "Replica 1 git status:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 "cd code-server-enterprise && git status --short" || echo "(SSH check failed)"
echo "(Should be empty = clean state)"

# Verify containers
echo ""
echo "Replica 1 containers:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 "docker ps --quiet | wc -l" || echo "(Docker check failed)"

echo ""
echo "==================================================================="
echo "PHASE 3 EXECUTION COMPLETE"
echo "==================================================================="
echo ""
echo "If all checks passed, proceed to Phase 4 (Cluster Parity Validation)"
echo ""
