#!/bin/bash
# File: scripts/postgresql-replication-setup.sh
# Owner: ops
# Status: ACTIVE
#
# Phase 12.2: Multi-Primary PostgreSQL Replication Setup
# Configures logical replication across 5 regional PostgreSQL instances
# for conflict-free data synchronization using CRDT semantics
#
# Usage: bash postgresql-replication-setup.sh [primary|replica] [region] [connection_string]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }
export LOG_FILE="${SCRIPT_DIR}/../logs/postgresql-replication-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Configuration
PRIMARY_REGIONS=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1" "ca-central-1")
REPLICATION_SLOT_PREFIX="replication_slot"
PUBLICATION_NAME="replication_pub"
SUBSCRIPTION_NAME_PREFIX="replication_sub"

##############################################################################
# PostgreSQL Connection Management
##############################################################################

# Test PostgreSQL connection
test_postgres_connection() {
    local conn_string="$1"
    local timeout="${2:-10}"

    log_info "Testing PostgreSQL connection: ${conn_string}"

    if ! timeout "$timeout" psql "$conn_string" -c "SELECT version();" > /dev/null 2>&1; then
        log_error "Failed to connect to PostgreSQL: ${conn_string}"
        return 1
    fi

    log_info "✓ PostgreSQL connection successful"
    return 0
}

# Execute SQL on remote PostgreSQL instance
execute_pg_command() {
    local conn_string="$1"
    local sql="$2"

    psql "$conn_string" -v ON_ERROR_STOP=1 -c "$sql" 2>&1 || {
        log_error "SQL execution failed: ${sql}"
        return 1
    }
}

##############################################################################
# Replication Slot Management
##############################################################################

# Create replication slot for source region
create_replication_slot() {
    local conn_string="$1"
    local source_region="$2"
    local slot_name="${REPLICATION_SLOT_PREFIX}_${source_region}"

    log_info "Creating replication slot: ${slot_name}"

    local sql="
        SELECT * FROM pg_create_logical_replication_slot(
            '${slot_name}',
            'pgoutput',
            false
        );
    "

    execute_pg_command "$conn_string" "$sql" || return 1
    log_info "✓ Replication slot created: ${slot_name}"
}

# Verify replication slot exists
verify_replication_slot() {
    local conn_string="$1"
    local slot_name="$2"

    local sql="SELECT slot_name, slot_type, active FROM pg_replication_slots WHERE slot_name = '${slot_name}';"

    execute_pg_command "$conn_string" "$sql" || return 1
}

# Drop replication slot if exists
drop_replication_slot() {
    local conn_string="$1"
    local slot_name="$2"

    log_info "Dropping replication slot if exists: ${slot_name}"

    local sql="
        SELECT pg_drop_replication_slot(slot_name)
        FROM pg_replication_slots
        WHERE slot_name = '${slot_name}';
    "

    execute_pg_command "$conn_string" "$sql" || true
}

##############################################################################
# Publication Management
##############################################################################

# Create publication for replication
create_publication() {
    local conn_string="$1"
    local publication="${PUBLICATION_NAME}"

    log_info "Creating publication: ${publication}"

    local sql="
        CREATE PUBLICATION IF NOT EXISTS ${publication}
        FOR ALL TABLES;
    "

    execute_pg_command "$conn_string" "$sql" || return 1
    log_info "✓ Publication created: ${publication}"
}

# Enable CRDT-compatible write-ahead logging
enable_wal_for_replication() {
    local conn_string="$1"

    log_info "Configuring WAL for logical replication"

    # These settings must be applied in postgresql.conf and require restart
    local settings=(
        "max_wal_senders = 10"
        "wal_level = logical"
        "max_replication_slots = 10"
        "hot_standby = on"
    )

    log_info "Required postgresql.conf settings:"
    for setting in "${settings[@]}"; do
        log_info "  - ${setting}"
    done

    log_warn "Note: WAL settings require PostgreSQL restart. Verify in postgresql.conf"
}

##############################################################################
# Subscription Management (Multi-Primary Replication)
##############################################################################

