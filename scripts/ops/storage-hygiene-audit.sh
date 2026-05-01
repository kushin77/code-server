#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Storage hygiene audit failed at line $LINENO"; exit 1' ERR

readonly MODE="${1:-inventory}"
readonly APPROVE_FLAG="${2:-}"
readonly REPORT_DIR="${REPO_ROOT}/artifacts/storage-hygiene"
readonly REPORT_FILE="${REPORT_DIR}/storage-hygiene-$(date +%Y%m%d-%H%M%S).json"

mkdir -p "$REPORT_DIR"

collect_inventory() {
  local stale_containers dangling_images dangling_volumes

  if command -v docker >/dev/null 2>&1; then
    stale_containers=$(docker ps -aq -f status=exited 2>/dev/null | wc -l | tr -d ' ')
    dangling_images=$(docker images -q -f dangling=true 2>/dev/null | sort -u | wc -l | tr -d ' ')
    dangling_volumes=$(docker volume ls -qf dangling=true 2>/dev/null | wc -l | tr -d ' ')
  else
    stale_containers=0
    dangling_images=0
    dangling_volumes=0
    log_warning "Docker not available; inventory defaults to zero counts"
  fi

  cat > "$REPORT_FILE" <<EOF
{
  "mode": "inventory",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stale_containers": ${stale_containers:-0},
  "dangling_images": ${dangling_images:-0},
  "dangling_volumes": ${dangling_volumes:-0}
}
EOF

  log_info "Storage hygiene inventory written to $REPORT_FILE"
  log_info "Stale containers: ${stale_containers:-0}"
  log_info "Dangling images: ${dangling_images:-0}"
  log_info "Dangling volumes: ${dangling_volumes:-0}"
}

dry_run_cleanup() {
  log_info "Dry-run cleanup requested"
  log_info "Would remove exited containers, dangling images, and dangling volumes after approval"
  collect_inventory
}

approved_cleanup() {
  if [[ "$APPROVE_FLAG" != "--approve" ]]; then
    log_error "Cleanup mode requires --approve"
    exit 1
  fi

  collect_inventory

  log_info "Removing exited containers..."
  command -v docker >/dev/null 2>&1 || { log_error "Docker not available for cleanup"; exit 1; }
  docker container prune -f

  log_info "Removing dangling images..."
  docker image prune -f

  log_info "Removing dangling volumes..."
  docker volume prune -f

  log_success "Storage hygiene cleanup complete"
}

case "$MODE" in
  inventory)
    collect_inventory
    ;;
  dry-run)
    dry_run_cleanup
    ;;
  cleanup)
    approved_cleanup
    ;;
  *)
    log_error "Usage: $0 [inventory|dry-run|cleanup --approve]"
    exit 1
    ;;
esac