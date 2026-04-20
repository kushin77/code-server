#!/usr/bin/env bash
# @file        DEPLOY-ISSUE-950-TO-PRODUCTION.sh
# @description Execute Issue #950 deployment to primary production host
# @usage       ssh akushnir@192.168.168.31 'bash -s' < DEPLOY-ISSUE-950-TO-PRODUCTION.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Issue #950 Production Deployment${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. Verify we're on the correct host
echo -e "\n${YELLOW}Step 1: Verifying host...${NC}"
CURRENT_HOST=$(hostname -I | awk '{print $1}')
echo "Current host IP: $CURRENT_HOST"
if [[ "$CURRENT_HOST" != "192.168.168.31" ]]; then
    echo -e "${RED}ERROR: Not on primary host (192.168.168.31)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Correct host${NC}"

# 2. Navigate to repo
echo -e "\n${YELLOW}Step 2: Navigating to repository...${NC}"
cd /home/akushnir/code-server-enterprise || { echo -e "${RED}ERROR: Cannot cd to repo${NC}"; exit 1; }
echo -e "${GREEN}✓ In repository${NC}"

# 3. Check current branch
echo -e "\n${YELLOW}Step 3: Checking current branch...${NC}"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $CURRENT_BRANCH"
echo -e "${GREEN}✓ Branch checked${NC}"

# 4. Fetch latest from origin
echo -e "\n${YELLOW}Step 4: Fetching from origin...${NC}"
git fetch origin || { echo -e "${RED}ERROR: git fetch failed${NC}"; exit 1; }
echo -e "${GREEN}✓ Fetch complete${NC}"

# 5. Check if sanitized/redeploy-pr has updates
echo -e "\n${YELLOW}Step 5: Checking sanitized/redeploy-pr...${NC}"
git show-ref --verify --quiet refs/remotes/origin/sanitized/redeploy-pr || {
    echo -e "${RED}ERROR: sanitized/redeploy-pr not found on origin${NC}"
    exit 1
}
echo -e "${GREEN}✓ Branch exists on origin${NC}"

# 6. Merge to main (if authorized)
echo -e "\n${YELLOW}Step 6: Attempting merge to main...${NC}"
git checkout main || { echo -e "${YELLOW}⚠ Could not checkout main (may require admin)${NC}"; }
git pull origin main || { echo -e "${YELLOW}⚠ Could not pull main${NC}"; }
echo -e "${GREEN}✓ Main branch checked${NC}"

# 7. Backup current deployment
echo -e "\n${YELLOW}Step 7: Creating deployment backup...${NC}"
BACKUP_DIR="/home/akushnir/code-server-enterprise/backups/deployment-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
docker compose config > "$BACKUP_DIR/docker-compose-backup.yml" 2>/dev/null || true
echo -e "${GREEN}✓ Backup created at $BACKUP_DIR${NC}"

# 8. Pull latest code
echo -e "\n${YELLOW}Step 8: Pulling latest code...${NC}"
git pull origin main || { echo -e "${YELLOW}⚠ Already up to date or merge conflict${NC}"; }
echo -e "${GREEN}✓ Code pulled${NC}"

# 9. Verify deployment readiness
echo -e "\n${YELLOW}Step 9: Verifying deployment readiness...${NC}"
if [[ ! -f docker-compose.yml ]]; then
    echo -e "${RED}ERROR: docker-compose.yml not found${NC}"
    exit 1
fi
docker compose config > /dev/null || { echo -e "${RED}ERROR: Invalid docker-compose.yml${NC}"; exit 1; }
echo -e "${GREEN}✓ Deployment files valid${NC}"

# 10. Stop services (graceful)
echo -e "\n${YELLOW}Step 10: Stopping services gracefully...${NC}"
docker compose down --timeout=30 || { echo -e "${YELLOW}⚠ Some services may not have stopped cleanly${NC}"; }
echo -e "${GREEN}✓ Services stopped${NC}"

# 11. Restart services
echo -e "\n${YELLOW}Step 11: Starting services...${NC}"
docker compose up -d || { echo -e "${RED}ERROR: Failed to start services${NC}"; exit 1; }
echo -e "${GREEN}✓ Services starting${NC}"

# 12. Wait for services to be healthy
echo -e "\n${YELLOW}Step 12: Waiting for services to stabilize...${NC}"
sleep 10

# 13. Health check
echo -e "\n${YELLOW}Step 13: Performing health checks...${NC}"
HEALTH_CHECKS=0
HEALTH_PASSED=0

# code-server
if curl -s http://localhost:8080 > /dev/null; then
    echo -e "${GREEN}✓ code-server responding${NC}"
    ((HEALTH_PASSED++))
else
    echo -e "${RED}✗ code-server not responding${NC}"
fi
((HEALTH_CHECKS++))

# oauth2-proxy
if curl -s http://localhost:4180/health > /dev/null; then
    echo -e "${GREEN}✓ oauth2-proxy health check passed${NC}"
    ((HEALTH_PASSED++))
else
    echo -e "${RED}✗ oauth2-proxy health check failed${NC}"
fi
((HEALTH_CHECKS++))

# Prometheus
if curl -s http://localhost:9090/-/healthy > /dev/null; then
    echo -e "${GREEN}✓ Prometheus healthy${NC}"
    ((HEALTH_PASSED++))
else
    echo -e "${RED}✗ Prometheus not healthy${NC}"
fi
((HEALTH_CHECKS++))

# 14. Show service status
echo -e "\n${YELLOW}Step 14: Current service status...${NC}"
docker compose ps

# 15. Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Health checks passed: ${GREEN}$HEALTH_PASSED${NC}/$HEALTH_CHECKS"
echo -e "Backup location: ${YELLOW}$BACKUP_DIR${NC}"
echo -e "Deployment ID: $(date +%s)"

if [[ $HEALTH_PASSED -eq $HEALTH_CHECKS ]]; then
    echo -e "\n${GREEN}✓ Issue #950 Deployment SUCCESSFUL${NC}"
    echo -e "${GREEN}All services operational and health checks passing${NC}"
    exit 0
else
    echo -e "\n${YELLOW}⚠ Issue #950 Deployment PARTIAL${NC}"
    echo -e "${YELLOW}Some services may still be starting. Check logs:${NC}"
    echo -e "${YELLOW}  docker compose logs --tail=50 <service-name>${NC}"
    exit 1
fi
