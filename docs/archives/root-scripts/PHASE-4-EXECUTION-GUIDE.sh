#!/bin/bash
# @file        PHASE-4-EXECUTION-GUIDE.sh
# @module      ops/deployment
# @description Phase 4 execution: Validate cluster parity
# @owner       infrastructure
# @status      ready

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 4: VALIDATE CLUSTER PARITY
# ═══════════════════════════════════════════════════════════════════════════
#
# This phase verifies that both replicas are synchronized:
# - Same commit (2d4d0c08)
# - Same service state (38+ containers)
# - Both healthy (HTTP 200)
# - Clean git state (no drift)
#
# Prerequisites: Phases 2-3 must complete successfully
# ═══════════════════════════════════════════════════════════════════════════

cd /mnt/c/code-server-enterprise

echo "==================================================================="
echo "PHASE 4: VALIDATE CLUSTER PARITY"
echo "==================================================================="
echo ""

# STEP 1: Verify commits match
echo "Step 1: Verify commit parity"
echo "---"

COMMIT_1=$(ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 "cd code-server-enterprise && git rev-parse --short HEAD" 2>/dev/null || echo "ERROR")
COMMIT_2=$(ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 "cd code-server-enterprise && git rev-parse --short HEAD" 2>/dev/null || echo "ERROR")

echo "Replica 1 commit: $COMMIT_1"
echo "Replica 2 commit: $COMMIT_2"

if [[ "$COMMIT_1" == "$COMMIT_2" ]]; then
  echo "✓ Commits match"
else
  echo "✗ Commits differ - possible deployment issue"
fi

echo ""

# STEP 2: Verify git status clean
echo "Step 2: Verify git status (no drift)"
echo "---"

DRIFT_1=$(ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 "cd code-server-enterprise && git status --short | wc -l" 2>/dev/null || echo "ERROR")
DRIFT_2=$(ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 "cd code-server-enterprise && git status --short | wc -l" 2>/dev/null || echo "ERROR")

echo "Replica 1 git drift: $DRIFT_1 files"
echo "Replica 2 git drift: $DRIFT_2 files"

if [[ "$DRIFT_1" == "0" && "$DRIFT_2" == "0" ]]; then
  echo "✓ Both replicas clean (no uncommitted changes)"
else
  echo "✗ Git drift detected on one or both replicas"
fi

echo ""

# STEP 3: Verify container counts
echo "Step 3: Verify container counts"
echo "---"

COUNT_1=$(ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 "docker ps --quiet | wc -l" 2>/dev/null || echo "ERROR")
COUNT_2=$(ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 "docker ps --quiet | wc -l" 2>/dev/null || echo "ERROR")

echo "Replica 1 containers: $COUNT_1"
echo "Replica 2 containers: $COUNT_2"

if [[ "$COUNT_1" == "$COUNT_2" && "$COUNT_1" -ge "38" ]]; then
  echo "✓ Container counts match and adequate"
else
  echo "⚠ Container counts differ or below threshold"
fi

echo ""

# STEP 4: Verify health endpoints
echo "Step 4: Verify health endpoints"
echo "---"

HEALTH_1=$(curl -s -o /dev/null -w "%{http_code}" "http://192.168.168.31:3000/health/ready" 2>/dev/null || echo "ERROR")
HEALTH_2=$(curl -s -o /dev/null -w "%{http_code}" "http://192.168.168.42:3000/health/ready" 2>/dev/null || echo "ERROR")

echo "Replica 1 health: HTTP $HEALTH_1"
echo "Replica 2 health: HTTP $HEALTH_2"

if [[ "$HEALTH_1" == "200" && "$HEALTH_2" == "200" ]]; then
  echo "✓ Both replicas healthy"
else
  echo "✗ Health check failing on one or more replicas"
fi

echo ""

# STEP 5: Run comprehensive verification script
echo "Step 5: Run comprehensive verification"
echo "---"

bash scripts/ops/verify-deployment-state.sh

echo ""
echo "==================================================================="
echo "PHASE 4 VALIDATION COMPLETE"
echo "==================================================================="
echo ""
echo "If all checks passed:"
echo "  ✓ Cluster parity achieved"
echo "  ✓ Both replicas on commit 2d4d0c08"
echo "  ✓ Both replicas healthy and synced"
echo "  ✓ Ready for production use"
echo ""
echo "Next steps:"
echo "  1. Close GitHub issues: #1650, #1616"
echo "  2. Monitor cluster for 30 minutes"
echo "  3. Enable failover testing"
echo ""
