#!/usr/bin/env bash
# @file        scripts/air-gapped/load-images.sh
# @module      air-gapped/image-management
# @description Load pre-saved container images into Docker on air-gapped host
#
# Usage:
#   bash scripts/air-gapped/load-images.sh /path/to/images/
#
# This script runs on the air-gapped host to load images that were previously
# saved from pre-load-images.sh. No internet access required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/logging.sh" || {
  echo "ERROR: Cannot source logging.sh" >&2
  exit 1
}

# ────────────────────────────────────────────────────────────────────────────
# Load all images from directory
# ────────────────────────────────────────────────────────────────────────────
main() {
  local image_dir="${1:?Image directory required}"
  
  if [[ ! -d "$image_dir" ]]; then
    log_error "Image directory not found: $image_dir"
    exit 1
  fi
  
  log_info "========================================================================"
  log_info "Loading Images from Air-Gapped Storage"
  log_info "========================================================================"
  log_info "Source directory: $image_dir"
  log_info ""
  
  # Check for .tar.gz files
  local images=()
  mapfile -t images < <(find "$image_dir" -maxdepth 1 -name "*.tar.gz" | sort)
  
  if [[ ${#images[@]} -eq 0 ]]; then
    log_error "No .tar.gz image files found in: $image_dir"
    exit 1
  fi
  
  log_info "Found ${#images[@]} image(s) to load"
  log_info ""
  
  local loaded=0
  local failed=0
  
  for image_file in "${images[@]}"; do
    local image_name
    image_name=$(basename "$image_file")
    
    log_info "Loading: $image_name"
    
    if gunzip -c "$image_file" | docker load 2>&1 | tail -5; then
      ((loaded++))
      log_info "✓ Loaded: $image_name"
    else
      log_error "✗ Failed to load: $image_name"
      ((failed++))
    fi
    
    log_info ""
  done
  
  log_info "========================================================================"
  log_info "Load Complete: $loaded loaded, $failed failed"
  log_info "========================================================================"
  
  # Verify all images are now present
  log_info ""
  log_info "Verifying loaded images:"
  docker images | grep -E "code-server|ollama|postgres|redis|synapse|element-web|caddy|prometheus|grafana|alertmanager" || true
  
  if [[ $failed -gt 0 ]]; then
    return 1
  fi
  
  return 0
}

main "$@"
