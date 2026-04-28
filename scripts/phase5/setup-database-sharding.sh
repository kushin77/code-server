#!/bin/bash
# @file scripts/phase5/setup-database-sharding.sh
# @description PostgreSQL horizontal sharding setup for multi-region distribution (Q3 Phase 5)
# @version 1.0.0
# @date April 25, 2026

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/artifacts/phase5/sharding-$(date +%Y%m%d-%H%M%S).log"
readonly SHARDS="${SHARDS:-4}"
readonly SHARD_ALGORITHM="${SHARD_ALGORITHM:-hash-user-id}"

mkdir -p "$(dirname "$LOG_FILE")"

# Note: Logging functions (log_info, log_success, log_error) are provided by
# scripts/_common/init.sh which sources apps/_shared/test.sh for enhanced logging.
# For script-specific file logging, wrap calls with: log_info "msg" | tee -a "$LOG_FILE"

# ============================================================================
# DATABASE SHARDING SCHEMA
# ============================================================================

create_sharding_metadata_schema() {
  log_info "Creating sharding metadata schema..."
  
  local pg_host="${PG_HOST:-postgres}"
  local pg_user="${PG_USER:-postgres}"
  local pg_pass="${PG_PASSWORD:-postgres}"
  
  PGPASSWORD="$pg_pass" psql -h "$pg_host" -U "$pg_user" -d kushnir_db <<'EOF' | tee -a "$LOG_FILE"
-- Sharding metadata tables
CREATE SCHEMA IF NOT EXISTS sharding;

-- Shard mapping table
CREATE TABLE IF NOT EXISTS sharding.shard_map (
  shard_id INT PRIMARY KEY,
  host VARCHAR(255) NOT NULL,
  port INT DEFAULT 5432,
  database_name VARCHAR(255) NOT NULL,
  is_primary BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- User to shard mapping (for lookups)
CREATE TABLE IF NOT EXISTS sharding.user_shard_lookup (
  user_id BIGINT PRIMARY KEY,
  shard_id INT NOT NULL REFERENCES sharding.shard_map(shard_id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Sharding configuration
CREATE TABLE IF NOT EXISTS sharding.config (
  key VARCHAR(255) PRIMARY KEY,
  value TEXT,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Insert base configuration
INSERT INTO sharding.config (key, value) VALUES 
  ('total_shards', '4'),
  ('algorithm', 'hash-user-id'),
  ('replication_factor', '3'),
  ('consistency_level', 'eventual')
ON CONFLICT (key) DO NOTHING;

CREATE INDEX idx_user_shard_lookup ON sharding.user_shard_lookup(shard_id);
CREATE INDEX idx_shard_map_active ON sharding.shard_map(is_active);

GRANT SELECT ON sharding.* TO app_user;
GRANT USAGE ON SCHEMA sharding TO app_user;

SELECT 'Sharding metadata schema created' as status;
EOF
  
  log_success "Sharding metadata schema created"
}

# ============================================================================
# SHARD INITIALIZATION
# ============================================================================

create_individual_shards() {
  log_info "Creating individual database shards (${SHARDS} total)..."
  
  local pg_host="${PG_HOST:-postgres}"
  local pg_user="${PG_USER:-postgres}"
  local pg_pass="${PG_PASSWORD:-postgres}"
  
  for shard_id in $(seq 0 $((SHARDS-1))); do
    local shard_db="kushnir_shard_${shard_id}"
    
    log_info "Creating shard $shard_id ($shard_db)..."
    
    # Create database
    PGPASSWORD="$pg_pass" psql -h "$pg_host" -U "$pg_user" <<EOF | tee -a "$LOG_FILE"
CREATE DATABASE IF NOT EXISTS $shard_db;
EOF
    
    # Apply base schema to shard
    PGPASSWORD="$pg_pass" psql -h "$pg_host" -U "$pg_user" -d "$shard_db" <<'EOF' | tee -a "$LOG_FILE"
-- Core application tables (sharded)

CREATE TABLE users (
  id BIGINT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(255),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE projects (
  id BIGINT PRIMARY KEY,
  owner_id BIGINT NOT NULL,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE sessions (
  id BIGINT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  token_hash VARCHAR(255) NOT NULL UNIQUE,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE activities (
  id BIGINT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  action VARCHAR(100) NOT NULL,
  resource_id BIGINT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Indices for common queries
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_projects_owner ON projects(owner_id);
CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_token ON sessions(token_hash);
CREATE INDEX idx_activities_user ON activities(user_id);
CREATE INDEX idx_activities_created ON activities(created_at);

SELECT 'Schema applied to shard' as status;
EOF
    
    log_success "Shard $shard_id initialized"
  done
}

# ============================================================================
# SHARDING MIDDLEWARE (PgBouncer)
# ============================================================================

setup_pgbouncer_sharding_middleware() {
  log_info "Setting up PgBouncer sharding middleware..."
  
  local pgbouncer_config="/etc/pgbouncer/pgbouncer.ini"
  
  cat > "$pgbouncer_config" <<EOF
[databases]
# Shard connections
kushnir_shard_0 = host=postgres-shard-0 port=5432 dbname=kushnir_shard_0
kushnir_shard_1 = host=postgres-shard-1 port=5432 dbname=kushnir_shard_1
kushnir_shard_2 = host=postgres-shard-2 port=5432 dbname=kushnir_shard_2
kushnir_shard_3 = host=postgres-shard-3 port=5432 dbname=kushnir_shard_3

# Sharding metadata database
sharding_meta = host=postgres-primary port=5432 dbname=kushnir_db

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 30
max_db_connections = 100
max_user_connections = 100

listen_port = 6432
listen_addr = *
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Logging
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid
verbose = 1

# Timeouts
connect_timeout = 15
idle_in_transaction_session_timeout = 300

# Monitoring
stats_period = 60
EOF

  # Create user credentials file
  cat > /etc/pgbouncer/userlist.txt <<EOF
"postgres" "password"
"app_user" "app_password"
EOF
  
  chmod 600 /etc/pgbouncer/userlist.txt
  
  # Restart PgBouncer
  systemctl restart pgbouncer
  
  log_success "PgBouncer middleware configured"
}

# ============================================================================
# SHARDING FUNCTIONS (SQL)
# ============================================================================

create_sharding_functions() {
  log_info "Creating sharding functions in metadata database..."
  
  local pg_host="${PG_HOST:-postgres}"
  local pg_user="${PG_USER:-postgres}"
  local pg_pass="${PG_PASSWORD:-postgres}"
  
  PGPASSWORD="$pg_pass" psql -h "$pg_host" -U "$pg_user" -d kushnir_db <<'EOF' | tee -a "$LOG_FILE"
-- Function to compute shard ID
CREATE OR REPLACE FUNCTION sharding.get_shard_id(user_id BIGINT)
RETURNS INT AS $$
DECLARE
  total_shards INT;
BEGIN
  SELECT value::INT INTO total_shards FROM sharding.config WHERE key = 'total_shards';
  RETURN user_id % total_shards;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get database name for shard
CREATE OR REPLACE FUNCTION sharding.get_shard_database(shard_id INT)
RETURNS VARCHAR AS $$
BEGIN
  RETURN 'kushnir_shard_' || shard_id::VARCHAR;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get shard connection string
CREATE OR REPLACE FUNCTION sharding.get_shard_connection(user_id BIGINT)
RETURNS VARCHAR AS $$
DECLARE
  shard_id INT;
  connection_string VARCHAR;
BEGIN
  shard_id := sharding.get_shard_id(user_id);
  
  SELECT 'postgresql://app_user:app_password@pgbouncer:6432/' || sharding.get_shard_database(shard_id)
  INTO connection_string;
  
  RETURN connection_string;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Procedure to register shard
CREATE OR REPLACE PROCEDURE sharding.register_shard(
  p_shard_id INT,
  p_host VARCHAR,
  p_port INT,
  p_is_primary BOOLEAN
)
AS $$
BEGIN
  INSERT INTO sharding.shard_map (shard_id, host, port, database_name, is_primary)
  VALUES (
    p_shard_id,
    p_host,
    p_port,
    'kushnir_shard_' || p_shard_id::VARCHAR,
    p_is_primary
  )
  ON CONFLICT (shard_id) DO UPDATE SET
    host = p_host,
    port = p_port,
    is_primary = p_is_primary,
    updated_at = NOW();
  
  COMMIT;
END;
$$ LANGUAGE plpgsql;

SELECT 'Sharding functions created' as status;
EOF
  
  log_success "Sharding functions created"
}

# ============================================================================
# INITIAL DATA DISTRIBUTION
# ============================================================================

initialize_shard_distribution() {
  log_info "Initializing shard distribution metadata..."
  
  local pg_host="${PG_HOST:-postgres}"
  local pg_user="${PG_USER:-postgres}"
  local pg_pass="${PG_PASSWORD:-postgres}"
  
  # Register each shard in metadata
  for shard_id in $(seq 0 $((SHARDS-1))); do
    local is_primary="false"
    if [[ $shard_id -eq 0 ]]; then
      is_primary="true"
    fi
    
    PGPASSWORD="$pg_pass" psql -h "$pg_host" -U "$pg_user" -d kushnir_db <<EOF | tee -a "$LOG_FILE"
CALL sharding.register_shard($shard_id, 'postgres-shard-$shard_id', 5432, $is_primary);
EOF
    
    log_success "Shard $shard_id registered"
  done
}

# ============================================================================
# REPLICATION SETUP
# ============================================================================

setup_shard_replication() {
  log_info "Setting up cross-shard replication..."
  
  # For each shard, set up replication to regional replicas
  # This is done via PostgreSQL streaming replication
  
  local replica_hosts=("postgres-replica-eu" "postgres-replica-apac")
  
  for shard_id in $(seq 0 $((SHARDS-1))); do
    local primary_host="postgres-shard-$shard_id"
    
    log_info "Setting up replication for shard $shard_id..."
    
    # Configure primary for replication
    ssh "ubuntu@$primary_host" <<'EOF'
      sudo tee -a /etc/postgresql/14/main/postgresql.conf > /dev/null <<'CONF'
wal_level = replica
max_wal_senders = 3
max_replication_slots = 3
hot_standby = on
CONF
      
      sudo systemctl restart postgresql
EOF
    
    # Create replication slots for each replica
    for replica in "${replica_hosts[@]}"; do
      log_info "Creating replication slot for shard $shard_id → $replica..."
      
      sudo -u postgres psql -h "$primary_host" <<SQL
SELECT pg_create_physical_replication_slot('slot_$replica', true);
SQL
    done
  done
  
  log_success "Shard replication configured"
}

# ============================================================================
# VALIDATION
# ============================================================================

validate_sharding_setup() {
  log_info "Validating sharding setup..."
  
  local pg_host="${PG_HOST:-postgres}"
  local pg_user="${PG_USER:-postgres}"
  local pg_pass="${PG_PASSWORD:-postgres}"
  
  # Check all shards exist
  local shard_count=$(PGPASSWORD="$pg_pass" psql -h "$pg_host" -U "$pg_user" -d kushnir_db -t -c "SELECT COUNT(*) FROM sharding.shard_map;")
  
  if [[ $shard_count -eq $SHARDS ]]; then
    log_success "All $SHARDS shards registered"
  else
    log_error "Expected $SHARDS shards but found $shard_count"
    exit 1
  fi
  
  # Test sharding functions
  log_info "Testing sharding functions..."
  PGPASSWORD="$pg_pass" psql -h "$pg_host" -U "$pg_user" -d kushnir_db -t -c "
    SELECT 
      user_id,
      sharding.get_shard_id(user_id) as shard_id,
      sharding.get_shard_database(sharding.get_shard_id(user_id)) as shard_db
    FROM (
      SELECT * FROM (VALUES (1::BIGINT), (100::BIGINT), (1000::BIGINT), (10000::BIGINT)) t(user_id)
    ) sub;" | tee -a "$LOG_FILE"
  
  log_success "Sharding functions validated"
}

# ============================================================================
# REPORTING
# ============================================================================

generate_sharding_report() {
  log_info "Generating sharding setup report..."
  
  local report_file="${SCRIPT_DIR}/artifacts/phase5/sharding-setup-report-$(date +%Y%m%d).md"
  
  cat > "$report_file" <<EOF
# Database Sharding Setup Report

**Setup Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
**Total Shards**: $SHARDS
**Algorithm**: $SHARD_ALGORITHM

## Shard Configuration

$(for shard_id in $(seq 0 $((SHARDS-1))); do
  echo "- **Shard $shard_id**: kushnir_shard_$shard_id"
done)

## Sharding Functions

- \`get_shard_id(user_id)\` - Compute shard ID from user ID
- \`get_shard_database(shard_id)\` - Get database name for shard
- \`get_shard_connection(user_id)\` - Get connection string for user

## Next Steps

1. Configure application ORM to use sharding functions
2. Migrate existing user data to shards
3. Set up cross-shard query federation
4. Validate data consistency across shards

## Logs
See: $LOG_FILE
EOF
  
  log_success "Report generated: $report_file"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "Starting database sharding setup (${SHARDS} shards, algorithm: ${SHARD_ALGORITHM})"
  
  create_sharding_metadata_schema
  create_individual_shards
  setup_pgbouncer_sharding_middleware
  create_sharding_functions
  initialize_shard_distribution
  setup_shard_replication
  validate_sharding_setup
  generate_sharding_report
  
  log_success "✓ Database sharding setup complete"
}

main "$@"
