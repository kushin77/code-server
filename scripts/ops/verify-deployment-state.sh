#!/bin/bash
# @file        scripts/ops/verify-deployment-state.sh
# @module      ops/verification
# @description Verify cluster deployment state against expected IaC state
# @owner       infrastructure
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPLICA_1="192.168.168.31"
REPLICA_2="192.168.168.42"
VERIFY_DEPLOY_USER="${DEPLOY_USER:-akushnir}"
VERIFY_DEPLOY_DIR="${DEPLOY_DIR:-/home/akushnir/code-server-enterprise}"
DEFAULT_SSH_KEY_PATH="${HOME}/.ssh/id_rsa_onprem"
SSH_KEY="${SSH_KEY:-$DEFAULT_SSH_KEY_PATH}"

# Expected state after 4-phase deployment
EXPECTED_COMMIT="$(git rev-parse --short origin/main 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
EXPECTED_CONTAINERS_PER_REPLICA=20
EXPECTED_CLUSTER_CONTAINERS=40
MIN_HEALTH_CHECK=200
EXPECTED_NONOWNED_PATHS=("./prometheus-rules-slo-phase-8.yml")
EXPECTED_TRACKED_DRIFT_PATHS=(
  "apps/session-broker/Dockerfile"
  "docker-compose.yml"
  "docker-compose.replica.yml"
)

log_info "==================================================================="
log_info "CLUSTER DEPLOYMENT STATE VERIFICATION (IaC)"
log_info "==================================================================="
log_info "Expected Commit: $EXPECTED_COMMIT"
log_info "Expected Containers per Replica: $EXPECTED_CONTAINERS_PER_REPLICA"
log_info "Expected Cluster Containers: $EXPECTED_CLUSTER_CONTAINERS"
log_info ""

# State tracking
STATE_MATCH=0
REPLICAS_SYNCED=0
ERRORS=0
TOTAL_CONTAINERS=0
TOTAL_NONOWNED=0

ssh_remote() {
  local host="$1"
  local command="$2"
  ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "${VERIFY_DEPLOY_USER}@${host}" "$command"
}

is_expected_nonowned_path() {
  local path="$1"
  local expected_path
  for expected_path in "${EXPECTED_NONOWNED_PATHS[@]}"; do
    if [[ "$path" == "$expected_path" ]]; then
      return 0
    fi
  done
  return 1
}

is_expected_tracked_drift_path() {
  local path="$1"
  local expected_path
  for expected_path in "${EXPECTED_TRACKED_DRIFT_PATHS[@]}"; do
    if [[ "$path" == "$expected_path" ]]; then
      return 0
    fi
  done
  return 1
}

# =========================================================================
# VERIFY REPLICA 1
# =========================================================================

log_info "REPLICA 1 ($REPLICA_1)"
log_info "---"

# Commit check
REPLICA_1_COMMIT=$(ssh_remote "$REPLICA_1" "cd ${VERIFY_DEPLOY_DIR} && git rev-parse --short HEAD" 2>/dev/null || echo "ERROR")
log_info "Commit: $REPLICA_1_COMMIT (expected: $EXPECTED_COMMIT)"
if [[ "$REPLICA_1_COMMIT" == "$EXPECTED_COMMIT" ]]; then
  log_info "  ✓ Commit matches"
else
  log_warn "  ⚠ Commit mismatch"
  ERRORS=$((ERRORS + 1))
fi

# Git status check
REPLICA_1_DRIFT_RAW=$(ssh_remote "$REPLICA_1" "cd ${VERIFY_DEPLOY_DIR} && git status --short --untracked-files=no" 2>/dev/null || echo "ERROR")
REPLICA_1_DRIFT_FILTERED=""
while IFS= read -r drift_line; do
  [[ -z "$drift_line" ]] && continue
  drift_path="${drift_line#?? }"
  if ! is_expected_tracked_drift_path "$drift_path"; then
    REPLICA_1_DRIFT_FILTERED+="${drift_line}"$'\n'
  fi
done <<< "$REPLICA_1_DRIFT_RAW"
REPLICA_1_DRIFT=$(printf '%s' "$REPLICA_1_DRIFT_FILTERED" | sed '/^$/d' | wc -l)
log_info "Git drift (tracked only): $REPLICA_1_DRIFT files"
if [[ "$REPLICA_1_DRIFT" =~ ^[0-9]+$ ]] && [[ "$REPLICA_1_DRIFT" -eq 0 ]]; then
  log_info "  ✓ Git state clean for deployment-relevant files"
else
  log_warn "  ⚠ Unexpected git state drift present"
  ERRORS=$((ERRORS + 1))
fi

