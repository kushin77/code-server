#!/usr/bin/env bash
# @file        scripts/security/deploy-mtls-phase3-rotation.sh
# @module      security/mtls-deployment
# @description Deploy systemd timer and rotation automation for certificate management

set -euo pipefail

echo "=========================================="
echo "P0 #1123: Phase 3 - Systemd Rotation Deployment"
echo "=========================================="
echo ""

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROTATION_SCRIPT="${SCRIPT_DIR}/rotate-mtls-certificates.sh"
ROTATION_MANIFEST="config/mtls-certs/rotation-manifest.json"

deploy_systemd_timer() {
    echo "Creating systemd timer and service unit..."
    
    # Create systemd service for rotation
    cat > /tmp/mtls-cert-rotation.service << 'EOF'
[Unit]
Description=mTLS Certificate Rotation Service
After=network.target
Requires=mtls-cert-rotation.timer

[Service]
Type=oneshot
ExecStart=/scripts/security/rotate-mtls-certificates.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mtls-rotation

[Install]
WantedBy=multi-user.target
EOF
    
    # Create systemd timer (daily at 02:00 UTC)
    cat > /tmp/mtls-cert-rotation.timer << 'EOF'
[Unit]
Description=mTLS Certificate Daily Rotation Timer
Requires=mtls-cert-rotation.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=300
Unit=mtls-cert-rotation.service

[Install]
WantedBy=timers.target
EOF
    
    echo "✓ Systemd units created"
    echo "  Service: /tmp/mtls-cert-rotation.service"
    echo "  Timer: /tmp/mtls-cert-rotation.timer"
}

verify_rotation_script() {
    echo "Verifying rotation script syntax..."
    
    if [ ! -f "$ROTATION_SCRIPT" ]; then
        echo "✗ Rotation script not found: $ROTATION_SCRIPT"
        return 1
    fi
    
    # Syntax check
    if bash -n "$ROTATION_SCRIPT" 2>&1; then
        echo "✓ Rotation script syntax valid"
        return 0
    else
        echo "✗ Rotation script has syntax errors"
        return 1
    fi
}

create_rotation_manifest() {
    echo "Creating rotation manifest..."
    
    cat > "$ROTATION_MANIFEST" << 'EOF'
{
  "rotation_config": {
    "enabled": true,
    "schedule": "02:00 UTC daily",
    "certificate_validity_days": 30,
    "rotation_threshold_days": 2,
    "timezone": "UTC"
  },
  "services": [
    "redis",
    "postgres",
    "pgbouncer",
    "code-server",
    "caddy",
    "prometheus",
    "alertmanager",
    "loki",
    "promtail",
    "error-triage-engine",
    "redis-sentinel-1",
    "redis-sentinel-arbiter",
    "redis-sentinel-2"
  ],
  "ca_configuration": {
    "root_ca_path": "config/mtls-certs/ca-root/ca-cert.pem",
    "intermediate_ca_path": "config/mtls-certs/ca-intermediate/ca-intermediate-cert.pem",
    "intermediate_key_path": "config/mtls-certs/ca-intermediate/ca-intermediate-key.pem",
    "service_cert_base_path": "config/mtls-certs",
    "backup_retention_days": 7,
    "backup_location": "/var/backups/mtls-certificates"
  },
  "rotation_log": {
    "location": "/var/log/mtls-rotation/rotation.log",
    "retention_days": 90,
    "level": "info"
  },
  "health_checks": {
    "verify_certificate_chain": true,
    "verify_service_connectivity": true,
    "verify_docker_secrets": true
  },
  "created_at": "2026-04-22T00:00:00Z",
  "phase": "phase3_automation"
}
EOF
    
    echo "✓ Rotation manifest created: $ROTATION_MANIFEST"
}

verify_phase3_readiness() {
    echo "Performing Phase 3 readiness verification..."
    echo ""
    
    local checks_passed=0
    local checks_failed=0
    
    # Check 1: Root CA exists
    if [ -f "config/mtls-certs/ca-root/ca-cert.pem" ]; then
        echo "✓ Root CA certificate present"
        ((checks_passed++))
    else
        echo "✗ Root CA certificate missing"
        ((checks_failed++))
    fi
    
    # Check 2: Intermediate CA exists
    if [ -f "config/mtls-certs/ca-intermediate/ca-intermediate-cert.pem" ]; then
        echo "✓ Intermediate CA certificate present"
        ((checks_passed++))
    else
        echo "✗ Intermediate CA certificate missing"
        ((checks_failed++))
    fi
    
    # Check 3: All 13 services have certificates
    local service_count=$(find config/mtls-certs -mindepth 1 -maxdepth 1 -type d | grep -v "ca-" | wc -l)
    if [ "$service_count" -eq 13 ]; then
        echo "✓ All 13 service certificates present"
        ((checks_passed++))
    else
        echo "✗ Expected 13 services, found $service_count"
        ((checks_failed++))
    fi
    
    # Check 4: Rotation script is syntactically valid
    if bash -n "$ROTATION_SCRIPT" 2>&1; then
        echo "✓ Rotation script syntax valid"
        ((checks_passed++))
    else
        echo "✗ Rotation script has syntax errors"
        ((checks_failed++))
    fi
    
    # Check 5: Systemd units created
    if [ -f "/tmp/mtls-cert-rotation.service" ] && [ -f "/tmp/mtls-cert-rotation.timer" ]; then
        echo "✓ Systemd units created"
        ((checks_passed++))
    else
        echo "✗ Systemd units not created"
        ((checks_failed++))
    fi
    
    echo ""
    echo "Phase 3 Readiness: $checks_passed/$((checks_passed + checks_failed)) checks passed"
    
    if [ "$checks_failed" -eq 0 ]; then
        echo "✓ Phase 3 READY FOR ACTIVATION"
        return 0
    else
        echo "✗ Phase 3 has $checks_failed blocking issues"
        return 1
    fi
}

main() {
    echo ""
    deploy_systemd_timer
    echo ""
    
    verify_rotation_script
    echo ""
    
    create_rotation_manifest
    echo ""
    
    verify_phase3_readiness
    echo ""
    
    echo "=========================================="
    echo "Phase 3 Deployment Summary"
    echo "=========================================="
    echo ""
    echo "Artifacts Generated:"
    echo "  - Systemd Service: /tmp/mtls-cert-rotation.service"
    echo "  - Systemd Timer: /tmp/mtls-cert-rotation.timer"
    echo "  - Rotation Manifest: $ROTATION_MANIFEST"
    echo ""
    echo "Next Steps:"
    echo "  1. Review systemd units in /tmp/"
    echo "  2. Copy to /etc/systemd/system/ on production hosts"
    echo "  3. Run: systemctl daemon-reload"
    echo "  4. Run: systemctl enable --now mtls-cert-rotation.timer"
    echo "  5. Monitor: journalctl -u mtls-cert-rotation -f"
    echo ""
}

main
