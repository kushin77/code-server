# ADR-002: Dual-Portal Architecture Decision (Backstage + Appsmith)

**Status**: ACCEPTED (Decision Record)  
**Date**: 2026-04-23  
**Author**: Platform Engineering Team  
**Issue**: P1 #385 - Portal Architecture  
**Related**: P1 #388 (RBAC), P2 #418 (Terraform), #322 (Backstage), #324 (Appsmith)

---

## Context

We operate a multi-service environment with growing complexity in software discovery, operational workflows, and governance. Previous evaluations identified two complementary portal technologies:

- **Backstage**: Software catalog, service ownership, templates, SLO dashboards, compliance
- **Appsmith**: Operational command center, approvals, incident response, DR triggers

The decision to adopt both requires a clear architectural division of responsibility, integration contracts, and deployment strategy.

---

## Decision

**Adopt a dual-portal architecture where:**

1. **Backstage** owns the **Developer Experience Layer**
   - Single source of truth for software catalog
   - Service ownership and metadata
   - Golden path templates for new services
   - SLO dashboards and service scorecards
   - Compliance and governance artifacts

2. **Appsmith** owns the **Operations Command Center**
   - Release approvals and deployment workflows
   - Incident response actions and runbooks
   - Disaster recovery test triggers
   - On-call management and escalations
   - AI governance controls and audit

