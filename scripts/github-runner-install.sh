#!/usr/bin/env bash
################################################################################
# GitHub Actions Self-Hosted Runner Installation
# File: scripts/github-runner-install.sh
# Purpose: Download and install GitHub Actions runner on Linux
# Usage: ./scripts/github-runner-install.sh [version]
# Default version: latest stable
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
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

RUNNER_VERSION="${1:-latest}"
RUNNER_HOME="/opt/github-actions-runner"
RUNNER_USER="runner"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"

echo "════════════════════════════════════════════════════════════════════════════"
echo "  GitHub Actions Self-Hosted Runner Installation"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  • Runner Version: ${RUNNER_VERSION}"
echo "  • Installation Dir: ${RUNNER_HOME}"
echo "  • Runner User: ${RUNNER_USER}"
echo "  • GitHub Repo: ${GITHUB_REPO}"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: SYSTEM DEPENDENCIES
# ════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}▸ Phase 1: Installing system dependencies...${NC}"

# Update package lists
sudo apt-get update

# Install required packages
sudo apt-get install -y \
  curl \
  wget \
  git \
  jq \
  build-essential \
  libssl-dev \
  libffi-dev \
  python3-dev \
  docker.io

# Add current user to docker group (for docker operations in runner)
sudo usermod -aG docker "${USER}" || true
echo -e "${GREEN}✓ System dependencies installed${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: CREATE RUNNER USER & HOME DIRECTORY
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 2: Setting up runner user and directories...${NC}"

# Create runner user if it doesn't exist
if ! id "${RUNNER_USER}" &>/dev/null; then
  sudo useradd -m -d "${RUNNER_HOME}" -s /bin/bash "${RUNNER_USER}"
  echo "  ✓ Created runner user: ${RUNNER_USER}"
fi

# Create runner directory
sudo mkdir -p "${RUNNER_HOME}"
sudo chown "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"
sudo chmod 755 "${RUNNER_HOME}"

# Allow runner user to use docker
sudo usermod -aG docker "${RUNNER_USER}" || true

echo -e "${GREEN}✓ Runner user and directories configured${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: DOWNLOAD & INSTALL RUNNER
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 3: Downloading GitHub Actions runner...${NC}"

# Determine architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    RUNNER_ARCH="x64"
    ;;
  aarch64)
    RUNNER_ARCH="arm64"
    ;;
  *)
    echo -e "${RED}✗ Unsupported architecture: ${ARCH}${NC}"
    exit 1
    ;;
esac

# Get latest release version if not specified
if [[ "$RUNNER_VERSION" == "latest" ]]; then
  RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')
fi

RUNNER_FILE="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_FILE}"

echo "  Downloading: ${RUNNER_URL}"
cd "${RUNNER_HOME}"
sudo -u "${RUNNER_USER}" curl -o "${RUNNER_FILE}" -L "${RUNNER_URL}"

if [[ ! -f "${RUNNER_FILE}" ]]; then
  echo -e "${RED}✗ Failed to download runner${NC}"
  exit 1
fi

# Extract runner
echo "  Extracting runner..."
sudo -u "${RUNNER_USER}" tar -xzf "${RUNNER_FILE}"

# Remove archive
rm "${RUNNER_FILE}"

echo -e "${GREEN}✓ Runner downloaded and extracted (v${RUNNER_VERSION})${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4: INSTALL DEPENDENCIES
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 4: Installing runner dependencies...${NC}"

cd "${RUNNER_HOME}"
sudo -u "${RUNNER_USER}" bash ./bin/installdependencies.sh

echo -e "${GREEN}✓ Runner dependencies installed${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 5: CONFIGURATION SUMMARY
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "  INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo ""
echo "1. Register the runner with GitHub:"
echo "   ./scripts/github-runner-register.sh <github-token> <runner-name>"
echo ""
echo "2. Verify runner is ready:"
echo "   ls -la ${RUNNER_HOME}"
echo ""
echo "3. Start runner:"
echo "   cd ${RUNNER_HOME} && ./run.sh"
echo ""
echo "4. Set up as systemd service (auto-start):"
echo "   ./scripts/github-runner-systemd-setup.sh"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓ GitHub Actions runner installation complete${NC}"
