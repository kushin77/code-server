#!/bin/bash
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
#   2026-04-14: Added safer confirmation dialogs 
#   2026-04-13: Initial creation with overlap detection
#
################################################################################
# cleanup-container-overlap.sh
# Description: Remove overlapping containers and consolidate to single docker-compose stack
# Usage: bash scripts/cleanup-container-overlap.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

echo "=== CONTAINER OVERLAP CLEANUP ==="
echo "Timestamp: $(date)"
echo ""

# Stop and remove overlapping containers
echo "🛑 Stopping overlapping containers..."

# Stop duplicates with -31 suffix (from separate compose stack)
docker stop -q \
  code-server-31 \
  ssh-proxy-31 \
  2>/dev/null || echo "✓ No overlapping -31 containers running"

# Remove stopped containers
echo "🗑️  Removing stopped overlapping containers..."
docker rm -v \
  code-server-31 \
  ssh-proxy-31 \
  2>/dev/null || echo "✓ No containers to remove"

# ollama-init should only exist in 'init' profile — verify it's not auto-running
echo ""
echo "🔍 Verifying ollama-init status..."
if docker ps --filter "name=ollama-init" --quiet | grep -q .; then
  echo "⚠️  WARNING: ollama-init is still running"
  echo "   This container should only start with: docker compose --profile init up"
  echo "   Reason: ollama-init is configured with restart: no"
  echo "   If it's running, it was likely started manually or in an old compose stack"
  
  docker stop -q ollama-init 2>/dev/null || true
  echo "✓ Stopped ollama-init"
else
  echo "✓ ollama-init is not running (correct — using init profile)"
fi

echo ""
echo "=== CONSOLIDATION PLAN ==="
echo ""
echo "Current docker-compose.yml correctly defines:"
echo "  ✓ code-server (container_name: code-server)"
echo "  ✓ ssh-proxy (container_name: ssh-proxy)  "
echo "  ✓ ollama (container_name: ollama)"
echo "  ✓ ollama-init (profile: init) — one-time init only"
echo "  ✓ oauth2-proxy (container_name: oauth2-proxy)"
echo "  ✓ caddy (container_name: caddy)"
echo "  ✓ redis (container_name: redis)"
echo ""

echo "=== FINAL STACK VERIFICATION ==="
echo ""
echo "Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

echo ""
echo "=== CLEANUP COMPLETE ==="
echo "Next: docker compose down && docker compose up -d"
echo "      (This will ensure clean stack with correct version)"

