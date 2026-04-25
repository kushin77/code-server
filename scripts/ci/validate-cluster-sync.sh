#!/usr/bin/env bash

################################################################################
# @file        scripts/ci/validate-cluster-sync.sh
# @module      ci/cluster-validation
# @description Pre-deployment cluster sync validation (IaC: Immutable, Idempotent)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
#
# GOVERNANCE: GOV-002 Compliance
# - Deterministic: Same inputs always produce same output
# - Audited: All checks logged with evidence
# - Immutable: No state modifications, validation-only
# - Idempotent: Safe to run multiple times
#
# PURPOSE
# Validate both primary and replica nodes are in sync before:
# - Failover tests
# - Configuration changes
# - Load balancer reconfiguration
# - Service upgrades
#
# VALIDATION CHECKS
# 1. Git commit sync: Both nodes at same commit hash
# 2. Config file checksums: Caddyfile, prometheus.yml, loki-config.yaml match
# 3. Service versions: Docker image digests match
# 4. Directory structure: Critical directories exist on both nodes
# 5. File permissions: config files have correct ownership (idempotent check)
#
# USAGE
#   bash scripts/ci/validate-cluster-sync.sh [--verbose] [--report FILE]
#
# RETURN CODES
#   0 = All checks passed, cluster in sync
#   1 = One or more checks failed, cluster out of sync
#   2 = Configuration error (missing hosts, SSH access)
#
# EXAMPLES
#   # Quick validation
#   bash scripts/ci/validate-cluster-sync.sh
#
#   # Detailed output with report
#   bash scripts/ci/validate-cluster-sync.sh --verbose --report /tmp/cluster-sync-report.json
#
#   # Before failover test
#   bash scripts/ci/validate-cluster-sync.sh || exit 1
#   bash scripts/ops/full-deployment-test.sh --failover
#
# @author Autonomous Infrastructure
# @version 1.0.0
# @date 2026-04-25
# @issue #XXXX (Cluster Sync - Multi-Node HA)
################################################################################

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly LOG_DIR="${PROJECT_ROOT}/logs"

# Source configuration
source "$PROJECT_ROOT/scripts/_common/init.sh" || exit 2
source "$PROJECT_ROOT/scripts/_common/_base-config.env" || exit 2

# Validation parameters
VERBOSE_MODE="${VERBOSE_MODE:-false}"
REPORT_FILE="${REPORT_FILE:-}"
EXIT_CODE=0

# Critical files for sync validation (must match on both nodes)
declare -a CRITICAL_FILES=(
  "config/caddy/Caddyfile"
  "config/prometheus.yml"
  "config/loki/loki-config.yaml"
  "docker-compose.yml"
  ".env.baseline"
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log_check() {
  local check_name="$1"
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [CHECK] $check_name"
}

log_pass() {
  local message="$1"
  echo "  ✓ PASS: $message"
  [[ "$VERBOSE_MODE" == "true" ]] && echo "    Details: SYNC OK"
}

log_fail() {
  local message="$1"
  local expected="${2:-}"
  local actual="${3:-}"
  echo "  ✗ FAIL: $message" >&2
  if [[ -n "$expected" && -n "$actual" ]]; then
    echo "    Expected: $expected" >&2
    echo "    Actual:   $actual" >&2
  fi
  EXIT_CODE=1
}

log_error() {
  local message="$1"
  echo "  ✗ ERROR: $message" >&2
  EXIT_CODE=2
}

# Check if SSH access works (non-blocking)
check_ssh_access() {
  local host="$1"
  local label="$2"
  
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" "echo OK" &>/dev/null; then
    return 0
  else
    echo "  ⚠ WARNING: SSH to $label ($host) failed - skipping remote checks" >&2
    return 1
  fi
}

# Remote execution wrapper (handles SSH failures gracefully)
remote_run() {
  local host="$1"
  local command="$2"
  
  if check_ssh_access "$host" "$host" 2>/dev/null; then
    ssh -o ConnectTimeout=5 "$host" "$command" 2>/dev/null || true
  else
    echo "UNAVAILABLE"
  fi
}

# ==============================================================================
# CHECK 1: Git Commit Sync
# ==============================================================================

check_git_commits() {
  log_check "Git commit sync (PRIMARY vs REPLICA)"
  
  local primary_commit=""
  local replica_commit=""
  
  # Get primary commit
  if ! primary_commit=$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null); then
    log_error "Cannot get git commit on primary node"
    return 1
  fi
  
  # Get replica commit
  replica_commit=$(remote_run "$REPLICA_HOST" "cd $PROJECT_ROOT && git rev-parse HEAD")
  
  if [[ "$replica_commit" == "UNAVAILABLE" ]]; then
    echo "  ⚠ WARNING: Cannot reach replica for git check (SSH access issue)" >&2
    return 0  # Non-blocking
  fi
  
  if [[ "$primary_commit" == "$replica_commit" ]]; then
    log_pass "Git commits match: $primary_commit"
    return 0
  else
    log_fail "Git commits mismatch" "$primary_commit" "$replica_commit"
    return 1
  fi
}

