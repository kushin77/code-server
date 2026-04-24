#!/usr/bin/env bash
# @file        scripts/ops/verify-p1-1661-deployment.sh
# @module      operations/monitoring
# @description Verify P1 #1661 (Cluster Health Monitoring) deployment on both replicas
# @owner       copilot-automation
# @status      production-ready

set -euo pipefail

# Configuration
REPLICA_31="192.168.168.31"
REPLICA_42="192.168.168.42"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_onprem}"
TIMEOUT=10
RESULTS_FILE="/tmp/p1-1661-verification-results.md"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Initialize results
{
    echo "# P1 #1661 Deployment Verification Results"
    echo ""
    echo "**Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "**Status**: In Progress"
    echo ""
} > "$RESULTS_FILE"

# Function to verify single replica
verify_replica() {
    local replica_ip="$1"
    local replica_name="$2"
    
    echo "## $replica_name ($replica_ip)" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    
    # Test 1: Container status
    echo "### 1. Container Status" >> "$RESULTS_FILE"
    if result=$(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        "akushnir@$replica_ip" \
        "cd code-server-enterprise && docker-compose ps prometheus" 2>&1); then
        if echo "$result" | grep -q "Up"; then
            echo "✅ **PASS** - Prometheus container is UP" >> "$RESULTS_FILE"
            echo '```' >> "$RESULTS_FILE"
            echo "$result" | head -20 >> "$RESULTS_FILE"
            echo '```' >> "$RESULTS_FILE"
        else
            echo "❌ **FAIL** - Prometheus container not running" >> "$RESULTS_FILE"
            echo '```' >> "$RESULTS_FILE"
            echo "$result" >> "$RESULTS_FILE"
            echo '```' >> "$RESULTS_FILE"
        fi
    else
        echo "❌ **FAIL** - SSH command failed" >> "$RESULTS_FILE"
        echo '```' >> "$RESULTS_FILE"
        echo "$result" >> "$RESULTS_FILE"
        echo '```' >> "$RESULTS_FILE"
    fi
    echo "" >> "$RESULTS_FILE"
    
    # Test 2: Health endpoint
    echo "### 2. Health Endpoint" >> "$RESULTS_FILE"
    if result=$(curl -k -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 \
        "https://$replica_ip/health" 2>&1); then
        if [ "$result" = "200" ]; then
            echo "✅ **PASS** - Health endpoint returning 200 OK" >> "$RESULTS_FILE"
        else
            echo "❌ **FAIL** - Health endpoint returned: $result" >> "$RESULTS_FILE"
        fi
    else
        echo "⚠️  **WARN** - Could not reach health endpoint: $result" >> "$RESULTS_FILE"
    fi
    echo "" >> "$RESULTS_FILE"
    
    # Test 3: Prometheus targets
    echo "### 3. Prometheus Scrape Targets" >> "$RESULTS_FILE"
    if result=$(curl -k -s "https://$replica_ip:9090/api/v1/targets" 2>&1 | \
        jq '.data.activeTargets[] | select(.job | contains("cluster-health")) | {job: .job, state: .lastScrapeStatus}' 2>/dev/null || echo "ERROR"); then
        if [ "$result" != "ERROR" ] && [ ! -z "$result" ]; then
            echo "✅ **PASS** - Scrape targets found" >> "$RESULTS_FILE"
            echo '```json' >> "$RESULTS_FILE"
            echo "$result" >> "$RESULTS_FILE"
            echo '```' >> "$RESULTS_FILE"
        else
            echo "⚠️  **WARN** - Could not query Prometheus targets" >> "$RESULTS_FILE"
        fi
    fi
    echo "" >> "$RESULTS_FILE"
    
    # Test 4: Alert rules
    echo "### 4. Alert Rules" >> "$RESULTS_FILE"
    if result=$(curl -k -s "https://$replica_ip:9090/api/v1/rules" 2>&1 | \
        jq '.data.groups[].rules[] | select(.name | contains("ClusterHealthCheck")) | {name: .name, state: .state}' 2>/dev/null || echo "ERROR"); then
        if [ "$result" != "ERROR" ] && [ ! -z "$result" ]; then
            echo "✅ **PASS** - Alert rules loaded" >> "$RESULTS_FILE"
            echo '```json' >> "$RESULTS_FILE"
            echo "$result" >> "$RESULTS_FILE"
            echo '```' >> "$RESULTS_FILE"
        else
            echo "⚠️  **WARN** - Could not query alert rules" >> "$RESULTS_FILE"
        fi
    fi
    echo "" >> "$RESULTS_FILE"
}

echo "Starting verification of P1 #1661 deployment..."

# Verify both replicas
verify_replica "$REPLICA_31" "Replica 31"
verify_replica "$REPLICA_42" "Replica 42"

# Summary
{
    echo "## Summary"
    echo ""
    echo "✅ Verification complete. Results saved to: $RESULTS_FILE"
    echo ""
    echo "**Next Steps**:"
    echo "1. Review results above"
    echo "2. Post results to GitHub issue #1661"
    echo "3. If all checks pass, mark issue as complete"
    echo ""
} >> "$RESULTS_FILE"

# Output results
echo ""
echo "=========================================="
echo "P1 #1661 DEPLOYMENT VERIFICATION RESULTS"
echo "=========================================="
echo ""
cat "$RESULTS_FILE"
echo ""
echo "=========================================="
echo "Results saved to: $RESULTS_FILE"
echo "=========================================="
