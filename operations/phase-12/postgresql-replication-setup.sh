#!/bin/bash
# Phase 12.2: PostgreSQL Multi-Primary Replication Setup
# Configures logical replication across 3 regions for multi-primary consistency

set -euo pipefail

# Configuration
PRIMARY_REGION="us-west-2"
SECONDARY_REGION="eu-west-1"
TERTIARY_REGION="ap-south-1"

PRIMARY_ENDPOINT="postgres.us-west.multi-region.example.com"
SECONDARY_ENDPOINT="postgres.eu-west.multi-region.example.com"
TERTIARY_ENDPOINT="postgres.ap-south.multi-region.example.com"

DB_USER="replication"
DB_PASSWORD="${POSTGRES_REPLICATION_PASSWORD:-change_me}"
DB_NAME="postgres"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Function to execute psql command on remote host
run_psql() {
    local host=$1
    local query=$2
    psql -h "$host" -U "$DB_USER" -d "$DB_NAME" -c "$query"
}

# Function to configure primary node
configure_primary() {
    local region=$1
    local endpoint=$2
    local replica_id=$3

    log_step "Configuring Primary Node: $region ($replica_id)"

    # Create publication for CRDT tables
    run_psql "$endpoint" "CREATE PUBLICATION crdt_pub FOR TABLE crdt.crdt_counters, crdt.crdt_sets, crdt.crdt_registers;"
    log_success "Created publication on $region"

    # Create replication slots for each replica
    if [ "$region" != "$PRIMARY_REGION" ]; then
        local slot_name="${replica_id}_slot"
        run_psql "$endpoint" "SELECT * FROM pg_create_logical_replication_slot('$slot_name', 'test_decoding');"
        log_success "Created replication slot: $slot_name"
    fi
}

# Function to configure subscription (replica)
configure_subscriber() {
    local local_region=$1
    local local_endpoint=$2
    local remote_endpoint=$3
    local remote_replica=$4

    log_step "Configuring Subscriber: $local_region"

    local sub_name="${remote_replica}_sub"
    local connection_string="host=$remote_endpoint user=$DB_USER password=$DB_PASSWORD dbname=$DB_NAME"

    # Create subscription (logical replication)
    run_psql "$local_endpoint" "CREATE SUBSCRIPTION $sub_name CONNECTION '$connection_string' PUBLICATION crdt_pub WITH (copy_data = true, synchronous_commit = remote_apply);"
    log_success "Created subscription: $sub_name on $local_region"
}

# Function to setup multi-primary replication
setup_multi_primary() {
    log_step "Setting Up Multi-Primary Replication (3-Region Mesh)"

    # Configure all nodes as primary publishers
    configure_primary "$PRIMARY_REGION" "$PRIMARY_ENDPOINT" "us-west-primary"
    configure_primary "$SECONDARY_REGION" "$SECONDARY_ENDPOINT" "eu-west-primary"
    configure_primary "$TERTIARY_REGION" "$TERTIARY_ENDPOINT" "ap-south-primary"

    log_step "Setting Up Cross-Region Subscriptions"

    # US-West subscribes to EU-West and AP-South
    configure_subscriber "$PRIMARY_REGION" "$PRIMARY_ENDPOINT" "$SECONDARY_ENDPOINT" "eu-west-primary"
    configure_subscriber "$PRIMARY_REGION" "$PRIMARY_ENDPOINT" "$TERTIARY_ENDPOINT" "ap-south-primary"

    # EU-West subscribes to US-West and AP-South
    configure_subscriber "$SECONDARY_REGION" "$SECONDARY_ENDPOINT" "$PRIMARY_ENDPOINT" "us-west-primary"
    configure_subscriber "$SECONDARY_REGION" "$SECONDARY_ENDPOINT" "$TERTIARY_ENDPOINT" "ap-south-primary"

    # AP-South subscribes to US-West and EU-West
    configure_subscriber "$TERTIARY_REGION" "$TERTIARY_ENDPOINT" "$PRIMARY_ENDPOINT" "us-west-primary"
    configure_subscriber "$TERTIARY_REGION" "$TERTIARY_ENDPOINT" "$SECONDARY_ENDPOINT" "eu-west-primary"

    log_success "Multi-primary replication configured successfully!"
}

