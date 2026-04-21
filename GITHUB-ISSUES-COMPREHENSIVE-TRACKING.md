# GitHub Issues - Comprehensive Tracking Summary
## April 21, 2026

This document provides a complete index of all GitHub issues created to track outstanding work across the code-server repository.

---

## Security & Compliance Issues (P0/P1)

### Critical Security Findings
- **#1051**: P1 - Remediate Security Findings - Private Keys and CVEs
  - Rotate OIDC issuer signing key
  - Rotate phase-2 secrets
  - Rotate OIDC configuration secrets
  - Remove all .env.* files from git history
  - Address CVE-2023-28155 (unpatched request package)
  - **Status**: Open | **Effort**: 6-8 hours

- **#1043**: [SECURITY][trivy] private-key in OIDC_ISSUER_SIGNING_KEY.env:5
- **#1042**: [SECURITY][trivy] private-key in .env.phase-2-additions:6
- **#1041**: [SECURITY][trivy] private-key in .env.oidc:7
- **#1040**: [SECURITY][trivy] CVE-2023-28155 in pnpm-lock.yaml

### Infrastructure Security
- **#1045**: P1 - Terraform Drift Detection - Migrate off static TF state keys to OIDC role auth
  - Implement OIDC-based AWS auth for terraform-drift-detection.yml
  - Migrate post-deploy-certification.yml to OIDC
  - Remove TF_STATE_ACCESS_KEY/TF_STATE_SECRET_KEY references
  - **Status**: Open | **Effort**: 4-6 hours

### Compliance & Audit
- **#1054**: P1 - Compliance and Audit - SOC2/ISO27001 Readiness
  - Create 6 foundational security policies
  - Collect compliance evidence
  - Audit controls verification
  - SOC2/ISO27001 gap analysis
  - **Status**: Open | **Effort**: 20-30 hours

---

## Infrastructure & Operations (P1/P2)

### OPA Policy Conformance
- **#1052**: P1 - OPA Policy Conformance - Fix Policy Service Validation
  - Diagnostic OPA service failures
  - Fix OPA service startup in CI
  - Audit and fix Rego syntax violations
  - **Status**: Open | **Effort**: 3-5 hours

- **#1044**: [AUTO-TRIAGE] OPA policy conformance failure

### Observability & Monitoring
- **#1055**: P2 - Infrastructure Observability - Add Missing Metrics and Dashboards
  - Add postgres_exporter, redis_exporter
  - Add session-broker metrics
  - Create Grafana dashboards (4 new)
  - Add AlertManager rules (4+ alerts)
  - **Status**: Open | **Effort**: 8-12 hours

### Production Deployment
- **#1085**: P1 - Production Deployment Checklist - Phase 2/3/4 IAM Stack
  - Pre-deployment verification (security, infrastructure, code, docs)
  - Hour-by-hour deployment execution plan
  - Post-deployment monitoring (24 hours)
  - Rollback procedures and criteria
  - **Status**: Open | **Effort**: 6-8 hours deployment + 24h monitoring

### Performance & Capacity
- **#1058**: P2 - Performance Optimization - Load Testing and Capacity Planning
  - Create 5 load test scenarios (k6)
  - Establish performance baselines
  - Define capacity planning targets
  - Create performance SLOs
  - **Status**: Open | **Effort**: 14-18 hours

### Incident Response Runbooks
- **#1057**: P2 - Production Readiness Runbooks - Incident Response and Recovery
  - Create 8 critical runbooks:
    - oidc-issuer-recovery.sh
    - session-broker-recovery.sh
    - database-failover.sh
    - network-partition-recovery.sh
    - certificate-renewal.sh
    - secret-rotation-emergency.sh
    - performance-degradation-diagnostic.sh
    - disaster-recovery-exercise.sh
  - **Status**: Open | **Effort**: 16-20 hours

---

## Code Quality & Refactoring (P1/P2)

### Frontend Code Quality
- **#1053**: P1 - Frontend Code Quality - Reduce Cyclomatic Complexity Violations
  - AdminControlsPage refactor (6 sub-components)
  - useWorkspaceState decomposition (4 hooks)
  - Type cleanup and @ts-prune-ignore fixes
  - **Status**: Open | **Effort**: 6-8 hours

### Dependency Management
- **#1050**: P2 - Remove Stale Dependencies - request, request-promise, package-lock.json
  - Audit request/request-promise usage
  - Replace with modern HTTP client (axios/fetch)
  - Remove stale package-lock.json files
  - Verify CVE cleanup
  - **Status**: Open | **Effort**: 8-12 hours

---

## Testing & QA (P2)

### Integration Tests
- **#1056**: P2 - Comprehensive Integration Test Suite - Phase 2/3 JWT and RBAC
  - JWT service auth integration tests (~300 lines)
  - RBAC enforcement integration tests (~250 lines)
  - Failover integration tests (~200 lines)
  - Test utilities and fixtures
  - **Status**: Open | **Effort**: 10-14 hours

