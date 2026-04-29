#!/bin/bash
# @file configure-postgres-ssl.sh
# @module security
# @description Configure PostgreSQL server to enforce SSL connections
# @governance GOV-002 - P1 Priority 3: Database connection encryption
# @idempotent YES

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

CERT_DIR="${REPO_ROOT}/vault-tls/postgres"
CONFIG_DIR="${REPO_ROOT}/config/postgres"
LOG_FILE="${REPO_ROOT}/logs/postgres-ssl-config.log"

mkdir -p "${CONFIG_DIR}" "${REPO_ROOT}/logs"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Create PostgreSQL configuration for SSL
create_postgres_ssl_config() {
  log "Creating PostgreSQL SSL configuration..."
  
  cat > "${CONFIG_DIR}/postgres-ssl.conf" <<'EOF'
# =============================================================================
# PostgreSQL SSL Configuration - P1 Priority 3 Security Hardening
# =============================================================================

# SSL is required for all connections
ssl = on
ssl_cert_file = '/var/lib/postgresql/data/certificates/server.crt'
ssl_key_file = '/var/lib/postgresql/data/certificates/server-key.pem'
ssl_ca_file = '/var/lib/postgresql/data/certificates/ca.crt'

# Only accept SSL connections from trusted clients
ssl_prefer_server_ciphers = on
ssl_ciphers = 'ECDHE+AESGCM:ECDHE+AES256:!aNULL:!MD5'

# Client certificate authentication for extra security (optional)
# Uncomment to require client certificates
# ssl_cert_file = '/var/lib/postgresql/data/certificates/server.crt'
# hostssl all all 0.0.0.0/0 cert

# Connection Security Settings
password_encryption = scram-sha-256  # Use strong password hashing
max_connections = 100
superuser_reserved_connections = 10

# Logging for audit trail
log_connections = on
log_disconnections = on
log_statement = 'all'  # Log all statements for audit compliance
log_duration = on
log_min_duration_statement = 0

# Connection timeout
idle_in_transaction_session_timeout = 600000  # 10 minutes
statement_timeout = 0
EOF
  
  log "✓ Created PostgreSQL SSL configuration"
}

# Create pg_hba.conf entries for SSL
create_pg_hba_config() {
  log "Creating pg_hba.conf SSL entries..."
  
  cat > "${CONFIG_DIR}/pg_hba-ssl.conf" <<'EOF'
# =============================================================================
# PostgreSQL Host-Based Authentication (HBA) - SSL Enforcement
# =============================================================================

# Local connections (Unix domain socket) - no SSL needed
local   all             all                                     trust

# IPv4 local connections - SSL required
hostssl all             all             127.0.0.1/32            scram-sha-256

# IPv4 remote connections - SSL required
hostssl all             all             0.0.0.0/0               scram-sha-256

# IPv6 local connections - SSL required
hostssl all             all             ::1/128                 scram-sha-256

# IPv6 remote connections - SSL required
hostssl all             all             ::/0                    scram-sha-256

# Reject all non-SSL connections
host    all             all             0.0.0.0/0               reject
host    all             all             ::/0                    reject

EOF
  
  log "✓ Created pg_hba.conf SSL configuration"
}

# Create environment variable documentation
create_env_documentation() {
  log "Creating environment variable documentation..."
  
  cat > "${CONFIG_DIR}/DATABASE-ENV-VARS.md" <<'EOF'
# PostgreSQL SSL Environment Variables

## Required for SSL Connections

```bash
# Connection parameters
export POSTGRES_HOST=${POSTGRES_CONTAINER_NAME}          # Container hostname
export POSTGRES_PORT=5432                  # PostgreSQL port
export POSTGRES_DB=appdb                   # Database name
export POSTGRES_USER=appuser               # Database user
export POSTGRES_PASSWORD=${DB_PASSWORD}    # From GSM (no default!)

# SSL/TLS parameters
export POSTGRES_SSLMODE=require             # Enforce SSL: require|prefer|disable
export POSTGRES_SSLCERT=/path/to/client.crt    # Client certificate
export POSTGRES_SSLKEY=/path/to/client-key.pem # Client private key
export POSTGRES_SSLROOTCERT=/path/to/ca.crt   # CA certificate
```

## Docker Compose Volumes

Ensure certificates are mounted into PostgreSQL container:

```yaml
postgres:
  volumes:
    - postgres_data:/var/lib/postgresql/data
    - ./vault-tls/postgres:/var/lib/postgresql/data/certificates:ro
    - ./config/postgres/postgres-ssl.conf:/etc/postgresql/postgresql.conf:ro
  environment:
    - POSTGRES_DB=${POSTGRES_DB}
    - POSTGRES_USER=${POSTGRES_USER}
    - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    - POSTGRES_SSLMODE=require
```

## Verification

### Test SSL connection from client

```bash
psql -h ${POSTGRES_CONTAINER_NAME} \
     -U appuser \
     -d appdb \
     -v sslmode=require \
     -c "SELECT version();"
```

### Verify SSL is active in PostgreSQL

```sql
-- Query active connections with SSL status
SELECT datname, usename, client_addr, ssl, sslversion, sslcipher
FROM pg_stat_activity
WHERE ssl = true;

-- Count SSL vs non-SSL connections
SELECT ssl, count(*) as connection_count
FROM pg_stat_activity
GROUP BY ssl;
```

### Check certificate details

```bash
# View certificate expiration
openssl x509 -in /path/to/server.crt -noout -dates

# Verify certificate chain
openssl verify -CAfile /path/to/ca.crt /path/to/server.crt

# Display certificate info
openssl x509 -in /path/to/server.crt -noout -text
```

## Troubleshooting

### "Certificate verification failed"
- Ensure CA certificate file exists and is readable
- Verify certificate chain is complete
- Check certificate wasn't self-signed incorrectly

### "SSL connection refused"  
- Ensure PostgreSQL is configured with ssl = on
- Check ssl_cert_file and ssl_key_file paths
- Verify files are readable by postgres user

### "unsupported frontend protocol"
- Client/server version mismatch
- Ensure PostgreSQL version supports SSL
- Check pg_hba.conf allows SSL connections

EOF
  
  log "✓ Created environment variable documentation"
}

main() {
  log "==========================================="
  log "PostgreSQL SSL Configuration - P1 #3"
  log "==========================================="
  
  create_postgres_ssl_config
  create_pg_hba_config
  create_env_documentation
  
  log ""
  log "✓ PostgreSQL SSL Configuration Complete"
  log "==========================================="
  log "Configuration Files:"
  log "  postgres-ssl.conf: ${CONFIG_DIR}/postgres-ssl.conf"
  log "  pg_hba-ssl.conf: ${CONFIG_DIR}/pg_hba-ssl.conf"
  log ""
  log "Next Steps:"
  log "1. Mount certificates in docker-compose.yml"
  log "2. Update PostgreSQL initialization scripts"
  log "3. Redeploy PostgreSQL container"
  log "4. Test SSL connections"
  log "==========================================="
}

main "$@"
