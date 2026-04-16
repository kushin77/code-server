# ADR-002: Dual-Portal Architecture - Backstage + Appsmith Operational Division

**Status**: ACCEPTED  
**Date**: April 23, 2026  
**Replaces**: NONE  
**Issue**: P1 #385  
**Version**: 1.0.0

---

## Executive Summary

This ADR codifies a dual-portal strategy that divides operational responsibilities between two complementary platforms:

- **Backstage**: Software catalog, service discovery, golden paths, compliance metadata, SLO dashboards
- **Appsmith**: Operational actions, release approvals, incident response, automation workflows, governance controls

The architecture enables independent scaling, different update cadences, and clear ownership boundaries while maintaining unified authentication (OIDC) and integrated audit trails.

---

## Problem Statement

Current state:
- No codified portal strategy; only evaluation in progress
- Unclear ownership of software catalog vs operational workflows  
- Portal services cannot be deployed without approved architecture
- Platform engineering roadmap blocked on architectural decision
- Risk of duplicate functionality or miscommunication about responsibilities

---

## Solution: Dual-Portal Architecture

### Portal Responsibility Matrix (RACI)

| Function | Backstage | Appsmith | Platform | Notes |
|----------|-----------|----------|----------|-------|
| **Software Catalog** | **A,R** | C | I | Backstage owns service registry, metadata, ownership |
| **Golden Path Templates** | **A,R** | C | I | Backstage defines templates, Appsmith uses for automation |
| **Incident Workflows** | C | **A,R** | I | Appsmith owns incident response, escalation workflows |
| **Release Approvals** | C | **A,R** | I | Appsmith coordinates approvals, Backstage provides context |
| **Compliance Metadata** | **A,R** | C | I | Backstage stores GDPR/SOC2 labels, Appsmith enforces |
| **SLO Dashboards** | **A,R** | C | I | Backstage queries Prometheus, Appsmith shows insights |
| **User Onboarding** | **A,R** | C | I | Backstage golden paths, Appsmith automates provision |
| **Feature Flags** | **A,R** | C | I | Backstage defines, Appsmith controls rollout |
| **Observability** | C | **A,R** | I | Appsmith drives on-call, Backstage provides runbooks |

**Legend**: A=Accountable, R=Responsible, C=Consulted, I=Informed

---

## Architecture

### 1. Backstage - Software Catalog & Engineering Platform

**Responsibility**: Single source of truth for all microservices, ownership, compliance, and infrastructure.

#### Core Features
- **Service Registry**: 100% of platform services (code-server, postgresql, redis, prometheus, grafana, jaeger, alertmanager, ollama, etc.)
- **Ownership Model**: Teams assigned to each service (backend, infra, platform, data)
- **Golden Path Templates**:
  - New microservice scaffold (boilerplate + CI/CD)
  - Helm chart template (K8s deployment)
  - API schema (OpenAPI 3.0)
  - SLO definition template
- **SLO/SLI Dashboards**: Real-time health via Prometheus integration
- **Compliance Metadata**:
  - GDPR classification (personal data, retention, location)
  - SOC2 mapping (security, reliability, availability)
  - ISO27001 controls (access, encryption, audit)
  - Data residency tags
- **Documentation Hub**: Runbooks, incident response guides, architecture diagrams
- **API Catalog**: All published APIs with schema, rate limits, authentication

#### Integrations
- **GitHub**: Sync service ownership from GitHub CODEOWNERS, team structure
- **Prometheus**: Query live metrics for SLO/SLI dashboards
- **PostgreSQL**: Store service catalog, metadata, audit logs
- **OAuth2-proxy**: SSO authentication (OIDC)
- **Slack**: Service onboarding notifications, compliance alerts

#### Non-Functional Requirements
- **Availability**: 99.5% SLA (4h annual downtime)
- **RTO**: 15 minutes (from replica)
- **RPO**: 5 minutes (backup-based)
- **Latency**: <500ms p95 for catalog queries
- **Scalability**: Support 10,000+ services, 1,000+ users
- **Data Retention**: Immutable catalog (full history maintained)

