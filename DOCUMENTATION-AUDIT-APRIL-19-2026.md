# Documentation Audit Report — April 19, 2026

**Scope**: kushin77/code-server-enterprise  
**Date**: April 19, 2026  
**Auditor**: GitHub Copilot  
**Status**: ACTIVE GAPS IDENTIFIED — 47 items (P0: 8, P1: 15, P2: 18, P3: 6)

---

## Executive Summary

The codebase has **substantial documentation coverage** but exhibits **critical gaps in operational runbooks, compliance documentation, and architecture completion**. Key findings:

- **452 markdown files exist** (mostly process/session docs, legacy artifacts)
- **8 P0-critical gaps** blocking production operations
- **15 P1-high priority gaps** affecting feature completeness
- **18 P2-medium gaps** related to code quality and maintenance
- **6 P3-low gaps** related to nice-to-have enhancements

**Primary Issue**: Lack of single-source-of-truth for key operational procedures, incomplete architecture decisions, and scattered session notes mixed with canonical docs.

---

## P0 — CRITICAL GAPS (Blocking Production Operations)

| File/Location | Gap Type | Missing Content | Impact | Fix Estimate |
|--|--|--|--|--|
| **docs/slos/README.md** | Missing file | SLO definitions, metrics, alerting thresholds | No agreed SLAs for uptime, latency, error rates | 4-6 hrs |
| **docs/ops/README.md** | Incomplete | Missing runbook index, incident response procedures, failover procedures | Operators cannot find/execute critical procedures | 6-8 hrs |
| **docs/DEPLOYMENT-CHECKLIST.md** | Missing file | Pre-deployment validation, post-deployment verification, rollback procedures | Deployments done ad-hoc without verification | 4-6 hrs |
| **docs/INCIDENT-RESPONSE.md** | Missing file | Alert definitions, response procedures, escalation paths, break-glass access | No documented incident procedures | 6-8 hrs |
| **docs/MONITORING-SETUP.md** | Missing file | Prometheus scrape configs, Grafana dashboard setup, AlertManager routing | Monitoring setup is manual/undocumented | 4-6 hrs |
| **docs/DISASTER-RECOVERY-PLAN.md** | Missing file | Backup procedures, restore procedures, RTO/RPO targets, data validation | No documented disaster recovery procedures | 6-8 hrs |
| **docs/COMPLIANCE-CHECKLIST.md** | Missing file | SOC 2 attestation items, GDPR/privacy requirements, audit logging | No compliance tracking or evidence collection | 6-8 hrs |
| **docs/adr/ADR-004-KUBERNETES-MIGRATION.md** | TBD marker | Kubernetes adoption timeline, Container orchestration strategy, Migration plan | Kubernetes path forward undefined | 12-16 hrs |

---

## P1 — HIGH PRIORITY GAPS (Feature Completeness)

| File/Location | Gap Type | Missing Content | Impact | Fix Estimate |
|--|--|--|--|--|
| **docs/TESTING-STRATEGY.md** | Missing file | Unit test requirements, E2E test harness, CI/CD test gates | Test coverage unmeasured, no test standards | 6-8 hrs |
| **docs/API-SPECIFICATION.md** | Missing file | REST API reference, gRPC contracts, client SDKs | No canonical API reference | 8-12 hrs |
| **docs/CONTRIBUTING-TECHNICAL.md** | Incomplete | Code review checklist, commit conventions, PR workflow | CONTRIBUTING.md covers process only, not technical | 4-6 hrs |
| **docs/SECURITY-HARDENING-GUIDE.md** | Missing file | Network policies, secret rotation, access controls | Security procedures scattered across 5+ docs | 8-10 hrs |
| **docs/PERFORMANCE-TUNING.md** | Missing file | Profiling tools, optimization baseline, load test results | No performance baseline or tuning guidance | 6-8 hrs |
| **docs/DATABASE-SCHEMA.md** | Missing file | Full schema, migration procedures, backup/restore | Schema hidden in SQLAlchemy models, no DDL ref | 4-6 hrs |
| **docs/CACHE-STRATEGY.md** | Missing file | Redis configuration, cache invalidation, hot-reload procedures | Cache patterns undocumented | 3-4 hrs |
| **docs/LOGGING-ARCHITECTURE.md** | Missing file | Log levels, structured logging format, retention policy | Logging scattered (Loki, Promtail, file logging) | 6-8 hrs |
| **docs/TRACING-SETUP.md** | Incomplete | OpenTelemetry config, Jaeger query syntax, trace correlation IDs | Tracing code exists but setup guide incomplete | 4-6 hrs |
| **docs/OAUTH2-FLOW-DIAGRAMS.md** | Missing file | Authentication flows, session management, token lifecycle | OAuth2 configured but flows undocumented | 4-6 hrs |
| **docs/RBAC-MATRIX.md** | Missing file | Role definitions, permission inheritance, service account mappings | RBAC implementation exists but matrix not documented | 6-8 hrs |
| **docs/WORKLOAD-IDENTITY.md** | Missing file | Service account provisioning, mTLS setup, token rotation | Workload identity architecture undefined | 8-10 hrs |
| **docs/ENVIRONMENT-SETUP.md** | Incomplete | Dev env bootstrap, local Docker setup, remote SSH setup | setup-state recovery exists but no bootstrap guide | 4-6 hrs |
| **docs/RELEASE-PROCESS.md** | Missing file | Version numbering, changelog format, release checklist | No versioning scheme or release procedure | 4-6 hrs |
| **docs/ROLLBACK-PROCEDURES.md** | Missing file | Rollback triggers, rollback steps, state recovery | Rollback options scattered across multiple docs | 4-6 hrs |

