# ADR-003: Dual-Portal Architecture - Backstage + Appsmith

**Status**: DRAFT (awaiting ADR-002 IAM approval)  
**Date**: April 16, 2026  
**Author**: Platform Engineering  
**Depends On**: ADR-002 (Unified Identity & RBAC)  
**Affected Components**: Backstage, Appsmith, GitHub, K8s, PagerDuty  

---

## Problem Statement

Platform lacks unified operational visibility and self-service capabilities across three critical dimensions:

1. **Service Ownership & Metadata** (WHO owns WHAT)
   - Service catalog unclear: 50+ services, unknown ownership, missing SLOs
   - No golden path templates for new services
   - Compliance metadata scattered across wikis + spreadsheets

2. **Operational Command Center** (HOW to respond to incidents)
   - Incident response is manual and error-prone
   - Release approvals email-based (slow, unauditable)
   - No self-service runbook execution
   - Alert acknowledgement requires context-switching

3. **Integration Fragmentation**
   - Ownership data in GitHub
   - Compliance metadata in Confluence  
   - Incident timeline in Slack
   - Deployment history in Jenkins/GitHub Actions
   - No unified view across these systems

**Impact**:
- Medium: MTTR 2+ hours (context-switching overhead)
- Medium: No single source of truth for service ownership
- High: Compliance audits require manual data aggregation
- Medium: New engineers cannot self-service common tasks

---

## Solution Overview

### Dual-Portal Strategy

**Portal 1: Backstage (Catalog & Insights)**  
Responsibility: *What is running and who owns it?*
- Service catalog (100+ microservices with metadata)
- Service scorecards (SLO compliance, incident rate, deployment frequency)
- Golden path templates for new services
- Ownership & RBAC matrix
- Compliance & audit metadata
- Architecture diagrams + dependency graphs
- Cost attribution per service/team

**Portal 2: Appsmith (Operations & Workflows)**  
Responsibility: *How do we respond and approve changes?*
- Incident response command center (alert→runbook→action)
- Release approval workflows (gate on tests, coverage, compliance)
- Disaster recovery test triggers
- Emergency access requests + audit trail
- Chaos engineering experiment launches
- Rollback controls + deployment history
- Alert acknowledgement + on-call handoff

### Architecture Diagram

```
Users
  ├─ All Engineers
  │   ├─ code-server → Backstage (read: service catalog, SLOs, architecture)
  │   └─ → Appsmith (read: incident history, dashboards)
  │
  ├─ SRE / On-Call
  │   ├─ → Backstage (write: service metadata, scorecards)
  │   └─ → Appsmith (write: run playbooks, approve releases, trigger chaos)
  │
  └─ Platform Lead
      ├─ → Backstage (admin: template management, policy definition)
      └─ → Appsmith (admin: workflow definition, escalation paths)

OAuth2/OIDC (ADR-002) → Unified Identity
  ├─ code-server: Application-level auth
  ├─ Backstage: SSO via oauth2-proxy
  └─ Appsmith: SSO via oauth2-proxy + RBAC enforcement

Data Sync
  ├─ Backstage: Pulls from GitHub (teams, repos, owners)
  ├─ Appsmith: Pulls from Backstage (service metadata for workflows)
  ├─ Appsmith: Pushes to PagerDuty (on-call assignments)
  └─ Both: Push to PostgreSQL (audit trail)
```

---

## Detailed Design

### Portal 1: Backstage (Service Catalog)

**Purpose**: Single source of truth for service ownership, SLOs, and golden paths

**Core Entities**:

```yaml
service:
  id: "code-server"
  displayName: "VS Code Server"
  description: "Multi-tenant VS Code editing environment"
  
  ownership:
    team: "platform-eng"
    slack_channel: "#platform-engineering"
    on_call: "sre-oncall-pagerduty-integration"
    escalation_path: ["alex@company.com", "platform-lead@company.com"]
  
  metadata:
    language: "typescript"
    framework: "express"
    repository: "github.com/kushin77/code-server"
    deployed_version: "4.115.0"
    health_check_url: "http://192.168.168.31:8080/healthz"
  
  slo:
    availability: 0.9999  # 99.99% uptime
    latency_p99_ms: 100
    error_budget_percent: 0.01
    current_compliance: 0.9997
  
  compliance:
    data_classification: "confidential"
    pii_handling: "yes"
    encryption_in_transit: "https"
    encryption_at_rest: "aes-256"
    audit_required: true
  
  dependencies:
    - postgresql  # database
    - redis       # caching
    - prometheus  # metrics
  
  runbooks:
    - name: "Restart code-server"
      link: "https://wiki/runbooks/code-server-restart"
    - name: "Backup workspace data"
      link: "https://wiki/runbooks/code-server-backup"
    - name: "Failover to replica"
      link: "https://wiki/runbooks/code-server-failover"
```

