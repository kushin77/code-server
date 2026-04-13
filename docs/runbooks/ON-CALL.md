# On-Call Runbook

## On-Call Expectations

As an on-call engineer, you are responsible for:
1. **Alerting Response**: Respond to alert pages within 15 minutes
2. **Triage & Mitigation**: Assess severity and reduce customer impact within 30 minutes
3. **Communication**: Update stakeholders every 15 minutes during incident
4. **Resolution**: Work toward root cause and permanent fix

**You are NOT responsible for**:
- Architecting new systems during incidents
- Writing code from scratch
- Reviewing existing code in detail

Focus on **MTTR (Mean Time To Resolution)**, not perfection.

---

## Before You Go On-Call

### Setup (30 minutes)

```bash
# Install required CLIs
gcloud components install gke-gcloud-auth-plugin
kubectl version --client

# Verify cluster access
kubectl cluster-info
kubectl get nodes

# Add to phone contacts
- On-call escalation path: /on-call/escalation
- Slack #incidents channel
- PagerDuty on-call number

# Test alert tools
- Try opening PagerDuty mobile app
- Verify Slack notifications working
- Test SMS delivery

# Download runbooks locally
git clone https://github.com/kushin77/code-server-enterprise
cd docs/incident-response/
# Read PLAYBOOK.md and runbooks/*
```

### Pre-On-Call Checklist (1 hour before shift)

- [ ] Confirm no active incidents
- [ ] Check deployment calendar (anything scheduled?)
- [ ] Review recent commits (what changed in past day?)
- [ ] Check error budget status (how much room to work?)
- [ ] Verify access to prod dashboards

```bash
# Quick health check
./scripts/health-check.sh prod
```

---

## Alert Response Flow

```
┌─────────────────┐
│ Page Received   │
└────────┬────────┘
         │ (15 sec to respond)
         ▼
┌─────────────────┐
│ Acknowledge     │
│ in PagerDuty    │
└────────┬────────┘
         │
         ▼
┌──────────────────────────────┐
│ Read Alert Details:          │
│ - What service?              │
│ - What metric violated?      │
│ - How long?                  │
│ - Impact on users?           │
└────────┬─────────────────────┘
         │ (3 min assessment)
         ▼
┌───────────────────┐
│ Notify Slack      │
│ #incidents channel│
└────────┬──────────┘
         │
         ▼
    ┌────────────┐
    │ Severity?  │
    └────┬───┬──┘
         │   │
      SEV1  SEV2/3/4
         │   │
         ▼   ▼
     [Immediate] [Investigation]
      Mitigation    Mode
```

---

## Severity-Based Response

### SEV1: Complete Service Down (Page on-call)

**Timeline**: 15 min response SLA

**First 5 minutes**:
```bash
# 1. Acknowledge page in PagerDuty
# 2. Notify Slack (copy incident template below)
# 3. Check service status
kubectl get pods -n code-server
kubectl get pods -n agents
kubectl get pods -n observability

# 4. Check error rate
curl -s http://prometheus:9090/api/v1/query?query='rate(http_requests_total{status=~"5.."}[1m])'
```

**Incident Notification Template**:
```
🚨 SEV1: Code-Server Down
Status: 🔴 INVESTIGATING
Start: 2026-04-13 15:23 UTC
Duration: 2 minutes and counting
Impact: All users unable to access code-server

Investigating: Possible pod crash loop
On-call: @engineer_name
```

**Next 10 minutes**:
```bash
# Check logs for obvious errors
kubectl logs -l app=code-server -n code-server --tail=100 --all-containers

# Is it a recent deployment?
git log --oneline -5
kubectl rollout history deployment/code-server -n code-server

# If obvious bad deploy, rollback:
kubectl rollout undo deployment/code-server -n code-server

# Did it come back?
kubectl get pods -n code-server --watch
# If yes: Success! Investigate root cause later
# If no: Escalate to engineering lead
```

**Escalation** (if not resolved in 15 min):
```bash
# Page engineering lead
# Use PagerDuty escalation policy, or:
/escalate-to engineering-lead
```

### SEV2: Degradation (Performance/Error spike)

**Timeline**: 1 hour investigation SLA

**Steps**:
```bash
# Assess scope
kubectl get pods -A | grep -c "Running"  # How many pods healthy?
curl https://health.code-server.prod/  # Is health check passing?

# Identify bottleneck
kubectl top node  # Is it CPU constrained?
kubectl top pod -A  # Which pod using most resources?

# Check recent changes
git log --oneline origin/main -10
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Typical SEV2 responses:
# 1. Scale up affected service (HPA might not be fast enough)
#    kubectl scale deployment/agent-api --replicas=10 -n agents
# 2. Reduce verbosity of logging temporary
# 3. Restart service if unhealthy
#    kubectl rollout restart deployment/agent-api -n agents
```

### SEV3: Minor Issue

**Timeline**: 4 hours to address

- Unusual logs but service still working
- Non-critical alerts firing
- Small error rate spike (< 1%)

**Response**: Create GitHub issue, document for next business day discussion.

### SEV4: No Impact

**Timeline**: Best effort

- Verbose warnings
- Non-critical service degradation
- Preventive alerts (predicted future issues)

**Response**: Read the alert, document findings, close ticket at end of shift.

---

## Common On-Call Scenarios

### Scenario 1: "I Don't Know What The Alert Means"

**Don't panic**. Most alerts have context.

```bash
# Step 1: Read the alert title carefully
# Example: "high_error_rate{service=agent-api}"
# Translation: Agent API is returning 5xx errors

# Step 2: Check the runbook
# Look in docs/incident-response/PLAYBOOK.md for that service
grep -r "Agent API" docs/incident-response/

# Step 3: Quick diagnosis command
# Most runbooks have a "Check Status" section with exact commands

# Step 4: If still unsure
/help-alert [alert-name]
# This Slack bot shows you exactly what to do
```

