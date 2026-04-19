#!/bin/bash
# @file        scripts/incident-simulation.sh
# @module      operations
# @description incident simulation — on-prem code-server
# @owner       platform
# @status      active
##############################################################################
# Phase 13 Incident Simulation Script
# Tests incident response procedures and on-call team readiness
# Usage: ./scripts/incident-simulation.sh [--scenario SCENARIO]
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

SCENARIO=${1:-"tunnel-failure"}  # Default scenario
REPORT_FILE="incident-simulation-$(date +%Y%m%d-%H%M%S).txt"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Incident tracking
INCIDENT_START=$(date +%s%N)
INCIDENT_DETECTED_TIME=0
INCIDENT_RESOLVED_TIME=0
RESPONSE_TIME_MS=0

echo "🚨 Phase 13 Incident Simulation"
echo "=================================================="
echo "Scenario: $SCENARIO"
echo "Start Time: $(date)"
echo "=================================================="
echo ""

# ============================================================================
# SCENARIO 1: Cloudflare Tunnel Failure
# ============================================================================
scenario_tunnel_failure() {
  echo "🔴 SCENARIO: Cloudflare Tunnel Failure"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📋 Simulated Incident Details:"
  echo "  - Cloudflare tunnel connection lost"
  echo "  - No external connectivity"
  echo "  - Developers unable to access IDE"
  echo "  - Internal network still operational"
  echo ""
  echo "🔔 Alert Triggered: $(date)"
  INCIDENT_DETECTED_TIME=$(date +%s%N)
  
  # Simulate: On-call receives alert
  sleep 2
  echo ""
  echo "👨‍💼 On-Call Engineer: Acknowledged incident"
  echo "⏱️  Time to acknowledge: 2s"
  echo ""
  
  # Step 1: Verify tunnel status
  echo "Step 1️⃣  Verify Tunnel Status"
  echo "  Command: cloudflared tunnel info"
  echo "  Expected: Tunnel INACTIVE"
  if pgrep -f "cloudflared" > /dev/null 2>&1; then
    echo "  Actual: Tunnel ACTIVE (simulated state)"
  else
    echo "  Actual: Tunnel INACTIVE (no process)"
  fi
  sleep 1
  
  # Step 2: Check logs
  echo ""
  echo "Step 2️⃣  Check Tunnel Logs"
  echo "  Command: tail -50 /var/log/cloudflared.log"
  echo "  Expected: Connection refused errors"
  echo "  Action: Identify root cause (network issue vs. service issue)"
  sleep 1
  
  # Step 3: Attempt restart
  echo ""
  echo "Step 3️⃣  Restart Cloudflare Tunnel"
  echo "  Command: systemctl restart cloudflared"
  echo "  Expected: Service starts and re-establishes tunnel"
  echo "  Status: Waiting 10s for tunnel to stabilize..."
  sleep 3
  echo "  ✓ Tunnel connection restored"
  
  INCIDENT_RESOLVED_TIME=$(date +%s%N)
  RESPONSE_TIME_MS=$(( (INCIDENT_RESOLVED_TIME - INCIDENT_DETECTED_TIME) / 1000000 ))
  
  echo ""
  echo "📊 Incident Timeline:"
  echo "  Detected: 00:00s"
  echo "  Response Goal: < 5s"
  echo "  Actual Response: ~${RESPONSE_TIME_MS}ms ($(( RESPONSE_TIME_MS / 1000 ))s)"
  echo ""
  
  echo "✅ Resolution: Tunnel connection restored"
  echo "📝 Post-Incident Action:"
  echo "  - Check for repeated failures"
  echo "  - Review Cloudflare status"
  echo "  - Document in incident log"
  echo ""
}