REPLICA_1_NONOWNED=$(ssh_remote "$REPLICA_1" "cd ${VERIFY_DEPLOY_DIR} && find . -maxdepth 2 \( -not -user ${VERIFY_DEPLOY_USER} -o -not -group ${VERIFY_DEPLOY_USER} \) -type f -printf '%P\n'" 2>/dev/null || echo "")
REPLICA_1_NONOWNED_FILTERED=""
while IFS= read -r nonowned_path; do
  [[ -z "$nonowned_path" ]] && continue
  if ! is_expected_nonowned_path "./${nonowned_path}"; then
    REPLICA_1_NONOWNED_FILTERED+="${nonowned_path}"$'\n'
  fi
done <<< "$REPLICA_1_NONOWNED"
REPLICA_1_NONOWNED_COUNT=$(printf '%s' "$REPLICA_1_NONOWNED_FILTERED" | sed '/^$/d' | wc -l)
log_info "Ownership drift (tracked only): $REPLICA_1_NONOWNED_COUNT files"
if [[ "$REPLICA_1_NONOWNED_COUNT" -eq 0 ]]; then
  log_info "  ✓ No unexpected ownership drift"
else
  log_warn "  ⚠ Unexpected ownership drift present"
  ERRORS=$((ERRORS + 1))
fi
TOTAL_NONOWNED=$((TOTAL_NONOWNED + REPLICA_1_NONOWNED_COUNT))

# Container count
REPLICA_1_CONTAINERS=$(ssh_remote "$REPLICA_1" "docker ps --format '{{.Names}}' | grep -vx 'ollama-init' | wc -l" 2>/dev/null || echo "ERROR")
log_info "Running containers: $REPLICA_1_CONTAINERS (expected: $EXPECTED_CONTAINERS_PER_REPLICA)"
if [[ "$REPLICA_1_CONTAINERS" =~ ^[0-9]+$ ]] && [[ "$REPLICA_1_CONTAINERS" -ge "$EXPECTED_CONTAINERS_PER_REPLICA" ]]; then
  log_info "  ✓ Container count OK"
else
  log_warn "  ⚠ Missing containers"
  ERRORS=$((ERRORS + 1))
fi
if [[ "$REPLICA_1_CONTAINERS" =~ ^[0-9]+$ ]]; then
  TOTAL_CONTAINERS=$((TOTAL_CONTAINERS + REPLICA_1_CONTAINERS))
fi

# Health check
REPLICA_1_HEALTH=$(ssh_remote "$REPLICA_1" "curl -sf http://localhost:8080/healthz >/dev/null && echo 200 || echo 000" 2>/dev/null || echo "000")
log_info "Health endpoint: HTTP $REPLICA_1_HEALTH (expected: 200)"
if [[ "$REPLICA_1_HEALTH" -eq 200 ]]; then
  log_info "  ✓ Health check passing"
else
  log_warn "  ⚠ Health check failing"
  ERRORS=$((ERRORS + 1))
fi

log_info ""

# =========================================================================
# VERIFY REPLICA 2
# =========================================================================

log_info "REPLICA 2 ($REPLICA_2)"
log_info "---"

# Commit check
REPLICA_2_COMMIT=$(ssh_remote "$REPLICA_2" "cd ${VERIFY_DEPLOY_DIR} && git rev-parse --short HEAD" 2>/dev/null || echo "ERROR")
log_info "Commit: $REPLICA_2_COMMIT (expected: $EXPECTED_COMMIT)"
if [[ "$REPLICA_2_COMMIT" == "$EXPECTED_COMMIT" ]]; then
  log_info "  ✓ Commit matches"
else
  log_warn "  ⚠ Commit mismatch"
  ERRORS=$((ERRORS + 1))
fi

# Git status check
REPLICA_2_DRIFT_RAW=$(ssh_remote "$REPLICA_2" "cd ${VERIFY_DEPLOY_DIR} && git status --short --untracked-files=no" 2>/dev/null || echo "ERROR")
REPLICA_2_DRIFT_FILTERED=""
while IFS= read -r drift_line; do
  [[ -z "$drift_line" ]] && continue
  drift_path="${drift_line#?? }"
  if ! is_expected_tracked_drift_path "$drift_path"; then
    REPLICA_2_DRIFT_FILTERED+="${drift_line}"$'\n'
  fi
done <<< "$REPLICA_2_DRIFT_RAW"
REPLICA_2_DRIFT=$(printf '%s' "$REPLICA_2_DRIFT_FILTERED" | sed '/^$/d' | wc -l)
log_info "Git drift (tracked only): $REPLICA_2_DRIFT files"
if [[ "$REPLICA_2_DRIFT" =~ ^[0-9]+$ ]] && [[ "$REPLICA_2_DRIFT" -eq 0 ]]; then
  log_info "  ✓ Git state clean for deployment-relevant files"
else
  log_warn "  ⚠ Unexpected git state drift present"
  ERRORS=$((ERRORS + 1))
fi

