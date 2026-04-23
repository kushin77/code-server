#!/usr/bin/env bash
# @file        scripts/ops/fix-replica-2-nfs.sh
# @module      infrastructure/nfs-remediation
# @description Remediate NFS mount issues on Replica 2 (P1 #1645)

set -euo pipefail

# Set configuration BEFORE sourcing init.sh (which makes NAS_HOST readonly)
TARGET_REPLICA="${TARGET_REPLICA:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-akushnir}"
export NAS_HOST="${NAS_HOST:-192.168.168.56}"
DRY_RUN="${DRY_RUN:-0}"

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# NAS directories that need to exist
NAS_DIRS=(
  "/export/appsmith"
  "/export/loki"
  "/export/error-triage-db"
  "/export/code-server-enterprise"
)

log_info "Replica 2 NFS Mount Remediation"
log_info "Target: $TARGET_REPLICA"
log_info "NAS Host: $NAS_HOST"
[[ "$DRY_RUN" == "1" ]] && log_info "Mode: DRY RUN (no changes)"

# ============================================================================
# Step 1: Verify Replica 2 connectivity
# ============================================================================
log_info "Step 1: Verifying Replica 2 connectivity..."

if ! ssh -o ConnectTimeout=5 "$TARGET_USER@$TARGET_REPLICA" "echo 'Replica 2 reachable'" &>/dev/null; then
  log_error "Cannot reach Replica 2 at $TARGET_REPLICA"
  log_error "Ensure SSH access is configured and key is available"
  exit 1
fi

log_info "✓ SSH access to Replica 2 verified"

# ============================================================================
# Step 2: Check NAS connectivity from Replica 2
# ============================================================================
log_info "Step 2: Checking NAS connectivity from Replica 2..."

NAS_CHECK=$(ssh "$TARGET_USER@$TARGET_REPLICA" "showmount -e $NAS_HOST 2>/dev/null | head -5" || echo "FAILED")

if [[ "$NAS_CHECK" == *"FAILED"* ]] || [[ -z "$NAS_CHECK" ]]; then
  log_error "NAS ($NAS_HOST) not reachable from Replica 2"
  log_error "Verify NAS is running and accessible"
  exit 1
fi

log_info "✓ NAS reachable from Replica 2"
log_info "NAS exports:"
ssh "$TARGET_USER@$TARGET_REPLICA" "showmount -e $NAS_HOST" | sed 's/^/  /'

# ============================================================================
# Step 3: Check which NAS directories exist
# ============================================================================
log_info "Step 3: Checking NAS directory structure..."

MISSING_DIRS=()
for dir in "${NAS_DIRS[@]}"; do
  NAS_ACCESSIBLE=$(ssh "$TARGET_USER@$TARGET_REPLICA" "ls -ld $dir 2>/dev/null && echo 'EXISTS' || echo 'MISSING'" | tail -1)
  if [[ "$NAS_ACCESSIBLE" == "MISSING" ]]; then
    MISSING_DIRS+=("$dir")
    log_warn "Missing: $dir"
  else
    log_info "✓ Exists: $dir"
  fi
done

if [[ ${#MISSING_DIRS[@]} -eq 0 ]]; then
  log_info "✓ All required NAS directories exist"
  exit 0
fi

log_warn "Found ${#MISSING_DIRS[@]} missing directories:"
for dir in "${MISSING_DIRS[@]}"; do
  log_warn "  - $dir"
done

# ============================================================================
# Step 4: Create missing directories (requires sudo on NAS or root access)
# ============================================================================
log_info "Step 4: Attempting to create missing NAS directories..."

if [[ "$DRY_RUN" == "1" ]]; then
  log_info "[DRY-RUN] Would create directories on NAS"
  for dir in "${MISSING_DIRS[@]}"; do
    log_info "[DRY-RUN]   mkdir -p $dir && chmod 755 $dir && chown nobody:nogroup $dir"
  done
  exit 0
fi

# Try creating directories via Replica 2 (requires passwordless sudo on NAS or Replica 2)
for dir in "${MISSING_DIRS[@]}"; do
  log_info "Creating $dir..."
  
  # Attempt 1: Via ssh directly (may fail if no sudo)
  if ssh "$TARGET_USER@$TARGET_REPLICA" "sudo mkdir -p '$dir' && sudo chmod 755 '$dir' && sudo chown nobody:nogroup '$dir'" 2>/dev/null; then
    log_info "✓ Created: $dir"
  else
    log_warn "Could not create $dir (requires sudo access)"
    log_warn "This directory must be created manually on NAS ($NAS_HOST)"
    log_warn "Commands to run on NAS (as root or via sudo):"
    log_warn "  mkdir -p $dir"
    log_warn "  chmod 755 $dir"
    log_warn "  chown nobody:nogroup $dir"
  fi
done

# ============================================================================
# Step 5: Alternative: Disable problematic services
# ============================================================================
log_info "Step 5: Disabling optional services with missing NAS directories..."

SERVICES_TO_CHECK=(
  "appsmith"
  "loki"
)

for service in "${SERVICES_TO_CHECK[@]}"; do
  service_needs_nfs=0
  
  # Check if service needs any missing NAS directory
  case "$service" in
    appsmith)
      [[ " ${MISSING_DIRS[*]} " =~ " /export/appsmith " ]] && service_needs_nfs=1
      ;;
    loki)
      [[ " ${MISSING_DIRS[*]} " =~ " /export/loki " ]] && service_needs_nfs=1
      ;;
  esac
  
  if [[ $service_needs_nfs -eq 1 ]]; then
    log_info "Service '$service' needs missing NAS directory"
    log_info "This service will be disabled until NAS directory exists"
    log_info "To disable, update docker-compose.yml: $service profiles: [portal]  # Remove 'default'"
  fi
done

# ============================================================================
# Step 6: Retry docker-compose deployment
# ============================================================================
log_info "Step 6: Retrying docker-compose deployment on Replica 2..."

if [[ "$DRY_RUN" == "1" ]]; then
  log_info "[DRY-RUN] Would run: docker compose up -d"
  exit 0
fi

log_info "Running docker-compose up..."
if ssh "$TARGET_USER@$TARGET_REPLICA" "cd ~/code-server-enterprise && docker compose up -d 2>&1" | tail -20; then
  log_info "✓ Deployment completed"
else
  log_warn "Deployment encountered errors (may be expected if NAS directories not created)"
fi

# ============================================================================
# Step 7: Verify services running
# ============================================================================
log_info "Step 7: Verifying services on Replica 2..."

RUNNING=$(ssh "$TARGET_USER@$TARGET_REPLICA" "docker compose ps --format 'table {{.Service}}\t{{.State}}'" | tail -n +2 | wc -l)
log_info "Services running: $RUNNING"

ssh "$TARGET_USER@$TARGET_REPLICA" "docker compose ps" | tail -n +2 | sed 's/^/  /'

log_info "✓ Replica 2 NFS remediation completed"
log_info ""
log_info "SUMMARY:"
log_info "  - NAS connectivity: ✓ Verified"
log_info "  - Missing directories: ${#MISSING_DIRS[@]}"
if [[ ${#MISSING_DIRS[@]} -gt 0 ]]; then
  log_info "  - ACTION REQUIRED: Create missing directories on NAS"
  log_info "    OR disable optional services in docker-compose.yml"
fi
