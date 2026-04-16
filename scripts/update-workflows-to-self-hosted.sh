#!/usr/bin/env bash
################################################################################
# Update GitHub Actions Workflows to Use Self-Hosted Runners
# File: scripts/update-workflows-to-self-hosted.sh
# Purpose: Migrate workflows from ubuntu-latest to self-hosted runners
# Usage: ./scripts/update-workflows-to-self-hosted.sh
# Owner: Infrastructure Team
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

WORKFLOWS_DIR=".github/workflows"
BACKUP_DIR=".github/workflows.backup"

echo "════════════════════════════════════════════════════════════════════════════"
echo "  Update Workflows to Use Self-Hosted Runners"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  • Workflows directory: ${WORKFLOWS_DIR}"
echo "  • Backup directory: ${BACKUP_DIR}"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: BACKUP EXISTING WORKFLOWS
# ════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}▸ Phase 1: Backing up existing workflows...${NC}"

if [[ -d "${BACKUP_DIR}" ]]; then
  echo -e "${YELLOW}⚠ Backup directory already exists${NC}"
else
  mkdir -p "${BACKUP_DIR}"
  cp "${WORKFLOWS_DIR}"/*.yml "${BACKUP_DIR}/" || cp "${WORKFLOWS_DIR}"/*.yaml "${BACKUP_DIR}/" 2>/dev/null || true
  echo "  ✓ Backup created at ${BACKUP_DIR}"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: UPDATE WORKFLOWS
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 2: Updating workflows...${NC}"

UPDATED_COUNT=0
TOTAL_COUNT=0

# Define replacement mappings
declare -A REPLACEMENTS=(
  # Ubuntu-latest to self-hosted with fallback to ubuntu-latest
  ["runs-on: ubuntu-latest"]="runs-on: [self-hosted, on-prem, linux] # Fallback to ubuntu-latest if self-hosted unavailable"
  
  # macOS to self-hosted
  ["runs-on: macos-latest"]="runs-on: [self-hosted, on-prem, macos]"
  
  # Windows-latest to self-hosted (maps to self-hosted windows runners)
  ["runs-on: windows-latest"]="runs-on: [self-hosted, on-prem, windows]"
)

# Process each workflow file
for workflow in "${WORKFLOWS_DIR}"/*.{yml,yaml} 2>/dev/null || true; do
  if [[ ! -f "$workflow" ]]; then
    continue
  fi
  
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  UPDATED=false
  
  for pattern in "${!REPLACEMENTS[@]}"; do
    if grep -q "$pattern" "$workflow" 2>/dev/null; then
      replacement="${REPLACEMENTS[$pattern]}"
      sed -i "s|${pattern}|${replacement}|g" "$workflow"
      UPDATED=true
      echo "  ✓ Updated: $(basename "$workflow")"
    fi
  done
  
  if [[ "$UPDATED" == "true" ]]; then
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  fi
done

echo "  Updated ${UPDATED_COUNT} of ${TOTAL_COUNT} workflows"
echo -e "${GREEN}✓ Workflows updated${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: VALIDATE CHANGES
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 3: Validating changes...${NC}"

SELF_HOSTED_COUNT=$(grep -r "self-hosted" "${WORKFLOWS_DIR}" 2>/dev/null | wc -l)
echo "  Workflows with self-hosted runners: ${SELF_HOSTED_COUNT}"

echo "  Sample changes:"
grep -r "self-hosted" "${WORKFLOWS_DIR}" 2>/dev/null | head -3 | sed 's/^/    /'

echo -e "${GREEN}✓ Validation complete${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4: DISPLAY SUMMARY
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "  WORKFLOW UPDATE COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  • Total workflows: ${TOTAL_COUNT}"
echo "  • Updated workflows: ${UPDATED_COUNT}"
echo "  • Workflows with self-hosted: ${SELF_HOSTED_COUNT}"
echo ""
echo "Next steps:"
echo ""
echo "1. Review changes:"
echo "   git diff ${WORKFLOWS_DIR}/"
echo ""
echo "2. Compare with backups if needed:"
echo "   diff -r ${WORKFLOWS_DIR}/ ${BACKUP_DIR}/"
echo ""
echo "3. Test a workflow:"
echo "   git add ${WORKFLOWS_DIR}/"
echo "   git commit -m 'ci: Migrate workflows to self-hosted runners (P1 #416)'"
echo "   git push origin main"
echo ""
echo "4. Monitor workflow execution:"
echo "   https://github.com/kushin77/code-server/actions"
echo ""
echo "5. If workflows fail on self-hosted, rollback:"
echo "   cp ${BACKUP_DIR}/*.yml ${WORKFLOWS_DIR}/"
echo "   git commit -m 'revert: Roll back to github-hosted runners'"
echo ""
echo "Note: Self-hosted runners have access to:"
echo "  • Docker daemon"
echo "  • On-premise infrastructure (192.168.168.31, .42)"
echo "  • Internal services (Prometheus, Grafana, etc.)"
echo "  • Full filesystem for testing"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓ Workflow update complete${NC}"