**Backstage Features**:

| Feature | Capability | Owner |
|---------|---|---|
| Service Catalog | Search + filter 100+ services by owner/language/compliance | All engineers (read) |
| Scorecards | SLO compliance, incident rate, deployment frequency, code coverage | All engineers (read) |
| Golden Paths | Cookiecutters for new services (service template → GitHub repo) | platform-eng (write) |
| Ownership Directory | Teams + individuals, escalation paths, on-call assignments | SRE (write) |
| Compliance Dashboard | PII risk, encryption status, audit requirements per service | Security (write) |
| Architecture Diagrams | Service dependency graph, data flows, disaster recovery topology | platform-eng (maintain) |
| Cost Attribution | Cloud + on-prem infrastructure cost per service/team | FinOps (write) |

**Data Sources**:
```
GitHub API
  ├─ Repository metadata (repo name, description, language)
  ├─ Team assignments (CODEOWNERS file)
  └─ Topics/labels (compliance tags)

PostgreSQL (custom)
  ├─ Service metadata (deployment version, health check URL)
  ├─ SLO targets + current compliance
  ├─ Runbook associations
  └─ Ownership assignments (override GitHub if needed)

Prometheus
  ├─ SLO current values (availability, latency)
  └─ Error rates + incident counts (last 30 days)

Slack
  ├─ Team channels (from workspace API)
  └─ On-call assignments (via SlackBot)
```

**Deployment**:
```yaml
service: backstage
image: backstage:latest  # official image
port: 7007
database:
  engine: postgresql
  url: ${DB_URL}
  migrations: auto
auth:
  oauth2_proxy: true
  url: http://oauth2-proxy:4180
volumes:
  - /data/backstage/plugins  # extensibility
```

---

### Portal 2: Appsmith (Operations Portal)

**Purpose**: Unified command center for incident response, approvals, and disaster recovery

**Core Use Cases**:

#### 1. Incident Response Command Center

**Workflow**:
```
1. Alert fires in AlertManager
2. Webhook → Appsmith: POST /api/alerts/new
3. Appsmith dashboard updates: Alert list (sorted by severity)
4. On-call SRE clicks alert → Appsmith pulls:
   - Alert definition + threshold
   - Associated runbook (from Backstage)
   - Service owner (from Backstage)
   - Incident history (last 30 days from Prometheus)
   - Team Slack channel + on-call escalation
5. SRE clicks "Run Runbook" → Appsmith:
   - Executes pre-approved playbook (shell script)
   - Captures output + logs to PostgreSQL
   - Posts update to Slack
   - Creates incident timeline
6. If resolved: SRE clicks "Resolve Incident"
   - Logs resolution action
   - Triggers post-mortem workflow (if MTTR > SLA)
```

**UI Components**:
```
┌─────────────────────────────────────┐
│ Incident Command Center             │
├─────────────────────────────────────┤
│                                     │
│ 🔴 CRITICAL: API latency p99 > 500ms│
│ Service: api-gateway                │
│ Owner: platform-eng                 │
│ Runbook: [View] [Run: Restart API]  │
│                                     │
│ 🟡 WARN: Disk 85% full              │
│ Service: postgresql                 │
│ Owner: database-team                │
│ Runbook: [View] [Run: Cleanup Logs] │
│                                     │
│ 🟢 INFO: Deployment successful      │
│ Service: code-server v4.115.0       │
│ Status: [Rollback] [Mark OK]        │
│                                     │
└─────────────────────────────────────┘

Incident Timeline (right panel):
├─ 14:05 Alert triggered (latency spike)
├─ 14:06 SRE ack'd incident
├─ 14:07 Runbook executed: Restart API
├─ 14:09 Service recovered
└─ 14:10 Post-mortem triggered
```

#### 2. Release Approval Gate

