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

- **Backlog/Future** (Post Phase 2/3/4): 90+ collaboration feature issues
  - 8 major epics (Collab-1 through Collab-8)
  - 90+ individual feature stories

### Total Effort Summary (Core Work - Phases 1-4)
- **Critical Path (P0/P1)**: ~95-140 hours
- **High Priority (P2)**: ~90-120 hours
- **Nice-to-have (P3)**: ~12-16 hours
- **Core Work Total**: ~195-275 hours (5-7 weeks for single engineer)

### Collaboration Features Roadmap (Future)
- **Total Effort**: ~615-915 hours (12-18 weeks)
- **Status**: Post-Phase 2/3/4 backlog
- **Issues**: 90+ features across 8 epics

### By Category (Core Work Only)
| Category | Issues | Effort | Priority |
|----------|--------|--------|----------|
| Security/Compliance | 4 | 30-45h | P1 |
| Infrastructure/Ops | 6 | 50-80h | P1/P2 |
| Code Quality | 2 | 14-20h | P1/P2 |
| Testing/QA | 2 | 26-34h | P2 |
| Documentation | 2 | 12-16h | P2/P3 |
| **CORE TOTAL** | **16** | **130-195h** | Mixed |
| **Collaboration (Future)** | **90+** | **615-915h** | P3/Backlog |

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

## Collaboration Features Roadmap (Future Phases)

The following 90+ issues represent the full product roadmap for collaborative IDE features:

### EPIC [Collab-1]: Real-Time Co-Editing Engine - CRDT-based concurrent file editing (#1071)
- #1072: Cursor & selection presence broadcast in shared editor
- #1073: Collaborative undo/redo history tree with per-user attribution
- #1074: Document conflict resolution UI with 3-way merge visualization
- #1076: Session hand-off protocol - transfer live coding session to another user
- #1077: Workspace forking - branch current state for exploratory work
- #1078: File advisory lock system for binary assets
- #1079: Live 'what changed while you were away' workspace diff
- #1080: Shared clipboard with cross-user paste history
- #1081: Collaborative breakpoint & debug session sharing
- **Status**: Roadmap | **Effort**: ~80-120 hours total

### EPIC [Collab-2]: Inline Code Comment Threads - GitHub PR-style on live code (#1082)
- #1083: Voice channel integration embedded in IDE sidebar
- #1084: Screen share + annotation overlay within IDE
- #1086: Async video message recording attached to code locations
- #1087: Shared AI Copilot context - team sees same conversation thread
- #1088: @mention system linking team members to code locations
- #1089: Code review request flow embedded in IDE
- #1090: Thread-per-function: persistent discussion tied to code sections
- #1091: Meeting mode - focus indicator + automatic DND during calendar events
- #1092: Async standup bot - AI-generated summaries from code activity
- **Status**: Roadmap | **Effort**: ~70-100 hours total

### EPIC [Collab-3]: AI Conflict Prediction & Resolution (#1093)
- #1094: AI-powered pair programming co-pilot with context awareness
- #1095: 'Who knows this code' expertise heatmap from git history
- #1096: Collaborative prompt library - shared team prompts for AI
- #1097: LLM knowledge extraction from past sessions into team wiki
- #1098: AI code review router - auto-assign to optimal reviewer
- #1099: AI debugging co-pilot with shared debug session state
- #1100: Automated test generation from pair session activity
- #1101: Semantic code search shared across team - unified knowledge base
- **Status**: Roadmap | **Effort**: ~60-90 hours total

### EPIC [Collab-4]: Rich Presence System - real-time team activity awareness (#1103)
- #1104: Focus/flow state detection with DND propagation
- #1105: Time zone overlay on team member presence cards
- #1106: Availability calendar integration (Google Cal/Outlook)
- #1107: Live team activity feed - stream of significant coding events
- #1108: Notification routing - IDE alerts to Slack/Matrix based on context
- #1109: 'Borrow a brain' async help request queue
- #1110: Code ownership graph visualization
- #1111: Team health dashboard - coding velocity, flow time, collaboration metrics
- #1112: Workspace map - visual overview of all active sessions and file locations
- **Status**: Roadmap | **Effort**: ~75-110 hours total

### EPIC [Collab-5]: Session Recording & Playback for onboarding and review (#1113)
- #1114: Workspace templates with pinned extensions, settings, and configurations
- #1115: Workspace hibernation and fast wake on demand (< 5 seconds)
- #1116: Per-project resource quotas with cgroup enforcement
- #1117: Guest sessions - scoped read-only access with time limits
- #1118: Session cost tracking per user and project for chargeback
- #1119: Hot workspace switching with state preservation < 200 ms
- #1120: PR preview environments auto-provisioned on branch push
- #1121: Persistent session snapshots with full restore
- #1122: One-click environment reproducibility with devcontainer helpers
- **Status**: Roadmap | **Effort**: ~85-125 hours total

### EPIC [Collab-6]: Zero-Trust Network Access layer for workspace connectivity (#1123)
- #1124: Code egress DLP - detect and block credential/PII leakage
- #1125: Workspace isolation with gVisor for untrusted code execution
- #1126: SOC2-grade immutable audit log for all file operations
- #1127: End-to-end encryption for all collaboration messages
- #1128: Git commit signing enforcement with Sigstore/Gitsign
- #1129: IP allowlist per workspace with violation alerting
- #1130: Ephemeral short-lived credentials per workspace session
- #1131: Workspace forensics mode - immutable session recording for incident response
- #1132: Collaborative security code review with SAST inline annotations
- **Status**: Roadmap | **Effort**: ~90-140 hours total

### EPIC [Collab-7]: Universal keyboard shortcut manager with team-shared profiles (#1133)
- #1134: Private org extension registry with version pinning
- #1135: Smart workspace auto-configuration from repo manifest
- #1136: Integrated API explorer with live request builder and history
- #1047: Database browser embedded in IDE with shared query history
- #1048: Integrated API explorer with live request builder and history
- #1049: Database browser embedded in IDE with shared query history
- #1050: IDE performance profiler showing per-extension overhead
- #1051: Dependency impact graph - visualize change blast radius
- #1052: Customizable status bar tiles with team metrics
- #1053: Multi-root workspace manager with per-project profiles
- **Status**: Roadmap | **Effort**: ~70-105 hours total

### EPIC [Collab-8]: Distributed tracing for all collaboration events end-to-end (#1057)
- #1058: SLO/SLA dashboard for collaboration sync guarantee < 100 ms
- #1059: Real-time WebSocket connection health monitoring
- #1060: User journey funnel analytics for collaboration onboarding
- #1061: Collaboration session replay in Grafana - full event timeline
- #1062: Capacity planning dashboard for session growth forecasting
- #1063: Anomaly detection for unusual access patterns in sessions
- #1064: DORA metrics dashboard for engineering velocity
- #1065: Synthetic monitoring for collaboration features with alerting
- **Status**: Roadmap | **Effort**: ~65-100 hours total

### Collaboration Features Summary
- **Total Epics**: 8 (Collab-1 through Collab-8)
- **Total Feature Issues**: 90+
- **Total Effort**: ~615-915 hours (12-18 weeks for 1 FTE)
- **Status**: Roadmap/Backlog (Post Phase 2/3/4 delivery)
- **Priority**: P3 (Future phase after core infrastructure stabilization)

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

### Collaboration Features Epics (Backlog)
- #1071-#1082-#1093-#1103-#1113-#1123-#1133-#1057: Full collaboration roadmap (90+ feature issues)

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
