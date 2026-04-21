#!/bin/bash
# @file        DEPLOYMENT-READY-VERIFICATION.sh
# @module      verification
# @description Final verification that all systems are ready for #984 deployment upon Issue #983 completion

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   DEPLOYMENT READY VERIFICATION - Issue #984${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

READY=0
ISSUES=0

# Check 1: All deployment scripts present
echo -e "${BLUE}[1]${NC} Checking deployment scripts..."
REQUIRED_SCRIPTS=(
    "ISSUE-984-ORCHESTRATOR.sh"
    "ISSUE-984-PRE-DEPLOYMENT-VERIFICATION.sh"
    "ISSUE-984-POST-DEPLOYMENT-VERIFICATION.sh"
    "ISSUE-984-ROLLBACK-PROCEDURE.sh"
    "MONITOR-ISSUE-983.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ] && [ -x "$SCRIPT_DIR/$script" ]; then
        echo -e "    ${GREEN}✓${NC} $script (executable)"
        ((READY++))
    else
        echo -e "    ${RED}✗${NC} $script (missing or not executable)"
        ((ISSUES++))
    fi
done

# Check 2: Core services running
echo ""
echo -e "${BLUE}[2]${NC} Checking core services..."
SERVICES=("code-server" "postgres" "redis" "caddy")

for service in "${SERVICES[@]}"; do
    if docker ps | grep -q "$service"; then
        echo -e "    ${GREEN}✓${NC} $service (running)"
        ((READY++))
    else
        echo -e "    ${RED}✗${NC} $service (not running)"
        ((ISSUES++))
    fi
done

# Check 3: Terraform ready
echo ""
echo -e "${BLUE}[3]${NC} Checking Terraform..."
if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version | grep Terraform | head -1)
    echo -e "    ${GREEN}✓${NC} Terraform installed: $TF_VERSION"
    ((READY++))
else
    echo -e "    ${RED}✗${NC} Terraform not found"
    ((ISSUES++))
fi

# Check 4: Git state
echo ""
echo -e "${BLUE}[4]${NC} Checking Git repository..."
if git -C "$SCRIPT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    COMMITS_AHEAD=$(git -C "$SCRIPT_DIR" rev-list --count origin/main..HEAD 2>/dev/null || echo "N/A")
    if [ "$(git -C "$SCRIPT_DIR" status --short)" == "" ]; then
        echo -e "    ${GREEN}✓${NC} Git working tree clean ($COMMITS_AHEAD commits ahead)"
        ((READY++))
    else
        echo -e "    ${YELLOW}⚠${NC}  Git working tree has changes"
    fi
else
    echo -e "    ${RED}✗${NC} Not a Git repository"
    ((ISSUES++))
fi

# Check 5: Configuration files
echo ""
echo -e "${BLUE}[5]${NC} Checking configuration files..."
CONFIG_FILES=(
    ".env"
    "docker-compose.yml"
    "terraform/main.tf"
)

for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        echo -e "    ${GREEN}✓${NC} $file"
        ((READY++))
    else
        echo -e "    ${RED}✗${NC} $file (missing)"
        ((ISSUES++))
    fi
done

# Check 6: Documentation
echo ""
echo -e "${BLUE}[6]${NC} Checking documentation..."
DOCS=(
    "ISSUE-984-QUICK-EXECUTION.md"
    "ISSUE-984-PRODUCTION-READY-CHECKLIST.md"
    "COMPLETE-DEPLOYMENT-AND-OPERATIONS-PLAYBOOK.md"
    "E2E-TESTS-EXECUTION-FRAMEWORK.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$SCRIPT_DIR/$doc" ]; then
        echo -e "    ${GREEN}✓${NC} $doc"
        ((READY++))
    else
        echo -e "    ${YELLOW}⚠${NC}  $doc (missing locally)"
    fi
done

# Check 7: Network connectivity
echo ""
echo -e "${BLUE}[7]${NC} Checking network connectivity..."
if ping -c 1 8.8.8.8 &> /dev/null; then
    echo -e "    ${GREEN}✓${NC} Internet connectivity"
    ((READY++))
else
    echo -e "    ${YELLOW}⚠${NC}  Internet unreachable"
fi

# Check 8: Docker daemon
echo ""
echo -e "${BLUE}[8]${NC} Checking Docker daemon..."
if docker ps &> /dev/null; then
    echo -e "    ${GREEN}✓${NC} Docker daemon responsive"
    ((READY++))
else
    echo -e "    ${RED}✗${NC} Docker daemon not accessible"
    ((ISSUES++))
fi

# Summary
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}VERIFICATION SUMMARY${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Checks Passed: ${GREEN}$READY${NC}"
echo -e "Issues Found: ${RED}$ISSUES${NC}"
echo ""

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✅ ALL SYSTEMS READY FOR DEPLOYMENT${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Verify Issue #983 is CLOSED (QA user created)"
    echo "2. Run: bash ISSUE-984-ORCHESTRATOR.sh"
    echo "3. Monitor deployment (40-50 minutes)"
    echo "4. Post-deployment verification will run automatically"
    echo "5. E2E tests will execute if enabled"
    echo ""
    exit 0
else
    echo -e "${RED}⚠️  ISSUES DETECTED - RESOLVE BEFORE DEPLOYMENT${NC}"
    echo ""
    echo "Failed checks must be resolved:"
    echo "- Missing scripts: Copy from local workspace to production"
    echo "- Stopped services: Run 'docker compose up -d'"
    echo "- Configuration: Verify .env and docker-compose.yml"
    echo ""
    exit 1
fi