#### Deployment
- **Container**: Docker image (hashicorp/backstage)
- **Storage**: PostgreSQL 15+
- **Cache**: Redis 7+ (catalog query cache)
- **Reverse Proxy**: Caddy (TLS termination, rate limiting)
- **URL**: `backstage.kushnir.cloud` (via Cloudflare tunnel)

---

### 2. Appsmith - Operational Command Center

**Responsibility**: Coordinate operational actions, approvals, automations, and governance controls.

#### Core Features
- **Release Management**:
  - Multi-stage promotion (dev → staging → prod)
  - Approval workflows (requires 2x code review)
  - Automated rollback (by service SLO threshold or manual)
  - Deployment audit trail (who, what, when, why)
- **Incident Response**:
  - Runbook execution (run commands on affected services)
  - Stakeholder notification (auto-notify on-call, managers)
  - Status page updates (user comms)
  - Incident timeline and resolution tracking
- **Disaster Recovery**:
  - Failover test triggers (automated weekly)
  - Database restore drills (monthly)
  - Security incident response (credential rotation, logs collection)
- **Feature Flag Control**:
  - Enable/disable flags by service/environment
  - Canary rollout (10% → 25% → 50% → 100%)
  - Instant rollback (if error rate exceeds threshold)
- **AI Governance**:
  - Model switch between Ollama/HuggingFace
  - Cost & quota management (token limits, rate limiting)
  - Usage dashboard and optimization recommendations
- **Compliance Workflows**:
  - GDPR DSAR request automation (data collection, anonymization)
  - SOC2 control testing (automation of periodic controls)
  - Security incident response (containment → investigation → remediation)
  - Offboarding workflows (access revocation, data cleanup)

#### Integrations
- **Backstage API**: Fetch service catalog, owners, runbooks
- **GitHub API**: Create deployments, read commit logs, manage releases
- **PostgreSQL**: Store approvals, audit logs, incident records
- **Kubernetes API**: Deploy services, manage ConfigMaps, tail logs
- **Docker Registry**: Pull images, manage versions
- **Slack**: Notify teams, collect approvals asynchronously
- **PagerDuty**: Fetch on-call schedule, create incidents
- **Prometheus**: Query metrics for SLO thresholds
- **Jaeger**: Fetch trace IDs for incidents
- **S3/Backup**: Trigger database backups, manage snapshots

#### Non-Functional Requirements
- **Availability**: 99.9% SLA (1h annual downtime, critical for prod changes)
- **RTO**: 5 minutes (hot standby)
- **RPO**: 1 minute (streaming replication)
- **Latency**: <200ms p95 for workflow execution
- **Throughput**: 100 concurrent operations (releases, incident actions)
- **Audit Completeness**: 100% of actions logged with correlation ID

#### Deployment
- **Container**: Docker image (appsmith/appsmith)
- **Storage**: PostgreSQL 15+ (audit logs, state)
- **Cache**: Redis 7+ (session storage, rate limiting)
- **Reverse Proxy**: Caddy (TLS termination, auth)
- **URL**: `ops.kushnir.cloud` (via Cloudflare tunnel)

---

## Data Flow & Integration Points

### 1. Unified Authentication (OAuth2-proxy)
```
User → Caddy (oauth2-proxy)
  ↓ (OIDC: Google/GitHub)
  ↓ (returns JWT with roles)
  → Backstage + Appsmith (both validate same JWT)
```

**JWT Claims**:
```json
{
  "sub": "user-id",
  "email": "alice@kushnir.cloud",
  "roles": ["admin", "platform-team"],
  "teams": ["backend", "infrastructure"],
  "aud": "code-server-platform",
  "exp": 1713898000,
  "iat": 1713894400
}
```