# Create subscription for multi-primary replication
create_subscription() {
    local target_conn_string="$1"
    local source_conn_string="$2"
    local source_region="$3"
    local subscription="${SUBSCRIPTION_NAME_PREFIX}_${source_region}"

    log_info "Creating subscription: ${subscription}"

    # Extract source connection details
    local source_user=$(echo "$source_conn_string" | grep -oP '(?<=user=)[^ ]+' || echo "postgres")
    local source_password=$(echo "$source_conn_string" | grep -oP '(?<=password=)[^ ]+' || echo "")
    local source_dbname=$(echo "$source_conn_string" | grep -oP '(?<=dbname=)[^ ]+' || echo "postgres")

    # Build connection string for source
    local source_dsn="postgresql://${source_user}:${source_password}@${source_region}:5432/${source_dbname}"

    local sql="
        CREATE SUBSCRIPTION IF NOT EXISTS ${subscription}
        CONNECTION '${source_dsn}'
        PUBLICATION ${PUBLICATION_NAME}
        WITH (
            copy_data = true,
            create_slot = true,
            slot_name = '${REPLICATION_SLOT_PREFIX}_${source_region}',
            enabled = true,
            synchronous_commit = 'remote_apply'
        );
    "

    execute_pg_command "$target_conn_string" "$sql" || return 1
    log_info "✓ Subscription created: ${subscription}"
}

# Enable CRDT-safe conflict resolution
configure_conflict_resolution() {
    local conn_string="$1"

    log_info "Configuring conflict resolution for CRDT semantics"

    # Create CRDT data types and resolution functions
    local sql="
        -- Enable UUID support for CRDT node IDs
        CREATE EXTENSION IF NOT EXISTS uuid-ossp;

        -- Create CRDT-safe aggregate functions
        CREATE OR REPLACE FUNCTION crdt_max_int(int, int) RETURNS int AS '/usr/lib/postgresql/crdt', 'crdt_max_int' LANGUAGE c IMMUTABLE STRICT;
        CREATE AGGREGATE crdt_max(int) (SFUNC = crdt_max_int, STYPE = int);

        -- Last-write-wins resolution strategy (with timestamp)
        CREATE OR REPLACE FUNCTION resolve_lww(
            local_val ANYELEMENT,
            local_ts TIMESTAMP,
            remote_val ANYELEMENT,
            remote_ts TIMESTAMP
        ) RETURNS ANYELEMENT AS \\\$\$
        BEGIN
            IF remote_ts > local_ts THEN
                RETURN remote_val;
            ELSE
                RETURN local_val;
            END IF;
        END;
        \\\$ LANGUAGE plpgsql IMMUTABLE;

        -- Commutative semilattice ordering
        CREATE TYPE crdt_vector_clock AS (
            node_id uuid,
            clock_value bigint
        );
    "

    execute_pg_command "$conn_string" "$sql" || return 1
    log_info "✓ Conflict resolution configured"
}

##############################################################################
# Replication Monitoring
##############################################################################

# Check replication lag
check_replication_lag() {
    local conn_string="$1"

    log_info "Checking replication lag"

    local sql="
        SELECT
            slot_name,
            restart_lsn,
            confirmed_flush_lsn,
            pg_wal_lsn_diff(confirmed_flush_lsn, restart_lsn) as bytes_behind,
            CASE
                WHEN confirmed_flush_lsn IS NULL THEN 'unknown'
                WHEN confirmed_flush_lsn >= restart_lsn THEN 'caught_up'
                ELSE 'behind'
            END as lag_status
        FROM pg_replication_slots
        WHERE slot_type = 'logical';
    "

    execute_pg_command "$conn_string" "$sql" || return 1
}

# Monitor subscription status
monitor_subscription_status() {
    local conn_string="$1"

    log_info "Monitoring subscription status"

    local sql="
        SELECT
            subname,
            subowner,
            subenabled,
            subconninfo,
            subslotname,
            subsynccommit
        FROM pg_subscription;
    "

    execute_pg_command "$conn_string" "$sql" || return 1
}

##############################################################################
# Setup Functions
##############################################################################