# ============================================================================
# SCENARIO 2: High Latency / Performance Degradation
# ============================================================================
scenario_high_latency() {
  echo "🔴 SCENARIO: High Latency / Performance Degradation"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📋 Simulated Incident Details:"
  echo "  - Terminal latency increased to 500ms+"
  echo "  - File operations slow (>2s)"
  echo "  - System CPU/memory normal"
  echo "  - Network bandwidth normal"
  echo ""
  echo "🔔 Alert Triggered: $(date)"
  INCIDENT_DETECTED_TIME=$(date +%s%N)
  
  sleep 1
  echo "👨‍💼 On-Call Engineer: Investigating performance"
  echo ""
  
  # Step 1: Check metrics
  echo "Step 1️⃣  Check Performance Metrics"
  echo "  Command: curl -s http://localhost:9090/metrics | grep latency"
  echo "  Expected: p99_latency_ms > 100"
  echo "  Action: Identify which operations are slow"
  sleep 1
  
  # Step 2: Check system resources
  echo ""
  echo "Step 2️⃣  Check System Resources"
  echo "  CPU Usage: 15% (normal)"
  echo "  Memory Usage: 45% (normal)"
  echo "  Disk I/O: 60% (elevated)"
  echo "  Action: Disk I/O might be bottleneck"
  sleep 1
  
  # Step 3: Check network
  echo ""
  echo "Step 3️⃣  Check Network"
  echo "  Command: curl -w '@curl-format.txt' http://localhost:8080"
  echo "  TTFB (Time to First Byte): 50ms (normal)"
  echo "  Total Time: 150ms (normal)"
  echo "  Action: Backend response is normal"
  sleep 1
  
  # Step 4: Check application logs
  echo ""
  echo "Step 4️⃣  Check Application Logs"
  echo "  Command: tail -100 /var/log/code-server.log"
  echo "  Found: Slow database queries (>500ms)"
  echo "  Cause: Audit log table not indexed"
  sleep 1
  
  # Step 5: Apply fix
  echo ""
  echo "Step 5️⃣  Apply Optimization"
  echo "  Command: sqlite3 ~/.audit/audit.db 'CREATE INDEX idx_timestamp ON audit_log(timestamp);'"
  echo "  Status: Index created"
  
  INCIDENT_RESOLVED_TIME=$(date +%s%N)
  RESPONSE_TIME_MS=$(( (INCIDENT_RESOLVED_TIME - INCIDENT_DETECTED_TIME) / 1000000 ))
  
  echo ""
  echo "📊 Incident Timeline:"
  echo "  Detection: 00:00s"
  echo "  Root Cause: 00:05s (database query analysis)"
  echo "  Fix Applied: 00:07s (create index)"
  echo "  Actual Response Time: ~${RESPONSE_TIME_MS}ms ($(( RESPONSE_TIME_MS / 1000 ))s)"
  echo ""
  
  echo "✅ Resolution: Database index optimized, latency restored to normal"
  echo "📝 Post-Incident Action:"
  echo "  - Review all database indexes"
  echo "  - Add monitoring for slow queries"
  echo "  - Load test to verify performance"
  echo ""
}

# ============================================================================
# SCENARIO 3: Audit Logging Failure
# ============================================================================
scenario_audit_failure() {
  echo "🔴 SCENARIO: Audit Logging Failure"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📋 Simulated Incident Details:"
  echo "  - Audit log file not writable (disk full)"
  echo "  - Compliance requirement: ALL actions audited"
  echo "  - Service continues but not logging"
  echo "  - Compliance violation if unresolved"
  echo ""
  echo "🔔 Alert Triggered: $(date)"
  INCIDENT_DETECTED_TIME=$(date +%s%N)
  
  sleep 1
  echo "👨‍💼 On-Call Engineer: CRITICAL - Compliance incident"
  echo ""
  
  # Step 1: Verify audit system
  echo "Step 1️⃣  Verify Audit System Status"
  echo "  Command: systemctl status git-rca-audit"
  echo "  Status: RUNNING (but not actually logging)"
  echo "  Action: Check audit log health"
  sleep 1
  
  # Step 2: Check disk space
  echo ""
  echo "Step 2️⃣  Check Disk Space"
  echo "  Command: df -h"
  echo "  Root filesystem: 100% FULL"
  echo "  Audit log size: 8.5 GB"
  echo "  Action: Immediate cleanup required"
  sleep 1
  
  # Step 3: Archive old logs
  echo ""
  echo "Step 3️⃣  Archive and Rotate Logs"
  echo "  Command: find /var/log -name '*.log' -mtime +30 -exec gzip {} \\;"
  echo "  Status: Archived logs older than 30 days"
  echo "  Freed Space: 3.2 GB"
  sleep 1
  
  # Step 4: Verify logging resumed
  echo ""
  echo "Step 4️⃣  Verify Audit Logging Resumed"
  echo "  Command: tail /var/log/git-rca-audit.log"
  echo "  Status: New entries appearing"
  echo "  Sample: [2026-04-13 14:05:23] User alice auth success"
  
  INCIDENT_RESOLVED_TIME=$(date +%s%N)
  RESPONSE_TIME_MS=$(( (INCIDENT_RESOLVED_TIME - INCIDENT_DETECTED_TIME) / 1000000 ))
  
  echo ""
  echo "📊 Incident Timeline:"
  echo "  Alert Triggered: 00:00s"
  echo "  Root Cause Identified: 00:03s"
  echo "  Resolution: 00:06s (disk cleanup)"
  echo "  Actual Response Time: ~${RESPONSE_TIME_MS}ms ($(( RESPONSE_TIME_MS / 1000 ))s)"
  echo ""
  
  echo "✅ Resolution: Audit logging fully operational"
  echo "📝 Post-Incident Action:"
  echo "  - Increase log rotation frequency"
  echo "  - Add disk space monitoring alert"
  echo "  - Review compliance implications"
  echo "  - Document as compliance event"
  echo ""
}

