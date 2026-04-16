# PHASE 1 IMPLEMENTATION PLAN — MAY 1-31, 2026

**Status**: READY FOR DEPLOYMENT  
**Timeline**: 4 weeks (May 1-31, 2026)  
**Effort**: ~240 hours (3-4 engineer team)  
**Success Criteria**: All Phase 1 components deployed to production + monitored  

---

## PHASE 1 SCOPE

### Track A: Observability (Error Fingerprinting)
**Canonical Issue**: #377 (Telemetry Spine), #378 (Error Fingerprinting)  
**Deliverables**: 
- ✅ Framework design (docs/ERROR-FINGERPRINTING-SCHEMA.md - READY)
- Loki log entry schema implementation
- Prometheus metrics for fingerprints
- Alert rules (new pattern, spike, persistent)
- Grafana dashboard for error trends

**Timeline**: May 1-8 (development) + May 9-15 (testing/deployment)

### Track B: Enterprise Portal
**Canonical Issue**: #385 (Portal Architecture ADR)  
**Deliverables**:
- ✅ Architecture decision (docs/ADR-PORTAL-ARCHITECTURE.md - READY)
- Appsmith deployment (docker-compose)
- OAuth2 integration
- Service catalog seeding
- Documentation hub
- Infrastructure dashboard

**Timeline**: May 1-10 (setup) + May 11-17 (integration/testing)

### Track C: Identity & Access Management
**Canonical Issue**: #382 (IAM Standardization)  
**Deliverables**:
- ✅ Phase 1 design (docs/IAM-STANDARDIZATION-PHASE-1.md - READY)
- oauth2-proxy hardening (PKCE, SameSite, audit logging)
- Grafana/Loki service-specific proxies
- RBAC configuration (5 roles)
- Session backend (Redis)
- Rate limiting

**Timeline**: May 1-10 (setup) + May 11-17 (integration/testing)

---

## IMPLEMENTATION SEQUENCE

### Week 1 (May 1-7): Foundation
- **Monday 5/1**: Kick-off + environment setup
  - [ ] Create deployment branch: `phase-1-deployment`
  - [ ] Review all 3 design docs with team
  - [ ] Assign owners (A, B, C)
  
- **Tuesday-Wednesday 5/2-3**: Loki Error Fingerprinting
  - [ ] Deploy Loki schema changes
  - [ ] Implement SHA256 normalization
  - [ ] Setup test data ingestion
  
- **Thursday 5/4**: Portal + IAM Foundation
  - [ ] Deploy Appsmith container
  - [ ] Configure oauth2-proxy instances
  - [ ] Setup PostgreSQL appsmith_db
  
- **Friday 5/5**: Integration Testing
  - [ ] End-to-end Loki → error fingerprints flow
  - [ ] End-to-end Portal auth integration
  - [ ] Load testing (1000 queries/sec)

### Week 2 (May 8-14): Feature Development
- **Monday 5/8**: Error Fingerprinting Completion
  - [ ] Deploy Prometheus metrics
  - [ ] Alert rules (new pattern, spike, persistent)
  - [ ] Grafana dashboard
  - [ ] Test 10K error logs/day
  
- **Tuesday-Wednesday 5/9-10**: Portal Feature Buildout
  - [ ] Service catalog (seeded with 10+ services)
  - [ ] Infrastructure dashboard
  - [ ] Docs hub (GitHub markdown integration)
  
- **Thursday 5/11**: IAM Phase 1 Completion
  - [ ] oauth2-proxy full hardening
  - [ ] RBAC role configuration
  - [ ] Session management (Redis)
  - [ ] Audit logging pipeline
  
- **Friday 5/12**: Security Hardening
  - [ ] SAST scan (Semgrep)
  - [ ] Dependency vulnerabilities
  - [ ] Container image scanning (Trivy)
  - [ ] Network segmentation validation

### Week 3 (May 15-21): Production Readiness
- **Monday 5/15**: Load Testing
  - [ ] Prometheus error fingerprinting (10K logs/min)
  - [ ] Portal concurrency (100 users)
  - [ ] IAM auth throughput (1000 req/sec)
  - [ ] Loki query performance (&lt;1s for 1M logs)
  