---

## P2 — MEDIUM PRIORITY GAPS (Code Quality & Maintenance)

| File/Location | Gap Type | Missing Content | Impact | Fix Estimate |
|--|--|--|--|--|
| **docs/CODE-QUALITY-STANDARDS.md** | Exists but incomplete | Linting config reference, formatter settings, code review criteria | Standards defined but formatter config not linked | 2-3 hrs |
| **docs/DEPENDENCY-MANAGEMENT.md** | Missing file | Npm/pip/cargo version policies, security scanning, update strategy | Renovate config exists but strategy undocumented | 3-4 hrs |
| **docs/ERROR-HANDLING.md** | Missing file | Error codes, HTTP status mappings, client error responses | Error patterns exist but no reference guide | 4-5 hrs |
| **docs/VALIDATION-RULES.md** | Missing file | Input validation schema, XSS/CSRF protections, field constraints | Validation scattered across multiple services | 6-8 hrs |
| **docs/DATA-RETENTION-POLICY.md** | Missing file | Backup retention, audit log archival, PII data lifecycle | Retention periods undefined | 3-4 hrs |
| **docs/ACCESSIBILITY-GUIDE.md** | Missing file | WCAG 2.1 AA compliance targets, keyboard navigation, screen reader testing | Accessibility standards not defined | 4-6 hrs |
| **docs/LOCALIZATION-STRATEGY.md** | Missing file | i18n approach, language support list, translation workflow | Localization not addressed | 3-4 hrs |
| **docs/CACHING-PATTERNS.md** | Missing file | Cache-aside, write-through, distributed cache patterns | Cache patterns not documented | 3-4 hrs |
| **docs/CIRCUIT-BREAKER-CONFIG.md** | Missing file | Fallback behaviors, recovery thresholds, downstream dependencies | Circuit breaker logic undocumented | 3-4 hrs |
| **docs/RATE-LIMITING.md** | Missing file | Rate limit strategies, quota models, enforcement points | Rate limiting patterns not documented | 3-4 hrs |
| **docs/COST-OPTIMIZATION.md** | Missing file | VM sizing, bandwidth usage, storage optimization | Cost baseline not established | 6-8 hrs |
| **docs/OBSERVABILITY-STANDARDS.md** | Missing file | Metrics cardinality limits, alert tuning, dashboard patterns | Observability standards scattered | 4-6 hrs |
| **docs/FEDERATION-SPEC.md** | Missing file | Identity federation with external systems, cross-tenant access | Federation architecture undefined | 8-10 hrs |
| **docs/MIGRATION-GUIDE.md** | Missing file | Data migration procedures, zero-downtime upgrade path, state consistency | Migration paths not documented | 6-8 hrs |
| **docs/CONFIGURATION-HIERARCHY.md** | Missing file | Config precedence, environment-specific overrides, secret injection | Config layering not documented | 3-4 hrs |
| **docs/PLUGIN-ARCHITECTURE.md** | Missing file | Extension/plugin system design, API contracts, sandbox model | Plugin system not designed | 8-12 hrs |
| **docs/VERSION-COMPATIBILITY.md** | Missing file | Breaking changes policy, deprecation timeline, upgrade matrix | Compatibility policy undefined | 4-6 hrs |
| **docs/NETWORK-POLICIES.md** | Missing file | Firewall rules, service mesh policies, ingress/egress rules | Network policies scattered | 6-8 hrs |

