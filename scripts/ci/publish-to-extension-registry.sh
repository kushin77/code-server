#!/usr/bin/env bash
# @file        scripts/ci/publish-to-extension-registry.sh
# @module      ci/registry
# @description Publishes VS Code extensions to kushnir.cloud private registry (Issue #1047)
#
# Usage:
#   publish-to-extension-registry.sh --extension-path ./extensions/my-ext.vsix --version 1.0.0
#   publish-to-extension-registry.sh --publisher kushin77 --name my-extension --version 1.0.0
#
# Requires:
#   - REGISTRY_URL environment variable (defaults to https://registry.kushnir.cloud)
#   - REGISTRY_AUTH_TOKEN environment variable (or fetch from GSM)
#   - Extension file (.vsix) or package.json + manifest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ── Configuration ────────────────────────────────────────────────────────────

REGISTRY_URL="${REGISTRY_URL:-https://registry.kushnir.cloud}"
REGISTRY_AUTH_TOKEN="${REGISTRY_AUTH_TOKEN:-}"
EXTENSION_PATH=""
PUBLISHER=""
EXTENSION_NAME=""
VERSION=""
DRY_RUN=false

# ── Parse arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-path)
      EXTENSION_PATH="$2"
      shift 2
      ;;
    --publisher)
      PUBLISHER="$2"
      shift 2
      ;;
    --name)
      EXTENSION_NAME="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --registry-url)
      REGISTRY_URL="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ── Validation ───────────────────────────────────────────────────────────────

if [[ -z "$REGISTRY_AUTH_TOKEN" ]]; then
  log_info "REGISTRY_AUTH_TOKEN not provided, attempting to fetch from GSM..."
  REGISTRY_AUTH_TOKEN="$(gcloud secrets versions access latest --secret="registry-auth-token" 2>/dev/null || echo "")"
  if [[ -z "$REGISTRY_AUTH_TOKEN" ]]; then
    log_fatal "REGISTRY_AUTH_TOKEN not found and GSM fetch failed"
  fi
fi

if [[ -n "$EXTENSION_PATH" ]]; then
  if [[ ! -f "$EXTENSION_PATH" ]]; then
    log_fatal "Extension file not found: $EXTENSION_PATH"
  fi
  log_info "Publishing extension from file: $EXTENSION_PATH"
  PUBLISHER=$(basename "$EXTENSION_PATH" .vsix | awk -F'-' '{print $1}')
  EXTENSION_NAME=$(basename "$EXTENSION_PATH" .vsix | awk -F'-' '{print $2}')
  VERSION=$(basename "$EXTENSION_PATH" .vsix | awk -F'-' '{print $3}')
else
  if [[ -z "$PUBLISHER" || -z "$EXTENSION_NAME" || -z "$VERSION" ]]; then
    log_fatal "Missing required arguments: --publisher, --name, and --version are required when not using --extension-path"
  fi
fi

log_info "Publishing extension: $PUBLISHER.$EXTENSION_NAME@$VERSION"

# ── Publish to registry ──────────────────────────────────────────────────────

UPLOAD_URL="$REGISTRY_URL/api/extensions/$PUBLISHER/$EXTENSION_NAME/versions/$VERSION"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY-RUN] Would upload to: $UPLOAD_URL"
  log_info "[DRY-RUN] Extension file: $EXTENSION_PATH"
  exit 0
fi

log_info "Uploading to registry: $UPLOAD_URL"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $REGISTRY_AUTH_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  -F "file=@$EXTENSION_PATH" \
  "$UPLOAD_URL")

if echo "$RESPONSE" | grep -q '"success":\s*true'; then
  log_info "✅ Extension published successfully: $PUBLISHER.$EXTENSION_NAME@$VERSION"
  exit 0
else
  log_error "❌ Failed to publish extension"
  log_error "Response: $RESPONSE"
  exit 1
fi