- **Tuesday 5/16**: Failover + HA
  - [ ] Primary (192.168.168.31) full deployment
  - [ ] Replica (192.168.168.42) sync + validation
  - [ ] Failover testing (&lt;30s)
  - [ ] Monitoring verification

- **Wednesday-Thursday 5/17-18**: Documentation
  - [ ] Architecture diagram (Portal + IAM)
  - [ ] Deployment runbooks
  - [ ] Troubleshooting guides
  - [ ] API documentation (error FP queries)
  
- **Friday 5/19**: Pre-Production Review
  - [ ] Code review (all 3 tracks)
  - [ ] Security sign-off
  - [ ] Performance sign-off
  - [ ] Monitoring configuration review

### Week 4 (May 22-31): Deployment + Monitoring
- **Monday 5/22**: Production Deployment
  - [ ] Deploy to primary (192.168.168.31)
  - [ ] Deploy to replica (192.168.168.42)
  - [ ] Smoke tests (basic functionality)
  - [ ] Monitor error rates (target: &lt;0.1%)
  
- **Tuesday-Friday 5/23-26**: Extended Monitoring
  - [ ] Track all 3 metric dashboards
  - [ ] Monitor error patterns (fingerprinting effectiveness)
  - [ ] Track Portal adoption (dashboard views)
  - [ ] Track auth SLO (p99 latency &lt;100ms)
  - [ ] Monitor for any rolling issues
  
- **Friday 5/26**: Phase 1 Completion Review
  - [ ] All acceptance criteria met
  - [ ] All metrics green (SLO maintained)
  - [ ] All runbooks validated
  - [ ] Team trained
  
- **Monday-Friday 5/27-31**: Buffer + Ops Handoff
  - [ ] Production support (on-call rotation)
  - [ ] Known issue triage
  - [ ] Performance optimization (if needed)
  - [ ] Phase 2 planning kickoff

---

## DEPLOYMENT CHECKLIST

### Error Fingerprinting (#378)
- [ ] Loki schema deployed (fingerprint field + normalization rules)
- [ ] Prometheus metrics ingested (fingerprint_count, fingerprint_spike_rate)
- [ ] Alert rules deployed (3 types: new pattern, spike, persistent)
- [ ] Grafana dashboard live (error trends by fingerprint)
- [ ] LogQL queries validated (500+ unique errors detected)
- [ ] PromQL metrics validated (spike alert fires at threshold)
- [ ] Documentation: ERROR-FINGERPRINTING-SCHEMA.md deployed to docs/

### Portal (#385)
- [ ] Appsmith container deployed (docker-compose)
- [ ] PostgreSQL appsmith_db created (schema initialized)
- [ ] oauth2-proxy port 4183 configured
- [ ] Service catalog seeded (10+ services configured)
- [ ] Infrastructure dashboard created (5+ key metrics)
- [ ] Docs hub linked (GitHub markdown auto-import)
- [ ] Grafana integration tested (Prometheus datasource)
- [ ] HTTPS enabled (Caddy termination)
- [ ] Documentation: ADR-PORTAL-ARCHITECTURE.md deployed

### IAM Phase 1 (#382)
- [ ] oauth2-proxy instances deployed (3 service proxies)
- [ ] PKCE enabled on all instances
- [ ] SameSite=Strict cookies enforced
- [ ] Audit logging pipeline active (→ Loki)
- [ ] Redis session backend (DB 0/1/2) configured
- [ ] Rate limiting enabled (10 req/sec per IP)
- [ ] RBAC roles configured (admin, viewer, readonly, developer, audit)
- [ ] Multi-provider fallback ready (Google primary, GitHub secondary)
- [ ] Documentation: IAM-STANDARDIZATION-PHASE-1.md deployed

---

## PRODUCTION SUCCESS CRITERIA (ALL MUST PASS)

