#!/usr/bin/env bash
# Rebuild and redeploy the full stack on the primary host using key-only SSH.
# Default target: 192.168.168.31 (from scripts/_common/config.sh)
#
# Usage:
#   bash scripts/deploy/rebuild-clean-remote.sh
#   bash scripts/deploy/rebuild-clean-remote.sh --with-prune
#   bash scripts/deploy/rebuild-clean-remote.sh --skip-build
#
# Notes:
# - Linux-only workflow.
# - No local terraform apply; runs remotely in deploy directory.
# - Requires passwordless SSH to primary deploy host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

WITH_PRUNE=0
SKIP_BUILD=0
NO_CACHE=1

usage() {
  cat <<'EOF'
Usage: rebuild-clean-remote.sh [options]

Options:
  --with-prune     Run docker system prune -f after compose down
  --skip-build     Skip docker compose build step
  --use-cache      Build with cache (default is --no-cache)
  -h, --help       Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-prune)
      WITH_PRUNE=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --use-cache)
      NO_CACHE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

main() {
  log_section "Remote Clean Rebuild"
  log_info "Deploy host: ${DEPLOY_USER}@${DEPLOY_HOST}"
  log_info "Deploy dir: ${DEPLOY_DIR}"

  verify_passwordless_ssh "${DEPLOY_USER}@${DEPLOY_HOST}"
  assert_ssh_up "$DEPLOY_HOST" "$DEPLOY_USER"

  log_info "Stopping stack and removing orphans..."
  ssh_in_deploy_dir "docker compose down --remove-orphans"

  if [[ "$WITH_PRUNE" -eq 1 ]]; then
    log_info "Pruning unused Docker resources..."
    ssh_exec "docker system prune -f"
  fi

  if [[ "$SKIP_BUILD" -eq 0 ]]; then
    if [[ "$NO_CACHE" -eq 1 ]]; then
      log_info "Building images with --no-cache..."
      ssh_in_deploy_dir "docker compose build --no-cache"
    else
      log_info "Building images with cache..."
      ssh_in_deploy_dir "docker compose build"
    fi
  else
    log_warn "Skipping image build step"
  fi

  log_info "Starting stack..."
  ssh_in_deploy_dir "docker compose up -d"

  log_info "Deployment status:"
  ssh_in_deploy_dir "docker compose ps"

  log_success "Remote clean rebuild completed"
}

main "$@"