3. **Portals integrate via shared RBAC layer** (P1 #388)
   - Single OIDC provider (Google)
   - JWT-based service-to-service auth
   - Role mapping from GitHub teams
   - Audit logging of all actions

---

## Rationale

### Why Dual Portals?

| Concern | Single Portal | Dual Portal |
|---------|---------------|------------|
| **Cognitive Load** | Overloaded UI mixing dev + ops | Clear separation of concerns |
| **Performance** | One portal slow → both suffer | Independent scalability |
| **Team Autonomy** | Shared roadmap conflicts | Independent evolution |
| **Operational Focus** | Backstage → Dev focus | Appsmith → Ops focus |
| **Integration Risk** | Tight coupling | Loose coupling via APIs |

### Why These Technologies?

**Backstage**:
- Industry-standard service catalog
- Extensible template system (TechDocs)
- GitHub/GitLab integration
- Scorecards for compliance
- Growing ecosystem

**Appsmith**:
- Low-code operational dashboards
- Workflow automation (approvals, webhooks)
- Database connectivity (PostgreSQL)
- RBAC and audit trails
- Faster iteration than custom code

---

## Architecture

### High-Level Topology

```
┌─────────────────────────────────────────────────────────┐
│                 API & OIDC Gateway                      │
│  (google auth + oauth2-proxy + JWT token issuance)      │
└─────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
   ┌─────────┐    ┌──────────┐    ┌──────────┐
   │Backstage│    │ Appsmith │    │Code-Server
   │(Catalog)│    │(Ops Ctrl)│    │(IDE)
   └────┬────┘    └────┬─────┘    └────┬─────┘
        │              │               │
        └──────────────┼───────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
    GitHub        PostgreSQL      Observability
    (Catalog)     (State)        (Prometheus, Loki)
```

### Responsibility Matrix (RACI)

| Task | Backstage | Appsmith | Platform | Security |
|------|-----------|----------|----------|----------|
| Service catalog import | **R/A** | C | C | - |
| SLO dashboard | **R/A** | C | C | - |
| Deployment approvals | C | **R/A** | - | C |
| Incident response | C | **R/A** | - | - |
| RBAC policy | C | C | **R/A** | C |
| Audit logging | C | C | **R/A** | C |
| Data sync contract | **A** | **A** | - | - |
| Incident escalation | C | **R/A** | - | C |
| AI governance | C | **R/A** | C | C |

**Legend**: R=Responsible, A=Accountable, C=Consulted, I=Informed

---

## Backstage: Developer Experience

### Responsibilities

**Primary:**
- Software catalog (git repos, services, components, APIs)
- Service ownership (team assignments, contacts, on-call)
- Golden path templates (scaffold new services from templates)
- SLO dashboards (SLIs, error budgets, health status)
- Compliance scorecards (security, reliability, documentation)
- Documentation (TechDocs, architecture decisions)

**Integration Points:**
- GitHub API → discover repos and configure catalog
- PostgreSQL → persist service metadata
- Prometheus → fetch SLO metrics
- Code-Server IDE → direct links to repo
- Appsmith → trigger operational workflows

### User Personas

- **Service Owners**: Manage their service metadata, SLOs, ownership
- **Developers**: Discover services, find owner contacts, view SLOs
- **Platform Team**: Administer catalog, manage templates
- **Compliance Officer**: Review scorecards, audit compliance

### Key Features

1. **Service Registry**
   - Auto-discover from GitHub (org:kushin77/*)
   - Manual registration for non-Git services (databases, APIs)
   - Team assignments and ownership
   - Documentation links

2. **SLO Dashboard**
   - Error rate SLI (target: 99.9%)
   - Latency SLI (target: <200ms p95)
   - Availability SLI (target: 99.99%)
   - Error budget consumption
   - Alerts when approaching exhaustion

3. **Golden Path Templates**
   - New service scaffolding (Next.js, FastAPI, Node.js)
   - CI/CD pipeline templates
   - Dockerfile and K8s manifests
   - GitHub Actions workflows
   - Documentation template

4. **Compliance Scorecards**
   - Security: Has secrets scanning, SBOM, rate limiting?
   - Reliability: Has monitoring, alerting, runbook?
   - Documentation: Has TechDocs, API docs, ADRs?
   - Operational: Has on-call, DR plan, postmortem process?

---

## Appsmith: Operations Command Center

### Responsibilities

**Primary:**
- Release approvals (deployments, database migrations)
- Incident response actions (create incident, notify, escalate)
- Disaster recovery testing (trigger DR drills, verify backups)
- On-call management (schedules, escalations, notifications)
- AI governance (model deployments, usage policy enforcement)
- Workflow automation (webhooks, integrations, custom logic)

**Integration Points:**
- GitHub Actions → trigger workflows
- PostgreSQL → read deployment state
- Slack → send notifications
- PagerDuty → manage on-call
- Prometheus → alert enrichment

### User Personas

- **Release Engineer**: Approve deployments, manage release trains
- **On-Call Engineer**: Triage incidents, execute runbooks
- **SRE**: Monitor health, trigger DR tests
- **Platform Team**: Manage workflows, approve critical changes

### Key Features

1. **Release Approval Board**
   - Pending deployments (to prod, staging)
   - Approval history
   - Rollback capability
   - Change log / deployment notes

2. **Incident Response Dashboard**
   - Create incident (auto-create Slack channel, PagerDuty alert)
   - Customer impact assessment
   - Runbook search and execution
   - Team assignment and escalation
   - Post-incident review automation

3. **Disaster Recovery Control**
   - DR drill scheduler
   - Backup validation
   - Failover testing
   - Recovery time measurement (RTO/RPO verification)

4. **On-Call Management**
   - Current on-call schedule
   - Escalation chains
   - Manual page option
   - Historical metrics (MTTR, escalation rate)

---

## Data Sync & Integration Contract

### Backstage → Appsmith

**Service Catalog Sync**
- Backstage discovers services from GitHub
- Exposes service metadata via API: `/catalog/entities?kind=Component`
- Appsmith fetches catalog hourly
- Appsmith builds release approval workflows per service

**SLO Integration**
- Backstage pulls SLI metrics from Prometheus
- Exposes SLO status via API: `/api/slo/status/{service}`
- Appsmith displays SLO health in incident dashboard
- Red SLO → escalate incident immediately

### Appsmith → Backstage

**Operational Data Sync**
- Appsmith logs deployment events (success/failure)
- Exposes deployment history: `/api/deployments/{service}`
- Backstage displays last deployment timestamp
- Backstage shows reliability impact (SLO vs deployments)

**Incident Data Sync**
- Appsmith logs incident data (duration, impact, resolution)
- Exposes incident history: `/api/incidents/{service}`
- Backstage displays MTTR metrics
- Backstage calculates error budget consumed

### Shared Data (PostgreSQL)

```sql
-- Services table (Backstage primary)
services (
  id, name, owner_team, github_repo, description,
  slo_availability, slo_latency, slo_error_rate,
  updated_at
)

-- Deployments table (Appsmith primary)
deployments (
  id, service_id, version, environment, status,
  deployed_by, deployed_at, change_log
)

-- Incidents table (Appsmith primary)
incidents (
  service_id, title, status, severity, duration,
  impact_users, impact_revenue, root_cause, resolved_at
)

-- SLO events table (shared)
slo_events (
  service_id, timestamp, sli_type, value,
  status (pass/warn/fail), error_budget_consumed
)
```

### API Contract

**Backstage → PostgreSQL**
```
POST /api/services - catalog discovery
GET /api/services/{id} - service metadata
PUT /api/services/{id} - update ownership, SLOs
```

**Appsmith → PostgreSQL**
```
POST /api/deployments - log deployment
POST /api/incidents - create incident
GET /api/services/{id}/slo - fetch SLO status
GET /api/incidents/{service_id} - incident history
```

---

## RBAC Integration (P1 #388)

Both portals authenticate via Google OIDC and validate JWT tokens:

```
┌─────────────────────────────────────────┐
│     Google OIDC                         │
│  accounts.google.com/o/oauth2/v2/auth   │
└──────────────┬──────────────────────────┘
               │
    ┌──────────▼──────────┐
    │ oauth2-proxy        │
    │ (token endpoint)    │
    └──────────┬──────────┘
               │
    ┌──────────▼──────────────────────┐
    │ JWT Token (1-hour TTL)          │
    │ - sub: user@kushnir.cloud       │
    │ - rbac_role: admin/op/viewer    │
    │ - teams: [ai-team, platform]    │
    │ - aud: kushnir77/code-server    │
    └──────────┬──────────────────────┘
               │
    ┌──────────▼──────────────────┐
    │ Backstage & Appsmith        │
    │ Validate JWT signature      │
    │ Check RBAC role             │
    │ Map teams to permissions    │
    └─────────────────────────────┘
```

### Portal Access Control

| Role | Backstage | Appsmith |
|------|-----------|----------|
| **admin** | All features | All features |
| **operator** | Catalog (R/O), SLOs (R/O) | Incident response, escalate |
| **viewer** | Catalog (R/O), SLOs (R/O) | View incidents (R/O) |

---

## External Integrations

### GitHub

**Backstage**:
- OAuth app for authentication
- GraphQL API to discover repos
- Webhooks for catalog updates (push events)
- Pull request creation for config changes

**Appsmith**:
- GitHub API to trigger workflows
- Webhook notifications (deployment status)
- Pull request checks (approval status)

### Slack

**Both Portals**:
- OAuth app for authentication
- Webhook notifications
- Interactive messages (approve/deny)
- Channel management (create incident channels)

### PagerDuty

**Appsmith Only**:
- Incident creation and escalation
- On-call schedule queries
- Notification integration

### PostgreSQL

**Both Portals**:
- Direct read/write access
- Service metadata and deployment state
- Audit logging

---

## Deployment Topology

### Network Architecture

```
┌────────────────────────────────────┐
│  Caddy (Reverse Proxy)             │
│  - TLS termination                 │
│  - Path routing                    │
│  - Rate limiting                   │
└─────────────────┬──────────────────┘
                  │
        ┌─────────┼─────────┐
        │         │         │
        ▼         ▼         ▼
   Backstage  Appsmith  Code-Server
   (port 3000)(port 8080) (port 8080)
        │         │         │
        └─────────┼─────────┘
                  │
        ┌─────────▼──────────┐
        │   PostgreSQL       │
        │   (port 5432)      │
        └────────────────────┘
```

### Kubernetes Deployment (K3s on .31)

```yaml
# Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: portals

---
# Backstage Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backstage
  namespace: portals
spec:
  replicas: 2
  containers:
  - name: backstage
    image: backstage:1.13.0
    ports:
    - containerPort: 3000
    env:
    - name: POSTGRES_HOST
      value: postgresql
    - name: POSTGRES_PORT
      value: "5432"
    - name: GITHUB_TOKEN
      valueFrom:
        secretKeyRef:
          name: github-secrets
          key: backstage-token

---
# Appsmith Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: appsmith
  namespace: portals
spec:
  replicas: 2
  containers:
  - name: appsmith
    image: appsmith:latest
    ports:
    - containerPort: 8080
    env:
    - name: POSTGRES_URL
      valueFrom:
        secretKeyRef:
          name: postgres-secrets
          key: appsmith-dsn
    - name: GOOGLE_OAUTH_ID
      valueFrom:
        secretKeyRef:
          name: oauth-secrets
          key: google-oauth-id
```

### Failover Strategy

**Primary Failure (.31 down)**:
1. Health checks detect primary unavailable
2. Cloudflare LB switches to secondary (.42)
3. Backstage and Appsmith failover to secondary
4. PostgreSQL replica promoted to primary
5. DNS updates cached clients (TTL: 60s)
6. RTO target: <2 minutes

**Graceful Failover**:
- Drain connections: 30s grace period
- Active sessions preserved (JWT tokens remain valid)
- Database connection pool fails over atomically
- No data loss (replication lag < 100ms)

---

## Non-Functional Requirements

### Performance SLOs

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Backstage homepage load** | <1s (p95) | Synthetic monitoring |
| **Catalog search** | <500ms (p95) | Real user monitoring |
| **Service detail page** | <800ms (p95) | RUM |
| **Appsmith dashboard load** | <2s (p95) | RUM |
| **Incident creation** | <500ms (p99) | APM |
| **Portal availability** | 99.9% | Uptime SLA |
| **API latency (p95)** | <100ms | Between portals |

### Scalability Targets

- **Services in catalog**: 10,000+
- **Concurrent users**: 1,000+
- **Deployments per day**: 500+
- **Incidents per month**: 100-200
- **DB transaction rate**: 10,000 TPS

### Security Requirements

- **Authentication**: OAuth 2.0 OIDC (Google)
- **Authorization**: RBAC (3 tiers: admin/operator/viewer)
- **Encryption**: TLS 1.3 for all traffic
- **Secrets**: Vault or GitHub Secrets
- **Audit**: All actions logged with user/timestamp/resource
- **Rate limiting**: 100 req/s per user, 1000 req/s global

### Reliability & DR

- **RTO**: < 2 minutes
- **RPO**: < 5 minutes
- **Backup frequency**: Hourly (PostgreSQL)
- **Backup retention**: 30 days
- **DR test frequency**: Monthly
- **Incident response**: < 15 minute MTTR target

---

## Migration Plan

### Phase 1: Foundation (Week 1-2)
- [ ] Deploy PostgreSQL schema for portals
- [ ] Create GitHub OAuth app for Backstage
- [ ] Create Google OAuth app for Appsmith
- [ ] Deploy Backstage and Appsmith to staging K3s

### Phase 2: Integration (Week 3)
- [ ] Connect Backstage to GitHub (catalog discovery)
- [ ] Connect Appsmith to PostgreSQL
- [ ] Implement service metadata sync
- [ ] Test RBAC role mapping (P1 #388)

### Phase 3: Staging Validation (Week 4)
- [ ] Populate service catalog (100+ services)
- [ ] Create release approval workflows
- [ ] Create incident response workflows
- [ ] Performance testing (99.9% uptime, <1s catalog search)

### Phase 4: Production Rollout (Week 5-6)
- [ ] Production deployment (K3s on .31)
- [ ] Replica (.42) failover testing
- [ ] Gradual user migration (10% → 100%)
- [ ] Monitoring and alerting setup

### Phase 5: Optimization (Week 7+)
- [ ] Golden path templates usage analysis
- [ ] Incident workflow iteration
- [ ] Compliance scorecard expansion
- [ ] AI governance controls rollout

---

## Success Metrics

| KPI | Target | Measurement |
|-----|--------|-------------|
| **Service catalog coverage** | 80%+ services cataloged | Monthly audit |
| **Incident MTTR reduction** | 25% improvement | vs pre-portal baseline |
| **Deployment approval time** | <30 min mean | From request to deploy |
| **Portal uptime** | 99.9% | SLA monitoring |
| **User adoption** | 90% of platform team | Monthly active users |
| **Time to discover service** | <2 min mean | User survey |
| **False positive alerts** | <5% | Incident analysis |

---

## Risk Mitigation

### Risk 1: Data Inconsistency Between Portals
**Mitigation**:
- Service metadata single source of truth (PostgreSQL)
- Hourly sync jobs with idempotent design
- Data validation on every sync
- Monitoring for sync lag

### Risk 2: RBAC Misconfiguration Blocks Users
**Mitigation**:
- Extensive testing of role mappings in staging
- Role definition templates (avoid manual YAML)
- Gradual rollout (10% users first)
- Emergency admin access documented

### Risk 3: Portal Performance Degradation
**Mitigation**:
- Load testing with 10,000+ services
- Database query optimization
- Caching layer (Redis) for catalog
- CDN for static assets (TechDocs)

### Risk 4: GitHub/Slack Integration Failures
**Mitigation**:
- Circuit breakers for external API calls
- Queue-based retry logic (dead letter queues)
- Manual fallback workflows
- Integration health dashboard

---

## Rollback & Downgrade Strategy

### Quick Rollback (< 5 minutes)
- Revert Caddy routing rules
- Switch DNS back to previous endpoint
- Restart services from clean image

### Graceful Shutdown (< 15 minutes)
- Drain active user sessions
- Preserve deployment/incident state in database
- No data loss (DB rollback not needed)

### Full Rollback (if data corruption)
- Restore PostgreSQL from hourly backup
- Restore GitHub catalog from git history
- Manual incident reconciliation

---

## Alternatives Considered

### Alternative 1: Single Portal (Backstage Only)
**Rejected because**:
- Backstage not optimized for operational workflows
- Approval workflows would be bolted-on
- Cognitive load for ops-focused users too high

### Alternative 2: Single Portal (Custom Dashboard)
**Rejected because**:
- No service catalog capability
- High maintenance burden
- Missing compliance scorecard features

### Alternative 3: Monolithic Portal (Merge Backstage + Appsmith)
**Rejected because**:
- Increases complexity for both platforms
- Couples dev and ops lifecycles
- Slower innovation velocity

---

## Dependencies & Related Issues

- **P1 #388**: RBAC enforcement (JWT, role mapping, audit logging)
- **P2 #418**: Terraform consolidation (infrastructure as code)
- **#322**: Backstage evaluation and setup
- **#324**: Appsmith evaluation and setup
- **#327**: Portal data integration and sync

---

## Approval

- [ ] Platform Engineering Lead
- [ ] Security Lead (threat modeling review)
- [ ] SRE Lead (reliability SLOs)
- [ ] Architecture Review Board (ADR process)

---

## Document History

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-04-23 | Platform Team | Initial ADR, accepted |

---

**Status**: ✅ ACCEPTED  
**Next Step**: Begin Phase 1 implementation (PostgreSQL schema + OAuth setup)  
**Owner**: @platform-engineering  
**Review Date**: 2026-05-23 (monthly check-in)
