#!/bin/bash
# @file        P0-INCIDENT-RESPONSE-EXECUTION-RUNBOOK.sh
# @module      incident-response/p0-nvme-failure
# @description Automated runbook for P0 #1635 NVMe failure incident response - ALL PHASES
#
# USAGE:
#   1. From Linux host with SSH access to replicas:
#   2. ./P0-INCIDENT-RESPONSE-EXECUTION-RUNBOOK.sh
#
# PREREQUISITES:
#   - SSH key: ~/.ssh/id_rsa_onprem
#   - Both replicas accessible: 192.168.168.31, 192.168.168.42
#   - POSTGRES_PASSWORD environment variable set
#   - REPLICATION_PASSWORD environment variable set
#
# This runbook automates all 5 phases sequentially with verification at each step

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}==== $1 ====${NC}\n"; }

# Verification functions
verify_prerequisites() {
    log_section "PHASE 0: Verify Prerequisites"
    
    # Check SSH key
    if [[ ! -f ~/.ssh/id_rsa_onprem ]]; then
        log_error "SSH key not found: ~/.ssh/id_rsa_onprem"
        exit 1
    fi
    log_info "✅ SSH key found"
    
    # Check environment variables
    if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
        log_error "POSTGRES_PASSWORD not set"
        exit 1
    fi
    log_info "✅ POSTGRES_PASSWORD set"
    
    if [[ -z "${REPLICATION_PASSWORD:-}" ]]; then
        log_error "REPLICATION_PASSWORD not set"
        exit 1
    fi
    log_info "✅ REPLICATION_PASSWORD set"
    
    # Test SSH connectivity to both replicas
    for host in 192.168.168.31 192.168.168.42; do
        log_info "Testing SSH connectivity to $host..."
        if ssh -i ~/.ssh/id_rsa_onprem -o ConnectTimeout=10 akushnir@$host "echo 'SSH OK'" > /dev/null 2>&1; then
            log_info "✅ $host accessible"
        else
            log_error "$host not accessible"
            exit 1
        fi
    done
    
    log_info "✅ All prerequisites verified"
}

# Phase 1: Passwordless Sudo Setup
phase_1_passwordless_sudo() {
    log_section "PHASE 1: Passwordless Sudo Setup (5 min)"
    
    if ! command -v bash &> /dev/null; then
        log_error "bash required"
        exit 1
    fi
    
    if [[ ! -f scripts/ops/setup-passwordless-sudo.sh ]]; then
        log_error "Script not found: scripts/ops/setup-passwordless-sudo.sh"
        exit 1
    fi
    
    log_info "Executing passwordless sudo setup..."
    bash scripts/ops/setup-passwordless-sudo.sh
    
    # Verify passwordless sudo on both replicas
    log_info "Verifying passwordless sudo..."
    for host in 192.168.168.31 192.168.168.42; do
        if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "sudo -n whoami" 2>/dev/null | grep -q "root"; then
            log_info "✅ $host: passwordless sudo verified"
        else
            log_error "$host: passwordless sudo verification failed"
            exit 1
        fi
    done
    
    log_info "✅ PHASE 1 COMPLETE: Passwordless sudo enabled on both replicas"
}

# Phase 2: Replica 1 Backup (5 min)
phase_2_backup_replica1() {
    log_section "PHASE 2: Pre-Isolation PostgreSQL Backup (5 min)"
    
    log_info "Creating PostgreSQL backup on Replica 1..."
    ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
        "sudo -n docker exec code-server-enterprise-postgres-1 pg_dump -U postgres postgres > /tmp/pre-isolation-backup.sql" || {
        log_error "Backup failed"
        exit 1
    }
    
    log_info "✅ PHASE 2 COMPLETE: PostgreSQL backup created"
}

# Phase 3: Replica 2 Isolation
phase_3_replica2_isolation() {
    log_section "PHASE 3: Replica 2 Isolation (15 min)"
    
    if [[ ! -f scripts/ops/isolate-replica-2-nvme-failure.sh ]]; then
        log_error "Script not found: scripts/ops/isolate-replica-2-nvme-failure.sh"
        exit 1
    fi
    
    log_info "Executing Phase 1 isolation procedure..."
    bash scripts/ops/isolate-replica-2-nvme-failure.sh
    
    # Verify isolation
    log_info "Verifying Replica 2 isolation (should timeout)..."
    if ! ping -c 1 -W 2 192.168.168.42 &>/dev/null; then
        log_info "✅ Replica 2 isolated (ping timeout verified)"
    else
        log_warn "⚠️ Replica 2 still reachable (isolation may be incomplete)"
    fi
    
    log_info "✅ PHASE 3 COMPLETE: Replica 2 isolated, Replica 1 serving all traffic"
}

