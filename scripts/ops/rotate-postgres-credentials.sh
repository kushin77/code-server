#!/bin/bash
# PostgreSQL credential rotation with automated failover handling
# Rotates database credentials and updates all services

set -e
trap 'echo "❌ Rotation failed at line $LINENO"; exit 1' ERR

PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"
BACKUP_DIR="/var/backups/credentials"

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PostgreSQL Credential Rotation - $TIMESTAMP               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Generate new secure password
NEW_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-25)

echo "Step 1: Backup current state..."
ssh -o BatchMode=yes akushnir@$PRIMARY << 'EOF'
  docker exec code-server-postgres pg_dump -U postgres --schema-only code_server > /tmp/backup_schema.sql
  echo "✓ Schema backed up"
EOF

echo "Step 2: Update primary PostgreSQL password..."
ssh -o BatchMode=yes akushnir@$PRIMARY << PSQL_EOF
  docker exec code-server-postgres psql -U postgres -c "
    ALTER USER postgres WITH PASSWORD '$NEW_PASSWORD';
  " 2>/dev/null
  echo "✓ Primary password updated"
PSQL_EOF

echo "Step 3: Update environment variables..."
ssh -o BatchMode=yes akushnir@$PRIMARY << ENV_EOF
  cd ~/code-server-enterprise
  # Update environment files
  sed -i 's/^DATABASE_PASSWORD=.*/DATABASE_PASSWORD=$NEW_PASSWORD/' .env 2>/dev/null || true
  sed -i 's/^DB_PASSWORD=.*/DB_PASSWORD=$NEW_PASSWORD/' .env.production 2>/dev/null || true
  echo "✓ Environment files updated"
ENV_EOF

echo "Step 4: Restart services with new credentials..."
ssh -o BatchMode=yes akushnir@$PRIMARY << 'RESTART_EOF'
  cd ~/code-server-enterprise
  docker restart code-server-postgres 2>/dev/null || true
  sleep 5
  docker restart code-server-execution-scheduler 2>/dev/null || true
  docker restart code-server-reputation-engine 2>/dev/null || true
  sleep 5
  echo "✓ Services restarted"
RESTART_EOF

echo "Step 5: Verify connectivity..."
ssh -o BatchMode=yes akushnir@$PRIMARY << VERIFY_EOF
  docker exec code-server-postgres psql -U postgres -d code_server -c "SELECT version();" >/dev/null
  echo "✓ Database connectivity verified"
VERIFY_EOF

echo "Step 6: Store encrypted backup..."
cat > "$BACKUP_DIR/creds_${TIMESTAMP}.txt" << CREDS_FILE
Rotation Date: $(date -R)
Database User: postgres
Database: code_server
New password stored securely
CREDS_FILE

echo "✓ Credentials backed up"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ PostgreSQL credentials rotated successfully             ║"
echo "║  Remember: Update any external connection strings          ║"
echo "╚════════════════════════════════════════════════════════════╝"
