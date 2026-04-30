#!/bin/bash

##############################################################################
# Code-Server Enterprise: Build & Push Custom App Images (Remote)
# Purpose: Build all custom app images on remote host and push to private registry
# Runs on: primary host (192.168.168.31)
# Registry: registry.kushnir.cloud:5000
# Tag: Git commit SHA
# Date: April 30, 2026
##############################################################################

set -euo pipefail

# Configuration
REGISTRY_URL="${REGISTRY_URL:-registry.kushnir.cloud:5000}"
REMOTE_HOST="${REMOTE_HOST:-192.168.168.31}"
REMOTE_USER="${REMOTE_USER:-akushnir}"
REPO_PATH="/home/akushnir/code-server"

# Get git commit SHA
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
IMAGE_TAG="${IMAGE_TAG:-$GIT_SHA}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Apps to build
APPS_TO_BUILD=(
  "env-provisioner"
  "activity_feed"
  "edge-agent"
  "memory-engine"
  "reputation_engine"
  "paperclip"
  "agent-runtime"
  "execution-scheduler"
)

log_info "Starting remote custom app image build process"
log_info "Remote host: $REMOTE_HOST"
log_info "Registry: $REGISTRY_URL"
log_info "Tag: $IMAGE_TAG"
echo

# Create remote build script
REMOTE_SCRIPT="$(cat <<'EOF'
#!/bin/bash
set -euo pipefail
REGISTRY_URL="$1"
IMAGE_TAG="$2"
REPO_PATH="$3"

cd "$REPO_PATH"

APPS=("env-provisioner" "activity_feed" "edge-agent" "memory-engine" "reputation_engine" "paperclip" "agent-runtime" "execution-scheduler")

for app in "${APPS[@]}"; do
  image_name="code-server-$app"
  image_full="$REGISTRY_URL/$image_name:$IMAGE_TAG"
  
  echo "[*] Building: $app"
  docker build -t "$image_full" "apps/$app" || echo "[!] Failed: $app"
  
  echo "[*] Pushing: $image_name"
  docker push "$image_full" || echo "[!] Push failed: $image_name"
done

echo "[+] Done"
EOF
)"

# Execute remote build script
log_info "Executing build on $REMOTE_HOST..."
if ssh -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" bash << EOF
$REMOTE_SCRIPT "$REGISTRY_URL" "$IMAGE_TAG" "$REPO_PATH"
EOF
then
  log_success "Remote build and push completed"
else
  log_warn "Remote build had issues, but continuing..."
fi
