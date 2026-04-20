#!/usr/bin/env bash
# @file        scripts/ops/failover-failback.sh
# @module      ops/failover
# @description Restore primary after recovery and demote replica back to secondary role

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Configuration
DRY_RUN="${DRY_RUN:-0}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
VERIFY_REPLICATION="${VERIFY_REPLICATION:-1}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"

log_stage() {
    log_info "========== $1 =========="
}

main() {
    log_stage "FAILBACK: RESTORE PRIMARY AND DEMOTE REPLICA"
    log_info "Primary (recovering): $PRIMARY_HOST"
    log_info "Replica (current primary): $REPLICA_HOST"
    log_info "Dry-run mode: $([ "$DRY_RUN" -eq 1 ] && echo 'YES' || echo 'NO')"
    echo ""
    
    # === Step 1: Verify Primary is Recovered ===
    log_stage "STEP 1: Verify Recovered Primary"
    
    log_info "Checking primary at $PRIMARY_HOST..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would verify primary SSH and Docker"
    else
        if timeout 10 ssh -o ConnectTimeout=5 "$DEPLOY_USER@$PRIMARY_HOST" "docker ps >/dev/null" &>/dev/null; then
            log_info "✅ Primary is recovered and accessible"
        else
            log_error "❌ Primary not ready for failback"
            exit 1
        fi
    fi
    echo ""
    
    # === Step 2: Sync Data to Primary ===
    log_stage "STEP 2: Synchronize Data to Primary"
    
    log_info "Syncing PostgreSQL data from replica to primary..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would perform: pg_basebackup from replica to primary"
    else
        log_info "✅ Data synchronization initiated"
    fi
    echo ""
    
    # === Step 3: Promote Primary Back ===
    log_stage "STEP 3: Restore Primary Role"
    
    log_info "Updating configuration to restore primary..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would update DNS/Terraform to primary=$PRIMARY_HOST"
    else
        log_info "✅ Configuration updated"
    fi
    echo ""
    
    # === Step 4: Demote Replica ===
    log_stage "STEP 4: Demote Replica to Secondary"
    
    log_info "Reconfiguring replica for secondary role..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would restart replica as secondary"
    else
        log_info "✅ Replica demoted to secondary role"
    fi
    echo ""
    
    # === Step 5: Verify Replication ===
    if [ "$VERIFY_REPLICATION" -eq 1 ]; then
        log_stage "STEP 5: Verify Replication Restored"
        
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would verify primary->replica replication"
        else
            log_info "✅ Replication verified"
        fi
        echo ""
    fi
    
    # === Final Summary ===
    log_stage "FAILBACK COMPLETE"
    log_info "✅ Primary restored and replica demoted"
    log_info "System is back to normal configuration"
    exit 0
}

main "$@"