### 2. Service Catalog Synchronization
```
Backstage → PostgreSQL (catalog)
          ↓
       Appsmith queries (service info for workflows)
          ↓
       Returns: owner, SLO, compliance tags, runbook URL
```

### 3. Release Workflow
```
Developer (GitHub) → PR merge → Appsmith (detects new commit)
  ↓ (creates release proposal)
  → Backstage (fetches owner, SLO, runbook)
  → Appsmith (collects 2x code review approvals from Slack)
  → Kubernetes (deploys new version)
  → Prometheus (monitors SLO for 5 minutes)
  → [If SLO breach] Auto-rollback
  → Audit trail (PostgreSQL + Slack notification)
```

### 4. Incident Response
```
Alert fires (Prometheus) → Appsmith (creates incident)
  ↓ (queries Backstage for service owner + runbook)
  → Appsmith (notifies on-call via PagerDuty + Slack)
  → Runbook displayed (from Backstage)
  → Actions available (restart, scale, failover)
  → Incident timeline tracked (PostgreSQL)
  → Post-incident review (stored with resolution)
```

---

## Owner Teams

| Portal | Owner Team | Responsibilities |
|--------|-----------|------------------|
| **Backstage** | Platform Engineering | Design, deployment, golden paths, catalog governance, SLO definitions |
| **Appsmith** | SRE + Platform Team | Release workflows, incident automation, runbook management, approval policies |
| **Shared** | Security + Compliance | OAuth2-proxy config, audit logging, GDPR/SOC2 compliance |

---

## Identity & RBAC Model

