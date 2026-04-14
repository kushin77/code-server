#!/bin/bash
# ============================================================================
# PHASE 13 DAY 1 - REMOTE EXECUTION WRAPPER FOR HOST 31
# Execute Phase 13 Day 1 tasks directly on 192.168.168.31 via SSH
#
# Usage:
#   ./scripts/phase-13-day1-remote.sh <host31_address> <username> <ssh_key>
#   ./scripts/phase-13-day1-remote.sh 192.168.168.31 akushnir ~/.ssh/akushnir-31
#
# This script:
# 1. Copies needed files to .31
# 2. Executes Phase 13 Day 1 on .31
# 3. Captures results and logs
# 4. Returns status to caller
# ============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
HOST_31="${1:-192.168.168.31}"
SSH_USER="${2:-akushnir}"
SSH_KEY="${3:-$HOME/.ssh/akushnir-31}"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 13 DAY 1 - REMOTE EXECUTION ON HOST 31${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Validate SSH key
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}[✗] SSH key not found: $SSH_KEY${NC}"
    echo ""
    echo "Please provide correct SSH key path as third argument:"
    echo "  $0 192.168.168.31 akushnir /path/to/ssh/key"
    exit 1
fi

echo -e "${BLUE}[+] Configuration:${NC}"
echo "    Host: $HOST_31"
echo "    User: $SSH_USER"
echo "    Key: $SSH_KEY"
echo ""

# Step 1: Test SSH connectivity
echo -e "${BLUE}[+] Testing SSH connectivity to $HOST_31...${NC}"
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "$SSH_USER@$HOST_31" "echo 'SSH connectivity OK'" >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] SSH connectivity verified${NC}"
else
    echo -e "${RED}[✗] Cannot connect to $HOST_31${NC}"
    echo "    Ensure Host 31 is reachable and SSH key is correct"
    exit 1
fi

echo ""

# Step 2: Copy deployment package to .31
echo -e "${BLUE}[+] Copying deployment files to $HOST_31...${NC}"

REMOTE_WORK_DIR="/tmp/phase-13-deployment-$(date +%s)"

ssh -i "$SSH_KEY" "$SSH_USER@$HOST_31" "mkdir -p $REMOTE_WORK_DIR"

# Copy this repository's scripts and docker-compose
scp -i "$SSH_KEY" -r \
    scripts/phase-13-day1-execute.sh \
    docker-compose.yml \
    .env \
    "$SSH_USER@$HOST_31:$REMOTE_WORK_DIR/" 2>/dev/null || {
    echo -e "${YELLOW}[!] Some files may not have copied (continuing anyway)${NC}"
}

echo -e "${GREEN}[✓] Deployment files copied${NC}"
echo ""

# Step 3: Execute Phase 13 Day 1 on .31
echo -e "${BLUE}[+] EXECUTING PHASE 13 DAY 1 ON HOST 31...${NC}"
echo ""

# Create execution wrapper
REMOTE_EXEC="/tmp/phase13-day1-$$.sh"

ssh -i "$SSH_KEY" "$SSH_USER@$HOST_31" "cat > $REMOTE_EXEC" << 'REMOTE_SCRIPT'
#!/bin/bash
cd /tmp/phase-13-deployment-*/
export REPO_ROOT="/tmp/phase-13-deployment-"*
bash phase-13-day1-execute.sh
REMOTE_SCRIPT

# Execute the wrapper on .31
ssh -i "$SSH_KEY" "$SSH_USER@$HOST_31" "bash $REMOTE_EXEC" || {
    echo -e "${RED}[✗] Phase 13 Day 1 execution failed${NC}"
    exit 1
}

echo ""
echo -e "${BLUE}[+] Retrieving execution results from $HOST_31...${NC}"

# Capture results back to local machine
RESULTS_DIR="/tmp/phase-13-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

scp -i "$SSH_KEY" -r \
    "$SSH_USER@$HOST_31:/tmp/phase-13-*.log" \
    "$SSH_USER@$HOST_31:/tmp/phase-13-*-report.md" \
    "$RESULTS_DIR/" 2>/dev/null || {
    echo -e "${YELLOW}[!] Some results could not be retrieved${NC}"
}

echo -e "${GREEN}[✓] Results saved to $RESULTS_DIR${NC}"
echo ""

# Step 4: Parse and display summary
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}EXECUTION SUMMARY${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -f "$RESULTS_DIR"/*.log ]; then
    # Extract key metrics from logs
    if grep -q "COMPLETE" "$RESULTS_DIR"/*.log; then
        echo -e "${GREEN}[✓] Phase 13 Day 1: COMPLETED${NC}"
    else
        echo -e "${YELLOW}[!] Phase 13 Day 1: Check logs for details${NC}"
    fi

    # Show notable lines from log
    echo ""
    echo "Key Results:"
    grep "^\[✓\]" "$RESULTS_DIR"/*.log | head -10 || true
    grep "^\[✗\]" "$RESULTS_DIR"/*.log | head -5 || true
fi

echo ""
echo "Detailed logs available at:"
ls -la "$RESULTS_DIR"/ 2>/dev/null | tail -n +2 || echo "  No logs found"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}NEXT STEPS:${NC}"
echo "1. Review execution logs: cat $RESULTS_DIR/*.log"
echo "2. Post results to GitHub Issue #202/#203"
echo "3. Team sign-off and proceed to Day 3 (Security)"
echo ""
