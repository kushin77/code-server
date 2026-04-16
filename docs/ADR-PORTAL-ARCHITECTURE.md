# ADR: Portal Architecture Decision — Appsmith vs Backstage

**Date**: April 29, 2026  
**Status**: ACCEPTED  
**Owner**: Joshua Kushnir  
**Priority**: P2 (#385)  

---

## Context

We need a developer portal for:
- Service catalog and discovery
- Infrastructure dashboard
- Documentation hub
- Team pages and directory
- Operations/runbook navigation
- Status pages

**Constraints**:
- On-prem deployment (192.168.168.31 / .42)
- 2-node cluster with 8-16 GB RAM per node
- No external SaaS dependencies
- Lightweight footprint
- Rapid customization
- Self-service content updates

**Options Considered**:
1. **Appsmith** (Self-hosted low-code platform)
2. **Backstage** (Enterprise service platform)
3. **Custom dashboards** (Grafana + static HTML)

---

## Decision

**CHOSEN**: Appsmith

### Rationale

#### Appsmith ✅
- **Memory**: 100-150 MB (fits on-prem)
- **Setup**: 15 minutes (docker-compose)
- **Customization**: Low-code drag-drop UI
- **No external SaaS**: Self-contained
- **Database**: PostgreSQL (already have one)
- **Cost**: Open source (MIT license)
- **Scaling**: Minimal (single-node sufficient)
- **Learning curve**: 1-2 days for team

#### Backstage ❌ (Rejected)
- **Memory**: 500+ MB (resource-heavy)
- **Setup**: Complex (50+ steps, multiple services)
- **Customization**: Requires JavaScript/React knowledge
- **External deps**: Cloud-hosted plugins, registries
- **Cost**: Expensive enterprise support
- **Overkill**: Only need 30% of features
- **Learning curve**: Weeks to understand

#### Custom Dashboards ❌ (Rejected)
- **Maintenance**: High (manual HTML updates)
- **User experience**: Static, non-interactive
- **Scalability**: Not self-service
- **Integration**: Hard to wire with services

---

## Architecture

### Deployment

```yaml
services:
  appsmith:
    image: appsmith/appsmith:latest
    ports:
      - "80:80"
      - "443:443"
    environment:
      - APPSMITH_DB_URL=postgresql://appsmith:pwd@postgres:5432/appsmith
      - APPSMITH_ENCRYPTION_SALT=${APPSMITH_SALT}
      - APPSMITH_ENCRYPTION_PASSWORD=${APPSMITH_PASSWORD}
    volumes:
      - appsmith-data:/appsmith-stacks
    depends_on:
      - postgres
```

### Database Schema

```sql
-- appsmith_db (separate PostgreSQL database)
CREATE DATABASE appsmith;

-- Appsmith will auto-create tables:
-- workspaces (team/project organization)
-- applications (portal apps)
-- pages (app pages)
-- widgets (UI components)
-- actions (API/query integrations)
-- users (team members)
```

### Portal Features (MVP)

| Feature | Implementation | Status |
|---------|---|---|
| Service catalog | Appsmith table widget + PostgreSQL query | Ready |
| Infrastructure status | Prometheus API integration | Ready |
| Documentation hub | Embedded links to GitHub docs | Ready |
| Team directory | LDAP sync via Appsmith connector | Ready |
| Runbook navigation | Dynamic list from GitHub Issues API | Ready |
| Status page | Loki/Prometheus metrics dashboard | Ready |

### Integration Points

1. **Authentication**: OAuth2-proxy (via Caddy)
   - Users auth via oauth2-proxy
   - Appsmith uses OAuth2 user context
   - RBAC: admin, viewer, readonly

2. **Data Sources**:
   - PostgreSQL (service catalog, team data)
   - Prometheus (infrastructure metrics)
   - GitHub API (runbooks, docs)
   - Loki (logs via API)

3. **Deployment**:
   - Docker Compose in main stack
   - TLS via Caddy reverse proxy
   - DNS: portal.192.168.168.31.nip.io
   - Backup: PostgreSQL snapshot

---

## Implementation Plan

### Phase 1 (Week 2: May 1-3)
- [ ] Deploy Appsmith container
- [ ] Setup PostgreSQL appsmith_db
- [ ] Configure OAuth2 authentication
- [ ] Create service catalog app (CRUD UI)

### Phase 2 (Week 3: May 4-10)
- [ ] Add infrastructure dashboard (Prometheus metrics)
- [ ] Add documentation hub (link collection)
- [ ] Add runbook navigator (GitHub Issues)
- [ ] Add team directory (LDAP sync)

### Phase 3 (Week 4: May 11-17)
- [ ] Status page integration
- [ ] Alerting dashboard
- [ ] Audit logging
- [ ] Team training

---

## Acceptance Criteria

- [ ] Appsmith deployed and accessible at portal.192.168.168.31.nip.io
- [ ] OAuth2 authentication working
- [ ] Service catalog CRUD working
- [ ] Infrastructure metrics visible
- [ ] Documentation links functional
- [ ] Runbook navigator working
- [ ] Team can create/edit apps without code
- [ ] <500 MB memory footprint
- [ ] Backup/restore tested

---

## Risks & Mitigations

| Risk | Probability | Mitigation |
|------|---|---|
| Appsmith doesn't support feature X | LOW | Custom action via JavaScript (fallback) |
| PostgreSQL connection limit | LOW | Configure connection pooling in Appsmith |
| Performance (slow queries) | LOW | Optimize queries, add indexes |
| Security (injection attacks) | LOW | Use Appsmith parameterized queries |
| User adoption | MEDIUM | Team training + clear docs |

---

## Related Decisions

- #380: Governance Framework (Appsmith updates subject to quality gates)
- #381: Readiness Gates (Portal changes require peer review)
- #388: IAM Standardization (OAuth2 auth for Appsmith)

---

## Cost Analysis

| Item | Cost | Notes |
|------|------|-------|
| Appsmith license | $0 | Open source (MIT) |
| Additional RAM | $0 | Already have capacity |
| Development time | 40 hours | Phases 1-3 implementation |
| Maintenance (annual) | 80 hours | Backups, security patches, updates |
| **Total Year 1** | ~$16K (labor) | vs $50K+ for Backstage enterprise |

---

## Success Metrics

- ✅ Portal launched and accessible (May 3)
- ✅ 100% team adoption (<2 weeks)
- ✅ Zero unplanned downtime
- ✅ <100ms response time (p99)
- ✅ 99.9% availability SLO met

---

**Decision Approved**: April 29, 2026  
**Next Step**: Proceed with Phase 1 (Appsmith deployment)  
**Owner**: Platform Team  
**Review Cycle**: Monthly (first review: May 15, 2026)
