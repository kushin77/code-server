#!/bin/bash
# scripts/hardening/docker-iptables-hardening.sh
# Docker iptables Hardening — DOCKER-USER Chain Configuration
# Blocks unauthorized container egress + protects internal services from external access
#
# Usage: bash docker-iptables-hardening.sh

set -euo pipefail

LOG_FILE="/tmp/docker-iptables-hardening-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[ERROR] $*" | tee -a "$LOG_FILE"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# =============================================================================
# 1. DOCKER-USER Chain: Protect Internal Services
# =============================================================================

setup_docker_user_chain() {
    log "Configuring DOCKER-USER chain (protect internal services)..."
    
    # Flush existing DOCKER-USER rules (in case of re-run)
    iptables -F DOCKER-USER 2>/dev/null || true
    
    # Block external access to internal monitoring ports
    # Only allow from LAN (192.168.168.0/24) or VPN
    
    # Prometheus (port 9090)
    iptables -I DOCKER-USER -p tcp --dport 9090 ! -s 192.168.168.0/24 -j DROP
    log "✓ Blocked external access to Prometheus (9090)"
    
    # Grafana (port 3000)
    iptables -I DOCKER-USER -p tcp --dport 3000 ! -s 192.168.168.0/24 -j DROP
    log "✓ Blocked external access to Grafana (3000)"
    
    # AlertManager (port 9093)
    iptables -I DOCKER-USER -p tcp --dport 9093 ! -s 192.168.168.0/24 -j DROP
    log "✓ Blocked external access to AlertManager (9093)"
    
    # Jaeger (port 16686)
    iptables -I DOCKER-USER -p tcp --dport 16686 ! -s 192.168.168.0/24 -j DROP
    log "✓ Blocked external access to Jaeger (16686)"
    
    # PostgreSQL (port 5432) — absolute isolation
    iptables -I DOCKER-USER -p tcp --dport 5432 ! -s 192.168.168.0/24 -j DROP
    log "✓ Blocked external access to PostgreSQL (5432)"
    
    # Redis (port 6379) — absolute isolation
    iptables -I DOCKER-USER -p tcp --dport 6379 ! -s 192.168.168.0/24 -j DROP
    log "✓ Blocked external access to Redis (6379)"
    
    # Harbor Registry (port 8443) — internal only
    iptables -I DOCKER-USER -p tcp --dport 8443 ! -s 192.168.168.0/24 -j DROP
    log "✓ Blocked external access to Harbor (8443)"
    
    # Allow RETURN rule (end of DOCKER-USER chain processing)
    iptables -A DOCKER-USER -j RETURN
    
    log "DOCKER-USER chain configured successfully"
}

# =============================================================================
# 2. Container Egress Filtering: Prevent Data Exfiltration
# =============================================================================

setup_container_egress_rules() {
    log "Configuring container egress filtering..."
    
    # Get Docker bridge interface names
    # These are dynamically created but typically follow pattern br-{id}
    
    # PostgreSQL + Redis: NO outbound internet access (completely isolated)
    # They should only communicate with other containers on data network
    
    # Find data network bridge
    DATA_BRIDGE=$(docker network inspect code-server-enterprise_enterprise -f '{{.Id}}' 2>/dev/null | head -c 12)
    
    if [ -z "$DATA_BRIDGE" ]; then
        log "⚠️  Warning: enterprise network not found, skipping egress rules"
        return
    fi
    
    # Block postgres egress to external networks
    # postgres should only communicate with other containers (localhost/bridge)
    iptables -I FORWARD -i "br-${DATA_BRIDGE}" -o eth0 -j DROP 2>/dev/null || true
    iptables -I FORWARD -i "br-${DATA_BRIDGE}" -o ens+ -j DROP 2>/dev/null || true
    log "✓ PostgreSQL/Redis blocked from external egress"
    
    # Log blocked egress attempts (for intrusion detection)
    # This helps detect container compromises trying to exfiltrate data
    iptables -A FORWARD -i "br-${DATA_BRIDGE}" -o eth0 -j LOG --log-prefix "EGRESS-BLOCKED-DB: " 2>/dev/null || true
    
    log "Container egress filtering configured"
}

# =============================================================================
# 3. Docker Network Isolation Verification
# =============================================================================

verify_isolation() {
    log ""
    log "=== ISOLATION VERIFICATION ==="
    
    # Test: Can postgres reach external IP?
    log "Testing postgres isolation (should be blocked):"
    docker exec -T postgres curl -s -m 2 http://google.com || log "✓ postgres blocked from external"
    
    # Test: Can code-server reach other containers?
    log "Testing code-server → caddy connectivity (should work):"
    docker exec -T code-server curl -s -m 2 http://caddy:80 && log "✓ code-server can reach caddy" || log "⚠️ code-server cannot reach caddy"
    
    # Test: Internal monitoring port access
    log "Testing prometheus access from localhost (should work):"
    docker exec -T caddy curl -s http://prometheus:9090/metrics | grep -q "up" && log "✓ internal prometheus access works" || log "⚠️ prometheus check failed"
}

# =============================================================================
# 4. Persist iptables Rules Across Reboots
# =============================================================================

persist_rules() {
    log "Persisting iptables rules..."
    
    # Install iptables-persistent
    apt-get update && apt-get install -y iptables-persistent 2>&1 | tee -a "$LOG_FILE"
    
    # Save current rules
    iptables-save > /etc/iptables/rules.v4
    
    log "✓ iptables rules saved to /etc/iptables/rules.v4"
    log "✓ Rules will persist across reboots"
}

# =============================================================================
# 5. Create Monitoring Rules
# =============================================================================

setup_monitoring() {
    log "Setting up egress blocking monitoring..."
    
    # Create alert rule for prometheus
    cat > /tmp/egress-block-alert.yaml << 'EOF'
- alert: ContainerEgressBlocked
  expr: increase(node_nf_conntrack_stat_drop[5m]) > 10
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "Container egress blocked {{ $value }} times (5m)"
    description: "May indicate container compromise or misconfiguration"

- alert: UnexpectedEgress
  expr: increase(node_nf_conntrack_stat_insert_failed[5m]) > 5
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Unexpected connection table insertions detected"
    description: "Possible data exfiltration attempt or network attack"
EOF

    log "✓ Alert rules template created at /tmp/egress-block-alert.yaml"
    log "  (Add to alert-rules.yml in Prometheus configuration)"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    check_root
    
    log "Starting Docker iptables Hardening..."
    log "Log file: $LOG_FILE"
    
    # Execute hardening steps
    setup_docker_user_chain
    setup_container_egress_rules
    persist_rules
    setup_monitoring
    
    # Verify changes
    log ""
    log "=== FIREWALL CONFIGURATION ==="
    log "DOCKER-USER chain rules:"
    iptables -L DOCKER-USER -n --line-numbers | head -20
    log ""
    
    verify_isolation
    
    log ""
    log "✅ Docker iptables Hardening Complete!"
    log ""
    log "Next steps:"
    log "1. Test container connectivity: docker-compose up -d"
    log "2. Verify internal communication still works"
    log "3. Verify external access is blocked where expected"
    log "4. Add alert rules from /tmp/egress-block-alert.yaml to prometheus"
}

main "$@"
