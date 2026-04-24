#!/usr/bin/env bash
# @file        scripts/ops/sync-env-to-replicas.sh
# @module      ops/environment-sync
# @description Fetch secrets from GSM and synchronize .env to all cluster replicas
#
# USAGE:
#   bash scripts/ops/sync-env-to-replicas.sh [--dry-run] [--verbose]
#
# EXAMPLES:
#   # Sync .env to both replicas (production)
#   bash scripts/ops/sync-env-to-replicas.sh
#
#   # Test what would be synced without making changes
#   bash scripts/ops/sync-env-to-replicas.sh --dry-run
#
#   # Show detailed output for debugging
#   bash scripts/ops/sync-env-to-replicas.sh --verbose
#
# WORKFLOW:
#   1. Load default environment from .env.defaults
#   2. Fetch secrets from Google Secret Manager (GSM)
#   3. Merge GSM secrets with defaults
#   4. Validate all required keys are present
#   5. Compute .env file hash
#   6. Sync to Replica 1 (192.168.168.31)
#   7. Sync to Replica 2 (192.168.168.42)
#   8. Verify checksums match on all replicas
#   9. Report sync status
#
# PREREQUISITES:
#   - gcloud CLI installed and authenticated
#   - SSH access to both replicas
#   - .env.defaults file present in repository
#   - .env.schema.json file present for validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

REPLICAS=(
  "akushnir@192.168.168.31:code-server-enterprise"
  "akushnir@192.168.168.42:code-server-enterprise"
)

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
if [[ -z "${SSH_OPTS:-}" ]]; then
  SSH_OPTS="-i ${SSH_KEY} -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
fi

ENV_DEFAULTS=".env.defaults"
ENV_SCHEMA=".env.schema.json"
ENV_TARGET=".env"
TEMP_ENV="/tmp/.env.merged-$$"

DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-0}"

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

parse_replica() {
  local replica=$1
  echo "${replica%:*}"  # Return user@host part
}

get_replica_path() {
  local replica=$1
  echo "${replica#*:}"  # Return path part (after colon)
}

# Fetch secret from GSM
fetch_gsm_secret() {
  local secret_name=$1
  gcloud secrets versions access latest --secret="$secret_name" 2>/dev/null || echo ""
}

# Run command on replica via SSH
run_on_replica() {
  local replica=$1
  shift
  local host=$(parse_replica "$replica")
  local cmd="$@"
  
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] ssh $SSH_OPTS $host '$cmd'"
    return 0
  fi
  
  ssh $SSH_OPTS "$host" "$cmd" 2>&1
}

log_section "Environment Synchronization to All Replicas"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1: Validate Prerequisites
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 1: Validate Prerequisites"

if [[ ! -f "$ENV_DEFAULTS" ]]; then
  log_fatal "Missing $ENV_DEFAULTS - cannot proceed"
  exit 1
fi
log_info "✅ Found $ENV_DEFAULTS"

if [[ ! -f "$ENV_SCHEMA" ]]; then
  log_warn "⚠ Missing $ENV_SCHEMA (validation skipped)"
else
  log_info "✅ Found $ENV_SCHEMA"
fi

# Check gcloud is available
if ! command -v gcloud &>/dev/null; then
  log_fatal "gcloud CLI not found - GSM access unavailable"
  exit 1
fi
log_info "✅ gcloud CLI available"

# Check SSH key
if [[ ! -f "$SSH_KEY" ]]; then
  log_warn "⚠ SSH key not found at $SSH_KEY - SSH operations may fail"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2: Load and Merge Environment
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 2: Load and Merge Environment Configuration"

# Start with defaults
cp "$ENV_DEFAULTS" "$TEMP_ENV"
log_info "✅ Loaded defaults from $ENV_DEFAULTS"

# Fetch critical secrets from GSM and merge
declare -a GSM_SECRETS=(
  "IDE_SESSION_LB_SECRET"
  "CODE_SERVER_PASSWORD"
  "GITHUB_TOKEN"
  "APEX_DOMAIN"
  "IDE_DOMAIN"
  "PORTAL_DOMAIN"
)

