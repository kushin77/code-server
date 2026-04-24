#!/bin/bash
# @file        PHASE-2-EXECUTION-GUIDE.sh
# @module      ops/deployment
# @description Phase 2 execution: Deploy WebSocket to production replicas (copy-paste ready)
# @owner       infrastructure
# @status      ready

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 2: DEPLOY WEBSOCKET TO BOTH REPLICAS
# ═══════════════════════════════════════════════════════════════════════════
#
# This script deploys Collab-9 WebSocket task sync to production.
# All operations are IaC, idempotent, and reversible.
#
# Copy each command section and execute on your terminal
# ═══════════════════════════════════════════════════════════════════════════

# STEP 1: Navigate to repository
cd /mnt/c/code-server-enterprise

# STEP 2: Verify current state (optional but recommended)
echo "=== PRE-DEPLOYMENT STATE ==="
echo "Local commit:"
git rev-parse --short HEAD

echo ""
echo "Replica 1 commit:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 'cd code-server-enterprise && git rev-parse --short HEAD' || echo "(SSH failed)"

echo ""
echo "Replica 2 commit:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 'cd code-server-enterprise && git rev-parse --short HEAD' || echo "(SSH failed)"

echo ""
echo "=== READY FOR DEPLOYMENT ==="

# ─────────────────────────────────────────────────────────────────────────
# EXECUTION OPTION A: Automated (Recommended)
# ─────────────────────────────────────────────────────────────────────────
# 
# This single command deploys to both replicas in parallel

bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42

# Expected output:
# - SSH access verification for both replicas
# - Parallel deployment progress
# - Health check verification
# - Success message

# ─────────────────────────────────────────────────────────────────────────
# EXECUTION OPTION B: Dry-Run First (Safer, Recommended)
# ─────────────────────────────────────────────────────────────────────────
#
# Execute without making changes to see what would happen

DRY_RUN=1 bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42

# Then execute actual deployment:
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42

# ─────────────────────────────────────────────────────────────────────────
# EXECUTION OPTION C: Sequential (Replica 1 then Replica 2)
# ─────────────────────────────────────────────────────────────────────────

# Deploy to Replica 1
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31

# Wait for confirmation, then deploy to Replica 2
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.42

# ─────────────────────────────────────────────────────────────────────────
# VERIFICATION AFTER DEPLOYMENT
# ─────────────────────────────────────────────────────────────────────────

echo ""
echo "=== POST-DEPLOYMENT VERIFICATION ==="

# Verify commits updated on both replicas
echo "Replica 1 commit:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 'cd code-server-enterprise && git rev-parse --short HEAD'

echo "Replica 2 commit:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 'cd code-server-enterprise && git rev-parse --short HEAD'

# Verify health endpoints
echo ""
echo "Replica 1 health:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://192.168.168.31:3000/health/ready

echo "Replica 2 health:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://192.168.168.42:3000/health/ready

# Verify containers running
echo ""
echo "Replica 1 containers:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.31 'docker ps --quiet | wc -l'

echo "Replica 2 containers:"
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 'docker ps --quiet | wc -l'

# ─────────────────────────────────────────────────────────────────────────
# SUCCESS CRITERIA
# ─────────────────────────────────────────────────────────────────────────
#
# Phase 2 is complete when:
# ✓ Both replicas updated to latest commit
# ✓ Both replicas health endpoint returns HTTP 200
# ✓ Both replicas have 38+ running containers
# ✓ No errors in deployment script output
#
# If criteria not met: Review troubleshooting section below

# ─────────────────────────────────────────────────────────────────────────
# TROUBLESHOOTING
# ─────────────────────────────────────────────────────────────────────────

# Issue: SSH command fails
# Solution: Verify SSH key and connection
# ssh -v -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 true

# Issue: Docker compose fails
# Solution: Check logs on replica
# ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose logs'

# Issue: Health check fails
# Solution: Wait 30 seconds for services to start, then retry
# sleep 30 && curl http://192.168.168.31:3000/health/ready

# ─────────────────────────────────────────────────────────────────────────
# MANUAL DEPLOYMENT (If script fails)
# ─────────────────────────────────────────────────────────────────────────

# SSH to Replica 1
ssh akushnir@192.168.168.31

# Once connected to Replica 1:
cd code-server-enterprise
git pull --ff-only origin main
docker compose pull
docker compose up -d
exit

# Then SSH to Replica 2
ssh akushnir@192.168.168.42

# Once connected to Replica 2:
cd code-server-enterprise
git pull --ff-only origin main
docker compose pull
docker compose up -d
exit

# ═══════════════════════════════════════════════════════════════════════════
# IDEMPOTENCY GUARANTEES
# ═══════════════════════════════════════════════════════════════════════════
#
# All operations below are idempotent (safe to run multiple times):
#
# git pull --ff-only origin main
#   - Only pulls if new commits exist
#   - Fails if local changes exist (safe)
#   - Can be safely retried
#
# docker compose pull
#   - Pulls latest images
#   - No-op if already current
#   - Can be safely retried
#
# docker compose up -d
#   - Starts/restarts services
#   - Updates if compose file changed
#   - Idempotent by design
#
# Result: Entire Phase 2 is idempotent and safe to execute multiple times
# ═══════════════════════════════════════════════════════════════════════════