### Functional
- ✅ Error Fingerprinting: 500+ unique errors detected + categorized
- ✅ Portal: 10+ services visible + searchable in service catalog
- ✅ IAM: All users authenticated via OAuth2 + RBAC enforced
- ✅ Monitoring: All dashboards live + alarms firing as designed

### Performance
- ✅ Loki query latency (1M log lines): &lt;1 second
- ✅ Portal load time: &lt;2 seconds (cold) + &lt;500ms (warm)
- ✅ IAM auth latency (p99): &lt;100ms
- ✅ Error fingerprinting throughput: 10K logs/minute without backlog

### Security
- ✅ SAST scan: 0 high/critical vulnerabilities
- ✅ Dependency scan: 0 unpatched critical CVEs
- ✅ Container scan: 0 high/critical CVEs in images
- ✅ Network segmentation: Service isolation verified
- ✅ Audit logging: All auth events captured (JSON structured)

### Reliability
- ✅ Uptime: 100% over 7-day monitoring window
- ✅ Error rate: &lt;0.1% (including fingerprinting queries)
- ✅ Failover time: &lt;30 seconds (primary → replica)
- ✅ Data integrity: No fingerprinting data loss during failover
- ✅ Backup: Daily snapshots + hourly WAL archiving

### Operations
- ✅ Runbooks: Documented for all 3 components
- ✅ Incident response: Team trained + drilled
- ✅ SLO targets: Documented + monitored
- ✅ Rollback procedure: Tested (&lt;60 seconds)

---

## ISSUE CLOSURES AFTER PHASE 1

After Phase 1 deployment (May 31, 2026), close/update:

**Close as Complete**:
- #378 (Error Fingerprinting) - Mark complete
- #385 (Portal Architecture) - Mark complete  
- #382 (IAM Standardization Phase 1) - Mark complete

**Defer to Phase 2** (June 1-30):
- #395 (Telemetry Phase 2) - Additional exporters
- #396 (Telemetry Phase 3) - Trace collection
- #397 (Telemetry Phase 4) - APM integration

**Related Issues** (update status):
- #381 (Production Runbooks) - Extend with Phase 1 runbooks
- #379 (Consolidation) - Mark as executed

---

## KNOWN RISKS

| Risk | Probability | Impact | Mitigation |
|------|---|---|---|
| Appsmith CORS issues with oauth2-proxy | Medium | MEDIUM | Pre-test with sample middleware, fallback to Caddy rewrite |
| Error fingerprinting regex performance | Low | HIGH | Test with 100K diverse errors, profile CPU usage |
| IAM session scaling (&gt;1000 users) | Medium | MEDIUM | Monitor Redis memory, implement session cleanup |
| Portal GitHub integration rate limits | Low | MEDIUM | Cache docs list, implement backoff retry |
| Loki disk space on error spike | Medium | MEDIUM | Set retention policy, alert on disk usage &gt;80% |

---

## RESOURCE ALLOCATION

| Resource | Allocation | Effort (hrs) | Owner |
|----------|---|---|---|
| **Track A Lead** (Error FP) | Full-time | 80 | TBD |
| **Track B Lead** (Portal) | Full-time | 100 | TBD |
| **Track C Lead** (IAM) | Full-time | 60 | TBD |
| **QA Lead** | 50% | 40 | TBD |
| **DevOps (deploy/monitor)** | 30% | 30 | TBD |
| **Security Review** | 10% | 10 | TBD |
| **Total** | | 240 | 3-4 engineers |

---

## SUCCESS METRICS (MONTHLY COMPARISON)

### April 2026 (Current State)
- Error fingerprinting: N/A
- Portal: None
- IAM: Basic (oauth2-proxy on code-server only)

### May 2026 (Target Post-Phase 1)
- Error fingerprinting: 500+ unique errors detected + trending
- Portal: Live with 10+ services + infrastructure dashboard
- IAM: All 3 services hardened + audit logging active
- SLO: 99.99% uptime, &lt;0.1% error rate

---

**APPROVALS REQUIRED**: CTO (architecture), Security Lead (IAM), Ops Lead (deployment)

**NEXT STEP**: Week 1 kickoff (May 1, 2026) - all resources allocated + environment ready
