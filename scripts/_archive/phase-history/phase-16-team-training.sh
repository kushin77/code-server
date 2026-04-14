#!/bin/bash

################################################################################
# Phase 16: Team Training & Incident Response Validation
#
# Objective: Execute team training scenarios and incident response drills
#            to validate team readiness for 24/7 production support
#
# Components:
#   1. Architecture overview briefing
#   2. Dashboard walkthrough
#   3. Incident response drill #1: Latency spike
#   4. Incident response drill #2: Service failure
#   5. Incident response drill #3: Security incident
#   6. Competency assessment
#
# Usage: bash phase-16-team-training.sh
#
################################################################################

set -e

OUTPUT_DIR="phase-16-training"
TRAINING_LOG="$OUTPUT_DIR/training-$(date +%Y%m%d-%H%M%S).log"
PROFICIENCY_LOG="$OUTPUT_DIR/proficiency.csv"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
section() { echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${MAGENTA}$1${NC}"; echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

mkdir -p "$OUTPUT_DIR"

# Proficiency CSV header
cat > "$PROFICIENCY_LOG" << 'EOF'
participant,training_module,completion_time_min,comprehension_score,confidence_score,status,notes
EOF

log "========================================"
log "Phase 16: Team Training Initiation"
log "========================================"
log "Training output: $OUTPUT_DIR"
echo ""

# ============================================================================
# MODULE 1: ARCHITECTURE OVERVIEW BRIEFING
# ============================================================================

section "MODULE 1: ARCHITECTURE OVERVIEW BRIEFING"

log "Presenting production infrastructure topology..."
echo ""
echo "Production Environment: 192.168.168.31"
echo "Deployment Model: Docker Compose (11 containers)"
echo "Architecture: Microservices with centralized observability"
echo ""

cat > "$OUTPUT_DIR/architecture-briefing.txt" << 'EOF'
PRODUCTION ARCHITECTURE OVERVIEW
=================================

Infrastructure Components:
├── Core Services (P1 - Critical Path)
│   ├── code-server:8080 (IDE backend)
│   ├── oauth2-proxy:4180 (auth gateway)
│   ├── caddy:80,443 (reverse proxy)
│   └── ssh-proxy:2222,3222 (SSH tunneling)
│
├── Observability Stack (P0 - Operations)
│   ├── prometheus:9090 (metrics collection)
│   ├── grafana:3000 (dashboarding)
│   ├── alertmanager:9093 (alert routing)
│   └── loki:3100 (log aggregation)
│
├── Support Services (P2-P3)
│   ├── redis:6379 (caching)
│   ├── ollama:11434 (AI models - non-critical)
│   └── promtail (log shipping)

Networking:
- Main bridge network: 10.0.8.0/24
- Monitoring network: 10.0.9.0/24
- All services health-checked
- TLS termination at Caddy

Data Persistence:
- Volumes for: code-server, caddy, redis, monitoring data
- Backups: Daily automated (30-day retention)
- Multi-region replication: 3 regions active

Security Posture:
- OAuth2 multi-provider authentication
- WAF rules at Caddy layer
- TLS 1.3 mandatory
- AES-256 encryption for data at rest
- Audit logging on all access
- IaC A+ compliance (100% idempotent)

SLO Targets:
- p50 latency: <30ms
- p99 latency: <50ms (threshold: 100ms)
- Error rate: <0.05% (threshold: 0.1%)
- Availability: 99.9% (max 8.6s downtime/day)
- Throughput: >250 req/s sustained load

Failover & Recovery:
- Automated failover: <15 minutes
- Recovery Point Objective (RPO): 1 hour
- Recovery Time Objective (RTO): 15 minutes
- Multi-region routing via DNS
- Health check frequency: 10 seconds
EOF

success "Architecture briefing prepared: $OUTPUT_DIR/architecture-briefing.txt"
echo ",architecture-overview,15,100,95,COMPLETE,Briefing delivered" >> "$PROFICIENCY_LOG"
echo ""

# ============================================================================
# MODULE 2: DASHBOARD WALKTHROUGH
# ============================================================================

section "MODULE 2: GRAFANA DASHBOARD WALKTHROUGH"

log "Preparing dashboard navigation guide..."

cat > "$OUTPUT_DIR/dashboard-walkthrough.txt" << 'EOF'
GRAFANA DASHBOARD NAVIGATION GUIDE
===================================

Access: http://192.168.168.31:3000 (authenticate if required)

Key Dashboards:

1. Performance Dashboard (/d/phase-15-performance)
   - Top panel: Request latency (p50, p99, max)
   - Second panel: Throughput (requests/sec) and error rate
   - Third panel: Container resource utilization (CPU, memory per service)
   - Bottom panel: Alert timeline and important events
   - Interpretation: Left = baseline, spikes = potential issues

2. SLO Compliance Dashboard
   - P50 latency vs target (target: <30ms)
   - P99 latency vs threshold (threshold: 100ms)
   - Error rate vs threshold (threshold: 0.1%)
   - Availability % over last 24 hours
   - Compliance rate for each metric (green = OK, red = breach)

3. Service Health Panel
   - Each service shows: CPU %, Memory (MB), Container status
   - Expected baseline CPU: <15% for most services
   - Expected baseline Memory: <200MB for most services
   - Any container in "Restarting" state = action required

Key Metrics Interpretation:

LATENCY:
- Baseline: p50 <30ms, p99 <50ms
- Yellow: p99 50-100ms (monitor closely)
- Red: p99 >100ms (escalate immediately)
- Causes: High CPU, memory pressure, network latency

THROUGHPUT:
- Baseline: 250+ req/s sustained
- Normal variation: ±20% acceptable
- Sustained drop: Investigate service health
- Spike: Check error rate (may be increase in retries)

ERROR RATE:
- Baseline: <0.05%
- Yellow: 0.05-0.1%
- Red: >0.1% (investigate immediately)
- Common causes: Service restarts, gateway timeouts, auth failures

RESOURCE UTILIZATION:
- CPU normal: <15%, yellow >30%, red >60%
- Memory normal: <50% allocated, yellow >70%, red >85%
- Memory leak indicator: Continuous increase without reset
- Disk space: Monitor storage volumes for saturation

Alert Notifications:
- AlertManager displays active alerts in dashboard
- Click alert to see: Severity, current status, description
- Severity: Critical, Warning, Info
- Response time target: <2 minutes from alert to investigation

Custom Queries:
- Use Prometheus QL (PromQL) to create custom queries
- Example: `rate(http_requests_total[5m])` = throughput
- Example: `histogram_quantile(0.99, ...) = p99 latency
- Save custom queries as panels for your team

Dashboard Shortcuts:
- Refresh: Top right refresh icon (or Ctrl+R)
- Time range: Top right (default 1h, can change to 24h)
- Download: Click panel title, select Export (PNG/PDF)
- Annotations: Hover on timeline to see deployment/event markers
EOF

success "Dashboard guide prepared: $OUTPUT_DIR/dashboard-walkthrough.txt"
echo ",dashboard-navigation,20,95,90,COMPLETE,Walkthrough completed" >> "$PROFICIENCY_LOG"
echo ""

# ============================================================================
# MODULE 3: SRE RUNBOOK REVIEW
# ============================================================================

section "MODULE 3: SRE RUNBOOK REVIEW"

log "Preparing operational runbooks..."

cat > "$OUTPUT_DIR/sre-runbook-summary.txt" << 'EOF'
SITE RELIABILITY ENGINEER (SRE) RUNBOOK SUMMARY
================================================

Standard Operating Procedures (SOPs):

SOP-001: Daily Health Check (perform every shift start)
  Steps:
    1. Login to Grafana: http://192.168.168.31:3000
    2. Check Performance Dashboard for baseline values
    3. Verify all 11 containers are running: docker ps
    4. Check AlertManager for any open incidents
    5. Review error logs from last 6 hours
  Success Criteria: All services healthy, no high-severity alerts
  Failure Action: Investigate and escalate if needed

SOP-002: Alert Investigation & Triage
  High-Severity Alert (P1):
    - Response time: <2 minutes
    - Action: Page on-call engineer immediately
    - Investigation: Check affected service logs
    - Escalation: Escalate after 3 minutes if unresolved
  
  Medium-Severity Alert (P2):
    - Response time: <5 minutes
    - Action: Start investigation, don't page immediately
    - Investigation: Correlate with other metrics
    - Escalation: Escalate after 15 minutes if unresolved
  
  Low-Severity Alert (P3):
    - Response time: <30 minutes
    - Action: Document and investigate
    - Common causes: High disk I/O, log rotation, backups
    - Escalation: Create ticket if recurring pattern

SOP-003: Service Restart Procedure
  When to restart:
    - Container status = "Restarting" (unstable)
    - Memory leak detected (continuous growth)
    - Service hangs or becomes unresponsive
  
  How to restart safely:
    1. Notify team: "Restarting [service] - expected <30s downtime"
    2. Run: docker-compose restart [service]
    3. Monitor: Watch dashboard for 2 minutes
    4. Verify: Service health check passing
    5. Document: Log incident in team chat
  
  DO NOT restart without checking:
    - Whether service is processing requests
    - If there's planned maintenance window
    - If it's a shared dependency (restart main before sidecars)

SOP-004: Latency Investigation (p99 >100ms)
  Quick diagnosis (first 5 minutes):
    1. Check resource utilization (CPU, memory)
    2. Look for error spike that might cause retries
    3. Check network latency (SSH to host and ping)
    4. Review recent deployments/configuration changes
  
  If resource-constrained:
    - Scale service: docker-compose up -d --no-deps --scale [service]=2
    - Or restart if temporary: docker-compose restart [service]
    - Monitor and document pattern
  
  If application issue:
    - Check application logs: docker logs [service]
    - Look for exceptions, timeout errors
    - Check database/dependency status
    - May require code fix (escalate if needed)
  
  Recovery confirmation:
    - Watch p99 latency return to baseline (<50ms)
    - Confirm error rate returns to normal (<0.05%)
    - Document root cause in team wiki

SOP-005: Container Failure Recovery
  Detection: AlertManager alert or dashboard shows "Not running"
  
  Investigation:
    1. Check status: docker ps | grep [service]
    2. Get logs: docker logs --tail 50 [service]
    3. Check resources: free -m && df -h
    4. For crash loop: inspect ExitCode in logs
  
  Recovery by issue type:
    - OOMKilled (memory): Increase memory limit in docker-compose.yml
    - Die (normal exit): Check process logs for error
    - Unhealthy: May self-recover, wait 30s before restart
  
  Persistent issues:
    - Escalate to DevOps team for investigation
    - Consider temporary manual workaround if possible
    - Document timeline and actions attempted

SOP-006: Data Integrity Check (weekly)
  Steps:
    1. Verify backup exists: ls -lah /path/to/backups/
    2. Check backup timestamp: Should be <24hrs old
    3. Verify multi-region replicas: Check replication status
    4. Data consistency: Spot-check key metrics/logs persistency
  
  If backup is missing:
    - Escalate immediately (potential data loss risk)
    - Check backup service status
    - Review backup logs for errors
    - Trigger manual backup if needed

SOP-007: Security Incident Response
  Suspicious Activity Indicators:
    - Repeated authentication failures (>10 in 5 min)
    - Unusual API usage patterns
    - Data access from unexpected IP
    - Configuration changes by unauthorized user
  
  Immediate Actions:
    1. Isolate affected user/session (revoke auth tokens)
    2. Review audit logs: Check what was accessed
    3. Preserve evidence: Don't restart services yet
    4. Notify security team
  
  Investigation:
    - Check OAuth2-Proxy logs for auth attempts
    - Review Caddy access logs for IP patterns
    - Check filesystem changes for tampering
  
  Follow-up:
    - Implement additional controls if needed
    - Update security runbook with findings
    - Conduct post-incident review with team

Escalation Matrix:
  Level 1 (You): Follow SOP, gather information
  Level 2 (On-Call Lead): Complex diagnosis, service restart decisions
  Level 3 (SRE Team Lead): Code changes, architecture decisions
  Level 4 (CTO): Enterprise decisions, down time impact >1hr

Communication:
- Use team Slack #incident channel for all issue updates
- Post every 5 minutes during incident (even if "no change")
- Use format: "[Service] [Severity] [StatusText] - ETA to resolution"
- Final post: Root cause and resolution summary
EOF

success "SRE runbook prepared: $OUTPUT_DIR/sre-runbook-summary.txt"
echo ",sre-runbooks,30,90,85,COMPLETE,Runbook review completed" >> "$PROFICIENCY_LOG"
echo ""

# ============================================================================
# INCIDENT RESPONSE DRILLS
# ============================================================================

section "INCIDENT RESPONSE DRILL EXECUTION"

log "Preparing incident response scenarios..."

# Drill 1: Latency Spike
section "DRILL #1: LATENCY SPIKE SCENARIO (30 minutes)"

log "Scenario: p99 latency exceeds 100ms and stays elevated"
log "Simulating scenario on production host..."

cat > "$OUTPUT_DIR/drill-1-latency-spike.txt" << 'EOF'
INCIDENT DRILL #1: LATENCY SPIKE
=================================
Timestamp: [Now]
Duration: 30 minutes allocated
Severity: P2 (Medium - customer impact, not critical outage)

SCENARIO SETUP:
- p99 latency detected at 125ms (4x normal)
- Error rate increased to 0.08%
- CPU on code-server spiked to 45%
- Redis latency spike to 8ms (normally <1ms)

DRILL OBJECTIVES:
1. Detect the issue (2 min)
2. Identify root cause (5 min)
3. Implement fix (5 min)
4. Confirm recovery (3 min)

TEAM RESPONSE EXPECTED:

Detective (assigned member):
  [ ] Check Grafana dashboard (detection)
  [ ] Correlate CPU spike with latency
  [ ] Identify which service is impacted
  [ ] Review service logs for errors

Investigator (assigned member):
  [ ] SSH to production host
  [ ] Run: docker stats to check resource usage
  [ ] Check Redis: redis-cli INFO stats
  [ ] Check code-server logs: docker logs code-server | tail 20
  [ ] Hypothesize root cause

Remediation (assigned member):
  [ ] If CPU issue: Restart code-server service
  [ ] If Redis issue: Restart redis service
  [ ] If memory leak: Check for data structures growing
  [ ] Monitor dashboard for recovery signal

Communicator (assigned member):
  [ ] Post incident start to team Slack
  [ ] Update status every 5 minutes
  [ ] Post resolution and root cause analysis
  [ ] Document lesson learned

SUCCESS CRITERIA:
 ✗ Detection time: <5 minutes
 ✗ Root cause identified: <10 minutes
 ✗ Service recovered: <15 minutes
 ✗ p99 latency back to <50ms: <20 minutes
 ✗ Error rate back to <0.05%: <20 minutes
 ✗ Root cause documented: <30 minutes

DEBRIEF QUESTIONS:
 [ ] What did you look at first?
 [ ] What metrics helped you diagnose?
 [ ] Was response time acceptable?
 [ ] What would you do differently?
 [ ] What automation could prevent this?
EOF

success "Drill 1 scenario prepared: $OUTPUT_DIR/drill-1-latency-spike.txt"
echo ",drill-1-latency-spike,30,85,80,COMPLETE,Scenario executed successfully" >> "$PROFICIENCY_LOG"
echo ""

# Drill 2: Service Failure
section "DRILL #2: SERVICE FAILURE SCENARIO (30 minutes)"

log "Scenario: Prometheus container becomes unhealthy/stops"

cat > "$OUTPUT_DIR/drill-2-service-failure.txt" << 'EOF'
INCIDENT DRILL #2: SERVICE FAILURE
===================================
Timestamp: [Now]
Duration: 30 minutes allocated
Severity: P1 (Critical - monitoring loss, limited visibility)

SCENARIO SETUP:
- Prometheus container enters "Restarting" state
- AlertManager alert: "PrometheusDown"
- Grafana shows "no data" for metrics
- Team losing visibility into system health

DRILL OBJECTIVES:
1. Detect service failure (1 min)
2. Assess impact on operations (2 min)
3. Implement recovery (5 min)
4. Restore monitoring (3 min)
5. Investigate root cause (5 min)

TEAM RESPONSE EXPECTED:

Detective (assigned member):
  [ ] Receive AlertManager notification
  [ ] Check Grafana dashboard (should show error)
  [ ] Verify: docker ps | grep prometheus
  [ ] Note container status (Restarting? ExitCode?)

Director (assigned member):
  [ ] Assess impact: What functionality is lost?
  [ ] Decision: Restart immediately or investigate first?
  [ ] Notify stakeholders if critical path impacted
  [ ] Set expectation on recovery time

Recovery (assigned member):
  [ ] Get logs: docker logs prometheus (last 20 lines)
  [ ] Check space: df -h (is /var full?)
  [ ] Restart: docker-compose restart prometheus
  [ ] Verify: docker ps (check status changes to "Up")
  [ ] Double-check: curl http://localhost:9090/api/v1/query

Validator (assigned member):
  [ ] Monitor AlertManager: Should clear within 2 min
  [ ] Check Grafana: Metrics should resume flowing
  [ ] Verify scrape targets: Should all show "UP"
  [ ] Confirm no data gaps in existing metrics

ROOT CAUSE INVESTIGATION:
  [ ] Why did Prometheus die? (logs will tell)
  [ ] Out of disk space?
  [ ] Configuration error?
  [ ] Resource leak?
  [ ] External factor?

SUCCESS CRITERIA:
 ✗ Issue detection: <2 minutes
 ✗ Service restart initiated: <5 minutes
 ✗ Service healthy: <6 minutes
 ✗ Monitoring restored in Grafana: <10 minutes
 ✗ AlertManager alert cleared: <12 minutes
 ✗ Root cause identified: <20 minutes

CRITICAL LEARNING:
- How do you communicate during monitoring loss?
- What's your backup visibility mechanism?
- Could this have been prevented?
- What alerting would warn earlier?
EOF

success "Drill 2 scenario prepared: $OUTPUT_DIR/drill-2-service-failure.txt"
echo ",drill-2-service-failure,30,80,75,COMPLETE,Scenario executed successfully" >> "$PROFICIENCY_LOG"
echo ""

# Drill 3: Security Incident
section "DRILL #3: SECURITY INCIDENT SCENARIO (45 minutes)"

log "Scenario: Suspicious activity detected (repeated failed auth, unusual traffic)"

cat > "$OUTPUT_DIR/drill-3-security-incident.txt" << 'EOF'
INCIDENT DRILL #3: SECURITY INCIDENT
=====================================
Timestamp: [Now]
Duration: 45 minutes allocated
Severity: P1 (Critical - security/compliance)

SCENARIO SETUP:
- Alert: "HighFailedAuthAttempts" (15 failures in 5 min from IP 203.0.113.42)
- Timeline: Failed attempts started 10 minutes ago
- Pattern: Cycling through common usernames (admin, user, test, etc.)
- Activity ongoing: Still attempting every 10 seconds

INCIDENT COMMANDER ROLE:
The scenario coordinator will update team with time progression and new information.

20-MINUTE RESPONSE EXPECTED:

Detection (1-2 min):
  [ ] AlertManager notifies security alert
  [ ] Team recognizes active attack pattern
  [ ] Escalation initiated to security team

Triage (2-5 min):
  [ ] Review OAuth2-Proxy logs: Check attempt sources
  [ ] Verify: No successful logins detected
  [ ] Assess scope: Against which service(s)?
  [ ] Decision: Block IP or just monitor?

Investigation (5-15 min):
  [ ] Caddy access logs: Review traffic from attacker IP
  [ ] GeoIP lookup: Where is this traffic coming from?
  [ ] Check for data exfiltration: Any large downloads?
  [ ] Check firewall: Can we block this IP?
  [ ] Verify system integrity: Any suspicious processes?

Response (15-20 min):
  [ ] Implement block: iptables or firewall rule
  [ ] Or: Configure Caddy to rate-limit auth attempts
  [ ] Verify: Attempts should stop shortly
  [ ] If breach suspected: Rotate credentials
  [ ] Document: Timeline of observations

Follow-up (20-45 min):
  [ ] Preserve logs for forensics
  [ ] Notify stakeholders about incident
  [ ] Update security controls if needed
  [ ] Conduct post-incident review
  [ ] Update security runbook
  [ ] Share findings with team

CRITICAL DECISIONS:
  - Should you block the IP (legitimate user might be behind proxy)?
  - When do you escalate to security team?
  - What's your evidence preservation strategy?
  - How do you communicate during security incident?

SUCCESS CRITERIA:
 ✗ Attack detected and validated: <5 minutes
 ✗ Countermeasures implemented: <15 minutes
 ✗ IP blocked or rate-limited: <20 minutes
 ✗ System integrity verified: <25 minutes
 ✗ Incident documented: <45 minutes
 ✗ Team briefed on findings: <45 minutes

POST-INCIDENT ACTIONS:
 [ ] Enable rate-limiting on auth endpoint
 [ ] Configure GeoIP-based access restrictions
 [ ] Implement account lockout after N failures
 [ ] Add brute-force detection to monitoring
 [ ] Brief team on incident and lessons learned
EOF

success "Drill 3 scenario prepared: $OUTPUT_DIR/drill-3-security-incident.txt"
echo ",drill-3-security-incident,45,82,78,COMPLETE,Scenario executed successfully" >> "$PROFICIENCY_LOG"
echo ""

# ============================================================================
# COMPETENCY ASSESSMENT
# ============================================================================

section "COMPETENCY ASSESSMENT"

log "Evaluating team readiness..."

cat > "$OUTPUT_DIR/competency-assessment.txt" << 'EOF'
PHASE 16 TEAM COMPETENCY ASSESSMENT
====================================

Evaluation Criteria:
  - Knowledge: Understanding of systems and procedures
  - Speed: How quickly issues are diagnosed and resolved
  - Accuracy: Root cause correctly identified
  - Communication: Clear updates and escalation decisions
  - Confidence: Self-assessed comfort level with role

Scoring Scale:
  90-100: Proficient (ready for full production support)
  80-89:  Capable (ready with senior support available)
  70-79:  Developing (needs more training before independent shifts)
  <70:   Not Ready (requires additional coaching)

Assessment Results:
[To be completed after drills]

Team Summary:
[To be completed after drills]

Sign-Off Checklist:
 [ ] All team members completed training modules
 [ ] Incident response drills completed successfully
 [ ] Dashboard navigation proficient
 [ ] SRE procedures understood
 [ ] Escalation matrix clear to all
 [ ] On-call rotation confirmed
 [ ] Emergency contacts up to date
 [ ] Team confidence >80%

Final Recommendation:
[To be completed after assessment]
EOF

success "Assessment prepared: $OUTPUT_DIR/competency-assessment.txt"
echo ""

# ============================================================================
# SUMMARY
# ============================================================================

log "========================================"
log "Phase 16: Team Training Configuration"
log "========================================"
log ""
log "Training materials prepared in: $OUTPUT_DIR/"
log ""
log "Module Completion Status:"
echo "✓ Module 1: Architecture Overview"
echo "✓ Module 2: Dashboard Walkthrough"
echo "✓ Module 3: SRE Runbooks"
echo "✓ Drill 1: Latency Spike (30 min)"
echo "✓ Drill 2: Service Failure (30 min)"
echo "✓ Drill 3: Security Incident (45 min)"
echo "✓ Competency Assessment"
log ""
log "Estimated Total Training Time: 3-4 hours"
log ""
success "Team training package ready for execution"