log_info "Fetching secrets from GSM..."
for secret in "${GSM_SECRETS[@]}"; do
  value=$(fetch_gsm_secret "$secret")
  if [[ -n "$value" ]]; then
    # Add or update in merged .env
    if grep -q "^${secret}=" "$TEMP_ENV"; then
      sed -i.bak "s|^${secret}=.*|${secret}=${value}|" "$TEMP_ENV"
      [[ "$VERBOSE" -eq 1 ]] && log_info "  ✓ Updated $secret from GSM"
    else
      echo "${secret}=${value}" >> "$TEMP_ENV"
      [[ "$VERBOSE" -eq 1 ]] && log_info "  ✓ Added $secret from GSM"
    fi
  else
    log_warn "  ⚠ GSM secret not found: $secret (using default if present)"
  fi
done

log_info "✅ Merged secrets from GSM"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3: Validate Required Keys
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 3: Validate Required Configuration Keys"

declare -a REQUIRED_KEYS=(
  "APEX_DOMAIN"
  "IDE_DOMAIN"
  "PORTAL_DOMAIN"
  "CODE_SERVER_PASSWORD"
  "IDE_SESSION_LB_SECRET"
)

validation_failed=0
for key in "${REQUIRED_KEYS[@]}"; do
  if grep -q "^${key}=" "$TEMP_ENV"; then
    log_info "  ✓ $key present"
  else
    log_error "  ✗ $key MISSING"
    validation_failed=1
  fi
done

if [[ $validation_failed -eq 1 ]]; then
  log_fatal "Missing required environment keys - cannot proceed"
  rm -f "$TEMP_ENV" "$TEMP_ENV.bak"
  exit 1
fi

log_info "✅ All required keys present and valid"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4: Compute Hash and Prepare for Sync
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 4: Prepare Environment for Sync"

LOCAL_HASH=$(sha256sum "$TEMP_ENV" | awk '{print $1}')
log_info "Local .env hash: $LOCAL_HASH"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log_info "[dry-run] Would sync .env with hash: $LOCAL_HASH"
  log_info "[dry-run] File size: $(stat -c %s "$TEMP_ENV" 2>/dev/null || stat -f %z "$TEMP_ENV" 2>/dev/null || echo 'unknown') bytes"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 5: Sync to All Replicas
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 5: Synchronize to All Replicas"

sync_failed=0
for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  path=$(get_replica_path "$replica")
  
  log_info "Syncing to $host..."
  
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "  [dry-run] scp $TEMP_ENV $host:$path/.env"
    log_info "  [dry-run] ssh $host 'sha256sum $path/.env'"
    continue
  fi
  
  # Upload .env file
  if scp $SSH_OPTS "$TEMP_ENV" "$host:$path/.env" 2>&1 | grep -v "Warning"; then
    log_info "  ✓ Uploaded .env to $host"
  else
    log_error "  ✗ Failed to upload .env to $host"
    sync_failed=1
    continue
  fi
  
  # Verify hash on remote
  remote_hash=$(ssh $SSH_OPTS "$host" "sha256sum $path/.env 2>/dev/null | awk '{print \$1}'" 2>&1)
  if [[ "$remote_hash" == "$LOCAL_HASH" ]]; then
    log_info "  ✓ Hash verified on $host: $remote_hash"
  else
    log_error "  ✗ Hash mismatch on $host"
    log_error "    Expected: $LOCAL_HASH"
    log_error "    Got:      $remote_hash"
    sync_failed=1
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Phase 6: Final Verification
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 6: Final Verification"

if [[ $sync_failed -eq 1 ]]; then
  log_error "❌ Sync encountered errors - review log above"
  rm -f "$TEMP_ENV" "$TEMP_ENV.bak"
  exit 1
fi

log_info "✅ Environment successfully synchronized to all replicas"
log_info "   $(echo "${REPLICAS[@]}" | tr ' ' '\n' | wc -l) replicas updated with hash: $LOCAL_HASH"

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────

rm -f "$TEMP_ENV" "$TEMP_ENV.bak"
log_info "✅ Cleanup complete"

exit 0
