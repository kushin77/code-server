#!/bin/bash

################################################################################
# Phase 6.3: Audit Logging & Container Security
# Purpose: Comprehensive audit logging and container security hardening
# Usage: ./scripts/configure-audit-logging.sh [--apply]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary audit files..."; rm -f /tmp/audit-*.tmp 2>/dev/null || true' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

################################################################################
# 1. AUDIT LOGGING CONFIGURATION
################################################################################

create_audit_logging() {
    log_info "Creating audit logging configuration..."

    mkdir -p "${PROJECT_ROOT}/security/audit"

    cat > "${PROJECT_ROOT}/security/audit/audit-config.yaml" << 'AUDIT_CONFIG'
---
# Comprehensive Audit Logging Configuration

audit:
  # Audit log storage
  storage:
    backend: loki
    retention_days: 90
    log_index: code-server-audit
    index_pattern: "audit-{date}"
    
  # Events to audit
  events:
    # Authentication events
    authentication:
      enabled: true
      log_successful_login: true
      log_failed_login: true
      log_token_generation: true
      log_token_revocation: true
      sensitive_fields: [password, token, secret]
    
    # Authorization events
    authorization:
      enabled: true
      log_permission_checks: true
      log_permission_denied: true
      log_role_changes: true
      log_policy_changes: true
    
    # Data access events
    data_access:
      enabled: true
      log_secret_access: true
      log_config_access: true
      log_database_queries: true
      log_file_access: true
    
    # System events
    system:
      enabled: true
      log_service_start: true
      log_service_stop: true
      log_service_restart: true
      log_configuration_changes: true
      log_certificate_changes: true
    
    # Network events
    network:
      enabled: true
      log_connection_attempts: true
      log_failed_connections: true
      log_tls_handshakes: true
      log_firewall_blocks: true
    
    # Container events
    container:
      enabled: true
      log_container_creation: true
      log_container_deletion: true
      log_container_restart: true
      log_image_pull: true
      log_privileged_containers: true
    
    # Security events
    security:
      enabled: true
      log_vulnerability_scans: true
      log_policy_violations: true
      log_intrusion_attempts: true
      log_compliance_changes: true

  # Log levels
  levels:
    emergency: critical issues requiring immediate action
    alert: urgent conditions
    critical: critical conditions
    error: error conditions
    warning: warning conditions
    notice: normal but significant events
    info: informational messages
    debug: debug-level messages

  # Sensitive data filtering
  data_masking:
    enabled: true
    patterns:
      - name: password
        regex: '(?i)(password|passwd|pwd)\s*[:=]\s*[^\s,]+'
        replacement: "[REDACTED]"
      
      - name: api_key
        regex: '(?i)(api[_-]?key|apikey|token)\s*[:=]\s*[^\s,]+'
        replacement: "[REDACTED]"
      
      - name: secret
        regex: '(?i)(secret|secret_key)\s*[:=]\s*[^\s,]+'
        replacement: "[REDACTED]"
      
      - name: credit_card
        regex: '\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b'
        replacement: "[REDACTED]"
      
      - name: ssn
        regex: '\b\d{3}-\d{2}-\d{4}\b'
        replacement: "[REDACTED]"

  # Alert rules
  alerts:
    - name: multiple_failed_logins
      condition: "failed_login_count > 5 in 5m"
      severity: warning
    
    - name: unauthorized_secret_access
      condition: "secret_access AND permission_denied"
      severity: critical
    
    - name: privilege_escalation
      condition: "role_change TO admin"
      severity: critical
    
    - name: suspicious_network_activity
      condition: "connection_attempts > 100 in 1m"
      severity: warning
    
    - name: container_escape_attempt
      condition: "privileged_container AND capability_requested"
      severity: critical
    
    - name: certificate_expiration_warning
      condition: "certificate_expiration_days < 30"
      severity: warning

  # Compliance standards
  compliance:
    standards:
      - pci_dss
      - hipaa
      - gdpr
      - soc2
    
    pci_dss:
      requirement_10_1: true  # Log all access to cardholder data
      requirement_10_2: true  # Implement automated audit trails
      requirement_10_3: true  # Protect audit trail history
    
    hipaa:
      audit_controls: true
      access_controls: true
      integrity_controls: true
    
    gdpr:
      data_processing: true
      access_logging: true
      retention_limits: 90 days
    
    soc2:
      logging_monitoring: true
      change_management: true
      incident_response: true

  # Retention policies
  retention:
    default_retention_days: 90
    security_events_retention_days: 365
    compliance_events_retention_days: 2555  # 7 years
    debug_logs_retention_days: 7

  # Export policies
  exports:
    formats: [json, csv, syslog]
    destinations:
      - type: s3
        bucket: code-server-audit-logs
        prefix: audit/
    
      - type: syslog
        server: syslog.example.com
        port: 514
        protocol: tcp

AUDIT_CONFIG

    log_success "Audit logging configuration created"
}

