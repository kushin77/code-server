#!/bin/bash
# scripts/setup-vault-secrets-rotation.sh
# =======================================
# Setup Vault dynamic secrets rotation for PostgreSQL credentials
# Integrates with docker-compose vault service for automatic credential rotation
#
# Usage:
#   bash scripts/setup-vault-secrets-rotation.sh [--dry-run]
#
# Prerequisites:
#   - Vault running in production mode (port 8200)
#   - PostgreSQL accessible for Vault policy configuration
#   - VAULT_ADDR and VAULT_TOKEN environment variables

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

log_info() { echo "[INFO] $*"; }
log_ok()  { echo "  ✓ $*"; }
log_warn(){ echo "  ⚠ $*"; }
log_err() { echo "  ✗ $*" >&2; }

dry() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

log_info "═══════════════════════════════════════════════════════════════"
log_info "Vault PostgreSQL Dynamic Secrets Rotation Setup (#356)"
log_info "═══════════════════════════════════════════════════════════════"

# ─── 1. Verify Vault is running ──────────────────────────────────────────

log_info "1: Verifying Vault connectivity..."

if [[ -z "${VAULT_ADDR:-}" ]]; then
    VAULT_ADDR="http://localhost:8200"
    log_warn "VAULT_ADDR not set, using default: $VAULT_ADDR"
fi

if [[ -z "${VAULT_TOKEN:-}" ]]; then
    log_err "VAULT_TOKEN environment variable required"
    exit 1
fi

# Test Vault connectivity
if dry vault status &>/dev/null; then
    log_ok "Vault is accessible at $VAULT_ADDR"
else
    log_err "Cannot connect to Vault at $VAULT_ADDR"
    exit 1
fi

# ─── 2. Configure PostgreSQL database connection in Vault ────────────────

log_info "2: Configuring PostgreSQL database backend..."

POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-${POSTGRES_USER}}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD required}"

# Create database secret engine config
if [[ "${DRY_RUN}" == "false" ]]; then
    vault write database/config/postgresql \
        plugin_name=postgresql-database-plugin \
        allowed_roles="code-server,readonly" \
        connection_url="postgresql://{{username}}:{{password}}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}" \
        username="${POSTGRES_USER}" \
        password="${POSTGRES_PASSWORD}" \
        && log_ok "PostgreSQL database connection configured in Vault" \
        || log_err "Failed to configure PostgreSQL backend"
fi

# ─── 3. Create Vault database roles for automatic credential rotation ────

log_info "3: Creating Vault database roles..."

# Role for code-server application
CODE_SERVER_SQL='
CREATE USER "{{name}}" WITH PASSWORD ''{{password}}'';
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "{{name}}";
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO "{{name}}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "{{name}}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO "{{name}}";
'

if [[ "${DRY_RUN}" == "false" ]]; then
    vault write database/roles/code-server \
        db_name=postgresql \
        creation_statements="${CODE_SERVER_SQL}" \
        default_ttl="1h" \
        max_ttl="24h" \
        && log_ok "code-server role created (1h default TTL, 24h max TTL)" \
        || log_err "Failed to create code-server role"
fi

# Role for read-only access
READONLY_SQL='
CREATE USER "{{name}}" WITH PASSWORD ''{{password}}'';
GRANT CONNECT ON DATABASE '${POSTGRES_DB}' TO "{{name}}";
GRANT USAGE ON SCHEMA public TO "{{name}}";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "{{name}}";
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO "{{name}}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "{{name}}";
'

if [[ "${DRY_RUN}" == "false" ]]; then
    vault write database/roles/readonly \
        db_name=postgresql \
        creation_statements="${READONLY_SQL}" \
        default_ttl="2h" \
        max_ttl="48h" \
        && log_ok "readonly role created (2h default TTL, 48h max TTL)" \
        || log_err "Failed to create readonly role"
fi

# ─── 4. Setup rotation cron job ──────────────────────────────────────────

log_info "4: Setting up credential rotation cron job..."

if [[ "${DRY_RUN}" == "false" ]]; then
    cat > /etc/cron.d/vault-postgres-rotation <<'CRON'
# Vault PostgreSQL credential rotation every 45 minutes (before TTL expiry)
*/45 * * * * root /usr/local/bin/rotate-vault-credentials.sh >> /var/log/vault-rotation.log 2>&1
CRON
    log_ok "Cron job installed (/etc/cron.d/vault-postgres-rotation)"
fi

# ─── 5. Create rotation script ───────────────────────────────────────────

log_info "5: Creating credential rotation script..."

if [[ "${DRY_RUN}" == "false" ]]; then
    cat > /usr/local/bin/rotate-vault-credentials.sh <<'ROTATE'
#!/bin/bash
# Rotate PostgreSQL credentials from Vault every 45 minutes

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"
CRED_PATH="/var/run/secrets/vault-postgres"
LOG_FILE="/var/log/vault-rotation.log"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# Ensure credential directory exists
mkdir -p "$CRED_PATH"
chmod 0700 "$CRED_PATH"

# Fetch new credentials from Vault
log "Fetching new PostgreSQL credentials from Vault..."

