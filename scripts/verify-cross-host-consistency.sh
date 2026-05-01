#!/bin/bash
# Cross-Host Consistency Verification Script
# Automated parity checks to detect divergence between primary and replica deployments
#
# Usage:
#   ./scripts/verify-cross-host-consistency.sh [--fail-on-mismatch] [--verbose]
#
# Modes:
#   --fail-on-mismatch    Exit with error code if any mismatches found (useful for CI)
#   --verbose, -v         Show detailed comparison output
#   --help, -h            Show this help message
#
# Output:
#   Summary table with service counts, image tags, health states
#   Detailed diff if mismatches detected
#   Exit code: 0 if consistent, 1 if mismatches

set -euo pipefail
trap 'error "Script failed at line $LINENO"' ERR
trap 'rm -f /tmp/consistency-check-*.tmp 2>/dev/null || true' EXIT

# Configuration
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5"
DEPLOY_DIR="~/code-server-enterprise"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# State variables
FAIL_ON_MISMATCH=false
VERBOSE=false
MISMATCH_COUNT=0

# Functions
log() {
  echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

mismatch() {
  echo -e "${RED}[MISMATCH]${NC} $*"
  MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --fail-on-mismatch)
      FAIL_ON_MISMATCH=true
      shift
      ;;
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      ;;
  esac
done

show_help() {
  cat << EOF
Cross-Host Consistency Verification Script

Compares service deployments between primary and replica hosts to detect divergence.
Checks: service count, names, image tags, health states, and restart behavior.

Usage:
  $0 [OPTIONS]

Options:
  --fail-on-mismatch    Exit with error code (1) if mismatches found (for CI/CD)
  --verbose, -v         Show detailed comparison; don't truncate diffs
  --help, -h            Show this help message

Examples:
  # Run consistency check and show summary
  $0

  # Fail if any mismatches (useful for CI gates)
  $0 --fail-on-mismatch

  # Show detailed output
  $0 --verbose

Typical output:
  PRIMARY (192.168.168.31):   37 services
  REPLICA (192.168.168.42):   37 services
  ✓ Service counts match
  ✓ Image tags identical
  ✓ Health states synchronized
  [All checks passed]

Error output (example mismatch):
  ✗ Service count mismatch: primary=37, replica=36
  [Check replica for missing services]
EOF
}

# Fetch service inventory from host
fetch_inventory() {
  local host="$1"
  local tmpfile="/tmp/consistency-check-${host}.tmp"

  ssh $SSH_OPTS "$host" "cd $DEPLOY_DIR && (
    echo '=== SERVICE_COUNT ==='
    docker ps --format '{{.Names}}' | grep '^code-server-' | wc -l
    echo ''
    echo '=== SERVICE_NAMES ==='
    docker ps --format '{{.Names}}' | grep '^code-server-' | sort
    echo ''
    echo '=== IMAGE_TAGS ==='
    docker ps --format '{{.Image}}' | sort | uniq
    echo ''
    echo '=== HEALTH_STATUS ==='
    docker ps --format '{{.Names}}\t{{.Status}}' | grep '^code-server-' | sort
    echo ''
    echo '=== RESTART_COUNT ==='
    docker ps --format '{{.Names}}\t{{.RestartCount}}' | grep '^code-server-' | sort
  )" > "$tmpfile" 2>&1 || error "Cannot fetch inventory from $host"

  cat "$tmpfile"
}

# Extract section from inventory output
extract_section() {
  local section="$1"
  echo "$2" | sed -n "/=== $section ===/,/^$/p" | sed '1d;$d'
}

