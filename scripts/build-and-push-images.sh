#!/bin/bash

##############################################################################
# Code-Server Enterprise: Build & Push Custom App Images
# Purpose: Build all custom app images and push to private registry
# Registry: registry.kushnir.cloud:5000
# Tag: Git commit SHA or provided tag
# Date: April 30, 2026
##############################################################################

set -euo pipefail

# Configuration
REGISTRY_URL="${REGISTRY_URL:-registry.kushnir.cloud:5000}"
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
IMAGE_TAG="${IMAGE_TAG:-$GIT_SHA}"
APPS_DIR="./apps"

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

# Log start
log_info "Starting custom app image build process"
log_info "Registry: $REGISTRY_URL"
log_info "Tag: $IMAGE_TAG"
log_info "Git SHA: $GIT_SHA"
echo

# Build and push each app
BUILT_COUNT=0
FAILED_APPS=()

for app in "${APPS_TO_BUILD[@]}"; do
  app_path="$APPS_DIR/$app"
  
  if [ ! -d "$app_path" ]; then
    log_warn "App directory not found: $app_path"
    FAILED_APPS+=("$app")
    continue
  fi
  
  if [ ! -f "$app_path/Dockerfile" ]; then
    log_warn "Dockerfile not found for: $app"
    FAILED_APPS+=("$app")
    continue
  fi
  
  # Build image
  image_name="code-server-$app"
  image_full="$REGISTRY_URL/$image_name:$IMAGE_TAG"
  
  log_info "Building: $app"
  if docker build -t "$image_full" "$app_path"; then
    log_success "Built: $image_name"
    ((BUILT_COUNT++))
  else
    log_warn "Failed to build: $app"
    FAILED_APPS+=("$app")
    continue
  fi
  
  # Push image
  log_info "Pushing: $image_name to $REGISTRY_URL"
  if docker push "$image_full"; then
    log_success "Pushed: $image_name:$IMAGE_TAG"
  else
    log_warn "Failed to push: $image_name"
    FAILED_APPS+=("$app")
  fi
  
  echo
done

# Summary
echo
log_info "Build & Push Summary"
log_success "Successfully built and pushed: $BUILT_COUNT/${#APPS_TO_BUILD[@]} images"

if [ ${#FAILED_APPS[@]} -gt 0 ]; then
  log_warn "Failed apps: ${FAILED_APPS[*]}"
  exit 1
else
  log_success "All custom app images built and pushed successfully"
fi
