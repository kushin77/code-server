#!/bin/bash
# Vault Audit Logging Setup — P0 #413 Phase 1 Step 3
# Enables comprehensive audit logging for compliance + security
# Run after Vault is unsealed and authenticated

set -euo pipefail

VAULT_ADDR=${VAULT_ADDR:-"https://localhost:8200"}
VAULT_TOKEN=${VAULT_TOKEN:-""}
VAULT_CACERT="${VAULT_CACERT:-/etc/vault/tls/ca.crt}"
AUDIT_LOG_DIR="/var/log/vault"

if [ -z "$VAULT_TOKEN" ]; then
  echo "ERROR: VAULT_TOKEN must be set"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════"
echo "Vault Audit Logging Setup — P0 #413"
echo "═══════════════════════════════════════════════════════════════"

export VAULT_ADDR VAULT_TOKEN VAULT_CACERT

# 1. Create audit log directory
echo "✓ Step 1: Create audit log directory"
mkdir -p "$AUDIT_LOG_DIR"
chmod 700 "$AUDIT_LOG_DIR"
echo "  Created: $AUDIT_LOG_DIR"

# 2. Enable file audit backend
echo "✓ Step 2: Enable file audit backend"
vault audit enable file file_path="$AUDIT_LOG_DIR/audit.log"
echo "  Enabled: file backend at $AUDIT_LOG_DIR/audit.log"

# 3. Verify audit is enabled
echo "✓ Step 3: Verify audit logging"
vault audit list
echo "  Status: Audit backends active"

# 4. Test audit logging
echo "✓ Step 4: Test audit logging (generate test entry)"
vault write sys/policies/acl/test-policy rules="path \"*\" { capabilities = [\"read\"] }"
echo "  Test policy created (should appear in audit log)"

# 5. Configure Loki log shipping (docker-compose integration)
cat > /tmp/vault-promtail-config.yaml << 'EOF'
# Promtail config for shipping Vault audit logs to Loki
scrape_configs:
  - job_name: vault-audit
    static_configs:
      - targets:
          - localhost
        labels:
          job: vault
          env: production
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_file
        replacement: /var/log/vault/audit.log

    # Ship to Loki
    loki_push_api:
      url: http://loki:3100/loki/api/v1/push
      batchwait: 10s
      batchsize: 102400
      labels:
        service: vault
        severity: audit
EOF

echo "✓ Step 5: Loki integration configuration"
echo "  Generated: /tmp/vault-promtail-config.yaml"
echo "  → Copy to docker-compose promtail volumes"

# 6. Prometheus monitoring (Vault metrics)
cat > /tmp/vault-prometheus-config.yaml << 'EOF'
# Prometheus job for Vault metrics
job_name: 'vault'
metrics_path: '/v1/sys/metrics'
params:
  format: ['prometheus']
bearer_token: '${VAULT_TOKEN}'  # Use monitoring policy token
scheme: 'https'
tls_config:
  ca_file: '/etc/vault/tls/ca.crt'
static_configs:
  - targets: ['localhost:8200']
EOF

echo "✓ Step 6: Prometheus metrics configuration"
echo "  Generated: /tmp/vault-prometheus-config.yaml"
echo "  → Merge into prometheus.yml"

# 7. Alert rules for critical Vault events
cat > /tmp/vault-alert-rules.yml << 'EOF'
# AlertManager rules for Vault security events
groups:
  - name: vault-security
    interval: 30s
    rules:
      # Vault is sealed (disaster scenario)
      - alert: VaultSealed
        expr: vault_core_unsealed == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Vault is sealed - immediate investigation required"
          description: "Vault instance {{ $labels.instance }} is sealed"

      # Auth token expiration soon
      - alert: VaultTokenExpirationWarning
        expr: vault_token_remaining_ttl < 86400  # 24 hours
        for: 5m
        labels:
          severity: high
        annotations:
          summary: "Vault token expiring soon"
          description: "Token {{ $labels.token_path }} expires in {{ $value }} seconds"

      # High number of auth failures
      - alert: VaultAuthFailureSpike
        expr: rate(vault_core_handle_login_request[5m]) > 1
        for: 5m
        labels:
          severity: high
        annotations:
          summary: "Vault authentication failure spike"
          description: "{{ $value }} failed auth attempts per second"

      # Audit log issues
      - alert: VaultAuditLogError
        expr: rate(vault_audit_log_request_failure[5m]) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Vault audit logging failure"
          description: "Audit log writes failing - compliance breach risk"

      # Storage issues
      - alert: VaultStorageError
        expr: rate(vault_core_storage_error[5m]) > 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Vault storage backend errors"
          description: "Storage backend reporting errors - data loss risk"
EOF

echo "✓ Step 7: AlertManager rules for critical Vault events"
echo "  Generated: /tmp/vault-alert-rules.yml"
echo "  → Merge into prometheus alert-rules directory"

# 8. Rotate audit logs (logrotate config)
cat > /tmp/vault-logrotate << 'EOF'
/var/log/vault/audit.log {
  daily
  rotate 90
  compress
  delaycompress
  missingok
  notifempty
  create 0600 vault vault
  postrotate
    vault audit list | grep file && echo "Vault audit log rotated"
  endscript
}
EOF

echo "✓ Step 8: Log rotation configuration"
echo "  Generated: /tmp/vault-logrotate"
echo "  → Copy to /etc/logrotate.d/vault"

# 9. Test audit log reading
echo "✓ Step 9: Verify audit log format"
if [ -f "$AUDIT_LOG_DIR/audit.log" ]; then
  echo "  Last 5 audit entries:"
  tail -5 "$AUDIT_LOG_DIR/audit.log" | jq . 2>/dev/null || tail -5 "$AUDIT_LOG_DIR/audit.log"
else
  echo "  Audit log not yet created (will appear after first operation)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✓ Audit Logging Setup Complete"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Configuration Files Generated:"
echo "  • /tmp/vault-promtail-config.yaml (Loki shipping)"
echo "  • /tmp/vault-prometheus-config.yaml (metrics)"
echo "  • /tmp/vault-alert-rules.yml (alerts)"
echo "  • /tmp/vault-logrotate (log rotation)"
echo ""
echo "Next Steps:"
echo "1. Review and merge configuration files into deployment"
echo "2. Enable encryption at rest (P0 #413 Phase 1 Step 4)"
echo "3. Test Loki log shipping (query vault audit logs in Grafana)"
echo "4. Verify AlertManager rules (check for vault alerts)"
echo ""
echo "⚠️  CRITICAL: Audit logs contain sensitive information"
echo "   • Restrict access: chmod 600 /var/log/vault/*"
echo "   • Centralize for backup: ship to secure log aggregation"
echo "   • Retain for 90 days minimum (compliance requirement)"