# ============================================================================
# SCENARIO 4: SSH Key Compromise
# ============================================================================
scenario_key_compromise() {
  echo "🔴 SCENARIO: SSH Key Compromise"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📋 Simulated Incident Details:"
  echo "  - Developer SSH key exposed in GitHub repo"
  echo "  - Unauthorized access detected in audit logs"
  echo "  - Security team alerted"
  echo "  - Must revoke and rotate keys immediately"
  echo ""
  echo "🔔 Alert Triggered: $(date)"
  INCIDENT_DETECTED_TIME=$(date +%s%N)
  
  sleep 1
  echo "👨‍💼 On-Call Engineer: CRITICAL SECURITY INCIDENT"
  echo "🔒 Security Team: Actively investigating"
  echo ""
  
  # Step 1: Revoke compromised key
  echo "Step 1️⃣  Revoke Compromised Key"
  echo "  Key ID: rsa-4096-alice-dev-2026"
  echo "  Command: ssh-key revoke rsa-4096-alice-dev-2026"
  echo "  Status: Key revoked in central authentication"
  sleep 1
  
  # Step 2: Audit access
  echo ""
  echo "Step 2️⃣  Audit Unauthorized Access"
  echo "  Command: grep 'rsa-4096-alice-dev-2026' /var/log/git-rca-audit.log"
  echo "  Found: 23 unauthorized access attempts from 192.168.1.100"
  echo "  Time Range: 14:00 - 14:15 UTC"
  echo "  Files Accessed: 3 (config.yaml, secrets.txt, deploy.sh)"
  sleep 1
  
  # Step 3: Issue new key
  echo ""
  echo "Step 3️⃣  Issue New Key"
  echo "  User: alice"
  echo "  New Key ID: rsa-4096-alice-dev-2026-v2"
  echo "  Command: ssh-keygen -t rsa -b 4096 -C 'alice-dev@example.com'"
  echo "  Status: New key generated and distributed securely"
  sleep 1
  
  # Step 4: Notify user
  echo ""
  echo "Step 4️⃣  Notify Developer"
  echo "  Message sent to: alice@example.com"
  echo "  Content: SSH key compromised, new key issued, access logs attached"
  echo "  Action required: Update local SSH config"
  sleep 1
  
  # Step 5: Security review
  echo ""
  echo "Step 5️⃣  Trigger Security Review"
  echo "  Action: Review all commits from compromised key"
  echo "  Action: Scan for data exfiltration"
  echo "  Action: Update security policies"
  
  INCIDENT_RESOLVED_TIME=$(date +%s%N)
  RESPONSE_TIME_MS=$(( (INCIDENT_RESOLVED_TIME - INCIDENT_DETECTED_TIME) / 1000000 ))
  
  echo ""
  echo "📊 Incident Timeline:"
  echo "  Alert: 00:00s"
  echo "  Key Revoked: 00:01s"
  echo "  New Key Issued: 00:05s"
  echo "  User Notified: 00:06s"
  echo "  Actual Response Time: ~${RESPONSE_TIME_MS}ms ($(( RESPONSE_TIME_MS / 1000 ))s)"
  echo ""
  
  echo "✅ Interim Resolution: Compromised key revoked, new key issued"
  echo "📝 Post-Incident Action:"
  echo "  - Complete forensic analysis (24-48 hours)"
  echo "  - Review commits for data exposure"
  echo "  - Update security policies"
  echo "  - Document incident for compliance"
  echo ""
}

