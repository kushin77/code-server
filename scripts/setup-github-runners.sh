#!/bin/bash
# Setup GitHub Actions Self-Hosted Runners on Primary and Replica Hosts
# P1 #416 - GitHub Actions deploy.yml fix
# 
# Usage: bash scripts/setup-github-runners.sh <github-token> <owner> <repo>
# 
# This script registers self-hosted runners on .31 and .42 for:
# - Terraform deployments
# - Docker Compose management
# - Production validations

set -euo pipefail

GITHUB_TOKEN="${1:-}"
GITHUB_OWNER="${2:-kushin77}"
GITHUB_REPO="${3:-code-server-enterprise}"
RUNNER_VERSION="2.315.0"

if [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ Error: GitHub token required"
  echo "Usage: $0 <github-token> [owner] [repo]"
  exit 1
fi

PRIMARY_HOST="192.168.168.31"
PRIMARY_USER="akushnir"
REPLICA_HOST="192.168.168.42"
REPLICA_USER="akushnir"

echo "═══════════════════════════════════════════════════════════════"
echo "GitHub Actions Runner Setup - On-Prem Infrastructure"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Target hosts:"
echo "  Primary: ssh://${PRIMARY_USER}@${PRIMARY_HOST}"
echo "  Replica: ssh://${REPLICA_USER}@${REPLICA_HOST}"
echo ""

# Function to setup runner on a single host
setup_runner_on_host() {
  local HOST=$1
  local USER=$2
  local ROLE=$3  # "primary" or "replica"
  local RUNNER_NAME="${ROLE}-runner"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Setting up ${ROLE} runner on ${HOST}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  ssh -o StrictHostKeyChecking=accept-new "${USER}@${HOST}" bash -s <<'RUNNER_SCRIPT'
set -euo pipefail

GITHUB_TOKEN=$1
GITHUB_OWNER=$2
GITHUB_REPO=$3
RUNNER_VERSION=$4
RUNNER_NAME=$5
RUNNER_LABELS=$6

RUNNER_HOME="/home/${USER}/github-runner"
RUNNER_DIR="${RUNNER_HOME}/${RUNNER_NAME}"

echo "Creating runner directory: ${RUNNER_DIR}"
mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

echo "Downloading runner v${RUNNER_VERSION}..."
if [ ! -f "runner-${RUNNER_VERSION}.tar.gz" ]; then
  curl -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    -o "runner-${RUNNER_VERSION}.tar.gz"
fi

echo "Extracting runner..."
tar xzf "runner-${RUNNER_VERSION}.tar.gz"
rm -f "runner-${RUNNER_VERSION}.tar.gz"

echo "Configuring runner..."
./config.sh \
  --url "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
  --token "${GITHUB_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --runnergroup "Default" \
  --unattended

echo "Installing runner service..."
sudo ./svc.sh install

echo "Starting runner service..."
sudo ./svc.sh start

echo "Verifying runner status..."
sleep 3
sudo ./svc.sh status

echo "✅ Runner ${RUNNER_NAME} successfully configured and started"
RUNNER_SCRIPT
  
  set +e
  ssh -o StrictHostKeyChecking=accept-new "${USER}@${HOST}" \
    "GITHUB_TOKEN='${GITHUB_TOKEN}' GITHUB_OWNER='${GITHUB_OWNER}' GITHUB_REPO='${GITHUB_REPO}' RUNNER_VERSION='${RUNNER_VERSION}' RUNNER_NAME='${RUNNER_NAME}' RUNNER_LABELS='on-prem,${ROLE}' bash -s" <<<"${RUNNER_SCRIPT}"
  set -e
}

# Setup primary runner
echo ""
echo "Step 1/2: Setting up PRIMARY runner (.31)..."
setup_runner_on_host "${PRIMARY_HOST}" "${PRIMARY_USER}" "primary"

# Setup replica runner
echo ""
echo "Step 2/2: Setting up REPLICA runner (.42)..."
setup_runner_on_host "${REPLICA_HOST}" "${REPLICA_USER}" "replica"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ All runners successfully configured"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Verify runners at: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/actions/runners"
echo ""
echo "Deploy workflow will now execute on self-hosted runners:"
echo "  Primary:  [self-hosted, on-prem, primary]"
echo "  Replica:  [self-hosted, on-prem, replica]"
