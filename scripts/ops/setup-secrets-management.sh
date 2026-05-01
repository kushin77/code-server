#!/bin/bash
# Secrets management initialization with encryption
# Set up secure vault for storing platform secrets

set -e
trap 'echo "❌ Setup failed"; exit 1' ERR

SECRETS_DIR="${SECRETS_DIR:-/var/secrets}"
BACKUP_DIR="/var/backups/sealing-keys"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Secrets Management Setup                                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$SECRETS_DIR" "$BACKUP_DIR"

echo "Creating sealed secrets infrastructure..."

# Generate RSA keypair for sealing
echo -n "  Generating RSA keypair... "
openssl genrsa -out "$SECRETS_DIR/sealing-key.pem" 2048 >/dev/null 2>&1
openssl rsa -in "$SECRETS_DIR/sealing-key.pem" -pubout -out "$SECRETS_DIR/sealing-key.pub" >/dev/null 2>&1
echo "✓"

# Backup keys securely
echo -n "  Backing up encryption keys... "
cp "$SECRETS_DIR/sealing-key.pem" "$BACKUP_DIR/sealing-key.pem.backup"
cp "$SECRETS_DIR/sealing-key.pub" "$BACKUP_DIR/sealing-key.pub.backup"
echo "✓"

# Set restrictive permissions
chmod 400 "$SECRETS_DIR/sealing-key.pem"
chmod 400 "$SECRETS_DIR/sealing-key.pub"
chmod 400 "$BACKUP_DIR/sealing-key.pem.backup"

echo ""
echo "Creating secrets utility scripts..."

# Create secret sealing script
cat > "$SECRETS_DIR/seal-secret.sh" << 'SEAL_EOF'
#!/bin/bash
# Seal a secret value using RSA public key

if [[ -z "$1" ]] || [[ -z "$2" ]]; then
  echo "Usage: $0 <secret-name> <secret-value>"
  exit 1
fi

SECRET_NAME=$1
SECRET_VALUE=$2
SEALING_KEY="/var/secrets/sealing-key.pub"

if [[ ! -f "$SEALING_KEY" ]]; then
  echo "❌ Sealing key not found: $SEALING_KEY"
  exit 1
fi

# Create sealed secret
SEALED=$(echo -n "$SECRET_VALUE" | openssl rsautl -encrypt -pubin -inkey "$SEALING_KEY" | base64 -w0)

echo "{\"secretName\": \"$SECRET_NAME\", \"sealed\": \"$SEALED\"}"
SEAL_EOF

chmod +x "$SECRETS_DIR/seal-secret.sh"

# Create secret unsealing script
cat > "$SECRETS_DIR/unseal-secret.sh" << 'UNSEAL_EOF'
#!/bin/bash
# Unseal a secret value using RSA private key

if [[ -z "$1" ]]; then
  echo "Usage: $0 <sealed-secret-base64>"
  exit 1
fi

SEALED_SECRET=$1
SEALING_KEY="/var/secrets/sealing-key.pem"

if [[ ! -f "$SEALING_KEY" ]]; then
  echo "❌ Sealing key not found: $SEALING_KEY"
  exit 1
fi

# Decode and decrypt
echo "$SEALED_SECRET" | base64 -d | openssl rsautl -decrypt -inkey "$SEALING_KEY"
UNSEAL_EOF

chmod +x "$SECRETS_DIR/unseal-secret.sh"

echo "  ✓ Sealing scripts created"
echo ""

# Create secrets inventory
cat > "$SECRETS_DIR/secrets-inventory.sh" << 'INVENTORY_EOF'
#!/bin/bash
# Inventory of all platform secrets and rotation status

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Platform Secrets Inventory                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

INVENTORY=(
  "database_password:PostgreSQL master password:monthly"
  "redis_password:Redis master password:quarterly"
  "api_key_primary:Primary API key:semi-annually"
  "api_key_secondary:Secondary API key:semi-annually"
  "tls_cert:TLS certificate:annually"
  "tls_key:TLS private key:annually"
  "oauth_client_secret:OAuth client secret:annually"
)

echo "Secret Name | Description | Rotation Interval"
echo "─────────────────────────────────────────────────────────"

for SECRET_INFO in "${INVENTORY[@]}"; do
  IFS=':' read -r NAME DESC INTERVAL <<< "$SECRET_INFO"
  printf "%-20s | %-30s | %s\n" "$NAME" "$DESC" "$INTERVAL"
done

echo ""
echo "Last Rotation Summary:"
echo "  PostgreSQL: $(stat -c %y /var/backups/credentials/creds_*.txt 2>/dev/null | head -1 | cut -d' ' -f1 || echo 'Never')"
echo ""
INVENTORY_EOF

chmod +x "$SECRETS_DIR/secrets-inventory.sh"

echo "  ✓ Inventory script created"
echo ""

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ Secrets management initialized                        ║"
echo "║                                                            ║"
echo "║  Location: $SECRETS_DIR                          ║"
echo "║  Backup: $BACKUP_DIR                 ║"
echo "║                                                            ║"
echo "║  Available commands:                                       ║"
echo "║    • seal-secret.sh <name> <value>                        ║"
echo "║    • unseal-secret.sh <sealed-base64>                     ║"
echo "║    • secrets-inventory.sh                                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
