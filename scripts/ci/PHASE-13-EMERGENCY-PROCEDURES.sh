#!/bin/bash
# PHASE 13 DAY 2 - EMERGENCY PROCEDURES & ESCALATION GUIDE
# Use during 24-hour load test if issues arise
# Contact: DevOps Lead (Primary), VP Engineering (Escalation)

# ============================================================================
# QUICK STATUS COMMANDS (Run anytime during 24-hour window)
# ============================================================================

echo "=== PHASE 13 EMERGENCY REFERENCE GUIDE ==="
echo ""
echo "Quick Status Commands:"
echo "  # Check container health"
echo "  docker ps --format 'table {{.Names}}\t{{.Status}}'"
echo ""
echo "  # Monitor SLOs in real-time"
echo "  tail -f /tmp/phase-13-monitoring.log"
echo ""
echo "  # Check system resources"
echo "  free -h && df -h /"
echo ""

# ============================================================================
# SCENARIO 1: CONTAINER FAILURE
# ============================================================================

handle_container_failure() {
  local container=$1
  echo "🔴 SCENARIO 1: CONTAINER FAILURE ($container)"
  echo ""
  echo "Step 1: Stop the failing container"
  echo "  docker stop $container"
  echo ""
  echo "Step 2: Check container logs for errors"
  echo "  docker logs $container --tail 100"
  echo ""
  echo "Step 3: Restart the container"
  echo "  docker restart $container"
  echo ""
  echo "Step 4: Verify restart was successful"
  echo "  docker ps --filter name=$container"
  echo ""
  echo "Step 5: If restart fails, escalate to Platform Manager"
  echo "  → Contact VP Engineering if unable to recover in 5 min"
  echo "  → Document error in Phase 13 incident log"
  echo ""
  echo "Escalation Path: DevOps → Platform Manager → VP Engineering"
}

# ============================================================================
# SCENARIO 2: SLO BREACH (p99 > 100ms or Error Rate > 0.1%)
# ============================================================================

handle_slo_breach() {
  echo "🔴 SCENARIO 2: SLO BREACH DETECTED"
  echo ""
  echo "Step 1: Immediate response (first 5 minutes)"
  echo "  • Notify Platform Manager"
  echo "  • Enable verbose logging: export DEBUG=1"
  echo "  • Capture current metrics snapshot"
  echo ""
  echo "Step 2: Investigation (5-15 minutes)"
  echo "  • Check which service is contributing to breach"
  echo "  • Review container resource usage"
  echo "  • Identify recent changes or anomalies"
  echo ""
  echo "Step 3: Remediation (15-30 minutes max)"
  echo ""
  echo "  If LATENCY breach:"
  echo "    → Check code-server container CPU/memory"
  echo "    → Verify network connectivity to backend"
  echo "    → Analyze slow queries in logs"
  echo ""
  echo "  If ERROR RATE breach:"
  echo "    → Check error logs for exception patterns"
  echo "    → Verify database connectivity"
  echo "    → Check auth service (oauth2-proxy) health"
  echo ""
  echo "  If THROUGHPUT breach:"
  echo "    → Check caddy proxy rate limiting"
  echo "    → Verify redis connection pool"
  echo "    → Monitor network bandwidth"
  echo ""
  echo "Step 4: Decision at 30 minutes"
  echo "  • If resolved: Continue monitoring, document incident"
  echo "  • If unresolved: FAIL → Escalate to VP Engineering"
  echo "                    → Begin root cause analysis"
  echo "                    → Plan 2-5 day retry"
}

# ============================================================================
# SCENARIO 3: DISK SPACE CRITICAL (<10GB)
# ============================================================================

handle_disk_space_issue() {
  echo "🔴 SCENARIO 3: LOW DISK SPACE"
  echo ""
  echo "Step 1: Check disk usage breakdown"
  echo "  du -sh /tmp /var/log /home --max-depth=1"
  echo ""
  echo "Step 2: Clean up non-critical files"
  echo "  # Remove old log files"
  echo "  find /var/log -name '*.log*' -mtime +7 -delete"
  echo ""
  echo "  # Clean Docker cache"
  echo "  docker system prune -a --volumes -f"
  echo ""
  echo "Step 3: Verify space recovered"
  echo "  df -h /"
  echo ""
  echo "Step 4: If space still critical (<5GB)"
  echo "  → Pause load test:"
  echo "    docker-compose stop code-server"
  echo "  → Escalate to Platform Manager"
  echo "  → Do NOT continue if <5GB remains"
}

# ============================================================================
# SCENARIO 4: NETWORK ISSUES (High Latency/Packet Loss)
# ============================================================================