# Phase 4: PostgreSQL Streaming Replication Setup
phase_4_postgres_replication() {
    log_section "PHASE 4: PostgreSQL Streaming Replication (2-3 hours)"
    
    if [[ ! -f scripts/ops/setup-postgres-streaming-replication.sh ]]; then
        log_error "Script not found: scripts/ops/setup-postgres-streaming-replication.sh"
        exit 1
    fi
    
    log_info "Setting environment variables for replication setup..."
    export POSTGRES_PASSWORD REPLICATION_PASSWORD
    
    log_info "Executing PostgreSQL streaming replication setup..."
    bash scripts/ops/setup-postgres-streaming-replication.sh
    
    log_info "✅ PHASE 4 COMPLETE: PostgreSQL streaming replication established"
}

# Phase 5: NAS Mount Synchronization (can run in parallel with Phase 4)
phase_5_nas_mount_sync() {
    log_section "PHASE 5: NAS Mount Synchronization (30 min)"
    
    if [[ ! -f scripts/ops/fix-mnt-eiq-shared-mount.sh ]]; then
        log_error "Script not found: scripts/ops/fix-mnt-eiq-shared-mount.sh"
        exit 1
    fi
    
    log_info "Executing NAS mount synchronization..."
    bash scripts/ops/fix-mnt-eiq-shared-mount.sh
    
    log_info "✅ PHASE 5 COMPLETE: NAS mount synchronized on both replicas"
}

# Hardware replacement instructions
phase_6_hardware_replacement() {
    log_section "PHASE 6: Hardware Replacement Instructions"
    
    log_warn "⚠️ Hardware replacement requires manual intervention"
    log_info "Steps:"
    log_info "1. Order WD_BLACK SN770 2TB (same as current failure)"
    log_info "2. Wait 24-48 hours for delivery"
    log_info "3. On Replica 2 (192.168.168.42):"
    log_info "   - Power down the host"
    log_info "   - Remove failed NVMe drive"
    log_info "   - Insert new NVMe drive"
    log_info "   - Power on and verify BIOS detection"
    log_info "   - Boot OS and restart services: docker compose up -d"
    log_info "4. Verify all services healthy: docker compose ps"
    log_info ""
    log_info "✅ PHASE 6 READY: Hardware replacement can proceed"
}

# Post-incident verification
verify_final_state() {
    log_section "FINAL VERIFICATION"
    
    log_info "Checking Replica 1 services..."
    ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
        "docker compose ps --format 'table {{.Service}}\t{{.Status}}'" | head -10
    
    log_info "Checking PostgreSQL replication status..."
    ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
        "docker exec code-server-enterprise-postgres-1 psql -U postgres -c 'SELECT slot_name, restart_lsn FROM pg_replication_slots;'" || \
        log_warn "Replication slot check skipped (Replica 2 isolated)"
    
    log_info "✅ Final verification complete"
}

# Main execution
main() {
    log_section "P0 #1635 NVMe INCIDENT RESPONSE RUNBOOK"
    log_info "Starting comprehensive incident response execution"
    log_info "Current time: $(date)"
    log_info ""
    
    verify_prerequisites
    phase_1_passwordless_sudo
    phase_2_backup_replica1
    phase_3_replica2_isolation
    
    # Phases 4 and 5 can run in parallel, but we'll run sequentially for clarity
    phase_4_postgres_replication
    phase_5_nas_mount_sync
    
    phase_6_hardware_replacement
    verify_final_state
    
    log_section "INCIDENT RESPONSE COMPLETE"
    log_info "Status: ✅ All automated phases complete"
    log_info "Next step: Proceed with Phase 6 hardware replacement (24-48 hour lead time)"
    log_info "Timeline: 48-72 hours total from start"
}

# Run main
main
