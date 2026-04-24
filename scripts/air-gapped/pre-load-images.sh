#!/usr/bin/env bash
# @file        scripts/air-gapped/pre-load-images.sh
# @module      air-gapped/image-management
# @description Pre-load all container images to local storage for air-gapped deployment
#
# Usage:
#   bash scripts/air-gapped/pre-load-images.sh --save /path/to/images/
#   bash scripts/air-gapped/pre-load-images.sh --check
#
# This script is meant to run on a host WITH internet access to pull and save
# all images needed for air-gapped deployment. The saved images can then be
# transferred to the air-gapped host via USB, internal network, etc.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/logging.sh" || {
  echo "ERROR: Cannot source logging.sh" >&2
  exit 1
}

# Images required for air-gapped deployment (from docker-compose-air-gapped.yml)
declare -a REQUIRED_IMAGES=(
  "code-server-enterprise:dev"
  "ollama/ollama:0.1.27"
  "postgres:15-alpine"
  "redis:7-alpine"
  "matrixdotorg/synapse:v1.95"
  "vectorim/element-web:v1.11.50"
  "caddy:2.7-alpine"
  "prom/prometheus:v2.48"
  "grafana/grafana:10.2"
  "prom/alertmanager:v0.26"
)

# ────────────────────────────────────────────────────────────────────────────
# Usage information
# ────────────────────────────────────────────────────────────────────────────
show_usage() {
  cat << 'EOF'
Usage: pre-load-images.sh [COMMAND] [OPTIONS]

Commands:
  --save DIR        Save all required images to DIR (for air-gapped transfer)
  --check           Verify all images are already loaded locally
  --help            Show this help message

Examples:
  # Save images for air-gapped deployment (requires internet)
  bash scripts/air-gapped/pre-load-images.sh --save /tmp/images/

  # Check which images are missing
  bash scripts/air-gapped/pre-load-images.sh --check

Environment Variables:
  DOCKER_REGISTRY   Custom registry prefix (default: docker.io)
  SKIP_BUILD        Skip code-server-enterprise build (0|1)

EOF
}

# ────────────────────────────────────────────────────────────────────────────
# Check if image exists locally
# ────────────────────────────────────────────────────────────────────────────
image_exists() {
  local image="$1"
  docker image inspect "$image" &>/dev/null
}

# ────────────────────────────────────────────────────────────────────────────
# Pull image from registry
# ────────────────────────────────────────────────────────────────────────────
pull_image() {
  local image="$1"
  
  if image_exists "$image"; then
    log_info "Image already exists: $image"
    return 0
  fi
  
  log_info "Pulling image: $image"
  if docker pull "$image" 2>&1 | tee -a /tmp/pull-$$.log; then
    log_info "✓ Successfully pulled: $image"
    return 0
  else
    log_error "✗ Failed to pull: $image"
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Save image to TAR file
# ────────────────────────────────────────────────────────────────────────────
save_image() {
  local image="$1"
  local output_dir="$2"
  local filename="${output_dir}/$(echo "$image" | tr ':/' '__').tar.gz"
  
  if [[ ! -d "$output_dir" ]]; then
    log_info "Creating output directory: $output_dir"
    mkdir -p "$output_dir"
  fi
  
  if [[ -f "$filename" ]]; then
    log_warn "Image already saved: $filename"
    return 0
  fi
  
  log_info "Saving image: $image → $filename"
  if docker save "$image" | gzip > "$filename" 2>&1; then
    local size
    size=$(du -h "$filename" | cut -f1)
    log_info "✓ Saved: $image ($size)"
    return 0
  else
    log_error "✗ Failed to save: $image"
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Build code-server-enterprise image locally
# ────────────────────────────────────────────────────────────────────────────
build_code_server() {
  if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
    log_warn "Skipping code-server-enterprise build (SKIP_BUILD=1)"
    return 0
  fi
  
  log_info "Building code-server-enterprise image..."
  cd "${SCRIPT_DIR}"
  
  if docker build -f Dockerfile.code-server -t code-server-enterprise:dev . 2>&1 | tail -20; then
    log_info "✓ Successfully built code-server-enterprise:dev"
    return 0
  else
    log_error "✗ Failed to build code-server-enterprise"
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Check command: verify all images are available
# ────────────────────────────────────────────────────────────────────────────
cmd_check() {
  log_info "Checking required images..."
  
  local missing=0
  for image in "${REQUIRED_IMAGES[@]}"; do
    if image_exists "$image"; then
      log_info "✓ $image"
    else
      log_error "✗ MISSING: $image"
      ((missing++))
    fi
  done
  
  if [[ $missing -eq 0 ]]; then
    log_info "✓ All required images are present"
    return 0
  else
    log_error "✗ $missing image(s) missing"
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Save command: pull and save all images
# ────────────────────────────────────────────────────────────────────────────
cmd_save() {
  local output_dir="${1:?Output directory required}"
  
  log_info "========================================================================"
  log_info "Pre-Loading Images for Air-Gapped Deployment"
  log_info "========================================================================"
  log_info "Output directory: $output_dir"
  log_info ""
  
  # Build custom image first
  build_code_server || return 1
  
  # Pull all images
  local failed=0
  for image in "${REQUIRED_IMAGES[@]}"; do
    pull_image "$image" || ((failed++))
  done
  
  if [[ $failed -gt 0 ]]; then
    log_error "✗ Failed to pull $failed image(s)"
    return 1
  fi
  
  log_info ""
  log_info "Saving images to: $output_dir"
  log_info ""
  
  # Save all images
  local save_failed=0
  for image in "${REQUIRED_IMAGES[@]}"; do
    save_image "$image" "$output_dir" || ((save_failed++))
  done
  
  if [[ $save_failed -gt 0 ]]; then
    log_error "✗ Failed to save $save_failed image(s)"
    return 1
  fi
  
  log_info ""
  log_info "========================================================================"
  log_info "✓ Image Pre-Loading Complete"
  log_info "========================================================================"
  log_info ""
  log_info "Next steps:"
  log_info "1. Transfer images to air-gapped host:"
  log_info "   scp -r $output_dir akushnir@192.168.168.31:/tmp/images/"
  log_info ""
  log_info "2. Load images on air-gapped host:"
  log_info "   bash scripts/air-gapped/load-images.sh /tmp/images/"
  log_info ""
  log_info "3. Deploy with air-gapped config:"
  log_info "   docker-compose -f docker-compose-air-gapped.yml up -d"
  log_info ""
  
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Main entry point
# ────────────────────────────────────────────────────────────────────────────
main() {
  if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
  fi
  
  case "${1:-}" in
    --save)
      cmd_save "${2:?Directory required for --save}"
      ;;
    --check)
      cmd_check
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    *)
      log_error "Unknown command: $1"
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