handle_network_issues() {
  echo "🔴 SCENARIO 4: NETWORK ISSUES"
  echo ""
  echo "Step 1: Check external connectivity"
  echo "  ping -c 5 8.8.8.8"
  echo "  traceroute 8.8.8.8 (or tracert on Windows)"
  echo ""
  echo "Step 2: Check local network"
  echo "  docker network ls"
  echo "  docker network inspect phase13-net"
  echo ""
  echo "Step 3: Restart Docker network (if needed)"
  echo "  docker network disconnect phase13-net caddy"
  echo "  docker network connect phase13-net caddy"
  echo ""
  echo "Step 4: If issue persists (>5 minutes)"
  echo "  → Contact infrastructure team"
  echo "  → Escalate to VP Engineering"
  echo "  → Continue load test if localized to specific service"
}

# ============================================================================
# COMMUNICATION TEMPLATE
# ============================================================================

echo ""
echo "============================================================================"
echo "ESCALATION COMMUNICATION TEMPLATE"
echo "============================================================================"
echo ""
echo "When escalating to Platform Manager:"
echo ""
echo "---"
echo "INCIDENT: Phase 13 Day 2 Load Test Issue"
echo "TIME: [HH:MM UTC]"
echo "SEVERITY: [CRITICAL|HIGH|MEDIUM]"
echo "STATUS: [ONGOING|INVESTIGATING|RESOLVED]"
echo ""
echo "ISSUE DESCRIPTION:"
echo "  [Brief description of problem]"
echo ""
echo "AFFECTED SERVICES:"
echo "  [List containers/services impacted]"
echo ""
echo "SLO IMPACT:"
echo "  • p99 Latency: [current value] (target: <100ms)"
echo "  • Error Rate: [current value] (target: <0.1%)"
echo "  • Availability: [current value] (target: >99.9%)"
echo ""
echo "ACTIONS TAKEN:"
echo "  1. [Action 1]"
echo "  2. [Action 2]"
echo "  3. [Action 3]"
echo ""
echo "NEXT STEPS:"
echo "  [What needs to happen next]"
echo ""
echo "---"
echo ""

# ============================================================================
# EMERGENCY CONTACTS
# ============================================================================

echo "============================================================================"
echo "EMERGENCY CONTACTS & ESCALATION"
echo "============================================================================"
echo ""
echo "Level 1 (First Response):"
echo "  • DevOps Lead: [On-call number]"
echo "  • PagerDuty: [URL to active rotation]"
echo ""
echo "Level 2 (Technical Escalation):"
echo "  • Platform Manager: [Contact info]"
echo "  • Performance Lead: [Contact info]"
echo ""
echo "Level 3 (Executive Escalation):"
echo "  • VP Engineering: [Contact info]"
echo "  • CTO: [Escalation only for critical failures]"
echo ""
echo "Slack Channels:"
echo "  • #code-server-production (main channel)"
echo "  • #ops-critical (incidents)"
echo "  • #oncall (24/7 rotation)"
echo ""

# ============================================================================
# DECISION CRITERIA
# ============================================================================

echo "============================================================================"
echo "GO/NO-GO DECISION CRITERIA (April 15, 12:00 UTC)"
echo "============================================================================"
echo ""
echo "🟢 GO TO PRODUCTION (Proceed to Phase 14):"
echo "  ✓ p99 Latency stayed < 100ms for full 24 hours"
echo "  ✓ Error rate stayed < 0.1% for full 24 hours"
echo "  ✓ Throughput maintained > 100 req/s"
echo "  ✓ Availability > 99.9%"
echo "  ✓ ZERO container restarts or failures"
echo "  ✓ No unresolved critical incidents"
echo ""
echo "🔴 NO-GO (Retry in 2-5 days):"
echo "  ✗ Any SLO breached beyond recoverable"
echo "  ✗ Multiple container failures"
echo "  ✗ Critical security issues discovered"
echo "  ✗ Unrecoverable data corruption"
echo "  ✗ Network infrastructure failure"
echo ""
echo "Borderline Cases (Escalate to VP Engineering):"
echo "  ? Single brief SLO spike recovered quickly"
echo "  ? One container restart (not recurring)"
echo "  ? Minor issues with clear root causes"
echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo "============================================================================"
echo "REMEMBER:"
echo "============================================================================"
echo ""
echo "✓ This is a 24-hour TEST - stay calm, document everything"
echo "✓ The goal is to verify production readiness, not perfection"
echo "✓ Communication is KEY - escalate early if uncertain"
echo "✓ Follow decision criteria strictly - no exceptions"
echo "✓ All incidents will be reviewed post-test"
echo ""
echo "Phone number for emergencies: [TBD by ops team]"
echo "Slack channel: #code-server-production"
echo ""
echo "Good luck! You've got this. 🚀"
echo ""