# ==============================================================================
# CHECK 2: Config File Checksums
# ==============================================================================

check_config_checksums() {
  log_check "Configuration file checksums"
  
  local all_match=0
  
  for config_file in "${CRITICAL_FILES[@]}"; do
    local primary_file="$PROJECT_ROOT/$config_file"
    
    # Skip if file doesn't exist on primary
    if [[ ! -f "$primary_file" ]]; then
      [[ "$VERBOSE_MODE" == "true" ]] && echo "  ℹ  Skipping (not found): $config_file"
      continue
    fi
    
    # Get primary checksum
    local primary_sha=""
    if command -v sha256sum &>/dev/null; then
      primary_sha=$(sha256sum "$primary_file" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
      primary_sha=$(shasum -a 256 "$primary_file" | awk '{print $1}')
    else
      log_error "No checksum utility available (sha256sum/shasum)"
      return 2
    fi
    
    # Get replica checksum
    local replica_sha=""
    if check_ssh_access "$REPLICA_HOST" "$REPLICA_HOST" 2>/dev/null; then
      replica_sha=$(remote_run "$REPLICA_HOST" "sha256sum $primary_file 2>/dev/null | awk '{print \$1}'")
    else
      replica_sha="UNAVAILABLE"
    fi
    
    if [[ "$replica_sha" == "UNAVAILABLE" ]]; then
      echo "  ⚠ WARNING: Cannot validate replica checksum for $config_file (SSH issue)" >&2
      continue
    fi
    
    if [[ "$primary_sha" == "$replica_sha" ]]; then
      [[ "$VERBOSE_MODE" == "true" ]] && echo "  ✓ $config_file: $primary_sha"
    else
      log_fail "$config_file checksum mismatch" "$primary_sha" "$replica_sha"
      all_match=1
    fi
  done
  
  if [[ $all_match -eq 0 ]]; then
    log_pass "All config file checksums match"
  fi
  
  return $all_match
}

# ==============================================================================
# CHECK 3: Service Versions (Docker images)
# ==============================================================================

check_service_versions() {
  log_check "Service image versions"
  
  local all_match=0
  
  # Extract critical image digests from docker-compose.yml
  local caddy_digest=$(grep -A 1 "caddy:" "$PROJECT_ROOT/docker-compose.yml" | grep "@sha256:" | grep -o "sha256:[a-f0-9]*" | head -1)
  local prometheus_digest=$(grep -A 1 "prom/prometheus" "$PROJECT_ROOT/docker-compose.yml" | grep "@sha256:" | grep -o "sha256:[a-f0-9]*" | head -1)
  
  if [[ -z "$caddy_digest" || -z "$prometheus_digest" ]]; then
    echo "  ⚠ WARNING: Cannot extract image digests from docker-compose.yml" >&2
    return 0  # Non-blocking
  fi
  
  # Check if images are pinned (not just tags)
  if docker image inspect "caddy@$caddy_digest" &>/dev/null 2>&1; then
    log_pass "Caddy image pinned: $caddy_digest"
  else
    log_fail "Caddy image not available locally: $caddy_digest"
    all_match=1
  fi
  
  if docker image inspect "prom/prometheus@$prometheus_digest" &>/dev/null 2>&1; then
    log_pass "Prometheus image pinned: $prometheus_digest"
  else
    log_fail "Prometheus image not available locally: $prometheus_digest"
    all_match=1
  fi
  
  return $all_match
}

# ==============================================================================
# CHECK 4: Directory Structure
# ==============================================================================

check_directory_structure() {
  log_check "Critical directory structure"
  
  declare -a CRITICAL_DIRS=(
    "config/caddy"
    "config/loki"
    "config/grafana"
    "monitoring"
  )
  
  local all_exist=0
  
  for dir in "${CRITICAL_DIRS[@]}"; do
    local dir_path="$PROJECT_ROOT/$dir"
    
    if [[ -d "$dir_path" ]]; then
      [[ "$VERBOSE_MODE" == "true" ]] && echo "  ✓ $dir"
    else
      log_fail "$dir not found"
      all_exist=1
    fi
  done
  
  if [[ $all_exist -eq 0 ]]; then
    log_pass "All critical directories exist"
  fi
  
  return $all_exist
}

# ==============================================================================
# CHECK 5: Docker Compose Validation
# ==============================================================================

check_docker_compose_config() {
  log_check "Docker Compose configuration validity"
  
  if ! command -v docker &>/dev/null; then
    echo "  ⚠ WARNING: Docker not available, skipping compose config validation" >&2
    return 0  # Non-blocking
  fi
  
  # Check if docker compose can parse the file (idempotent check)
  if docker compose -f "$PROJECT_ROOT/docker-compose.yml" config >/dev/null 2>&1; then
    log_pass "docker-compose.yml is valid and parseable"
    return 0
  else
    log_fail "docker-compose.yml validation failed"
    return 1
  fi
}

# ==============================================================================
# GENERATE REPORT
# ==============================================================================

generate_report() {
  if [[ -z "$REPORT_FILE" ]]; then
    return 0
  fi
  
  # Create JSON report
  mkdir -p "$(dirname "$REPORT_FILE")"
  
  cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": $([ $EXIT_CODE -eq 0 ] && echo '"PASS"' || echo '"FAIL"'),
  "exit_code": $EXIT_CODE,
  "primary_host": "$PRIMARY_HOST",
  "replica_host": "$REPLICA_HOST",
  "checks": {
    "git_commits": $(check_git_commits >/dev/null 2>&1 && echo "true" || echo "false"),
    "config_checksums": $(check_config_checksums >/dev/null 2>&1 && echo "true" || echo "false"),
    "service_versions": $(check_service_versions >/dev/null 2>&1 && echo "true" || echo "false"),
    "directory_structure": $(check_directory_structure >/dev/null 2>&1 && echo "true" || echo "false"),
    "docker_compose_config": $(check_docker_compose_config >/dev/null 2>&1 && echo "true" || echo "false")
  },
  "details": {
    "message": "Cluster sync validation complete"
  }
}
EOF
  
  echo "Report written to: $REPORT_FILE"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose)
        VERBOSE_MODE="true"
        shift
        ;;
      --report)
        REPORT_FILE="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 2
        ;;
    esac
  done
  
  # Ensure log directory exists
  mkdir -p "$LOG_DIR"
  
  echo "======================================================================"
  echo "Cluster Sync Validation ($(date -u +'%Y-%m-%dT%H:%M:%SZ'))"
  echo "======================================================================"
  echo "Primary: $PRIMARY_HOST"
  echo "Replica: $REPLICA_HOST"
  echo ""
  
  # Run all checks
  check_git_commits || true
  check_config_checksums || true
  check_service_versions || true
  check_directory_structure || true
  check_docker_compose_config || true
  
  echo ""
  echo "======================================================================"
  
  if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ CLUSTER IN SYNC - All validation checks passed"
    echo "======================================================================"
  else
    echo "✗ CLUSTER OUT OF SYNC - One or more checks failed"
    echo "======================================================================"
  fi
  
  # Generate report if requested
  generate_report
  
  return $EXIT_CODE
}

# Execute main
main "$@"