REPLICA_2_NONOWNED=$(ssh_remote "$REPLICA_2" "cd ${VERIFY_DEPLOY_DIR} && find . -maxdepth 2 \( -not -user ${VERIFY_DEPLOY_USER} -o -not -group ${VERIFY_DEPLOY_USER} \) -type f -printf '%P\n'" 2>/dev/null || echo "")
REPLICA_2_NONOWNED_FILTERED=""
while IFS= read -r nonowned_path; do
  [[ -z "$nonowned_path" ]] && continue
  if ! is_expected_nonowned_path "./${nonowned_path}"; then
    REPLICA_2_NONOWNED_FILTERED+="${nonowned_path}"$'\n'
  fi
done <<< "$REPLICA_2_NONOWNED"
REPLICA_2_NONOWNED_COUNT=$(printf '%s' "$REPLICA_2_NONOWNED_FILTERED" | sed '/^$/d' | wc -l)
log_info "Ownership drift (tracked only): $REPLICA_2_NONOWNED_COUNT files"
if [[ "$REPLICA_2_NONOWNED_COUNT" -eq 0 ]]; then
  log_info "  ✓ No unexpected ownership drift"
else
  log_warn "  ⚠ Unexpected ownership drift present"
  ERRORS=$((ERRORS + 1))
fi
TOTAL_NONOWNED=$((TOTAL_NONOWNED + REPLICA_2_NONOWNED_COUNT))

# Container count
REPLICA_2_CONTAINERS=$(ssh_remote "$REPLICA_2" "docker ps --format '{{.Names}}' | grep -vx 'ollama-init' | wc -l" 2>/dev/null || echo "ERROR")
log_info "Running containers: $REPLICA_2_CONTAINERS (expected: $EXPECTED_CONTAINERS_PER_REPLICA)"
if [[ "$REPLICA_2_CONTAINERS" =~ ^[0-9]+$ ]] && [[ "$REPLICA_2_CONTAINERS" -ge "$EXPECTED_CONTAINERS_PER_REPLICA" ]]; then
  log_info "  ✓ Container count OK"
else
  log_warn "  ⚠ Missing containers"
  ERRORS=$((ERRORS + 1))
fi
if [[ "$REPLICA_2_CONTAINERS" =~ ^[0-9]+$ ]]; then
  TOTAL_CONTAINERS=$((TOTAL_CONTAINERS + REPLICA_2_CONTAINERS))
fi

# Health check
REPLICA_2_HEALTH=$(ssh_remote "$REPLICA_2" "curl -sf http://localhost:8080/healthz >/dev/null && echo 200 || echo 000" 2>/dev/null || echo "000")
log_info "Health endpoint: HTTP $REPLICA_2_HEALTH (expected: 200)"
if [[ "$REPLICA_2_HEALTH" -eq 200 ]]; then
  log_info "  ✓ Health check passing"
else
  log_warn "  ⚠ Health check failing"
  ERRORS=$((ERRORS + 1))
fi

log_info ""

# =========================================================================
# VERIFY PARITY
# =========================================================================

log_info "CLUSTER PARITY CHECK"
log_info "---"

if [[ "$REPLICA_1_COMMIT" == "$REPLICA_2_COMMIT" && "$REPLICA_1_COMMIT" == "$EXPECTED_COMMIT" ]]; then
  log_info "✓ Both replicas on commit $EXPECTED_COMMIT"
  REPLICAS_SYNCED=1
else
  log_warn "⚠ Replicas not synced"
  log_warn "  Replica 1: $REPLICA_1_COMMIT"
  log_warn "  Replica 2: $REPLICA_2_COMMIT"
fi

if [[ "$REPLICA_1_DRIFT" =~ ^[0-9]+$ ]] && [[ "$REPLICA_2_DRIFT" =~ ^[0-9]+$ ]] && [[ "$REPLICA_1_DRIFT" -eq 0 && "$REPLICA_2_DRIFT" -eq 0 ]]; then
  log_info "✓ Both replicas have clean git state (no drift)"
else
  log_warn "⚠ Git drift detected"
fi

if [[ "$TOTAL_NONOWNED" -eq 0 ]]; then
  log_info "✓ No unexpected ownership drift detected"
else
  log_warn "⚠ Unexpected ownership drift detected"
fi

log_info "✓ Cluster container total: ${TOTAL_CONTAINERS} (expected: ${EXPECTED_CLUSTER_CONTAINERS})"
if [[ "$TOTAL_CONTAINERS" -ne "$EXPECTED_CLUSTER_CONTAINERS" ]]; then
  log_warn "⚠ Cluster container total does not match expected total"
  ERRORS=$((ERRORS + 1))
fi

log_info ""

# =========================================================================
# SUMMARY
# =========================================================================

log_info "==================================================================="
if [[ $ERRORS -eq 0 && $REPLICAS_SYNCED -eq 1 ]]; then
  log_info "✓ DEPLOYMENT STATE VERIFIED - CLUSTER PARITY ACHIEVED"
  log_info "==================================================================="
  exit 0
else
  log_warn "⚠ DEPLOYMENT STATE INCOMPLETE - ISSUES DETECTED ($ERRORS errors)"
  log_info "==================================================================="
  exit 1
fi