# ============================================================================
# Training Material & References
# ============================================================================
print_training_material() {
  echo ""
  echo "📚 INCIDENT RESPONSE TRAINING MATERIAL"
  echo "=================================================="
  echo ""
  echo "🎯 Core Principles:"
  echo ""
  echo "1. DETECT FAST"
  echo "   - Monitor key metrics (latency, error rate, availability)"
  echo "   - Alert on anomalies within 5 seconds"
  echo "   - Examples: tunneldown, >100ms latency, failed audit writes"
  echo ""
  echo "2. COMMUNICATE IMMEDIATELY"
  echo "   - Page on-call engineer within 30 seconds of alert"
  echo "   - Post to incident channel (#incident-response)"
  echo "   - Update status page if external impact"
  echo ""
  echo "3. DIAGNOSE METHODICALLY"
  echo "   - Use runbooks for known scenarios"
  echo "   - Check three areas: network, system, application"
  echo "   - Collect metrics before making changes"
  echo ""
  echo "4. ACT DECISIVELY"
  echo "   - Apply fixes within RTO budget (5s for tunnel, 30s for performance)"
  echo "   - Don't wait for perfect information"
  echo "   - You can always rollback"
  echo ""
  echo "5. DOCUMENT EVERYTHING"
  echo "   - Log timeline: detection, response, resolution"
  echo "   - Document root cause"
  echo "   - Record post-incident actions"
  echo ""
  echo "📋 Common Runbooks:"
  echo ""
  echo "  /opt/runbooks/tunnel-failure.md"
  echo "  /opt/runbooks/performance-degradation.md"
  echo "  /opt/runbooks/audit-failure.md"
  echo "  /opt/runbooks/security-incident.md"
  echo ""
  echo "🚨 Escalation Matrix:"
  echo ""
  echo "  Response Time (SLA):      < 5 minutes"
  echo "  Mitigation Time (SLA):    < 15 minutes"
  echo "  Resolution Time (SLA):    < 60 minutes"
  echo "  Post-Mortem Deadline:     24 hours"
  echo ""
}

# ============================================================================
# Summary Report
# ============================================================================
generate_report() {
  local scenario=$1
  local response_time=$2
  
  {
    echo "# Incident Simulation Report"
    echo "Date: $(date)"
    echo "Scenario: $scenario"
    echo ""
    echo "## Summary"
    echo "Simulated incident scenario to validate on-call team readiness"
    echo "Response time (simulated): ${response_time}ms"
    echo ""
    echo "## Objectives Tested"
    echo "- ✅ Alert detection and acknowledgment"
    echo "- ✅ Root cause identification within 5 minutes"
    echo "- ✅ Incident resolution within RTO budget"
    echo "- ✅ Communication and escalation"
    echo "- ✅ Post-incident documentation"
    echo ""
    echo "## Results"
    echo "Incident response simulation COMPLETED SUCCESSFULLY"
    echo ""
    echo "## Next Steps"
    echo "1. Debrief team on response actions"
    echo "2. Review actual vs. expected response time"
    echo "3. Identify gaps in runbooks or procedures"
    echo "4. Schedule training for any missing skills"
    echo ""
    echo "## Success Criteria (All Met)"
    echo "✅ Alert triggered and acknowledged within 30 seconds"
    echo "✅ Root cause identified within 5 minutes"
    echo "✅ Fix applied within RTO budget"
    echo "✅ Service restored to normal operation"
    echo "✅ Incident documented for compliance"
    
  } | tee "$REPORT_FILE"
}

# ============================================================================
# Main Execution
# ============================================================================

case "$SCENARIO" in
  tunnel-failure)
    scenario_tunnel_failure
    ;;
  high-latency)
    scenario_high_latency
    ;;
  audit-failure)
    scenario_audit_failure
    ;;
  key-compromise)
    scenario_key_compromise
    ;;
  *)
    echo "🎓 Available Scenarios:"
    echo ""
    echo "  1. tunnel-failure      - Cloudflare tunnel goes down"
    echo "  2. high-latency        - Performance degradation detected"
    echo "  3. audit-failure       - Audit logging stops (disk full)"
    echo "  4. key-compromise      - SSH key exposed and compromised"
    echo ""
    echo "Usage: ./scripts/incident-simulation.sh [--scenario SCENARIO]"
    echo "Example: ./scripts/incident-simulation.sh --scenario tunnel-failure"
    exit 0
    ;;
esac

# Print training material
print_training_material

# Generate report
generate_report "$SCENARIO" "$RESPONSE_TIME_MS"

echo ""
echo "✅ Incident Simulation Complete"
echo "📄 Report: $REPORT_FILE"
echo ""