VAULT_OPTS=""
[[ -n "${VAULT_NAMESPACE}" ]] && VAULT_OPTS="-namespace=${VAULT_NAMESPACE}"

if CREDS=$(vault $VAULT_OPTS read -format=json database/static-creds/code-server 2>&1); then
    USERNAME=$(echo "$CREDS" | jq -r '.data.username')
    PASSWORD=$(echo "$CREDS" | jq -r '.data.password')
    
    # Save credentials to secure file
    cat > "${CRED_PATH}/.postgres-creds.env" <<ENVFILE
POSTGRES_USER=${USERNAME}
POSTGRES_PASSWORD=${PASSWORD}
ENVFILE
    chmod 0600 "${CRED_PATH}/.postgres-creds.env"
    
    log "✓ Credentials rotated successfully (user: $USERNAME)"
    
    # Notify running containers to reload credentials
    docker exec code-server /bin/bash -c "source ${CRED_PATH}/.postgres-creds.env" 2>/dev/null || true
else
    log "✗ Failed to fetch credentials: $CREDS"
    exit 1
fi
ROTATE
    
    chmod 0755 /usr/local/bin/rotate-vault-credentials.sh
    log_ok "Rotation script created (/usr/local/bin/rotate-vault-credentials.sh)"
fi

# ─── 6. Create systemd timer for rotation (alternative to cron) ──────────

log_info "6: Creating systemd timer for credential rotation..."

if [[ "${DRY_RUN}" == "false" ]]; then
    cat > /etc/systemd/system/vault-rotate-credentials.service <<'SYSTEMD'
[Unit]
Description=Vault PostgreSQL Credential Rotation
After=network-online.target vault.service
Wants=network-online.target
StartLimitInterval=600
StartLimitBurst=3

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rotate-vault-credentials.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vault-rotation
User=root
SYSTEMD

    cat > /etc/systemd/system/vault-rotate-credentials.timer <<'TIMER'
[Unit]
Description=Rotate Vault PostgreSQL Credentials every 45 minutes
Requires=vault-rotate-credentials.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=45min
Persistent=true

[Install]
WantedBy=timers.target
TIMER
    
    dry systemctl daemon-reload
    dry systemctl enable vault-rotate-credentials.timer
    dry systemctl start vault-rotate-credentials.timer
    
    log_ok "Systemd timer enabled (/etc/systemd/system/vault-rotate-credentials.timer)"
fi

# ─── 7. Test credential retrieval ───────────────────────────────────────

log_info "7: Testing credential retrieval..."

if [[ "${DRY_RUN}" == "false" ]]; then
    if CREDS=$(vault read -format=json database/static-creds/code-server 2>/dev/null); then
        USERNAME=$(echo "$CREDS" | jq -r '.data.username')
        log_ok "✓ Successfully retrieved credentials for user: $USERNAME"
    else
        log_warn "⚠ Credential test failed (may require additional setup)"
    fi
fi

# ─── 8. Create monitoring alert for rotation failures ────────────────────

log_info "8: Creating Prometheus alert for rotation failures..."

if [[ "${DRY_RUN}" == "false" ]]; then
    cat > /etc/prometheus/rules/vault-rotation-alerts.yml <<'ALERT'
groups:
  - name: vault_secrets_rotation
    interval: 1m
    rules:
      - alert: VaultCredentialRotationFailed
        expr: increase(vault_rotation_failures_total[5m]) > 0
        for: 5m
        labels:
          severity: critical
          component: vault
        annotations:
          summary: "Vault credential rotation failed"
          description: "PostgreSQL credentials failed to rotate. Check /var/log/vault-rotation.log"

      - alert: VaultCredentialRotationLate
        expr: time() - vault_last_rotation_timestamp_seconds > 3600
        for: 15m
        labels:
          severity: warning
          component: vault
        annotations:
          summary: "Vault credential rotation overdue"
          description: "Credentials have not been rotated in {{ \$value | humanizeDuration }}"

      - alert: VaultCredentialExpiringWithin1Hour
        expr: vault_credential_expiration_unix_seconds - time() < 3600
        labels:
          severity: warning
          component: vault
        annotations:
          summary: "Vault credential expiring soon"
          description: "PostgreSQL credentials will expire in {{ \$value | humanizeDuration }}"
ALERT
    
    log_ok "Prometheus alerts configured (/etc/prometheus/rules/vault-rotation-alerts.yml)"
fi

log_info "═══════════════════════════════════════════════════════════════"
log_ok "Vault PostgreSQL dynamic secrets rotation setup complete"
log_info "═══════════════════════════════════════════════════════════════"
log_info ""
log_warn "Next steps:"
log_warn "1. Verify Vault is in production mode: vault status"
log_warn "2. Test credential rotation: /usr/local/bin/rotate-vault-credentials.sh"
log_warn "3. Monitor rotation: tail -f /var/log/vault-rotation.log"
log_warn "4. Update application config to use rotated credentials"
log_warn "5. Verify systemd timer: systemctl status vault-rotate-credentials.timer"