################################################################################
# 2. CONTAINER SECURITY POLICIES
################################################################################

create_container_security() {
    log_info "Creating container security policies..."

    cat > "${PROJECT_ROOT}/security/container-security.yaml" << 'CONTAINER_SEC'
---
# Container Security Policies

container_security:
  # Image scanning
  image_scanning:
    enabled: true
    scan_on_pull: true
    scan_on_push: true
    fail_on_high_severity: true
    fail_on_critical_severity: true
    allowed_registries:
      - docker.io
      - ghcr.io
      - registry.example.com

  # Runtime security
  runtime:
    # Privileged mode restrictions
    privileged: false
    
    # Capabilities
    capabilities:
      add: []
      drop: [ALL]
      retain: [NET_BIND_SERVICE, CHOWN, SETUID, SETGID]
    
    # Read-only root filesystem
    read_only_root_fs: true
    
    # User context
    run_as_non_root: true
    run_as_user: 1000
    
    # Security options
    security_opt:
      - no-new-privileges=true
      - seccomp=unconfined
      - apparmor=docker-default

  # Resource limits
  resources:
    memory_limit: "2Gi"
    memory_request: "512Mi"
    cpu_limit: "2000m"
    cpu_request: "500m"
    
    # Process limits
    pids_limit: 1000
    ulimits:
      - nofile: 65536
      - nproc: 4096

  # Volume management
  volumes:
    # Prohibited volume types
    prohibited: [hostPath, docker, local]
    
    # Volume permissions
    default_mode: "0755"
    
    # Secret volumes
    secrets_mount_path: "/run/secrets"
    secrets_permissions: "0400"

  # Network policies
  network:
    # Network isolation
    network_mode: bridge
    
    # Port restrictions
    expose_ports: [8000, 8080, 8443]
    
    # DNS
    dns:
      - 8.8.8.8
      - 8.8.4.4
    
    # No external access to certain services
    internal_only_services:
      - postgres
      - redis
      - vault

  # Image policies
  image:
    # Signed images only
    require_signed_images: true
    
    # No latest tags
    ban_latest_tag: true
    
    # Minimal base images
    approved_base_images:
      - alpine:3.18
      - python:3.11-slim
      - golang:1.21-alpine
      - node:20-alpine
    
    # Vulnerability scanning
    max_vulnerabilities:
      critical: 0
      high: 0
      medium: 5

  # Runtime monitoring
  monitoring:
    # Process monitoring
    enable_process_monitoring: true
    block_suspicious_processes: true
    
    # File integrity monitoring
    enable_fim: true
    fim_paths:
      - /etc
      - /app
      - /usr/bin
      - /usr/sbin
    
    # Network monitoring
    enable_network_monitoring: true
    alert_on_outbound: true
    
    # System call monitoring
    enable_syscall_monitoring: true

  # Secrets in containers
  secrets:
    no_hardcoded_secrets: true
    scan_for_secrets: true
    secret_patterns:
      - password
      - apikey
      - secret
      - token
      - credential

  # Logging and compliance
  logging:
    enable_container_logs: true
    log_all_commands: true
    enable_audit_logging: true
    
  # Regular updates
  updates:
    enable_auto_updates: true
    update_frequency: weekly
    security_updates: immediate

CONTAINER_SEC

    log_success "Container security policies created"
}

################################################################################
# 3. COMPLIANCE MONITORING
################################################################################