Both portals enforce the same RBAC model (defined in P1 #388):

### Roles
```
admin
├─ Full access to all portals
├─ Can approve releases, resolve incidents, modify policies
├─ MFA required

operator
├─ Access to Appsmith only (operational actions)
├─ Can execute runbooks, approve release staging only (not prod)
├─ Cannot modify policy
├─ MFA optional

viewer
├─ Read-only access to both portals
├─ Can view catalog, audit logs, incident history
├─ Cannot execute any actions
├─ No MFA required
```

### Service Accounts
```
backstage-sa
├─ Read from GitHub API (org structure, CODEOWNERS)
├─ Read/write PostgreSQL (catalog DB)
├─ Read Prometheus metrics

appsmith-sa
├─ Read from Backstage API (catalog)
├─ Read/write PostgreSQL (approvals, incidents)
├─ Read/write Kubernetes API (deployments)
├─ Write Slack (notifications)
├─ Write GitHub (deployments, releases)
```

---

## Deployment Topology

### High Availability Setup
```
Primary (192.168.168.31)
├─ Backstage pod (x3 replicas)
├─ Appsmith pod (x3 replicas)
└─ PostgreSQL primary (replication to secondary)

Secondary/Failover (192.168.168.42)
├─ Backstage pod (x3 replicas)
├─ Appsmith pod (x3 replicas)
└─ PostgreSQL replica (read-only standby)

Cloudflare Tunnel
├─ backstage.kushnir.cloud → Primary:3001
├─ ops.kushnir.cloud → Primary:3002
└─ Automatic failover to Secondary if primary unavailable
```

### Network Isolation
- Backstage and Appsmith on separate K8s namespaces
- Service-to-service auth via Workload Federation (P1 #388 Phase 2)
- mTLS between portal services (optional, for high-trust networks)

---

## Non-Functional Requirements

### Performance SLOs
| Metric | Target | P95 Latency |
|--------|--------|-------------|
| Service catalog search | 10k services <500ms | <500ms |
| Release approval workflow | <5s per step | <200ms |
| Incident action execution | <2s | <500ms |
| SLO dashboard update | Real-time via Prometheus | <1s |

### Availability SLOs
| Component | Target | RTO | RPO |
|-----------|--------|-----|-----|
| Backstage | 99.5% | 15 min | 5 min |
| Appsmith | 99.9% | 5 min | 1 min |
| Shared PostgreSQL | 99.9% | 5 min | 1 min |

### Scalability
- **Catalog Size**: 10,000+ microservices
- **User Base**: 1,000+ concurrent users
- **Deployment Frequency**: 100+ releases/day
- **Incident Rate**: 50+ incidents/month
- **Audit Log Volume**: 10,000+ events/hour

---

## Migration Path

### Phase 0: Preparation (Week 1)
1. Deploy Backstage and Appsmith to staging environment
2. Populate Backstage with 20% of services (by team)
3. Create test incidents in Appsmith, validate workflows
4. Train platform team on portal usage

### Phase 1: Soft Launch (Week 2)
1. Deploy to production with read-only access
2. Populate Backstage with 50% of services
3. Golden path templates available (no enforcement)
4. Appsmith available for dry-runs (no prod automation)

### Phase 2: Moderate Usage (Week 3-4)
1. Expand Backstage to 100% of services
2. Enable release approvals for non-production deployments
3. Enable SLO monitoring (warnings, no auto-rollback)
4. Incident runbook execution (manual approval required)

### Phase 3: Full Production (Week 5+)
1. Release approvals for production deployments
2. Auto-rollback on SLO breach
3. Incident runbook automation (requires operator role)
4. Feature flag canary rollouts (10% → 100%)

---

## Success Metrics

| KPI | Target | Measurement |
|-----|--------|-------------|
| **Service Coverage** | 100% of microservices in Backstage | Count of services / total services |
| **Owner Assignment** | 100% of services have assigned team | Count with owner / total services |
| **Golden Path Usage** | 80% of new services use templates | Audit trail in GitHub + Backstage |
| **Release Cycle Time** | <1 hour from merge to prod | Appsmith audit logs |
| **Incident MTTR** | Reduce by 25% (from current 30min to 22min) | PagerDuty incident duration |
| **Runbook Accuracy** | 90% of manual runbook steps automated | Incident post-mortems |
| **User Adoption** | 70% of engineers use portals weekly | Backstage access logs |

---

## Dependencies & Blockers

### Blocking Items
- **P1 #388**: Identity & RBAC (Phase 1 COMPLETE, Phase 2-4 DESIGNED)
  - Portal deployment requires OIDC + JWT validation
  - Appsmith automation requires workload identity

### Blocked By
- None (ready to implement immediately)

### Related Issues
- P1 #322: Portal onboarding workflows
- P2 #324: Portal POC and integration testing
- P2 #427: Observability for portals

---

## Rollback & Downgrade Strategy

### If Backstage Unavailable
1. Service catalog reverts to GitHub CODEOWNERS (read-only)
2. Golden paths unavailable (manual scaffolding)
3. SLO dashboards unavailable (fallback to Grafana)
4. **RTO**: 15 minutes (from replica on secondary host)
5. **Mitigation**: Platform team maintains runbooks, documentation always current

### If Appsmith Unavailable
1. Release approvals revert to GitHub pull request review + manual testing
2. Incident response via PagerDuty incident management (manual steps)
3. Feature flag control via kubectl ConfigMap edits (requires terminal access)
4. **RTO**: 5 minutes (hot standby on secondary)
5. **Mitigation**: All workflows have fallback manual procedures documented

### Both Unavailable
1. Service catalog accessible via GitHub API
2. Releases proceed with manual GitHub-based approval workflow
3. Incidents triaged via PagerDuty without automation
4. **RTO**: 5 minutes (failover to secondary host)
5. **Duration**: Should be rare (both require simultaneous failure)

---

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| Unauthorized release approval | RBAC enforcement, 2x code review requirement, audit trail |
| Incident runbook misuse | MFA for admin, approval gates for destructive actions |
| Privilege escalation | OIDC token rotation, no long-lived tokens, service account isolation |
| Data exfiltration (service catalog) | GDPR compliance via P1 #388, DSAR automation in Appsmith |
| Audit log tampering | PostgreSQL immutable table design, S3 archival after 90 days |
| Runaway automation | Rate limiting, cost budgets, per-service quotas |

### Compliance Mapping

- **GDPR**: Service catalog metadata includes personal data classification, DSAR workflows in Appsmith
- **SOC2**: Audit logging (100% coverage), access control (RBAC), incident management (Appsmith)
- **ISO27001**: Identity management (OIDC), access control (RBAC), audit trails

---

## Operational Procedures

### Accessing Portals
```bash
# Backstage (software catalog)
https://backstage.kushnir.cloud

# Appsmith (operational command center)
https://ops.kushnir.cloud

# Both require OIDC login (Google/GitHub)
# Roles assigned via GitHub teams (P1 #388)
```

### Adding a Service to Backstage
1. Create `backstage.yaml` in service repository (at root)
2. Specify service metadata (owner, SLO, compliance tags)
3. Commit to main branch
4. Backstage auto-syncs from GitHub (5-minute interval)
5. Service appears in catalog with golden path

### Creating a Release via Appsmith
1. Merge PR to main branch (triggers CI/CD)
2. Appsmith creates release proposal (shows service info from Backstage)
3. Post approval request in Slack (requires 2x code reviews)
4. Once approved, Appsmith deploys to staging
5. Prometheus monitors SLO for 5 minutes
6. If healthy, prompts for production approval
7. Manual approval required for production deployment
8. Audit trail recorded with all approvals

### Responding to Incident via Appsmith
1. Prometheus alert fires → Appsmith creates incident
2. Backstage queried for: service owner, runbook, SLO
3. Appsmith notifies on-call via PagerDuty + Slack
4. Incident commander runs runbook actions from Appsmith UI
5. Status page auto-updated (or manual update)
6. Post-incident review recorded in Appsmith audit logs

---

## Review Checklist

- [x] Backstage and Appsmith responsibilities clearly divided (no overlap)
- [x] RACI matrix defined (accountable owner for each function)
- [x] Data flows documented (catalog sync, release automation, incident response)
- [x] Identity and RBAC model linked to P1 #388
- [x] Deployment topology supports HA failover (both hosts)
- [x] Non-functional requirements specified (SLOs, latency, scalability)
- [x] Migration plan documented (5 phases, gradual rollout)
- [x] Success metrics quantified (adoption, MTTR reduction)
- [x] Rollback procedures documented for both partial and full failures
- [x] Security threat model and compliance mapping complete
- [x] Operational procedures for common tasks (add service, release, incident)
- [x] Owner teams assigned (Platform Eng, SRE, Security)

---

## Decision

**ACCEPTED**: Dual-portal architecture (Backstage + Appsmith) with clear responsibility division.

**Rationale**:
- Enables independent evolution of each portal
- Clear ownership boundaries prevent miscommunication
- Reuses proven tools (Backstage from Spotify, Appsmith as low-code platform)
- Integrates with existing systems (OIDC, Prometheus, Kubernetes, GitHub, Slack)
- Scalable to 10k+ services and 1000+ users
- Compliance-by-design (GDPR, SOC2, ISO27001)

**Implementation Plan**:
1. Deploy to staging environment (this week)
2. Populate with test data and validate workflows
3. Train platform team on operations
4. Soft-launch to production (read-only Backstage, dry-run Appsmith)
5. Gradual rollout over 5 weeks to full production automation

**Timeline**: Ready to implement immediately after P1 #388 Phase 1 is merged.

---

**Approved By**: [Platform Engineering Lead, SRE Lead, Security Lead - to be filled during review]

**Reviewed By**: [Reviewers TBD]

**Date Approved**: [To be filled]

---

## References

- [Backstage Documentation](https://backstage.io/docs)
- [Appsmith Documentation](https://docs.appsmith.com)
- [P1 #388: Identity & RBAC](https://github.com/kushin77/code-server/issues/388)
- [P2 #324: Portal POC](https://github.com/kushin77/code-server/issues/324)
- [ADR-001: Cloudflare Tunnel Architecture](https://github.com/kushin77/code-server/blob/main/docs/ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md)
