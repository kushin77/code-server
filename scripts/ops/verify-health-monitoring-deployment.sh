#!/usr/bin/env bash
# @file        scripts/ops/verify-health-monitoring-deployment.sh
# @module      monitoring/verification
# @description Verify Prometheus & AlertManager deployed and operational on both replicas
#

set -euo pipefail

REPLICAS=("192.168.168.31" "192.168.168.42")
SSH_USER="akushnir"
SSH_KEY="$HOME/.ssh/id_rsa_onprem"
REPORT="/tmp/health-monitoring-verify-$(date +%s).md"

{
  echo "# Health Monitoring Deployment Verification Report"
  echo "**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  for replica in "${REPLICAS[@]}"; do
    echo "## Replica: $replica"
    echo ""
    
    # Check Prometheus running
    echo "### Prometheus Status"
    status=$(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" \
      "docker-compose ps prometheus 2>&1 | grep prometheus || echo CONTAINER_NOT_FOUND" 2>/dev/null || echo UNREACHABLE)
    echo "\`\`\`"
    echo "$status"
    echo "\`\`\`"
    echo ""
    
    # Check AlertManager running  
    echo "### AlertManager Status"
    status=$(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" \
      "docker-compose ps alertmanager 2>&1 | grep alertmanager || echo CONTAINER_NOT_FOUND" 2>/dev/null || echo UNREACHABLE)
    echo "\`\`\`"
    echo "$status"
    echo "\`\`\`"
    echo ""
    
    # Check Prometheus metrics endpoint
    echo "### Prometheus Metrics Endpoint"
    http_code=$(ssh -i "$SSH_KEY" -o BatchMode=yes "$SSH_USER@$replica" \
      "curl -sf http://localhost:9090/api/v1/query?query=up | head -c 100" 2>/dev/null | wc -c)
    if [[ $http_code -gt 0 ]]; then
      echo "✓ Metrics endpoint responding"
    else
      echo "✗ Metrics endpoint not responding"
    fi
    echo ""
    
    # Check scrape targets
    echo "### Scrape Targets"
    ssh -i "$SSH_KEY" -o BatchMode=yes "$SSH_USER@$replica" \
      "curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -o '\"labels\":{[^}]*}' | head -5 || echo FAILED_TO_FETCH_TARGETS" 2>/dev/null || echo ""
    echo ""
  done
  
  echo "---"
  echo "**Verification Complete** — Report: $REPORT"
} | tee "$REPORT"

cat "$REPORT"
