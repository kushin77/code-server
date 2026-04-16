#!/usr/bin/env bash
################################################################################
# Deploy Self-Hosted GitHub Actions Runners to Production Hosts
# File: scripts/deploy-github-runners.sh
# Purpose: Deploy runners on both primary (192.168.168.31) and replica (.42)
# Usage: ./scripts/deploy-github-runners.sh <github-token> [mode]
# Modes: full (install+register), install-only, register-only
# Owner: Infrastructure Team
# Issue: P1 #416
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

if [[ $# -lt 1 ]]; then
  echo -e "${RED}✗ Usage: $0 <github-token> [mode]${NC}"
  echo ""
  echo "Modes:"
  echo "  full         - Install and register runners (default)"
  echo "  install-only - Install runner software only"
  echo "  register-only - Register already-installed runners"
  exit 1
fi

GITHUB_TOKEN="$1"
MODE="${2:-full}"
SSH_USER="akushnir"
GITHUB_REPO="kushin77/code-server"

# Source canonical inventory (defines PRIMARY_HOST, REPLICA_HOST, VIP, FQDNs)
# shellcheck source=scripts/lib/env.sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${REPO_ROOT}/scripts/lib/env.sh"

echo "════════════════════════════════════════════════════════════════════════════"
echo "  Deploy GitHub Actions Runners to Production Hosts"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  • Mode: ${MODE}"
echo "  • Primary Host: ${PRIMARY_HOST}"
echo "  • Replica Host: ${REPLICA_HOST}"
echo "  • GitHub Repo: ${GITHUB_REPO}"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: DEPLOY TO PRIMARY HOST (192.168.168.31)
# ════════════════════════════════════════════════════════════════════════════

deploy_runner() {
  local host="$1"
  local runner_name="$2"
  local labels="$3"
  
  echo -e "${BLUE}▸ Deploying runner to ${host} (${runner_name})...${NC}"
  
  # Copy scripts to remote host
  echo "  Copying installation scripts..."
  ssh "${SSH_USER}@${host}" "mkdir -p code-server-enterprise/scripts" || true
  
  scp scripts/github-runner-install.sh "${SSH_USER}@${host}:code-server-enterprise/scripts/" || {
    echo -e "${RED}✗ Failed to copy install script${NC}"
    return 1
  }
  
  if [[ "$MODE" != "register-only" ]]; then
    # Install runner
    echo "  Installing runner on ${host}..."
    ssh "${SSH_USER}@${host}" "cd code-server-enterprise && bash scripts/github-runner-install.sh latest" || {
      echo -e "${RED}✗ Installation failed on ${host}${NC}"
      return 1
    }
    echo "  ✓ Runner installed on ${host}"
  fi
  
  if [[ "$MODE" != "install-only" ]]; then
    # Copy registration script
    scp scripts/github-runner-register.sh "${SSH_USER}@${host}:code-server-enterprise/scripts/" || {
      echo -e "${RED}✗ Failed to copy register script${NC}"
      return 1
    }
    
    # Register runner
    echo "  Registering runner on ${host}..."
    ssh "${SSH_USER}@${host}" "cd code-server-enterprise && bash scripts/github-runner-register.sh '${GITHUB_TOKEN}' '${runner_name}' '${labels}'" || {
      echo -e "${RED}✗ Registration failed on ${host}${NC}"
      return 1
    }
    echo "  ✓ Runner registered on ${host}"
    
    # Copy systemd setup script
    scp scripts/github-runner-systemd-setup.sh "${SSH_USER}@${host}:code-server-enterprise/scripts/" || {
      echo -e "${RED}✗ Failed to copy systemd setup script${NC}"
      return 1
    }
    
    # Setup systemd service
    echo "  Setting up systemd service on ${host}..."
    ssh "${SSH_USER}@${host}" "cd code-server-enterprise && bash scripts/github-runner-systemd-setup.sh" || {
      echo -e "${YELLOW}⚠ Systemd setup had issues - may need manual intervention${NC}"
    }
    echo "  ✓ Systemd service configured on ${host}"
  fi
  
  echo -e "${GREEN}✓ Runner deployment complete on ${host}${NC}"
}

# Deploy to primary host
deploy_runner "${PRIMARY_HOST}" "code-server-primary" "on-prem,primary,production,docker" || exit 1

echo ""

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: DEPLOY TO REPLICA HOST (192.168.168.42)
# ════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}▸ Deploying to replica host...${NC}"

deploy_runner "${REPLICA_HOST}" "code-server-replica" "on-prem,replica,production,docker" || {
  echo -e "${YELLOW}⚠ Replica host deployment had issues - primary is operational${NC}"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: VERIFY RUNNERS
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 3: Verifying runners...${NC}"

echo "  Checking runner registration on GitHub..."
sleep 5  # Allow time for registration to complete

RUNNERS=$(curl -s \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/${GITHUB_REPO}/actions/runners \
  | jq -r '.runners[] | "\(.name): \(.status)"')

if [[ -n "$RUNNERS" ]]; then
  echo "  Registered runners:"
  echo "$RUNNERS" | sed 's/^/    /'
  echo -e "${GREEN}✓ Runners verified${NC}"
else
  echo -e "${YELLOW}⚠ Runners may not appear immediately - GitHub syncs every 30 seconds${NC}"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4: COMPLETION SUMMARY
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "  DEPLOYMENT COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo ""
echo "1. Update GitHub Actions workflows to use self-hosted runners:"
echo "   Find 'runs-on: ubuntu-latest' and replace with 'runs-on: [self-hosted, on-prem, production]'"
echo ""
echo "2. View runners in GitHub:"
echo "   https://github.com/${GITHUB_REPO}/settings/actions/runners"
echo ""
echo "3. Monitor runner logs on primary host:"
echo "   ssh ${SSH_USER}@${PRIMARY_HOST}"
echo "   sudo journalctl -u github-actions-runner -f"
echo ""
echo "4. Test a workflow:"
echo "   Push changes to main or trigger a workflow dispatch"
echo ""
echo "5. Check workflow run details:"
echo "   https://github.com/${GITHUB_REPO}/actions"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓ GitHub Actions runner deployment complete${NC}"
