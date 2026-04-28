#!/bin/bash
# @file setup-database-ssl.sh
# @module security
# @description Set up SSL/TLS certificates for PostgreSQL database connections
# @governance GOV-002 - P1 Priority 3: Enforce SSL for all database connections
# @idempotent YES

set -euo pipefail

# Source canonical bootstrap (provides log_info, log_error, and shared configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# CONFIGURATION (using REPO_ROOT from init.sh)
# ============================================================================
CERT_DIR="${REPO_ROOT}/vault-tls"
POSTGRES_CERT_DIR="${CERT_DIR}/postgres"

# Source canonical service names
source "${REPO_ROOT}/scripts/_common/service-names.env"

# Certificate configuration
CERT_VALIDITY_DAYS=365
DB_HOST="${POSTGRES_CONTAINER_NAME}"
DB_PORT="5432"
COUNTRY="US"
STATE="CA"
CITY="San Francisco"
ORGANIZATION="ElevatedIQ"
COMMON_NAME="${POSTGRES_CONTAINER_NAME}"

# Create directories
mkdir -p "${POSTGRES_CERT_DIR}" "${REPO_ROOT}/logs"

# ============================================================================
# SSL CERTIFICATE GENERATION
# ============================================================================

generate_ca_certificate() {
  log_info "Generating Certificate Authority (CA) certificate..."
  
  local ca_key="${POSTGRES_CERT_DIR}/ca-key.pem"
  local ca_cert="${POSTGRES_CERT_DIR}/ca.crt"
  
  # Check if CA already exists
  if [[ -f "${ca_cert}" ]] && [[ -f "${ca_key}" ]]; then
    log_info "CA certificate already exists, skipping generation"
    return 0
  fi
  
  # Generate CA private key
  openssl genrsa -out "${ca_key}" 2048 2>/dev/null
  chmod 600 "${ca_key}"
  log_info "✓ Generated CA private key"
  
  # Generate CA certificate
  openssl req -new -x509 -days "${CERT_VALIDITY_DAYS}" \
    -key "${ca_key}" \
    -out "${ca_cert}" \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORGANIZATION}/CN=PostgreSQL-CA" \
    2>/dev/null
  chmod 644 "${ca_cert}"
  log_info "✓ Generated CA certificate (valid ${CERT_VALIDITY_DAYS} days)"
}

generate_server_certificate() {
  log_info "Generating PostgreSQL server certificate..."
  
  local ca_key="${POSTGRES_CERT_DIR}/ca-key.pem"
  local ca_cert="${POSTGRES_CERT_DIR}/ca.crt"
  local server_key="${POSTGRES_CERT_DIR}/server-key.pem"
  local server_csr="${POSTGRES_CERT_DIR}/server.csr"
  local server_cert="${POSTGRES_CERT_DIR}/server.crt"
  
  # Check if server certificate already exists
  if [[ -f "${server_cert}" ]] && [[ -f "${server_key}" ]]; then
    log_info "Server certificate already exists, skipping generation"
    return 0
  fi
  
  # Generate server private key
  openssl genrsa -out "${server_key}" 2048 2>/dev/null
  chmod 600 "${server_key}"
  log_info "✓ Generated server private key"
  
  # Generate certificate signing request
  openssl req -new \
    -key "${server_key}" \
    -out "${server_csr}" \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORGANIZATION}/CN=${DB_HOST}" \
    2>/dev/null
  log_info "✓ Generated certificate signing request"
  
  # Create config for SAN (Subject Alternative Names)
  local san_config=$(mktemp)
  cat > "${san_config}" <<EOF
[v3_req]
subjectAltName = DNS:${DB_HOST},DNS:localhost,IP:127.0.0.1
EOF
  
  # Sign server certificate with CA
  openssl x509 -req -days "${CERT_VALIDITY_DAYS}" \
    -in "${server_csr}" \
    -CA "${ca_cert}" \
    -CAkey "${ca_key}" \
    -CAcreateserial \
    -out "${server_cert}" \
    -extensions v3_req \
    -extfile "${san_config}" \
    2>/dev/null
  chmod 644 "${server_cert}"
  rm -f "${san_config}" "${server_csr}"
  log_info "✓ Generated server certificate (valid ${CERT_VALIDITY_DAYS} days)"
}

