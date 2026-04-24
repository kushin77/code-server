#!/usr/bin/env bash
# @file        tmp-verify-p1-1661.sh
# @module      deployment/verification
# @description Verify P1 #1661 health monitoring deployment

set -uo pipefail

HOST31="akushnir@192.168.168.31"
HOST42="akushnir@192.168.168.42"
SSH_OPTS="-i ~/.ssh/id_rsa_onprem -o BatchMode=yes -o ConnectTimeout=5"
OUTFILE="/tmp/P1-1661-DEPLOYMENT-VERIFICATION.txt"

{
  echo "======== P1 #1661 DEPLOYMENT VERIFICATION ========"
  echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  
  # R31 Verification
  echo "=== REPLICA 31 (192.168.168.31) ==="
  ssh $SSH_OPTS $HOST31 "cd /home/akushnir/code-server-enterprise && git rev-parse --short HEAD" && echo "✓ Git state verified" || echo "✗ Git state check failed"
  
  echo -n "Prometheus container: "
  ssh $SSH_OPTS $HOST31 "docker ps --quiet --filter name=prometheus" | head -1 && echo "✓ RUNNING" || echo "✗ NOT RUNNING"
  
  echo -n "AlertManager container: "
  ssh $SSH_OPTS $HOST31 "docker ps --quiet --filter name=alertmanager" | head -1 && echo "✓ RUNNING" || echo "✗ NOT RUNNING"
  
  echo -n "Health check endpoint: "
  ssh $SSH_OPTS $HOST31 "curl -sf http://localhost:8080/healthz >/dev/null && echo RESPONDING" && echo "✓ OK" || echo "✗ FAILED"
  
  echo ""
  
  # R42 Verification
  echo "=== REPLICA 42 (192.168.168.42) ==="
  ssh $SSH_OPTS $HOST42 "cd /home/akushnir/code-server-enterprise && git rev-parse --short HEAD" && echo "✓ Git state verified" || echo "✗ Git state check failed"
  
  echo -n "Prometheus container: "
  ssh $SSH_OPTS $HOST42 "docker ps --quiet --filter name=prometheus" | head -1 && echo "✓ RUNNING" || echo "✗ NOT RUNNING"
  
  echo -n "AlertManager container: "
  ssh $SSH_OPTS $HOST42 "docker ps --quiet --filter name=alertmanager" | head -1 && echo "✓ RUNNING" || echo "✗ NOT RUNNING"
  
  echo -n "Health check endpoint: "
  ssh $SSH_OPTS $HOST42 "curl -sf http://localhost:8080/healthz >/dev/null && echo RESPONDING" && echo "✓ OK" || echo "✗ FAILED"
  
  echo ""
  echo "======== VERIFICATION COMPLETE ========"
  
} | tee "$OUTFILE"

echo ""
echo "✓ Full verification saved to: $OUTFILE"
cat "$OUTFILE"
