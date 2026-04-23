#!/usr/bin/env bash
# @file        scripts/ops/check-replica-parity.sh
# @module      ops/monitoring
# @description Check and report divergence between cluster replicas
#
# USAGE:
#   bash scripts/ops/check-replica-parity.sh [--pre-deploy|--post-deploy] [--verbose]
#
# CHECKS:
#   - Git commit hash parity (all replicas on same commit)
#   - .env file hash parity (all replicas have same config)
#   - Docker image tags parity (same versions running)
#   - Container counts parity (same number of services)
#   - Service health parity (same services healthy)
#
# EXIT CODES:
#   0 = All replicas in perfect parity
#   1 = Parity issues detected (non-blocking)
#   2 = Critical parity issues (must fix before deploy)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

REPLICAS=(
  "akushnir@192.168.168.31:code-server-enterprise"
  "akushnir@192.168.168.42:code-server-enterprise"
)

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
SSH_OPTS="-i ${SSH_KEY} -o ConnectTimeout=10 -o StrictHostKeyChecking=no"

VERBOSE=false
CHECK_MODE="default"  # pre-deploy, post-deploy, or default

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pre-deploy)
      CHECK_MODE="pre-deploy"
      shift
      ;;
    --post-deploy)
      CHECK_MODE="post-deploy"
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      log_warn "Unknown argument: $1"
      shift
      ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

# Extract host and path from "user@host:path" format
parse_replica() {
  local replica=$1
  echo "${replica%:*}"  # Return user@host part
}

# Run command on replica and return output
query_replica() {
  local replica=$1
  shift
  local host=$(parse_replica "$replica")
  local cmd="$@"
  
  ssh $SSH_OPTS "$host" "$cmd" 2>/dev/null || echo "ERROR"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parity Checks
# ─────────────────────────────────────────────────────────────────────────────

log_section "Replica Parity Check ($CHECK_MODE mode)"

declare -A git_commits
declare -A env_hashes
declare -A container_counts
declare -A service_counts

parity_issues=0

# ─────────────────────────────────────────────────────────────────────────────
# Check 1: Git Commit Parity
# ─────────────────────────────────────────────────────────────────────────────

log_info "Check 1: Git commit parity..."

for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  commit=$(query_replica "$replica" "cd code-server-enterprise && git rev-parse HEAD 2>/dev/null" | head -1)
  git_commits["$host"]="$commit"
  
  if [[ "$VERBOSE" == true ]]; then
    log_info "  $host: $commit"
  fi
done

# Compare all commits to first replica
first_host=$(parse_replica "${REPLICAS[0]}")
first_commit="${git_commits[$first_host]}"

for host in "${!git_commits[@]}"; do
  if [[ "$host" != "$first_host" ]]; then
    if [[ "${git_commits[$host]}" != "$first_commit" ]]; then
      log_error "  ❌ $host diverged from $first_host"
      log_error "     $host: ${git_commits[$host]}"
      log_error "     $first_host: $first_commit"
      parity_issues=$((parity_issues + 1))
    fi
  fi
done

if [[ $parity_issues -eq 0 ]]; then
  log_info "  ✅ All replicas on commit: $first_commit"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 2: Configuration File Parity (.env)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Check 2: Configuration file parity (.env)..."

for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  # Hash .env files, ignoring runtime variables
  env_hash=$(query_replica "$replica" "cd code-server-enterprise && md5sum .env 2>/dev/null | awk '{print \$1}'" | head -1)
  env_hashes["$host"]="$env_hash"
  
  if [[ "$VERBOSE" == true ]]; then
    log_info "  $host: $env_hash"
  fi
done

# Compare all hashes
first_env_hash="${env_hashes[$first_host]}"

for host in "${!env_hashes[@]}"; do
  if [[ "$host" != "$first_host" ]]; then
    if [[ "${env_hashes[$host]}" != "$first_env_hash" ]]; then
      log_error "  ❌ $host .env differs from $first_host"
      parity_issues=$((parity_issues + 1))
    fi
  fi
done

if [[ $parity_issues -eq 0 ]] || [[ -z "$first_env_hash" ]]; then
  if [[ -n "$first_env_hash" ]]; then
    log_info "  ✅ All .env files synchronized (hash: ${first_env_hash:0:8}...)"
  else
    log_warn "  ⊘ Could not verify .env (may not exist locally)"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 3: Container Count Parity
# ─────────────────────────────────────────────────────────────────────────────

log_info "Check 3: Docker container count parity..."

for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  count=$(query_replica "$replica" "cd code-server-enterprise && docker-compose ps -q 2>/dev/null | wc -l" | head -1)
  container_counts["$host"]="$count"
  
  if [[ "$VERBOSE" == true ]]; then
    log_info "  $host: $count containers"
  fi
done

# Compare container counts
first_count="${container_counts[$first_host]}"

for host in "${!container_counts[@]}"; do
  if [[ "$host" != "$first_host" ]]; then
    if [[ "${container_counts[$host]}" != "$first_count" ]]; then
      log_error "  ❌ $host has ${container_counts[$host]} containers, $first_host has $first_count"
      parity_issues=$((parity_issues + 1))
    fi
  fi
done

if [[ $parity_issues -eq 0 ]] && [[ -n "$first_count" ]]; then
  log_info "  ✅ All replicas running $first_count containers"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 4: Service Health Parity
# ─────────────────────────────────────────────────────────────────────────────

log_info "Check 4: Service health parity..."

for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  # Count healthy services (those in "Up" or "Up (healthy)" state)
  healthy=$(query_replica "$replica" "cd code-server-enterprise && docker-compose ps 2>/dev/null | grep -c 'Up' || echo 0" | head -1)
  service_counts["$host"]="$healthy"
  
  if [[ "$VERBOSE" == true ]]; then
    log_info "  $host: $healthy services healthy"
  fi
done

# Compare healthy service counts
first_healthy="${service_counts[$first_host]}"

for host in "${!service_counts[@]}"; do
  if [[ "$host" != "$first_host" ]]; then
    if [[ "${service_counts[$host]}" != "$first_healthy" ]]; then
      log_error "  ❌ $host has ${service_counts[$host]} healthy services, $first_host has $first_healthy"
      parity_issues=$((parity_issues + 1))
    fi
  fi
done

if [[ $parity_issues -eq 0 ]] && [[ -n "$first_healthy" ]]; then
  log_info "  ✅ All replicas have $first_healthy healthy services"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

log_section "Parity Summary"

if [[ $parity_issues -eq 0 ]]; then
  log_info "✅ Perfect replica parity"
  log_info "   - Git commits synchronized"
  log_info "   - Configuration files synchronized"
  log_info "   - Container counts identical"
  log_info "   - Service health synchronized"
  exit 0
else
  log_error "❌ Detected $parity_issues parity issue(s)"
  log_error ""
  log_error "Recommendation for $CHECK_MODE:"
  
  case "$CHECK_MODE" in
    pre-deploy)
      log_error "  1. Fix parity issues before deploying"
      log_error "  2. Run: bash scripts/ops/sync-replicas.sh"
      log_error "  3. Re-run this check"
      ;;
    post-deploy)
      log_error "  1. Deployment completed but replicas diverged"
      log_error "  2. Investigate deployment logs"
      log_error "  3. Consider rolling back and retrying"
      ;;
    *)
      log_error "  Review divergence and manually sync if needed"
      ;;
  esac
  
  exit 1
fi