**Workflow**:
```
1. CI/CD pipeline completes tests + coverage scan
2. GitHub Action → Appsmith: POST /api/releases/pending
   - Artifact: code-server:v4.116.0
   - Test coverage: 87%
   - Security scan: No critical issues
   - Changelog: 12 commits
3. Appsmith creates approval card:
   - ✅ Tests passed
   - ✅ Coverage > 80%
   - ✅ Security scan passed
   - ⏳ Awaiting SRE approval
4. On-call SRE reviews + clicks "Approve"
   - Appsmith logs decision (user, timestamp, reason)
   - Appsmith triggers GitHub Action: Deploy to production
5. Deployment proceeds → On-call monitors
6. If errors: SRE clicks "Rollback" → Previous version restored
```

**RBAC Gates**:
```
- Test results: Any engineer can view
- Approval gate: operator role required
- Rollback: operator or admin
- Deployment history: All (read-only)
```

#### 3. Disaster Recovery Testing

**Workflow**:
```
1. Weekly schedule: Trigger DR test
   - Appsmith shows checklist:
     ☐ Backup integrity verified
     ☐ Replica in sync
     ☐ Failover script tested
     ☐ Data loss < 5 min acceptable
2. SRE starts test → Appsmith:
   - Records start time
   - Creates isolated environment (clone prod DB)
   - Executes failover playbook
   - Monitors recovery metrics
   - Logs all actions
3. Test complete → Appsmith:
   - Calculates RTO (time to recovery)
   - Calculates RPO (data loss)
   - Compares vs. SLA targets
   - Updates DR dashboard
4. Post-test: Engineer reviews results + signs off
```

**SLA Tracking**:
```
Service: code-server
RTO Target: < 10 minutes
RPO Target: < 5 minutes

Last 4 DR Tests:
├─ 2026-04-15: RTO=4min ✅, RPO=2min ✅
├─ 2026-04-08: RTO=6min ✅, RPO=3min ✅
├─ 2026-04-01: RTO=8min ✅, RPO=1min ✅
└─ 2026-03-25: RTO=3min ✅, RPO=45sec ✅

Status: SLA target achieved last 20 tests
```

#### 4. Emergency Access Management

**Scenario**: Need to access production to fix critical issue

**Workflow**:
```
1. SRE clicks "Request Emergency Access"
   - Form: Reason + duration + target environment
   - Example: "SSH to 192.168.168.31 for 30 min to debug CPU spike"
2. Appsmith:
   - Routes request to on-call platform lead (PagerDuty)
   - Sends Slack notification + approval link
   - Sets 30-min countdown timer
3. Lead approves → Appsmith:
   - Generates temporary SSH key (30-min lifetime)
   - Delivers key via secure channel
   - Logs: User, action, approval, time
   - Creates audit entry in PostgreSQL
4. Access expires → SSH key auto-revoked
5. After incident: Access log reviewed by security
```

**Audit Trail**:
```sql
SELECT timestamp, user_email, action, resource, approval_status
FROM appsmith_actions
WHERE action = 'emergency_access'
ORDER BY timestamp DESC
LIMIT 100;
```

---

## Data Synchronization

### Backstage ← GitHub (polling, hourly)

```python
# Poll GitHub API for updated metadata
github_api = GitHub(token=GSM.secret('github-backstage-token'))

for repo in github_api.org_repos():
    # Extract from CODEOWNERS
    owners = parse_codeowners(repo)
    
    # Extract from topics/labels
    compliance_tags = repo.topics
    
    # Update Backstage catalog
    backstage.upsert_service(
        id=repo.name,
        repo=repo.url,
        owners=owners,
        compliance=compliance_tags
    )
```

### Appsmith ← Backstage (on-demand + polling)

```
When incident fires:
1. AlertManager webhook → Appsmith
2. Appsmith queries Backstage: GET /api/entities?kind=service&q=code-server
3. Backstage responds: { owner, runbooks, escalation_path, slo }
4. Appsmith populates incident card with this metadata
```

### Appsmith → PostgreSQL (all actions)

```sql
-- Every action in Appsmith is logged to audit_events
INSERT INTO audit_events (
  timestamp, user_id, service_name, action, resource_type,
  authorization_decision, correlation_id
) VALUES (
  NOW(), 'user@company.com', 'appsmith', 'incident.acknowledge',
  'alert-code-server-cpu', 'ALLOW', 'trace-xyz-123'
);
```