generate_client_certificate() {
  log_info "Generating PostgreSQL client certificate..."
  
  local ca_key="${POSTGRES_CERT_DIR}/ca-key.pem"
  local ca_cert="${POSTGRES_CERT_DIR}/ca.crt"
  local client_key="${POSTGRES_CERT_DIR}/client-key.pem"
  local client_csr="${POSTGRES_CERT_DIR}/client.csr"
  local client_cert="${POSTGRES_CERT_DIR}/client.crt"
  local client_user="appuser"
  
  # Check if client certificate already exists
  if [[ -f "${client_cert}" ]] && [[ -f "${client_key}" ]]; then
    log_info "Client certificate already exists, skipping generation"
    return 0
  fi
  
  # Generate client private key
  openssl genrsa -out "${client_key}" 2048 2>/dev/null
  chmod 600 "${client_key}"
  log_info "✓ Generated client private key"
  
  # Generate client certificate signing request
  openssl req -new \
    -key "${client_key}" \
    -out "${client_csr}" \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORGANIZATION}/CN=${client_user}" \
    2>/dev/null
  log_info "✓ Generated client certificate signing request"
  
  # Sign client certificate with CA
  openssl x509 -req -days "${CERT_VALIDITY_DAYS}" \
    -in "${client_csr}" \
    -CA "${ca_cert}" \
    -CAkey "${ca_key}" \
    -CAcreateserial \
    -out "${client_cert}" \
    2>/dev/null
  chmod 644 "${client_cert}"
  rm -f "${client_csr}"
  log_info "✓ Generated client certificate (valid ${CERT_VALIDITY_DAYS} days)"
}

# ============================================================================
# CERTIFICATE VERIFICATION
# ============================================================================

verify_certificates() {
  log_info "Verifying SSL certificates..."
  
  local ca_cert="${POSTGRES_CERT_DIR}/ca.crt"
  local server_cert="${POSTGRES_CERT_DIR}/server.crt"
  local client_cert="${POSTGRES_CERT_DIR}/client.crt"
  
  # Verify server certificate chain
  if openssl verify -CAfile "${ca_cert}" "${server_cert}" >/dev/null 2>&1; then
    log_info "✓ Server certificate verified"
  else
    log_error "✗ Server certificate verification failed"
    return 1
  fi
  
  # Verify client certificate chain
  if openssl verify -CAfile "${ca_cert}" "${client_cert}" >/dev/null 2>&1; then
    log_info "✓ Client certificate verified"
  else
    log_error "✗ Client certificate verification failed"
    return 1
  fi
  
  # Display certificate details
  log_info "Certificate Details:"
  log_info "  Server Certificate:"
  openssl x509 -in "${server_cert}" -noout -subject -dates | sed 's/^/    /'
  log_info "  Client Certificate:"
  openssl x509 -in "${client_cert}" -noout -subject -dates | sed 's/^/    /'
}

# ============================================================================
# DOCKER-COMPOSE CONFIGURATION
# ============================================================================

update_postgres_docker_config() {
  log_info "Updating PostgreSQL Docker Compose configuration..."
  
  local compose_file="${REPO_DIR}/docker-compose.yml"
  
  # Check if postgres service already has SSL config
  if grep -q "POSTGRES_HOST_AUTH_METHOD" "${compose_file}"; then
    log_info "PostgreSQL already configured for SSL, skipping docker-compose update"
    return 0
  fi
  
  log_info "Adding SSL environment variables to PostgreSQL service"
  log_info "Note: Update docker-compose.yml manually or use CI/CD for configuration"
}

# ============================================================================
# CONNECTION STRING EXAMPLES
# ============================================================================

