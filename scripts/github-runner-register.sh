#!/usr/bin/env bash
################################################################################
# GitHub Actions Self-Hosted Runner Registration
# File: scripts/github-runner-register.sh
# Purpose: Register GitHub Actions runner with GitHub and start it
# Usage: ./scripts/github-runner-register.sh <github-token> [runner-name] [labels]
# Example: ./scripts/github-runner-register.sh ghp_xxxx code-server-primary "on-prem,production,docker"
# Owner: Infrastructure Team
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION & VALIDATION
# ════════════════════════════════════════════════════════════════════════════

if [[ $# -lt 1 ]]; then
  echo -e "${RED}✗ Usage: $0 <github-token> [runner-name] [labels]${NC}"
  echo ""
  echo "Arguments:"
  echo "  github-token: GitHub Personal Access Token (classic) or fine-grained token"
  echo "               Must have: repo, workflow, admin:org_hook scopes"
  echo "  runner-name:  (optional) Name for this runner (default: hostname)"
  echo "  labels:       (optional) Comma-separated labels (default: on-prem,production)"
  exit 1
fi

GITHUB_TOKEN="$1"
RUNNER_NAME="${2:-$(hostname)}"
RUNNER_LABELS="${3:-on-prem,production,docker}"
RUNNER_HOME="/opt/github-actions-runner"
RUNNER_USER="runner"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
GITHUB_OWNER=$(echo "${GITHUB_REPO}" | cut -d/ -f1)

echo "════════════════════════════════════════════════════════════════════════════"
echo "  GitHub Actions Runner Registration"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  • Repository: ${GITHUB_REPO}"
echo "  • Runner Name: ${RUNNER_NAME}"
echo "  • Runner Labels: ${RUNNER_LABELS}"
echo "  • Installation Dir: ${RUNNER_HOME}"
echo "  • Runner User: ${RUNNER_USER}"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: VALIDATE TOKEN & REPOSITORY ACCESS
# ════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}▸ Phase 1: Validating GitHub token and repository access...${NC}"

# Test token by checking user info
GITHUB_USER=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  https://api.github.com/user | jq -r '.login')

if [[ -z "$GITHUB_USER" || "$GITHUB_USER" == "null" ]]; then
  echo -e "${RED}✗ Invalid GitHub token - cannot authenticate${NC}"
  exit 1
fi

echo "  Authenticated as: ${GITHUB_USER}"

# Check if user has access to repository
REPO_ACCESS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  https://api.github.com/repos/${GITHUB_REPO} | jq -r '.name')

if [[ -z "$REPO_ACCESS" || "$REPO_ACCESS" == "null" ]]; then
  echo -e "${RED}✗ No access to repository ${GITHUB_REPO}${NC}"
  exit 1
fi

echo "  Repository access confirmed: ${GITHUB_REPO}"
echo -e "${GREEN}✓ Token validation passed${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: CONFIGURE RUNNER
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 2: Configuring runner...${NC}"

cd "${RUNNER_HOME}"

# Create registration token (expires in 1 hour)
echo "  Getting registration token..."
REGISTRATION_TOKEN=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token \
  | jq -r '.token')

if [[ -z "$REGISTRATION_TOKEN" || "$REGISTRATION_TOKEN" == "null" ]]; then
  echo -e "${RED}✗ Failed to get registration token${NC}"
  exit 1
fi

echo "  Registration token obtained (valid for 1 hour)"

# Run configuration with non-interactive mode
echo "  Configuring runner..."
sudo -u "${RUNNER_USER}" ./config.sh \
  --url "https://github.com/${GITHUB_REPO}" \
  --token "${REGISTRATION_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --work "_work" \
  --replace \
  --unattended

echo -e "${GREEN}✓ Runner configured${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: VERIFY REGISTRATION
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 3: Verifying runner registration...${NC}"

# Check if runner is registered
REGISTERED_RUNNERS=$(curl -s \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/${GITHUB_REPO}/actions/runners \
  | jq -r '.runners[] | .name')

if echo "${REGISTERED_RUNNERS}" | grep -q "^${RUNNER_NAME}$"; then
  echo "  ✓ Runner registered: ${RUNNER_NAME}"
  echo -e "${GREEN}✓ Runner successfully registered with GitHub${NC}"
else
  echo -e "${YELLOW}⚠ Runner may not appear immediately - GitHub updates every 30s${NC}"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4: NEXT STEPS
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "  RUNNER REGISTRATION COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo ""
echo "1. Start the runner manually (for testing):"
echo "   cd ${RUNNER_HOME}"
echo "   sudo -u ${RUNNER_USER} ./run.sh"
echo ""
echo "2. Set up as systemd service (auto-start on boot):"
echo "   ./scripts/github-runner-systemd-setup.sh"
echo ""
echo "3. View runner in GitHub:"
echo "   https://github.com/${GITHUB_REPO}/settings/actions/runners"
echo ""
echo "4. Runner will show as 'idle' once started"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓ Runner registration complete${NC}"