### Appsmith → PagerDuty (on-call updates)

```
Workflow:
1. Appsmith updates on-call assignment: SRE rotates
2. Appsmith API call: PagerDuty POST /escalation_policies/.../overrides
   - Start time: NOW
   - End time: NOW + 7 days
   - User: ${SRE_EMAIL}
3. PagerDuty accepts → New on-call is live
```

---

## Deployment Architecture

### Multi-Region Design

```
Primary (192.168.168.31)
├─ Backstage pods (3 replicas)
├─ Appsmith pods (3 replicas)
├─ Postgres primary (backup to NAS)
└─ Redis cache (replication to .42)

Secondary/Failover (192.168.168.42)
├─ Standby (can become active)
├─ PostgreSQL replica (lag < 1sec)
└─ Service mesh: Prometheus + Jaeger scrape both
```

### High Availability

**Requirement**: RTO < 5 minutes (auto-failover)

**Implementation**:
```yaml
backstage:
  replicas: 3
  affinity: spread across nodes
  health_check: liveness + readiness
  
appsmith:
  replicas: 3
  affinity: spread across nodes
  health_check: liveness + readiness

database:
  primary: 192.168.168.31:5432
  replica: 192.168.168.42:5432
  replication_lag_sla: < 1 second
  failover: manual (requires human approval)
```

---

## Success Criteria

### Adoption
- [ ] 90% of services cataloged in Backstage within 30 days
- [ ] 100% of runbooks linked from Appsmith incident cards
- [ ] MTTR reduction: 2 hours → 15 minutes (8x improvement)

### Data Quality
- [ ] Ownership assigned for 95%+ of services
- [ ] SLO compliance visible + trending in dashboards
- [ ] Golden paths used for 80%+ of new services

### Operational
- [ ] Incident response completable from Appsmith (no context-switching)
- [ ] Release approval workflow: &lt;2 min review time
- [ ] DR tests: Automated + results tracked

### Compliance
- [ ] 100% audit trail for privileged operations
- [ ] Emergency access requests trackable + approved
- [ ] Service compliance metadata up-to-date (quarterly refresh)

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|---|---|---|
| Data sync lag between Backstage + Appsmith | Medium | Low | Cache metadata for 1 hour; manual refresh button |
| Portal downtime during incident | Low | Critical | HA setup (3 replicas); DR runbooks can execute without UI |
| Over-reliance on automation (gate failure) | Medium | Medium | Manual override available (requires 2 approvals) |
| Compliance metadata becomes stale | High | Medium | Quarterly audit + email reminders to owners |

---

## Dependencies

- **ADR-002**: Unified identity + RBAC (must be deployed first)
- **Backstage**: open-source, requires GitHub API token
- **Appsmith**: open-source, requires PostgreSQL backend
- **PostgreSQL**: Audit trail storage
- **PagerDuty API**: On-call integration (optional, can use manual assignment)

---

## Implementation Phases

### Phase 1: Backstage Deployment (Week 1-2)
- [ ] Deploy Backstage to 192.168.168.31
- [ ] Integrate with GitHub API (service catalog sync)
- [ ] Create 10 example services in catalog
- [ ] Review + refine Backstage configuration
- [ ] Team training

### Phase 2: Appsmith Deployment (Week 2-3)
- [ ] Deploy Appsmith to 192.168.168.31
- [ ] Integrate with Backstage (metadata pull)
- [ ] Implement incident response dashboard
- [ ] Implement release approval workflow
- [ ] Integrate with AlertManager + GitHub Actions

### Phase 3: Data Synchronization (Week 3-4)
- [ ] Implement GitHub sync (hourly polling)
- [ ] Implement Backstage ← Prometheus (SLO metrics)
- [ ] Implement Appsmith → PostgreSQL (audit logging)
- [ ] Implement Appsmith → PagerDuty (on-call sync)
- [ ] Validate data freshness

### Phase 4: Production & Training (Week 4+)
- [ ] Canary: 10% of incidents routed through Appsmith
- [ ] Monitoring: Alert on portal downtime, data sync lag
- [ ] Team training: How to use incident command center
- [ ] Runbook authoring: How to create automated responses

---

**Next Action**: After ADR-002 IAM approval, schedule architecture review for this ADR.