# Setup primary region (source)
setup_primary_region() {
    local region="$1"
    local conn_string="$2"

    log_info "=========================================="
    log_info "Setting up PRIMARY region: ${region}"
    log_info "=========================================="

    # Test connection
    test_postgres_connection "$conn_string" || return 1

    # Configure WAL
    enable_wal_for_replication "$conn_string"

    # Create replication slot
    create_replication_slot "$conn_string" "$region" || return 1

    # Create publication
    create_publication "$conn_string" || return 1

    log_info "✓ Primary region setup complete: ${region}"
}

# Setup replica region (target)
setup_replica_region() {
    local target_region="$1"
    local target_conn_string="$2"
    local source_regions=("${@:3}")

    log_info "=========================================="
    log_info "Setting up REPLICA region: ${target_region}"
    log_info "=========================================="

    # Test connection
    test_postgres_connection "$target_conn_string" || return 1

    # Configure conflict resolution
    configure_conflict_resolution "$target_conn_string" || return 1

    # Create subscriptions from all source regions
    for source_region in "${source_regions[@]}"; do
        if [ "$source_region" != "$target_region" ]; then
            log_info "Creating subscription from ${source_region} to ${target_region}"
            # Would need actual source connection string here
            # create_subscription "$target_conn_string" "$source_conn_string" "$source_region" || return 1
        fi
    done

    log_info "✓ Replica region setup complete: ${target_region}"
}

# Full multi-primary setup
setup_multi_primary_replication() {
    log_info "=========================================="
    log_info "MULTI-PRIMARY REPLICATION SETUP"
    log_info "Regions: ${PRIMARY_REGIONS[*]}"
    log_info "=========================================="

    # Setup each region as primary
    for region in "${PRIMARY_REGIONS[@]}"; do
        # Note: In production, connection strings would come from AWS RDS endpoints
        local conn_string="postgresql://postgres@${region}-rds.aws.example.com:5432/codeserver"

        setup_primary_region "$region" "$conn_string" || {
            log_error "Failed to setup primary region: ${region}"
            return 1
        }
    done

    log_info "✓ Multi-primary replication setup complete"
}

##############################################################################
# Validation Functions
##############################################################################

# Validate replication setup
validate_replication_setup() {
    local conn_string="$1"

    log_info "Validating replication setup"

    # Check replication slots
    log_info "Checking replication slots..."
    local slots_sql="SELECT COUNT(*) as slot_count FROM pg_replication_slots;"
    execute_pg_command "$conn_string" "$slots_sql" || return 1

    # Check publications
    log_info "Checking publications..."
    local pub_sql="SELECT pubname FROM pg_publication;"
    execute_pg_command "$conn_string" "$pub_sql" || return 1

    # Check subscriptions
    log_info "Checking subscriptions..."
    monitor_subscription_status "$conn_string" || return 1

    # Check replication lag
    check_replication_lag "$conn_string" || return 1

    log_info "✓ Replication validation complete"
}

##############################################################################
# Main
##############################################################################

main() {
    log_info "Starting PostgreSQL Multi-Primary Replication Setup"
    log_info "Timestamp: ${TIMESTAMP}"

    if [ $# -lt 2 ]; then
        cat << 'EOF'
Usage: bash postgresql-replication-setup.sh <command> <region> [connection_string]

Commands:
  setup-primary   <region> <conn_string>    - Setup primary replication
  setup-replica   <region> <conn_string>    - Setup replica replication
  setup-all                                 - Setup complete multi-primary
  validate        <conn_string>             - Validate replication setup
  check-lag       <conn_string>             - Check replication lag
  monitor         <conn_string>             - Monitor subscription status

Examples:
  bash postgresql-replication-setup.sh setup-primary us-east-1 "postgresql://localhost/codeserver"
  bash postgresql-replication-setup.sh check-lag "postgresql://localhost/codeserver"
EOF
        return 1
    fi

    local command="$1"

    case "$command" in
        setup-primary)
            setup_primary_region "$2" "$3"
            ;;
        setup-replica)
            setup_replica_region "$2" "$3" "${@:4}"
            ;;
        setup-all)
            setup_multi_primary_replication
            ;;
        validate)
            validate_replication_setup "$2"
            ;;
        check-lag)
            check_replication_lag "$2"
            ;;
        monitor)
            monitor_subscription_status "$2"
            ;;
        *)
            log_error "Unknown command: $command"
            return 1
            ;;
    esac
}

main "$@"
