#!/usr/bin/env bash
# @file        scripts/ops/pre-flight-deployment-check.sh
# @module      ops/deployment
# @description Pre-flight validation for production deployments (IaC compliance check)
#
# Validates deployment prerequisites before execution:
# - SSH connectivity to both replicas
# - Git state (clean working tree)
# - NAS connectivity (mount test)
# - File permissions (akushnir:akushnir ownership)
# - Disk space (minimum 10GB free)
# - docker-compose syntax validation
#
# Usage: bash scripts/ops/pre-flight-deployment-check.sh [--replicas R31,R42] [--json] [--strict]
#
# Exit Codes:
#   0 = All checks passed
#   1 = One or more checks failed (warning level)
#   2 = Critical check failed (deployment blocked)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
REPLICAS="${REPLICAS:-}"
SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"
DEFAULT_SSH_KEY_PATH="${HOME}/.ssh/id_rsa_onprem"
SSH_KEY="${SSH_KEY:-$DEFAULT_SSH_KEY_PATH}"
PRECHECK_NAS_HOST="${NAS_HOST:-}"
PRECHECK_NAS_EXPORT="${NAS_EXPORT_PATH:-/export}/appsmith"
MIN_DISK_GB=10
JSON_OUTPUT=0
STRICT_MODE=0

if [[ -z "$REPLICAS" ]]; then
  if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
    REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
  else
    log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before running the pre-flight check"
  fi
fi

if [[ -z "$SSH_USER" ]]; then
  log_fatal "Set SSH_USER or DEPLOY_USER before running the pre-flight check"
fi

if [[ -z "$PRECHECK_NAS_HOST" ]]; then
  log_fatal "Set NAS_HOST before running the pre-flight check"
fi

# Tracking
CHECKS_PASSED=0
CHECKS_WARNED=0
CHECKS_FAILED=0
CHECK_RESULTS=()

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --replicas)
      REPLICAS="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    --strict)
      STRICT_MODE=1
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 2
      ;;
  esac
done

# ============================================================================
# Helper Functions
# ============================================================================

check_pass() {
  local name="$1"
  local detail="${2:-}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  CHECK_RESULTS+=("PASS|$name|$detail")
  log_info "✅ $name${detail:+ — $detail}"
}

check_warn() {
  local name="$1"
  local detail="${2:-}"
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
  CHECK_RESULTS+=("WARN|$name|$detail")
  log_warn "⚠️  $name${detail:+ — $detail}"
}

check_fail() {
  local name="$1"
  local detail="${2:-}"
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  CHECK_RESULTS+=("FAIL|$name|$detail")
  log_error "❌ $name${detail:+ — $detail}"
}

