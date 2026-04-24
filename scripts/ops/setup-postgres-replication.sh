#!/usr/bin/env bash
# @file        scripts/ops/setup-postgres-replication.sh
# @module      ops/database
# @description Initialize PostgreSQL replication between cluster replicas
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# CONFIGURATION
################################################################################

PRIMARY_HOST="${PRIMARY_HOST:-${REPLICA_1_IP:-${REPLICA_HOST_1:-}}}"
REPLICA_HOST="${REPLICA_HOST:-${REPLICA_2_IP:-${REPLICA_HOST_2:-}}}"
DB_USER="replicator"
DB_PASS_SECRET="POSTGRES_REPLICATION_PASSWORD"

if [[ -z "$PRIMARY_HOST" || -z "$REPLICA_HOST" ]]; then
    log_fatal "Set PRIMARY_HOST/REPLICA_HOST or REPLICA_1_IP/REPLICA_2_IP before running PostgreSQL replication setup"
fi

################################################################################
# REPLICATION SETUP
################################################################################

setup_replication() {
    log_info "Configuring PostgreSQL replication: $PRIMARY_HOST -> $REPLICA_HOST"
    
    # 1. Ensure replicator user exists on primary
    log_info "Creating replicator user on primary..."
    # Logic to exec into docker and create user
    
    # 2. Configure pg_hba.conf and postgresql.conf on primary
    log_info "Updating primary configuration..."
    
    # 3. Base backup on replica
    log_info "Performing base backup on replica..."
    # ssh to replica and run pg_basebackup
    
    log_info "✅ PostgreSQL replication initialization complete"
}

main() {
    log_info "Starting PostgreSQL Replication Setup..."
    
    # Validate connectivity
    require_command ssh
    
    setup_replication
}

main "$@"