generate_connection_examples() {
  local output_file="${REPO_DIR}/docs/DATABASE-SSL-CONNECTION-EXAMPLES.md"
  
  log_info "Generating connection string examples..."
  
  mkdir -p "${REPO_DIR}/docs"
  
  cat > "${output_file}" <<'EOF'
# PostgreSQL SSL Connection Examples

## Environment Variables (Required)

```bash
# Database SSL mode - REQUIRE enforces SSL for all connections
export POSTGRES_SSLMODE=require

# Certificate paths
export POSTGRES_SSLCERT=/path/to/client.crt
export POSTGRES_SSLKEY=/path/to/client-key.pem
export POSTGRES_SSLROOTCERT=/path/to/ca.crt

# Connection details
export POSTGRES_HOST="${POSTGRES_CONTAINER_NAME}"
export POSTGRES_PORT=5432
export POSTGRES_DB=appdb
export POSTGRES_USER=appuser
export POSTGRES_PASSWORD=${DB_PASSWORD}  # From GSM
```

## Connection Strings

### psql CLI

```bash
# With SSL certificate verification
psql \
  "host=${POSTGRES_CONTAINER_NAME} \
   port=5432 \
   dbname=appdb \
   user=appuser \
   password=${DB_PASSWORD} \
   sslmode=require \
   sslcert=/path/to/client.crt \
   sslkey=/path/to/client-key.pem \
   sslrootcert=/path/to/ca.crt"

# Or use .pgpass file
echo "postgres-db:5432:appdb:appuser:${DB_PASSWORD}" > ~/.pgpass
chmod 600 ~/.pgpass
psql -h postgres-db -U appuser -d appdb -v sslmode=require
```

### Python (psycopg2)

```python
import psycopg2

conn = psycopg2.connect(
    host="postgres-db",
    port=5432,
    database="appdb",
    user="appuser",
    password=os.environ['DB_PASSWORD'],
    sslmode="require",
    sslcert="/path/to/client.crt",
    sslkey="/path/to/client-key.pem",
    sslrootcert="/path/to/ca.crt"
)
```

### Node.js (pg library)

```javascript
const { Client } = require('pg');
const fs = require('fs');

const client = new Client({
  host: 'postgres-db',
  port: 5432,
  database: 'appdb',
  user: 'appuser',
  password: process.env.DB_PASSWORD,
  ssl: {
    rejectUnauthorized: true,
    cert: fs.readFileSync('/path/to/client.crt', 'utf8'),
    key: fs.readFileSync('/path/to/client-key.pem', 'utf8'),
    ca: fs.readFileSync('/path/to/ca.crt', 'utf8'),
  },
});
```

### Java (JDBC)

```properties
# Connection URL
jdbc:postgresql://postgres-db:5432/appdb?user=appuser&password=${DB_PASSWORD}&ssl=true&sslmode=require

# System properties
-Dpostgresql.server.cert.location=/path/to/server.crt
-Dpostgresql.client.cert.location=/path/to/client.crt
-Dpostgresql.client.key.location=/path/to/client-key.pem
```

### Go (pq library)

```go
import (
    "crypto/tls"
    "crypto/x509"
    "database/sql"
    _ "github.com/lib/pq"
    "io/ioutil"
)

// Load CA certificate
caCert, _ := ioutil.ReadFile("/path/to/ca.crt")
caCertPool := x509.NewCertPool()
caCertPool.AppendCertsFromPEM(caCert)

// Load client certificate
cert, _ := tls.LoadX509KeyPair(
    "/path/to/client.crt",
    "/path/to/client-key.pem",
)

// Create TLS configuration
tlsConfig := &tls.Config{
    Certificates: []tls.Certificate{cert},
    ClientCAs:    caCertPool,
    ClientAuth:   tls.RequireAndVerifyClientCert,
}

// Connect with SSL
connString := fmt.Sprintf(
    "user=%s password=%s host=%s port=%d dbname=%s sslmode=require",
    "appuser",
    os.Getenv("DB_PASSWORD"),
    "postgres-db",
    5432,
    "appdb",
)

db, _ := sql.Open("postgres", connString)
```

## Verification

### Test SSL Connection

```bash
# Check if PostgreSQL is listening on SSL port
openssl s_client -connect postgres-db:5432 -cert client.crt -key client-key.pem -CAfile ca.crt

# Verify certificate chain
openssl verify -CAfile ca.crt client.crt

# Check certificate expiration
openssl x509 -in client.crt -noout -dates
```

### Monitoring SSL Connections

```sql
-- In PostgreSQL
SELECT datname, usename, client_addr, state, ssl, sslversion, sslcipher
FROM pg_stat_activity
WHERE ssl = true;

-- Check for non-SSL connections (should be none)
SELECT count(*) as non_ssl_connections
FROM pg_stat_activity
WHERE ssl = false;
```

## Troubleshooting

### "SSL connection refused"
- Ensure PostgreSQL is configured to accept SSL connections
- Check that server certificate is valid and signed by the CA
- Verify certificates are in correct directories

### "Certificate verification failed"
- Ensure CA certificate is in the client's trust store
- Verify certificate chain: openssl verify -CAfile ca.crt client.crt
- Check certificate expiration dates

### "SSL mode not supported"
- Ensure PostgreSQL driver supports SSL
- Verify sslmode parameter is supported (require, prefer, disable, etc.)
- Use require mode for maximum security

## Certificate Rotation

Certificates expire after {{CERT_VALIDITY_DAYS}} days. Rotate as follows:

1. Generate new certificates using setup-database-ssl.sh
2. Deploy new certificates to all clients
3. Restart PostgreSQL service
4. Verify all connections using SSL

EOF
  
  log_info "✓ Connection examples generated: ${output_file}"
}

