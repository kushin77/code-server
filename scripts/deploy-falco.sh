#!/bin/bash
# scripts/deploy-falco.sh
# Deploy Falco runtime security monitoring with eBPF syscall detection
# Detects: shell spawning, privilege escalation, crypto mining, unauthorized file access

set -euo pipefail

LOG_FILE="/tmp/falco-deploy-$(date +%Y%m%d-%H%M%S).log"

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
# 1. INSTALL FALCO + DEPENDENCIES
# =============================================================================

install_falco() {
    log "Installing Falco v0.37.1 (modern eBPF driver)..."
    
    # Add Falco repository
    curl -s https://falco.org/repo/falcoproj-3672BA8F.asc | apt-key add -
    echo "deb https://download.falco.org/packages/deb stable main" | \
        tee /etc/apt/sources.list.d/falcoproj.list
    
    apt-get update
    apt-get install -y falco=0.37.1-1 2>&1 | tee -a "$LOG_FILE"
    
    # Enable and start Falco
    systemctl enable falco
    systemctl start falco
    
    log "✓ Falco v0.37.1 installed and started"
}

# =============================================================================
# 2. CONFIGURE FALCO RULES
# =============================================================================

setup_falco_rules() {
    log "Configuring Falco custom security rules..."
    
    mkdir -p /etc/falco/rules.d
    
    # Create custom rules file for container security
    cat > /etc/falco/rules.d/container-security.yaml << 'EOF'
# Container Security Rules for Falco

- list: allowed_processes
  items: [bash, sh, python, node, java, postgres, redis, caddy]

- rule: Unauthorized Shell Access
  desc: Detect unexpected shell spawning in containers
  condition: >
    spawned_process and container and
    proc.name in (bash, sh, bash -i) and
    not proc.parent.name in (allowed_processes)
  output: >
    Unauthorized shell spawned (user=%user.name proc=%proc.name parent=%proc.parent.name
    container=%container.name image=%container.image.repository)
  priority: WARNING
  tags: [process_monitoring, security, container]

- rule: Privilege Escalation Attempt
  desc: Detect privilege escalation attempts (sudo, su, capset)
  condition: >
    (syscall.name = capset or (spawned_process and proc.name in (sudo, su, sudo -i))) and
    container and
    proc.uid > 0
  output: >
    Privilege escalation attempt (user=%user.name proc=%proc.name uid=%proc.uid
    container=%container.name)
  priority: CRITICAL
  tags: [privilege_escalation, security]

- rule: Cryptominer Detection
  desc: Detect cryptocurrency mining malware
  condition: >
    spawned_process and container and
    (proc.name in (xmrig, cpuminer, mkxminer, minerd, cgminer) or
     proc.args contains "pool.monero" or
     proc.args contains "stratum" or
     proc.args contains "mining")
  output: >
    Cryptominer detected (proc=%proc.name container=%container.name user=%user.name
    cmdline=%proc.cmdline)
  priority: CRITICAL
  tags: [malware, security, crypto]

- rule: Unauthorized File Access
  desc: Detect suspicious file access patterns
  condition: >
    file.name in (/etc/shadow, /etc/passwd, /root/.ssh, /etc/docker/daemon.json) and
    container and
    proc.uid != 0 and
    not proc.name in (allowed_processes)
  output: >
    Unauthorized file access (user=%user.name file=%file.name proc=%proc.name
    container=%container.name)
  priority: HIGH
  tags: [file_monitoring, security]

- rule: Outbound C2 Connection
  desc: Detect command and control (C2) connections
  condition: >
    outbound and container and
    not fd.sip in (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12) and
    not fd.sport in (53, 80, 443) and
    not proc.name in (caddy, curl, wget, docker)
  output: >
    Suspicious outbound connection (user=%user.name proc=%proc.name
    src=%fd.sip:%fd.sport dst=%fd.dip:%fd.dport container=%container.name)
  priority: HIGH
  tags: [network, security, c2]

- rule: Docker Socket Access
  desc: Detect unauthorized Docker socket access
  condition: >
    file.name = /var/run/docker.sock and
    container and
    proc.uid > 0
  output: >
    Docker socket accessed from container (user=%user.name proc=%proc.name
    container=%container.name)
  priority: CRITICAL
  tags: [docker, security]

- rule: Suspicious Process Properties
  desc: Detect processes with suspicious properties
  condition: >
    spawned_process and container and
    (proc.name = "" or
     proc.parent.name = "" or
     proc.exe = "" or
     proc.pname matches "(zombie|<defunct>)")
  output: >
    Suspicious process detected (name=%proc.name parent=%proc.parent.name
    exe=%proc.exe container=%container.name)
  priority: HIGH
  tags: [process_monitoring, security]

- rule: Kernel Module Manipulation
  desc: Detect kernel module loading/unloading
  condition: >
    syscall.name in (init_module, delete_module, finit_module) and
    container
  output: >
    Kernel module manipulation attempt (user=%user.name syscall=%syscall.name
    container=%container.name)
  priority: CRITICAL
  tags: [kernel, security]
EOF

    log "✓ Custom security rules configured at /etc/falco/rules.d/container-security.yaml"
}