output_json() {
  local status="PASS"
  [[ $CHECKS_FAILED -gt 0 ]] && status="FAIL"
  [[ $CHECKS_WARNED -gt 0 && $CHECKS_FAILED -eq 0 ]] && status="WARN"

  cat <<EOF
{
  "status": "$status",
  "checks_passed": $CHECKS_PASSED,
  "checks_warned": $CHECKS_WARNED,
  "checks_failed": $CHECKS_FAILED,
  "results": [
EOF

  local first=1
  for result in "${CHECK_RESULTS[@]}"; do
    IFS='|' read -r res_type res_name res_detail <<<"$result"
    [[ $first -eq 0 ]] && echo ","
    printf '    {"type": "%s", "name": "%s", "detail": "%s"}' "$res_type" "$res_name" "$res_detail"
    first=0
  done

  echo ""
  echo "  ]"
  echo "}"
}

# ============================================================================
# Pre-Flight Checks
# ============================================================================

log_info "=== PRE-FLIGHT DEPLOYMENT CHECK ==="
log_info "Deployment IaC validation for: $REPLICAS"
log_info ""

# --- Check 1: SSH Key Availability ---
log_info "CHECK: SSH key availability"
if [[ -f "$SSH_KEY" ]]; then
  check_pass "SSH key present" "$SSH_KEY"
else
  check_fail "SSH key missing" "Required: $SSH_KEY"
fi

# --- Check 2: Local Git State ---
log_info "CHECK: Local git repository state"
if cd "$REPO_ROOT" 2>/dev/null; then
  if git status --short | grep -q .; then
    check_warn "Git working tree dirty" "$(git status --short | wc -l) uncommitted changes"
  else
    check_pass "Git working tree clean"
  fi

  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "UNKNOWN")
  commit=$(git rev-parse --short HEAD 2>/dev/null || echo "UNKNOWN")
  check_pass "Git state" "branch=$branch commit=$commit"
else
  check_fail "Local repository not found" "$REPO_ROOT"
fi

# --- Check 3: SSH Connectivity to Replicas ---
log_info "CHECK: SSH connectivity to replicas"
IFS=',' read -ra REPLICA_ARRAY <<<"$REPLICAS"

for replica in "${REPLICA_ARRAY[@]}"; do
  replica="${replica// /}"  # Remove spaces
  if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$replica" "echo OK" >/dev/null 2>&1; then
    check_pass "SSH connectivity" "$replica"
  else
    check_fail "SSH connectivity failed" "$replica"
  fi
done

# --- Check 4: File Permissions (sample check) ---
log_info "CHECK: File ownership on local repo"
if [[ -d "$REPO_ROOT/.git" ]]; then
  owner=$(stat -c '%U:%G' "$REPO_ROOT/.git" 2>/dev/null || echo "UNKNOWN")
  if [[ "$owner" == *"akushnir"* ]]; then
    check_pass "Git directory ownership" "$owner"
  else
    check_warn "Git directory not owned by akushnir" "$owner"
  fi
fi

# --- Check 5: Disk Space on Replicas ---
log_info "CHECK: Disk space availability"
for replica in "${REPLICA_ARRAY[@]}"; do
  replica="${replica// /}"
  disk_free_gb=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 "$SSH_USER@$replica" \
    "df /home/akushnir/code-server-enterprise | tail -1 | awk '{print \$4}'" 2>/dev/null || echo "0")
  disk_free_gb=$((disk_free_gb / 1024 / 1024))  # Convert KB to GB

  if [[ $disk_free_gb -ge $MIN_DISK_GB ]]; then
    check_pass "Disk space on $replica" "${disk_free_gb}GB free (need $MIN_DISK_GB GB)"
  else
    check_fail "Low disk space on $replica" "${disk_free_gb}GB free (need $MIN_DISK_GB GB)"
  fi
done

# --- Check 6: docker-compose Syntax ---
log_info "CHECK: docker-compose configuration syntax"
if cd "$REPO_ROOT" 2>/dev/null; then
  if command -v docker-compose >/dev/null 2>&1; then
    if docker-compose config >/dev/null 2>&1; then
      check_pass "docker-compose syntax valid"
    else
      check_fail "docker-compose syntax invalid" "Run: docker-compose config"
    fi
  elif command -v docker >/dev/null 2>&1; then
    if docker compose config >/dev/null 2>&1; then
      check_pass "docker compose syntax valid"
    else
      check_fail "docker compose syntax invalid" "Run: docker compose config"
    fi
  else
    check_warn "docker tooling unavailable" "Skipping local compose syntax validation"
  fi
fi

# --- Check 7: NAS Connectivity (Sample) ---
log_info "CHECK: NAS connectivity"
if ping -c 1 -W 2 "$PRECHECK_NAS_HOST" >/dev/null 2>&1; then
  check_pass "NAS host reachable" "$PRECHECK_NAS_HOST"

  if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$PRECHECK_NAS_HOST" "test -d '$PRECHECK_NAS_EXPORT'" >/dev/null 2>&1; then
    check_pass "NAS export path present" "$PRECHECK_NAS_EXPORT"
  else
    check_fail "NAS export path missing" "$PRECHECK_NAS_EXPORT on $PRECHECK_NAS_HOST"
  fi
else
  check_warn "NAS host unreachable" "$PRECHECK_NAS_HOST (non-critical, services can start without NAS)"
fi

# ============================================================================
# Summary & Exit
# ============================================================================

log_info ""
log_info "=== SUMMARY ==="
log_info "Passed: $CHECKS_PASSED | Warned: $CHECKS_WARNED | Failed: $CHECKS_FAILED"

if [[ $JSON_OUTPUT -eq 1 ]]; then
  log_info ""
  output_json
fi

# Determine exit code
if [[ $CHECKS_FAILED -gt 0 ]]; then
  if [[ $STRICT_MODE -eq 1 ]]; then
    log_error "Pre-flight check FAILED (strict mode)"
    exit 2
  else
    log_warn "Pre-flight check completed with failures (non-strict mode)"
    exit 1
  fi
elif [[ $CHECKS_WARNED -gt 0 ]]; then
  log_warn "Pre-flight check completed with warnings"
  exit 0
else
  log_info "✅ All pre-flight checks passed — deployment safe to proceed"
  exit 0
fi