### E2E Tests
- **#1057**: P2 - E2E Test Coverage - Matrix Collaboration and Appsmith Portal
  - Matrix homeserver E2E tests (~150 lines)
  - Real-time presence E2E tests (~150 lines)
  - Bridge integration E2E tests (~200 lines)
  - Video integration E2E tests (~150 lines)
  - Appsmith portal access/deployment/datasources E2E tests (~400 lines)
  - Failover E2E tests (~100 lines)
  - **Status**: Open | **Effort**: 16-20 hours

---

## Documentation (P2/P3)

### API Documentation
- **#1059**: P3 - API Documentation - OpenAPI/Swagger Specification
  - OpenAPI 3.0 spec (4500+ lines)
  - Swagger UI deployment
  - API reference guide (800+ lines)
  - Optional: Generate client SDKs (TypeScript, Python, Go)
  - **Status**: Open | **Effort**: 12-16 hours

---

## Summary Statistics

### By Priority
- **P0/P1** (Critical/Blocking): 8 issues
  - Security/Compliance: 4
  - Infrastructure/Ops: 3
  - Code Quality: 1

- **P2** (High/Important): 8 issues
  - Observability: 1
  - Performance: 1
  - Incident Response: 1
  - Dependencies: 1
  - Testing: 2
  - Documentation: 2

- **P3** (Nice-to-have): 1 issue
  - API Documentation: 1

### Total Effort Summary
- **Critical Path (P0/P1)**: ~95-140 hours
- **High Priority (P2)**: ~90-120 hours
- **Nice-to-have (P3)**: ~12-16 hours
- **Total**: ~195-275 hours (5-7 weeks for single engineer)

### By Category
| Category | Issues | Effort | Priority |
|----------|--------|--------|----------|
| Security/Compliance | 4 | 30-45h | P1 |
| Infrastructure/Ops | 6 | 50-80h | P1/P2 |
| Code Quality | 2 | 14-20h | P1/P2 |
| Testing/QA | 2 | 26-34h | P2 |
| Documentation | 2 | 12-16h | P2/P3 |
| **TOTAL** | **16** | **130-195h** | Mixed |

---

## Next Steps (Recommended Execution Order)

### Week 1: Security & Compliance
1. #1051 - Remediate Private Keys (6-8h)
2. #1045 - Terraform OIDC Migration (4-6h)
3. #1052 - OPA Policy Conformance (3-5h)

### Week 2: Infrastructure & Observability
4. #1055 - Infrastructure Observability (8-12h)
5. #1058 - Performance Load Testing (14-18h)

### Week 3: Testing & Deployment
6. #1056 - Integration Tests (10-14h)
7. #1053 - Frontend Code Quality (6-8h)

### Week 4: Runbooks & Documentation
8. #1057 - Incident Response Runbooks (16-20h)
9. #1085 - Production Deployment Checklist (6-8h)

### Week 5+: Extended Work
10. #1050 - Dependency Cleanup (8-12h)
11. #1054 - SOC2/ISO27001 Compliance (20-30h)
12. #1059 - API Documentation (12-16h)

---

## Related Existing Issues

These newly created issues relate to and depend on existing work:

### Completed/In-Progress Epics
- #388: Identity & Workload Authentication Standardization (P1)
  - Dependencies: #1026, #1030, #1025 (Phase 2/3/4)
  - Security: #1051, #1045
  - Testing: #1056
  - Deployment: #1085

- #954: High Availability Architecture (P1)
  - Performance: #1058
  - Observability: #1055
  - Operations: #1057

- #965: Observability & Monitoring (P1)
  - Metrics: #1055
  - Performance: #1058

- #982: QA & Testing Epic (P2)
  - Testing: #1056, #1057

- #793: Security Hardening (P1)
  - Compliance: #1054
  - Security: #1051, #1045

---

## Issue Tracking Dashboard

**Last Updated**: April 21, 2026

### Metrics
- Total Open Issues: 16
- P0/P1 Issues: 8
- P2 Issues: 8
- P3 Issues: 1
- Total Effort: ~195-275 hours

### Critical Path (Must Complete Before Prod)
- #1051 (Security rotation)
- #1045 (Terraform OIDC)
- #1052 (OPA fix)
- #1085 (Deployment checklist)

### Deployment Blocking Issues
- #1051 (if secrets compromised)
- #1052 (OPA validation gate)
- #1085 (pre-deployment checklist)

---

## Notes

1. **All issues include**:
   - Clear acceptance criteria
   - Effort estimates (in hours)
   - Related issue cross-references
   - Priority level and impact

2. **Dependency tree**:
   - Security fixes (#1051) → Deployment (#1085)
   - Observability (#1055) → Monitoring & Incidents
   - Testing (#1056, #1057) → Deployment confidence

3. **Team assignments**:
   - Security/Compliance: Alex Kushnir (kushin77)
   - Infrastructure/Ops: Ops team
   - Frontend/QA: Frontend team
   - Testing: QA team

4. **Success criteria**:
   - All P1 issues resolved before production deployment
   - At least 80% of P2 issues completed
   - Comprehensive documentation and runbooks
   - Team trained and ready for production support

---

## References

- **GitHub Issues**: https://github.com/kushin77/code-server/issues
- **Deployment Guide**: PHASE-2-DEPLOYMENT-GUIDE.md
- **Operations Guide**: docs/governance/
- **Architecture**: docs/architecture/

---

Generated: April 21, 2026
Repository: kushin77/code-server