# =============================================================================
# 3. CONFIGURE FALCO OUTPUT
# =============================================================================

setup_falco_output() {
    log "Configuring Falco output (JSON, syslog, HTTP webhook)..."
    
    # Backup original config
    cp /etc/falco/falco.yaml /etc/falco/falco.yaml.bak
    
    # Update Falco config for JSON output
    sed -i 's/json_output: false/json_output: true/' /etc/falco/falco.yaml
    sed -i 's/json_include_output_property: false/json_include_output_property: true/' /etc/falco/falco.yaml
    
    # Add custom output configuration
    cat >> /etc/falco/falco.yaml << 'EOF'

# Custom outputs
file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/alerts.json

syslog_output:
  enabled: true
  facility: LOG_LOCAL0

# Alert severity levels
log_level: warning

# Container runtime
container_orchestration:
  use_docker: true

# Modern eBPF driver (more efficient than kernel module)
modern_ebpf:
  enabled: true
EOF

    log "✓ Falco output configured (JSON, syslog)"
}

# =============================================================================
# 4. CREATE ALERT ROUTING
# =============================================================================

setup_alert_routing() {
    log "Creating alert routing configuration..."
    
    mkdir -p /etc/falco/alerts
    
    # AlertManager integration
    cat > /etc/falco/alerts/alertmanager-routing.yaml << 'EOF'
# Falco Alert Routing to AlertManager

routes:
  - match:
      severity: CRITICAL
    receiver: 'critical-alert'
    group_wait: 10s
    group_interval: 60s
    repeat_interval: 4h

  - match:
      severity: HIGH
    receiver: 'high-alert'
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 12h

  - match:
      severity: MEDIUM
    receiver: 'medium-alert'
    group_wait: 1m
    group_interval: 10m
    repeat_interval: 24h

receivers:
  - name: 'critical-alert'
    webhook_configs:
      - url: 'http://alertmanager:9093/api/v1/alerts'
        send_resolved: true
    pagerduty_configs:
      - service_key: '{{ env "PAGERDUTY_KEY" }}'

  - name: 'high-alert'
    webhook_configs:
      - url: 'http://alertmanager:9093/api/v1/alerts'

  - name: 'medium-alert'
    webhook_configs:
      - url: 'http://alertmanager:9093/api/v1/alerts'

inhibit_rules:
  - source_match:
      severity: 'CRITICAL'
    target_match:
      severity: 'HIGH'
    equal: ['container', 'process']
EOF

    log "✓ Alert routing configured at /etc/falco/alerts/alertmanager-routing.yaml"
}

# =============================================================================
# 5. SETUP PROMETHEUS METRICS
# =============================================================================

