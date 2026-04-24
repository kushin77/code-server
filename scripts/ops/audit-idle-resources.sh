#!/usr/bin/env bash
# @file        scripts/ops/audit-idle-resources.sh
# @module      ops/storage
# @description Audit idle Docker, NAS, and artifact resources without deleting anything
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

require_command docker "docker is required for storage auditing"
require_command find "find is required for stale artifact discovery"

OUTPUT_DIR="${OUTPUT_DIR:-artifacts/triage}"
REPORT_BASENAME="${REPORT_BASENAME:-idle-resource-audit}"
REPORT_FILE="${REPORT_FILE:-${OUTPUT_DIR}/${REPORT_BASENAME}.md}"

main() {
  mkdir -p "$OUTPUT_DIR"

  log_info "Auditing idle resources"

  {
    echo "# Idle Resource Audit"
    echo
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "## Docker System Usage"
    docker system df
    echo
    echo "## Container Snapshot"
    docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' || true
    echo
    echo "## Image Snapshot"
    docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}\t{{.Size}}' || true
    echo
    echo "## Dangling Volumes"
    docker volume ls -f dangling=true || true
    echo
    echo "## Stale Triage Artifacts"
    find artifacts/triage -type f -mtime +30 -print | sort || true
    echo
    echo "## GitHub Rate Limit"
    if command -v gh >/dev/null 2>&1; then
      gh api rate_limit --jq '.rate | "limit=\(.limit) remaining=\(.remaining) reset=\(.reset)"' || true
    else
      echo "gh unavailable"
    fi
  } > "$REPORT_FILE"

  log_info "Idle resource audit written to ${REPORT_FILE}"
}

main "$@"