### Scenario 2: "I Get 5 Pages At Once"

This usually means one root cause, not 5 separate issues.

```bash
# Identify common thread
# Example:
# - auth_service_errors
# - elevated_latency
# - pod_crash_loops
# All spike at same time = probably auth service crashed

# Fix the root cause (auth), other alerts should auto-resolve
kubectl logs -l app=keycloak -n code-server --tail=50
# Is it OOM? Stuck startup? Bad config?

# Once root cause is fixed, related alerts clear
# If related alerts don't clear after 5 min, investigate separately
```

### Scenario 3: "It's 3am And I'm Tired"

- **Set a timer** for 5 minutes. Even if you don't have a solution, update status at 5-min marks
- **Escalate faster**. No shame in calling engineering lead if unsure
- **Use runbooks verbatim**. Don't try to remember commands, copy-paste
- **Open Slack thread** so others can follow

```bash
# Tired on-call template:
1. Acknowledge page (30 sec)
2. Run Slack /health-status command (1 min)
3. If anything red, escalate (immediately)
4. Otherwise, follow runbook step by step
5. Update every 5 min
6. Don't debug deeply, just mitigate
```

---

## Escalation Contacts

**Tier 1: Immediate Escalation** (Page immediately if incident ongoing)
- Engineering Lead: @alice, cell: 555-0123
- CTO: @bob, cell: 555-0124

**Tier 2: Business Hours Escalation**
- Cloud Infrastructure Team: #cloud-incidents
- Database Team: #database-incidents

**Tier 3: Critical Business Escalation**
- VP Engineering: @carol (only for multi-hour outages)
- CEO: reserved for security/data loss incidents

---

## During Incident (Every 15 Minutes)

**Incident Channel Update Template**:
```
🔴 STILL INVESTIGATING:
- Started: 15:23 UTC (12 min ago)
- Service: Agent API latency spike
- Status: Scaled to 8 replicas, no improvement
- Next: Check database query performance
- ETA: 15 min
```

**Update Frequency**:
- SEV1: Every 5 minutes
- SEV2: Every 15 minutes
- SEV3+: Hourly

---

## Post-Incident (Mandatory Within 24 Hours)

**Incident Report Template**: (File in GitHub issue)

```markdown
# Incident: [Brief Title]

## Timeline
- **15:23** Alert fired: high_error_rate
- **15:25** Page acknowledged
- **15:32** Root cause identified: memory leak in agent-api
- **15:45** Fix validated in prod
- **15:50** All-clear, service restored

## Impact
- Duration: 27 minutes
- Users affected: ~200
- Error rate: 100% during incident
- Revenue: ~$500 (estimated downtime)

## Root Cause
Agent API memory leak introduced in commit abc123d, causing OOM after 1.5 hours.

## Immediate Fix
Rolled back to previous version.

## Permanent Fix
- Code change PR #456 under review
- Waits for: Memory profiling improvements

## Prevention
- [ ] Add memory regression tests to CI
- [ ] Load test for 48 hours before deployment
- [ ] Alert on memory growth rate

## Learning
Memory leaks slipped through because we don't profile in staging. Need to add
memory profiling tool to deployment checklist.
```

---

## On-Call Tools

**Must Have Installed**:
- `kubectl` - manage k8s
- `gcloud` - GCP access
- `jq` - JSON parsing
- Slack mobile app
- PagerDuty mobile app

**Useful Aliases** (add to `~/.bashrc`):
```bash
alias k='kubectl'
alias kgp='kubectl get pods -o wide'
alias kl='kubectl logs'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kex='kubectl exec -it'
alias kaf='kubectl apply -f'
alias krr='kubectl rollout restart'
alias kgh='kubectl get events --sort-by=.metadata.creationTimestamp'
```

**Slack Commands**:
```
/health-status  → Show service health
/slo-status     → Show SLO compliance
/hotspots       → Show current error hotspots
/help-alert <alert-name> → Runbook for specific alert
/escalate <target> → Page on-call engineer
```

---

## After Your On-Call Shift

**Feedback Loop** (30 min):
- [ ] Note any alerts that were confusing
- [ ] Note any missing runbooks
- [ ] Note any tools you wish you had
- [ ] Post in #on-call-feedback

**Example**:
```
Feedback from my shift:
- "pod_not_scheduling" alert doesn't clearly state which pod
- Wish there was a "scale up all services" command
- We need clearer PagerDuty escalation paths
```

---

## Red Flags (Escalate Immediately)

🚨 **ESCALATE RIGHT NOW** if you see:

1. **Data loss**: Any indication data is missing/corrupted
2. **Security breach**: Unauthorized access, credentials exposed
3. **Complete cloud region down**: Multiple services unreachable
4. **Multi-hour duration**: Already 1+ hour, not improving
5. **Cascading failures**: One service down breaks others, ripple effect
6. **Unknown root cause** after 30 minutes of investigation

In all above cases:
```bash
# Escalate to engineering lead AND CTO
/escalate engineering-lead
/escalate cto
# Explain what you've already tried
# Provide current logs/metrics
```

---

## On-Call Compensation

- Primary on-call: $X/week
- Incident response: $Y/hour during incident
- Nights/weekends: +25% pay multiplier
- Fatigue: If 3+ incidents in shift, next shift optional

---

## Questions?

- Read `docs/incident-response/PLAYBOOK.md` for specific incidents
- Ping #on-call-support for procedural questions
- Post in #on-call-feedback after your shift
