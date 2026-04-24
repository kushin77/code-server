#!/bin/bash
set -euo pipefail

# Phase 2 execution wrapper (minimal, focused)
cd /mnt/c/code-server-enterprise

# Execute deployment script to both replicas
bash scripts/ops/collab-9-deploy.sh --hosts 192.168.168.31,192.168.168.42

# Verification
echo ""
echo "=== PHASE 2 VERIFICATION ==="
echo ""

# Check both replicas
for host in 192.168.168.31 192.168.168.42; do
  echo "Replica: $host"
  ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@$host "cd code-server-enterprise && git rev-parse --short HEAD" 2>/dev/null || echo "SSH failed"
  ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@$host "docker ps --quiet | wc -l" 2>/dev/null || echo "Docker check failed"
  echo ""
done

echo "Phase 2 execution complete"
