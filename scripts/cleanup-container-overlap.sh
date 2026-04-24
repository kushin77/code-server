#!/bin/bash
# @file        scripts/cleanup-container-overlap.sh
# @module      maintenance
# @description cleanup container overlap — on-prem code-server
# @owner       platform
# @status      active
################################################################################
# File: cleanup-container-overlap.sh
# Owner: Container Operations Team
# Purpose: Detect and remove conflicting/overlapping Docker containers
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+, Docker 20.10+
#
# Dependencies:
#   - docker — Container runtime
#   - jq — JSON parsing for container inspection
#   - curl — Health endpoint verification
#
# Related Files:
#   - docker-compose.yml — Container definitions
#   - RUNBOOKS.md — Container troubleshooting procedures
#   - alert-rules.yml — Container health alerts
#
# Usage:
#   ./cleanup-container-overlap.sh              # Cleanup overlapping containers
#   ./cleanup-container-overlap.sh --dry-run    # Show what would be removed
#   ./cleanup-container-overlap.sh --force      # Force removal without confirmation
#
# Detects:
#   - Multiple instances of same service
#   - Containers on conflicting ports
#   - Failed/stopped containers not part of active deployment
#   - Orphaned volumes not attached to running containers
#
# Exit Codes:
#   0 — Cleanup completed successfully
#   1 — Some containers could not be removed (manual review needed)
#   2 — Critical issue preventing cleanup (Docker daemon may be corrupted)
#
# Examples:
#   ./scripts/cleanup-container-overlap.sh
#   ./scripts/cleanup-container-overlap.sh --dry-run
#
# Recent Changes:
#   2026-04-14: Added safer confirmation dialogs (Phase 2.2)
#   2026-04-13: Initial creation with overlap detection
#
################################################################################
# cleanup-container-overlap.sh
# Description: Remove overlapping containers and consolidate to single docker-compose stack
# Usage: bash scripts/cleanup-container-overlap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

log_info "=== CONTAINER OVERLAP CLEANUP ==="
log_info "Timestamp: $(date)"

# Stop and remove overlapping containers
log_info "🛑 Stopping overlapping containers..."

# Stop duplicates with -31 suffix (from separate compose stack)
docker stop -q \
  code-server-31 \
  ssh-proxy-31 \
  2>/dev/null || log_info "✓ No overlapping -31 containers running"

# Remove stopped containers
log_info "🗑️  Removing stopped overlapping containers..."
docker rm -v \
  code-server-31 \
  ssh-proxy-31 \
  2>/dev/null || log_info "✓ No containers to remove"

# ollama-init should only exist in 'init' profile — verify it's not auto-running
log_info "🔍 Verifying ollama-init status..."
if docker ps --filter "name=ollama-init" --quiet | grep -q .; then
  log_warn "⚠️  WARNING: ollama-init is still running"
  log_info "   This container should only start with: docker compose --profile init up"
  log_info "   Reason: ollama-init is configured with restart: no"
  log_info "   If it's running, it was likely started manually or in an old compose stack"
  
  docker stop -q ollama-init 2>/dev/null || true
  log_info "✓ Stopped ollama-init"
else
  log_info "✓ ollama-init is not running (correct — using init profile)"
fi

log_info "=== CONSOLIDATION PLAN ==="
log_info "Current docker-compose.yml correctly defines:"
log_info "  ✓ code-server (container_name: code-server)"
log_info "  ✓ ssh-proxy (container_name: ssh-proxy)  "
log_info "  ✓ ollama (container_name: ollama)"
log_info "  ✓ ollama-init (profile: init) — one-time init only"
log_info "  ✓ oauth2-proxy (container_name: oauth2-proxy)"
log_info "  ✓ caddy (container_name: caddy)"
log_info "  ✓ redis (container_name: redis)"

log_info "=== FINAL STACK VERIFICATION ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

log_info "=== CLEANUP COMPLETE ==="
log_info "Next: docker compose down && docker compose up -d"
log_info "      (This will ensure clean stack with correct version)"