# Compare inventories
compare_inventories() {
  log "Fetching inventory from primary ($PRIMARY_HOST)..."
  local primary_inv=$(fetch_inventory "$PRIMARY_HOST")

  log "Fetching inventory from replica ($REPLICA_HOST)..."
  local replica_inv=$(fetch_inventory "$REPLICA_HOST")

  # Extract sections
  local primary_count=$(extract_section "SERVICE_COUNT" "$primary_inv" | head -1)
  local replica_count=$(extract_section "SERVICE_COUNT" "$replica_inv" | head -1)

  local primary_names=$(extract_section "SERVICE_NAMES" "$primary_inv")
  local replica_names=$(extract_section "SERVICE_NAMES" "$replica_inv")

  local primary_images=$(extract_section "IMAGE_TAGS" "$primary_inv")
  local replica_images=$(extract_section "IMAGE_TAGS" "$replica_inv")

  local primary_health=$(extract_section "HEALTH_STATUS" "$primary_inv")
  local replica_health=$(extract_section "HEALTH_STATUS" "$replica_inv")

  local primary_restarts=$(extract_section "RESTART_COUNT" "$primary_inv")
  local replica_restarts=$(extract_section "RESTART_COUNT" "$replica_inv")

  # Display summary
  echo ""
  echo "===== CONSISTENCY VERIFICATION SUMMARY ====="
  echo ""
  printf "%-50s %s\n" "PRIMARY ($PRIMARY_HOST):" "$primary_count services"
  printf "%-50s %s\n" "REPLICA ($REPLICA_HOST):" "$replica_count services"
  echo ""

  # Check service count
  if [[ "$primary_count" == "$replica_count" ]]; then
    success "Service counts match ($primary_count services on both hosts)"
  else
    mismatch "Service count mismatch: primary=$primary_count, replica=$replica_count"
  fi

  # Check service names
  if [[ "$primary_names" == "$replica_names" ]]; then
    success "Service names identical"
  else
    mismatch "Service names differ between hosts"
    echo ""
    warning "In primary but not replica:"
    comm -23 <(echo "$primary_names") <(echo "$replica_names") | sed 's/^/  - /' || true
    warning "In replica but not primary:"
    comm -13 <(echo "$primary_names") <(echo "$replica_names") | sed 's/^/  - /' || true
    echo ""
  fi

  # Check image tags
  if [[ "$primary_images" == "$replica_images" ]]; then
    success "Image tags identical"
  else
    mismatch "Image tags differ between hosts"
    if [[ "$VERBOSE" == "true" ]]; then
      echo ""
      warning "Primary images:"
      echo "$primary_images" | sed 's/^/  /'
      warning "Replica images:"
      echo "$replica_images" | sed 's/^/  /'
      echo ""
    fi
  fi

  # Check health states
  if [[ "$primary_health" == "$replica_health" ]]; then
    success "Health states synchronized"
  else
    mismatch "Health states differ between hosts"
    if [[ "$VERBOSE" == "true" ]]; then
      echo ""
      warning "Service health differences:"
      diff <(echo "$primary_health") <(echo "$replica_health") | head -20 || true
      echo ""
    fi
  fi

  # Check restart counts (should be low, ideally 0)
  local primary_restarts_total=$(echo "$primary_restarts" | awk '{sum+=$2} END {print sum+0}')
  local replica_restarts_total=$(echo "$replica_restarts" | awk '{sum+=$2} END {print sum+0}')

  if [[ $primary_restarts_total -eq 0 ]] && [[ $replica_restarts_total -eq 0 ]]; then
    success "No unexpected restarts (0 total on both hosts)"
  else
    warning "Restart count: primary=$primary_restarts_total, replica=$replica_restarts_total"
    if [[ $primary_restarts_total -gt 5 ]] || [[ $replica_restarts_total -gt 5 ]]; then
      mismatch "High restart count detected (may indicate instability)"
      if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        warning "Primary service restarts:"
        echo "$primary_restarts" | awk '$2 > 0 {print "  " $0}' || echo "  (none)"
        warning "Replica service restarts:"
        echo "$replica_restarts" | awk '$2 > 0 {print "  " $0}' || echo "  (none)"
        echo ""
      fi
    fi
  fi

  echo ""
  echo "===== RESULT ====="
  if [[ $MISMATCH_COUNT -eq 0 ]]; then
    success "All consistency checks PASSED ✓"
    echo "Both hosts are in sync; deployment is consistent."
    return 0
  else
    mismatch "$MISMATCH_COUNT inconsistenc$([ $MISMATCH_COUNT -gt 1 ] && echo 'ies' || echo 'y') detected"
    echo ""
    warning "Recommended actions:"
    if [[ "$primary_count" != "$replica_count" ]]; then
      echo "  1. Re-run deployment script on host with fewer services"
      echo "     ./scripts/ops/enterprise-deploy.sh --target=replica --mode=apply"
    fi
    if [[ "$primary_names" != "$replica_names" ]]; then
      echo "  2. Check logs on both hosts: docker logs <service_name>"
      echo "  3. Verify docker-compose file synced correctly"
    fi
    echo "  4. See docs/operations/TROUBLESHOOTING.md for detailed guidance"
    echo ""
    if [[ "$FAIL_ON_MISMATCH" == "true" ]]; then
      return 1
    fi
  fi
}

# Main execution
main() {
  log "Starting Cross-Host Consistency Verification"
  log "Primary: $PRIMARY_HOST | Replica: $REPLICA_HOST"
  log "Mode: $([ "$VERBOSE" == "true" ] && echo "verbose" || echo "summary")"
  echo ""

  if ! compare_inventories; then
    if [[ "$FAIL_ON_MISMATCH" == "true" ]]; then
      exit 1
    fi
  fi
}

# Execute main
main "$@"