---

## P3 — LOW PRIORITY GAPS (Nice-to-Have)

| File/Location | Gap Type | Missing Content | Impact | Fix Estimate |
|--|--|--|--|--|
| **docs/TROUBLESHOOTING-GUIDE.md** | Missing file | Common issues, diagnostic procedures, log file locations | Users must debug without reference | 6-8 hrs |
| **docs/FAQ.md** | Missing file | Common questions, frequent errors, solutions | No FAQ for common issues | 4-6 hrs |
| **docs/GLOSSARY.md** | Missing file | Technical terms, acronyms, architecture terminology | No centralized vocabulary | 2-3 hrs |
| **docs/EXAMPLES/** | Minimal | Code examples, configuration samples, step-by-step walkthroughs | Only sparse examples exist | 8-12 hrs |
| **docs/TUTORIALS/** | Missing folder | Getting started guide, first deployment, common workflows | No tutorial path | 10-16 hrs |
| **docs/ARCHITECTURE-DIAGRAMS/** | Minimal | System topology, service dependencies, data flow diagrams | Few diagrams; mostly in ADRs | 6-8 hrs |

---

## SECONDARY GAPS (Process & Structure)

### Documentation Structure Issues

| Issue | Details | P-Level |
|--|--|--|
| **Legacy Root-Level Markdown** | 40+ bridge docs at repository root (legacy migration incomplete from #691) | P3 |
| **Session Notes Mixed with Canonical Docs** | `.archived/session-docs/` contains 25+ session summaries; some operational | P2 |
| **Duplicate Guidance** | OAuth2 documented in 5+ files with contradicting details | P2 |
| **Broken Cross-References** | ADR #004 marked TBD but referenced; docs/ folder maps point to non-existent files | P2 |
| **Orphaned Files** | 30+ docs with "Incomplete", "Draft", "TBD" markers but never closed | P2 |
| **No Version Matrix** | No docs showing which versions support which features | P2 |

### Documentation Completeness Checklist

| Category | Status | Example |
|--|--|--|
| **Runbooks** | ⚠️ Partial | E2E provisioning, OLLAMA-GPU exist but no master index |
| **Architecture Decisions** | ⚠️ Partial | ADR-001-003 complete, ADR-004+ TBD |
| **API References** | ❌ Missing | No OpenAPI/REST API spec |
| **Tutorials** | ❌ Missing | No "Getting Started" guide |
| **Deployment Procedures** | ⚠️ Partial | Production guide exists; staging/dev unclear |
| **Troubleshooting** | ❌ Missing | No troubleshooting guide |
| **SLOs/SLAs** | ❌ Missing | No SLO definitions |
| **Performance Baselines** | ❌ Missing | No load test results or latency targets |
| **Security Policies** | ⚠️ Partial | OAuth2, RBAC scattered; no consolidated security guide |
| **Incident Procedures** | ❌ Missing | No incident response runbook |

---

## DETAILED ANALYSIS BY CATEGORY

### 1. Missing Operational Runbooks

**Status**: ⚠️ CRITICAL

Runbooks exist for:
- ✅ E2E provisioning (PLAYWRIGHT-STORAGE-STATE-PROVISIONING-750.md)
- ✅ OLLAMA GPU operations (OLLAMA-GPU-REPLICA-OPERATIONS.md)
- ✅ Portal OAuth bootstrap (PORTAL-OAUTH-GCP-GSM-BOOTSTRAP-695.md)
- ❌ **Missing**: Master runbook index (docs/ops/README.md)
- ❌ **Missing**: On-call procedures
- ❌ **Missing**: Common incident responses
- ❌ **Missing**: Failover procedures

**Fix**: Create docs/ops/README.md with runbook index + create master on-call guide (8 hrs).

---

### 2. Incomplete Architecture Documentation

**Status**: 🔴 CRITICAL

**Existing ADRs**:
- ✅ ADR-001: Containerized Deployment
- ✅ ADR-002: OAuth2 Authentication
- ✅ ADR-003: Terraform Infrastructure
- ❌ **ADR-004**: Kubernetes Migration (marked TBD — never filled)
- ❌ **Missing**: ADR-005+ (federation, plugin model, plugin system)

**Incomplete Architecture Docs**:
- ❌ Identity architecture (PHASE-2-* files reference it but no unified doc)
- ❌ Service-to-service auth (design docs exist, implementation runbook missing)
- ❌ Session isolation (ephemeral-workspace-lifecycle-755.md exists but incomplete)
- ❌ Workload identity (P1-388-* files address it but no consolidated spec)

**Fix**: Consolidate IAM docs into single docs/architecture/IAM-ARCHITECTURE.md (12 hrs).

---

### 3. Missing Compliance & SLO Documentation

**Status**: 🔴 CRITICAL

**What's Missing**:
- ❌ SLO definitions (docs/slos/README.md referenced in GOVERNANCE.md but doesn't exist)
- ❌ Compliance checklist (SOC 2, GDPR, audit logging)
- ❌ Data retention policy (undefined across services)
- ❌ Disaster recovery plan (no RTO/RPO targets)
- ❌ Incident response procedures (no runbook)

**What Exists**:
- ✅ Alert rules (alert-rules*.yml)
- ✅ Governance policy (GOVERNANCE.md)
- ⚠️ Audit logging infrastructure (no SSOP logging retention doc)

**Fix**: Create SLO definitions + compliance checklist (12 hrs).

---

### 4. Missing Testing Documentation

**Status**: 🔴 CRITICAL

**What's Missing**:
- ❌ Test strategy (no canonical test approach doc)
- ❌ E2E test procedures (E2E service account exists but runbook incomplete)
- ❌ Load test baselines (no documented load test results)
- ❌ Coverage targets (no minimum coverage threshold)
- ❌ CI/CD test gates (workflows define tests but no reference guide)

**Partial/Scattered**:
- ⚠️ Vitest configs exist (core-conformance-vitest.json shows 131 tests passing)
- ⚠️ Playwright tests (PLAYWRIGHT-STORAGE-STATE-PROVISIONING-750.md)
- ⚠️ E2E provisioning (E2E-ACCOUNT-PROVISIONING-RUNBOOK-750.md)

**Fix**: Create docs/TESTING-STRATEGY.md + consolidate test runbooks (10 hrs).

---

### 5. Missing API Documentation

**Status**: 🟠 HIGH

**What's Missing**:
- ❌ REST API specification (no OpenAPI/Swagger)
- ❌ gRPC service definitions (proto files exist but no doc)
- ❌ Client library documentation
- ❌ Error code reference
- ❌ Rate limiting policy

**Partial**:
- ⚠️ Apps have API.md files (apps/frontend/API.md) but incomplete
- ⚠️ Code comments have some API descriptions
- ⚠️ Sessions & workspaces have implied APIs

**Fix**: Create docs/API-SPECIFICATION.md + generate OpenAPI spec from code (16 hrs).

---

### 6. Missing Security & Hardening Documentation

**Status**: 🟠 HIGH

**What's Missing**:
- ❌ Security hardening guide (consolidated)
- ❌ Network policies reference (Caddyfile and networking scattered)
- ❌ Secret rotation procedures
- ❌ mTLS setup guide (PHASE-2-2-MTLS-INFRASTRUCTURE.md exists but incomplete)
- ❌ RBAC enforcement procedures (PHASE3-RBAC-ENFORCEMENT-COMPLETE.md exists but no runbook)

**Partial**:
- ⚠️ Caddyfile has TLS config
- ⚠️ ansible/site-hardening.yml exists
- ⚠️ OAuth2 security (docs/adr/002-oauth2-authentication.md)
- ⚠️ RBAC matrix (P1-388-PHASE3 docs reference it)

**Fix**: Consolidate into docs/SECURITY-HARDENING-GUIDE.md (10 hrs).

---

### 7. Incomplete Environment & Deployment Documentation

**Status**: 🟠 HIGH

**What's Missing**:
- ❌ Development environment bootstrap guide (CODE-SERVER-DEV-ENVIRONMENT.md exists but scattered)
- ❌ Staging environment guide
- ❌ Production deployment checklist (PHASE-19-DEPLOYMENT-GUIDE.md too phase-specific)
- ❌ Rollback procedures (ROLLBACK-VALIDATION-CHECKLIST-683.md exists but no consolidated runbook)
- ❌ Zero-downtime deployment guide (ZERO-DOWNTIME-DEPLOY-679.md exists but incomplete)

**Partial**:
- ⚠️ README.md has quick start
- ⚠️ docker-compose.yml is self-documenting
- ⚠️ Multiple environment setup guides scattered (DIRECT-31-NODE-DEVELOPMENT.md, etc.)

**Fix**: Consolidate into docs/DEPLOYMENT-PROCEDURES.md (12 hrs).

---

### 8. Missing Monitoring & Observability Documentation

**Status**: 🟠 HIGH

**What's Missing**:
- ❌ Monitoring setup guide (Prometheus/Grafana/AlertManager config)
- ❌ Tracing setup guide (OpenTelemetry/Jaeger config)
- ❌ Logging architecture (Loki/Promtail configuration)
- ❌ Metrics reference (what metrics are collected, what they mean)
- ❌ Dashboard creation guide (Grafana dashboards exist; no creation guide)

**Partial**:
- ⚠️ Prometheus config (prometheus.yml)
- ⚠️ Alert rules (alert-rules*.yml)
- ⚠️ Correlation ID tracking (correlation-id-audit-fabric-758.md)
- ⚠️ Log aggregation exists (Loki profile in docker-compose.yml)

**Fix**: Create docs/MONITORING-SETUP.md + docs/OBSERVABILITY-STANDARDS.md (14 hrs).

---

### 9. Scattered TODO/FIXME Markers

**Status**: 🟠 HIGH

**Files with Unresolved Markers**:
- [docs/adr/002-oauth2-authentication.md](docs/adr/002-oauth2-authentication.md#L238) — Lines 238-240: "Audit logging: pending log aggregation", "Fallback auth: pending implementation", "Performance: pending load test"
- [docs/adr/001-containerized-deployment.md](docs/adr/001-containerized-deployment.md#L76) — Line 76: "Can migrate to Kubernetes later (ADR-004 TBD)"
- [docs/architecture/iam-standardization.md](docs/architecture/iam-standardization.md#L206-L226) — Lines 206-226: 20+ incomplete checklist items
- [.github/workflows/deploy.yml](.github/workflows/deploy.yml#L22) — Line 22: "TODO: pin all action refs to commit SHAs via Renovate (#358)"
- [src/services/shared-workspace-acl/index.ts](src/services/shared-workspace-acl/index.ts#L482-L600) — Lines 482-600: 3 TODO comments about missing metadata retrieval

**Fix**: Create docs/TODO-TRACKER.md to consolidate and prioritize (6 hrs).

---

### 10. Legacy Documentation Migration (Incomplete)

**Status**: 🟡 MEDIUM

**Issue**: Issue #691 intended to consolidate root-level markdown into docs/ folders but **left 40+ bridge files**:
- `CONTRIBUTING.md` (root, but canonical version exists)
- `GOVERNANCE.md` (root; should migrate to docs/governance/)
- `OAUTH-DEPLOYMENT-STATUS.md`, `OAUTH-PORTAL-FIX-COMPLETE.md`, etc. (40+ operational artifacts)

**Location**: [docs/triage/LEGACY-DOCS-ROOT-INVENTORY-2026-04-18.md](docs/triage/LEGACY-DOCS-ROOT-INVENTORY-2026-04-18.md)

**Impact**: Repository root now contains mixed canonical + bridge + session docs.

**Fix**: Complete #691 migration by moving remaining 40+ files (8-10 hrs).

---

## MISSING DOCUMENTATION BY FILE

### Architecture Files (Missing)

```
❌ docs/SYSTEM-ARCHITECTURE.md          — System topology diagram
❌ docs/architecture/ADR-004-*.md        — Kubernetes migration (TBD)
❌ docs/architecture/ADR-005-*.md        — Federation architecture (TBD)
❌ docs/architecture/DATA-FLOWS.md       — Service data flows
❌ docs/architecture/NETWORK-TOPOLOGY.md — Network architecture
❌ docs/architecture/SERVICE-MESH.md     — mTLS & service mesh
```

### Operational Files (Missing)

```
❌ docs/ops/ON-CALL-PROCEDURES.md              — On-call runbook
❌ docs/ops/INCIDENT-RESPONSE-PLAYBOOKS.md    — Incident procedures
❌ docs/ops/FAILOVER-ORCHESTRATION-RUNBOOK.md — Failover procedures
❌ docs/ops/BACKUP-RESTORE-PROCEDURES.md      — Backup/restore
❌ docs/ops/CAPACITY-PLANNING.md               — Capacity planning
❌ docs/ops/COST-OPTIMIZATION-RUNBOOK.md      — Cost optimization
```

### Compliance Files (Missing)

```
❌ docs/COMPLIANCE-CHECKLIST.md            — SOC 2, GDPR, audit
❌ docs/DATA-RETENTION-POLICY.md           — Data lifecycle
❌ docs/SECURITY-AUDIT-PROCEDURES.md       — Security audit
❌ docs/INCIDENT-RESPONSE-PROCEDURES.md    — Incident procedures
```

### Reference Files (Missing)

```
❌ docs/API-SPECIFICATION.md         — REST/gRPC API reference
❌ docs/GLOSSARY.md                  — Technical terminology
❌ docs/TROUBLESHOOTING-GUIDE.md     — Common issues
❌ docs/FAQ.md                        — Frequently asked questions
```

---

## ANALYSIS: Root Causes

### 1. Session-Driven Development Model
- Each session produces 3-5 new markdown files documenting context
- Files accumulate in `.archived/session-docs/` (25+ files)
- Canonical docs not updated from session findings
- **Result**: Operational knowledge scattered, not consolidated

### 2. Phase-Based Development
- Each "Phase" creates phase-specific docs (PHASE-14, PHASE-15, etc.)
- Phase docs are checkpoints, not canonical references
- **Result**: Historical docs mix with operational docs

### 3. Incomplete Architecture Decisions
- ADR-004 onward marked "TBD" (Kubernetes path undefined)
- Multiple identity architectures (P1-388-*, PHASE-2-*, etc.)
- **Result**: No unified architecture specification

### 4. Issue-Driven Documentation
- GitHub issues spawn docs but docs never consolidate into canonical form
- Issue evidence (XXXX-ISSUE-NUMBER.md) left in docs/ tree
- **Result**: 100+ operational artifacts but no index

### 5. Documentation Structure Mismatch
- Canonical folder structure defined in docs/structure/README.md
- 40+ legacy root files haven't migrated
- Some files in wrong folders (phase docs in docs/ root, not docs/status/)
- **Result**: "Run `ls docs/` and grep for topic" required

---

## RECOMMENDED FIXES (Priority Order)

### Phase 1: Emergency Documentation (1-2 weeks, P0 items)

| # | Document | Owner | Est. Time | Depends On |
|--|--|--|--|--|
| 1 | docs/slos/README.md | SRE | 4 hrs | None |
| 2 | docs/ops/README.md (index + incident procedures) | Ops | 8 hrs | None |
| 3 | docs/DEPLOYMENT-CHECKLIST.md | DevOps | 6 hrs | #1 |
| 4 | docs/INCIDENT-RESPONSE.md | On-call lead | 6 hrs | #1 |
| 5 | docs/MONITORING-SETUP.md | Platform | 6 hrs | #1 |
| 6 | docs/DISASTER-RECOVERY-PLAN.md | Data team | 8 hrs | None |
| 7 | docs/COMPLIANCE-CHECKLIST.md | Security | 6 hrs | None |
| 8 | docs/adr/ADR-004-KUBERNETES-MIGRATION.md | Arch | 12 hrs | None |

**Total**: ~56 hours (~2 weeks for dedicated team)

### Phase 2: Feature Documentation (2-3 weeks, P1 items)

| # | Document | Est. Time |
|--|--|--|
| 1 | docs/TESTING-STRATEGY.md | 8 hrs |
| 2 | docs/API-SPECIFICATION.md (with OpenAPI gen) | 12 hrs |
| 3 | docs/CONTRIBUTING-TECHNICAL.md | 6 hrs |
| 4 | docs/SECURITY-HARDENING-GUIDE.md (consolidate) | 10 hrs |
| 5 | docs/PERFORMANCE-TUNING.md | 8 hrs |
| 6-15 | Other P1 docs (10 @ 6 hrs ea) | 60 hrs |

**Total**: ~104 hours (~3 weeks)

### Phase 3: Maintenance & Migration (1-2 weeks, P2/P3 items)

| # | Task | Est. Time |
|--|--|--|
| 1 | Complete #691 legacy root migration | 10 hrs |
| 2 | Consolidate session docs into canonical locations | 12 hrs |
| 3 | Create TODO tracker and close resolved items | 6 hrs |
| 4 | Create docs/TROUBLESHOOTING-GUIDE.md | 8 hrs |
| 5 | Create docs/EXAMPLES/ folder with 5-10 tutorials | 12 hrs |

**Total**: ~48 hours (~1.5 weeks)

---

## ENFORCEMENT CHECKLIST

To prevent future gaps:

- [ ] **New features require matching docs** (checked in PR code review)
- [ ] **Docs consolidation**: No topic should have >1 canonical doc (checked in PR)
- [ ] **Metadata headers**: All `.md` files at docs root should match standard (checked in CI)
- [ ] **No TODO/FIXME**: All docs should have resolution path (checked in PR)
- [ ] **Cross-references checked**: Links should be tested (new pre-commit hook needed)
- [ ] **Session docs archived**: Move session-completed docs to .archived/ weekly
- [ ] **Quarterly audits**: Review docs/ structure, consolidate duplicates

---

## APPENDIX: File Inventory

### Markdown Files by Category

**Canonical Docs** (should-be single sources of truth):
- docs/README.md ✅
- docs/adr/README.md ✅
- docs/adr/ADR-001-ADR-003.md ✅
- .github/GOVERNANCE.md ⚠️ (should migrate to docs/)
- CONTRIBUTING.md ✅ (but process-only; tech guide missing)

**Process/Phase Docs** (session output, candidates for archival):
- 25+ files in .archived/session-docs/ ✅ (archived appropriately)
- 40+ bridge files at repository root ❌ (incomplete migration)

**Operational Runbooks** (useful but scattered):
- 16 files in docs/ops/ ✅ (but no master index)
- Multiple deployment guides (scattered across docs/) ❌ (should consolidate)

**Architecture Decisions**:
- docs/adr/ (6 files, but ADR-004+ TBD) ⚠️

**Missing Reference**:
- No master index of all 452 markdown files
- No canonical location for API specification
- No canonical location for runbook index

---

## SUMMARY TABLE: Impact × Effort

```
┌──────────────────────────────────────┬────────┬──────────┐
│         DOCUMENTATION TYPE            │ EFFORT │ IMPACT   │
├──────────────────────────────────────┼────────┼──────────┤
│ SLO Definitions                       │ 4 hrs  │ 🔴 Crit  │
│ Incident Response Runbook             │ 6 hrs  │ 🔴 Crit  │
│ Deployment Checklist                  │ 6 hrs  │ 🔴 Crit  │
│ Architecture ADR-004 (Kubernetes)     │ 12 hrs │ 🟠 High  │
│ Testing Strategy                      │ 8 hrs  │ 🟠 High  │
│ API Specification                     │ 12 hrs │ 🟠 High  │
│ Security Hardening Guide              │ 10 hrs │ 🟠 High  │
│ Consolidated Troubleshooting Guide    │ 6 hrs  │ 🟡 Med   │
│ Legacy Root Migration (#691)          │ 10 hrs │ 🟡 Med   │
│ Tutorials & Examples                  │ 12 hrs │ 🟡 Med   │
└──────────────────────────────────────┴────────┴──────────┘

Total: 86 hours (~2.5 weeks for single person)
       or 1 week for team of 3
```

---

## Related Issues

- #691: Legacy docs root migration (incomplete)
- #358: Renovate workflow action pinning (TODO in deploy.yml)
- #388: Identity standardization (P1-388-* docs reference but no single arch)
- #624: Issue-centric workflow (policy defined, enforcement incomplete)

---

**Next Steps**: 
1. ✅ Assign owners to P0 items
2. ✅ Create issues for each missing doc
3. ✅ Update CONTRIBUTING.md with docs requirements
4. ✅ Add pre-commit hook for broken links + TODO markers

**Last Updated**: April 19, 2026  
**Status**: DRAFT — Ready for team review