setup_prometheus_metrics() {
    log "Setting up Prometheus metrics for Falco..."
    
    # Create metrics exporter script
    cat > /usr/local/bin/falco-metrics-exporter.sh << 'EOF'
#!/bin/bash
# Export Falco alerts as Prometheus metrics

FALCO_LOG="/var/log/falco/alerts.json"
METRICS_PORT=8765

# Start simple HTTP server on port 8765
while true; do
    {
        echo "HTTP/1.1 200 OK"
        echo "Content-Type: text/plain"
        echo ""
        
        # Count alerts by severity
        echo "# HELP falco_alerts_total Total number of Falco alerts"
        echo "# TYPE falco_alerts_total counter"
        grep -c "CRITICAL" "$FALCO_LOG" 2>/dev/null | xargs echo "falco_alerts_total{severity=\"CRITICAL\"} " || echo "falco_alerts_total{severity=\"CRITICAL\"} 0"
        grep -c "HIGH" "$FALCO_LOG" 2>/dev/null | xargs echo "falco_alerts_total{severity=\"HIGH\"} " || echo "falco_alerts_total{severity=\"HIGH\"} 0"
        grep -c "MEDIUM" "$FALCO_LOG" 2>/dev/null | xargs echo "falco_alerts_total{severity=\"MEDIUM\"} " || echo "falco_alerts_total{severity=\"MEDIUM\"} 0"
        
        # Uptime
        echo "# HELP falco_up Falco service status"
        echo "# TYPE falco_up gauge"
        systemctl is-active falco &>/dev/null && echo "falco_up 1" || echo "falco_up 0"
    } | nc -l -p $METRICS_PORT
done
EOF

    chmod +x /usr/local/bin/falco-metrics-exporter.sh
    
    # Create systemd service
    cat > /etc/systemd/system/falco-metrics-exporter.service << 'EOF'
[Unit]
Description=Falco Prometheus Metrics Exporter
After=falco.service
Wants=falco.service

[Service]
Type=simple
ExecStart=/usr/local/bin/falco-metrics-exporter.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable falco-metrics-exporter.service
    systemctl start falco-metrics-exporter.service
    
    log "✓ Prometheus metrics exporter configured on port 8765"
}

# =============================================================================
# 6. VERIFY FALCO DEPLOYMENT
# =============================================================================

verify_deployment() {
    log ""
    log "=== FALCO DEPLOYMENT VERIFICATION ==="
    
    # Check service status
    log "Falco Service Status:"
    systemctl status falco --no-pager | head -5
    
    # Check rules loaded
    log "Rules Loaded:"
    falco --dump-rule-names 2>/dev/null | wc -l | xargs echo "  Total rules:"
    
    # Check alerts being generated
    log "Recent Alerts:"
    tail -5 /var/log/falco/alerts.json 2>/dev/null | head -3 || echo "  (no alerts yet)"
    
    # Check metrics
    log "Metrics Status:"
    curl -s http://localhost:8765/metrics 2>/dev/null | head -5 || echo "  (metrics not ready yet)"
    
    log ""
    log "✅ Falco Deployment Complete!"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    check_root
    
    log "Starting Falco Runtime Security Deployment..."
    log "Log file: $LOG_FILE"
    
    install_falco
    setup_falco_rules
    setup_falco_output
    setup_alert_routing
    setup_prometheus_metrics
    verify_deployment
    
    log ""
    log "Next Steps:"
    log "1. Verify Falco is running: systemctl status falco"
    log "2. Check alerts: tail -f /var/log/falco/alerts.json"
    log "3. Access metrics: curl http://localhost:8765/metrics"
    log "4. Configure Prometheus scrape job for port 8765"
    log "5. Setup AlertManager routing in prometheus/alertmanager.yml"
    log "6. Deploy to production hosts (192.168.168.31, 192.168.168.42)"
}

main "$@"