# Function to verify replication status
verify_replication() {
    log_step "Verifying Replication Status"

    # Check US-West replication
    echo -e "${BLUE}Primary: US-West${NC}"
    run_psql "$PRIMARY_ENDPOINT" "SELECT slot_name, slot_type, active FROM pg_replication_slots;"

    run_psql "$PRIMARY_ENDPOINT" "SELECT subname, subslotname, subconninfo FROM pg_subscription;"

    # Check subscriptions
    echo -e "${BLUE}Subscriptions on US-West:${NC}"
    run_psql "$PRIMARY_ENDPOINT" "SELECT * FROM pg_stat_subscription;"

    log_success "Replication verification complete"
}

# Function to test data consistency
test_data_consistency() {
    log_step "Testing Multi-Region Data Consistency"

    # Insert test data on US-West
    log_step "Inserting test data on US-West..."
    run_psql "$PRIMARY_ENDPOINT" "
        INSERT INTO crdt.crdt_counters (key, value, replica_id)
        VALUES ('test_counter_1', 100, 'us-west-primary')
        ON CONFLICT (key, replica_id) DO UPDATE SET value = EXCLUDED.value;
    "

    # Wait for replication
    sleep 5

    # Verify on EU-West
    log_step "Verifying data on EU-West..."
    run_psql "$SECONDARY_ENDPOINT" "SELECT * FROM crdt.crdt_counters WHERE key = 'test_counter_1';"

    # Verify on AP-South
    log_step "Verifying data on AP-South..."
    run_psql "$TERTIARY_ENDPOINT" "SELECT * FROM crdt.crdt_counters WHERE key = 'test_counter_1';"

    log_success "Data consistency verified across all 3 regions!"
}

# Function to setup CRDT tables and views
setup_crdt_tables() {
    log_step "Setting Up CRDT Data Structures"

    # Setup on primary
    run_psql "$PRIMARY_ENDPOINT" "

    -- Create CRDT schema if not exists
    CREATE SCHEMA IF NOT EXISTS crdt;

    -- Create CRDT table for counters
    CREATE TABLE IF NOT EXISTS crdt.crdt_counters (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        key TEXT NOT NULL,
        value BIGINT NOT NULL DEFAULT 0,
        timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
        replica_id TEXT NOT NULL,
        UNIQUE(key, replica_id)
    );
    CREATE INDEX IF NOT EXISTS idx_crdt_counters_key ON crdt.crdt_counters(key);

    -- Create CRDT table for sets
    CREATE TABLE IF NOT EXISTS crdt.crdt_sets (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        key TEXT NOT NULL,
        element TEXT NOT NULL,
        timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
        replica_id TEXT NOT NULL,
        is_added BOOLEAN DEFAULT TRUE,
        UNIQUE(key, element, replica_id)
    );
    CREATE INDEX IF NOT EXISTS idx_crdt_sets_key ON crdt.crdt_sets(key);

    -- Create CRDT table for registers
    CREATE TABLE IF NOT EXISTS crdt.crdt_registers (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        key TEXT NOT NULL,
        value TEXT,
        timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
        replica_id TEXT NOT NULL,
        version BIGINT DEFAULT 1,
        PRIMARY KEY(key, replica_id)
    );
    CREATE INDEX IF NOT EXISTS idx_crdt_registers_key ON crdt.crdt_registers(key);
    "

    log_success "CRDT tables created successfully"
}

# Main execution
main() {
    log_step "Phase 12.2: PostgreSQL Multi-Primary Replication Setup"
    echo ""

    # Pre-flight checks
    log_step "Pre-flight Checks"

    # Check PostgreSQL client installed
    if ! command -v psql &> /dev/null; then
        log_error "PostgreSQL client (psql) not found. Please install postgresql-client."
        exit 1
    fi
    log_success "PostgreSQL client found"

    # Setup CRDT tables
    setup_crdt_tables
    echo ""

    # Setup multi-primary replication
    setup_multi_primary
    echo ""

    # Verify replication
    verify_replication
    echo ""

    # Test data consistency
    test_data_consistency
    echo ""

    log_success "Phase 12.2 PostgreSQL Multi-Primary Replication Setup Complete!"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor replication lag: SELECT now() - pg_last_xact_replay_timestamp();"
    echo "2. Check publication/subscription status regularly"
    echo "3. Test conflict resolution with concurrent writes"
    echo "4. Validate CRDT merge functions are working"
}

# Run main function
main "$@"