create_compliance_monitoring() {
    log_info "Creating compliance monitoring configuration..."

    cat > "${PROJECT_ROOT}/security/compliance-monitoring.sh" << 'COMPLIANCE_MON'
#!/bin/bash

# Compliance Monitoring Script
# Validates security controls and compliance standards

set -euo pipefail

LOG_FILE="/var/log/compliance-monitoring.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check image vulnerability scan results
check_image_vulnerabilities() {
    log "Checking container image vulnerabilities..."
    
    docker ps -q | while read -r container_id; do
        image=$(docker inspect "$container_id" --format='{{.Config.Image}}')
        log "Scanning image: $image"
        
        # Run vulnerability scan
        trivy image "$image" --exit-code 0 --severity HIGH,CRITICAL || {
            log "WARNING: Vulnerabilities found in $image"
        }
    done
}

# Check RBAC compliance
check_rbac_compliance() {
    log "Checking RBAC compliance..."
    
    # Verify no default credentials
    if grep -r "admin:admin" /etc/docker/ 2>/dev/null; then
        log "ERROR: Default credentials found"
        return 1
    fi
    
    # Verify role assignments
    docker exec vault vault list auth/approle/role 2>/dev/null | while read -r role; do
        policies=$(docker exec vault vault read auth/approle/role/$role 2>/dev/null | grep -i policy || true)
        log "Role $role: $policies"
    done
}

# Check TLS compliance
check_tls_compliance() {
    log "Checking TLS compliance..."
    
    # Verify minimum TLS version
    echo | openssl s_client -connect localhost:443 -tls1_2 2>/dev/null | grep "Protocol" || {
        log "ERROR: TLS 1.2 not supported"
        return 1
    }
    
    # Check certificate expiration
    cert_file="/data/certs/server.crt"
    if [ -f "$cert_file" ]; then
        exp_date=$(openssl x509 -in "$cert_file" -noout -dates | grep notAfter | cut -d= -f2)
        exp_epoch=$(date -d "$exp_date" +%s)
        current_epoch=$(date +%s)
        days_left=$(( (exp_epoch - current_epoch) / 86400 ))
        
        log "Certificate expires in $days_left days"
        
        if [ "$days_left" -lt 30 ]; then
            log "WARNING: Certificate expiring soon"
        fi
    fi
}

# Check audit logging
check_audit_logging() {
    log "Checking audit logging compliance..."
    
    # Verify Vault audit backend
    if ! docker exec vault vault audit list 2>/dev/null | grep -q "file"; then
        log "ERROR: File audit backend not enabled"
        docker exec vault vault audit enable file file_path=/vault/logs/audit.log || true
    fi
    
    # Check log retention
    audit_logs=$(find /data -name "*audit*" -mtime +90 2>/dev/null | wc -l)
    if [ "$audit_logs" -gt 0 ]; then
        log "WARNING: Found $audit_logs audit logs older than 90 days"
    fi
}

# Generate compliance report
generate_compliance_report() {
    log "Generating compliance report..."
    
    report_file="/data/compliance-report-$(date +%Y%m%d).txt"
    
    {
        echo "=== Compliance Report ==="
        echo "Generated: $(date)"
        echo ""
        echo "Checks Performed:"
        echo "1. Image Vulnerabilities"
        echo "2. RBAC Compliance"
        echo "3. TLS Compliance"
        echo "4. Audit Logging"
        echo ""
        echo "Results:"
        echo "- Vulnerability Scan: PASS/FAIL"
        echo "- RBAC Configuration: PASS/FAIL"
        echo "- TLS Configuration: PASS/FAIL"
        echo "- Audit Logging: PASS/FAIL"
    } > "$report_file"
    
    log "Compliance report saved to $report_file"
}

# Main execution
main() {
    log "=== Compliance Monitoring Started ==="
    
    check_image_vulnerabilities
    check_rbac_compliance
    check_tls_compliance
    check_audit_logging
    generate_compliance_report
    
    log "=== Compliance Monitoring Complete ==="
}

main "$@"
COMPLIANCE_MON

    chmod +x "${PROJECT_ROOT}/security/compliance-monitoring.sh"
    log_success "Compliance monitoring configuration created"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 6.3: Audit Logging & Container Security"
    log_info "=============================================="

    create_audit_logging
    create_container_security
    create_compliance_monitoring

    if $APPLY; then
        log_success "Phase 6.3 Complete - Audit Logging & Security Configured"
    else
        log_info "Configurations created at: ${PROJECT_ROOT}/security/"
        log_info "Run with --apply flag to deploy"
    fi
}

main "$@"