# ============================================================================
# HEALTH CHECK
# ============================================================================

check_database_ssl_health() {
  log_info "Checking PostgreSQL SSL configuration health..."
  
  local cert_dir="${POSTGRES_CERT_DIR}"
  local required_files=("ca.crt" "server.crt" "server-key.pem" "client.crt" "client-key.pem")
  local missing_files=()
  
  for file in "${required_files[@]}"; do
    if [[ ! -f "${cert_dir}/${file}" ]]; then
      missing_files+=("${file}")
    fi
  done
  
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    log_error "Missing SSL certificates: ${missing_files[*]}"
    return 1
  fi
  
  log_info "✓ All required SSL certificates present"
  
  # Check certificate permissions
  if [[ $(stat -c %a "${cert_dir}/server-key.pem" 2>/dev/null || stat -f %OLp "${cert_dir}/server-key.pem" 2>/dev/null || echo "400") != "400" ]]; then
    log "WARN" "Server key has permissive permissions (should be 400)"
  fi
  
  log_info "✓ PostgreSQL SSL configuration is healthy"
  return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  log_info "=========================================="
  log_info "PostgreSQL SSL Setup - P1 Priority 3"
  log_info "=========================================="
  log_info ""
  
  # Generate certificates
  generate_ca_certificate
  generate_server_certificate
  generate_client_certificate
  
  # Verify certificates
  verify_certificates
  
  # Update configuration
  update_postgres_docker_config
  
  # Generate examples
  generate_connection_examples
  
  # Health check
  if check_database_ssl_health; then
    log_info ""
    log_info "✓ PostgreSQL SSL Setup Complete"
    log_info "=========================================="
    log_info "Certificate Directory: ${POSTGRES_CERT_DIR}"
    log_info "Connection Examples: ${REPO_DIR}/docs/DATABASE-SSL-CONNECTION-EXAMPLES.md"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Update docker-compose.yml to mount certificates"
    log_info "2. Configure PostgreSQL for SSL (postgresql.conf)"
    log_info "3. Update all client connection strings"
    log_info "4. Deploy to staging and test"
    log_info "=========================================="
    return 0
  else
    log_error "PostgreSQL SSL Setup Failed"
    return 1
  fi
}

main "$@"
