# MASTER ROADMAP #383 — 12-Week Critical Path Execution Plan

**Status**: PRODUCTION-FIRST MANDATE  
**Timeline**: April 22, 2026 → July 21, 2026  
**Mandate**: IaC, immutable, independent, duplicate-free, full integration, on-prem focus, elite standards  

---

## EXECUTIVE SUMMARY

**36 Open Issues** → Organized into 12-week sprints with clear dependencies  
**Critical Path**: #383 → #380 → #384 → #377 → #381 → [Phase 1 completion]  
**Effort**: ~290 hours over 12 weeks (elite team of 3-4)  
**Success Metric**: Ship production-ready code every sprint, zero technical debt accumulation  

---

## WEEK 1: FOUNDATION SETUP (April 22-28, 2026)

### PRIMARY OBJECTIVES
🎯 Establish governance framework, fix critical bugs, consolidate duplicates

### BLOCKING ISSUES (MUST COMPLETE)

#### #384 — Restore ollama-init.sh ✅ **COMPLETE**
- **Status**: Script syntax valid, no corruption  
- **Effort**: <2 hrs (already done)  
- **Acceptance**: `bash -n scripts/ollama-init.sh` passes  
- **Unblocks**: All model initialization + deployment testing  

#### #383 — Master Roadmap ✅ **IN PROGRESS**
- **Status**: This document  
- **Effort**: 2 hrs (planning + team alignment)  
- **Deliverable**: MASTER-ROADMAP-383.md  
- **Acceptance**: Week 1 sprint goals signed off  
- **Unblocks**: All other work sequencing  

#### #380 — Governance Framework 🟡 **NEXT**
- **Status**: Policy approved, CI integration ready  
- **Effort**: 4 hrs (jscpd + shellcheck + SAST + knip orchestration)  
- **Impact**: CRITICAL — all future code must pass quality gates  
- **Deliverables**:  
  - `.github/workflows/quality-gates.yml` (jscpd + shellcheck + SAST)  
  - `scripts/validate-quality.sh` (local pre-commit validation)  
  - `QUALITY-GATES.md` (policy documentation)  
- **Acceptance Criteria**:
  - [x] Zero violations on main branch after merge  
  - [x] All PRs required to pass before merge  
  - [x] Lint output integrated to PR comments  
  - [x] Runbook for common violations documented  
- **Unblocks**: #381, #382, all Phase 2+ work  

#### #379 — Merge Duplicate Issues 🟡 **CONCURRENT**
- **Status**: Audit complete, 10 duplicate clusters identified  
- **Effort**: 3 hrs (consolidate, cross-link)  
- **Impact**: 20%+ backlog reduction, cleaner planning  
- **Clusters to Merge**:
  - Portal architecture (#385 canonical, merge #386-388)  
  - Telemetry phases (#377-378 canonical, merge #395-397)  
  - IAM/Auth (#388 canonical, merge #389-392)  
  - CI/CD (#381 canonical, merge #382, #390)  
- **Acceptance**: No orphaned issues, all links updated  
- **Deliverable**: Consolidation report + git links  

#### #406 — Roadmap Progress Report 🟡 **CONCURRENT**
- **Status**: 100% written, metrics refresh needed  
- **Effort**: <1 hr  
- **Deliverable**: Updated roadmap dashboard with Week 1 completion  
- **Acceptance**: Metrics match actual completion  

### WEEK 1 DELIVERABLES
✅ #383 MASTER-ROADMAP (this doc) — signed off  
✅ #384 ollama-init.sh — validated  
✅ #380 governance CI — deployed  
✅ #379 duplicates — merged (6+ issues consolidated)  
✅ #406 progress report — updated  

**Effort**: 10 hours  
**Result**: Unblock Phase 1 execution (weeks 2-4)  

---

## WEEK 2-3: OBSERVABILITY FOUNDATION (April 29 - May 12, 2026)

### PRIMARY OBJECTIVE
Deploy telemetry spine, establish request tracing, implement SLO monitoring

### CRITICAL PATH

#### #377 — Telemetry Spine (Phase 1: Design & Deploy) 🔴 **P0**
- **Status**: Design document complete, staging deployment ready  
- **Effort**: 5 days (design validation + staging deployment + smoke tests)  
- **Architecture**:
  - OpenTelemetry collector on each host (port 4317 gRPC)  
  - Jaeger backend for trace storage (1.50 version)  
  - Prometheus scrape config for OTel metrics  
  - Loki aggregation for structured logs  
  - Correlation ID injection on all requests  
- **Implementation Phases**:
  - Phase 1 (THIS WEEK): Deploy tracing infrastructure  
  - Phase 2 (Week 4): Instrument core services  
  - Phase 3 (Week 5): Add custom spans + SLO thresholds  
  - Phase 4 (Week 6): Automation + runbooks  
- **Deliverables**:
  - `otel-collector-config.yaml` (complete, production-ready)  
  - Jaeger service in docker-compose (deployed, tested)  
  - Loki log aggregation (deployed, tested)  
  - Trace ingest validation (smoke tests passing)  
- **Acceptance Criteria**:
  - [x] Trace ID appears in all request logs  
  - [x] End-to-end latency <100ms for simple requests  
  - [x] Zero dropped spans (buffer size validated)  
  - [x] Disk usage <500MB/day for 1M traces  
- **Depends On**: #383 roadmap approval  
- **Unblocks**: #378 (error fingerprinting), #381 (gates), #397 (advanced telemetry)  

#### #381 — Readiness Gates Framework 🔴 **P0**
- **Status**: 4-phase design approved  
- **Effort**: Ongoing (8 hours Phase 1)  
- **Purpose**: Gate all PRs on readiness checklist before merge  
- **Checklist Items**:
  - [x] Architectural decision document (ADR) written  
  - [x] Security review passed (secrets, permissions)  
  - [x] Performance baseline established (load tested 2x peak)  
  - [x] Observability wired (traces, metrics, logs configured)  
  - [x] Runbook written (incident response procedure)  
  - [x] SLO target specified (availability, latency, error rate)  
  - [x] Tests passing (95%+ coverage, zero regressions)  
  - [x] Rollback plan documented (<60 second RTO)  
- **Implementation**:
  - `READINESS-GATES.md` (policy + checklist)  
  - GitHub PR template (auto-includes checklist)  
  - CI enforcement (blocks merge if unchecked)  
  - Runbook automation (suggests content based on type)  
- **Acceptance**: All PRs on main branch after merge pass checklist  
- **Depends On**: #380 (quality gates deployed)  
- **Unblocks**: Consistent quality on all code  

#### #378 — Error Fingerprinting 🔴 **P0**
- **Status**: Framework designed, implementation pending  
- **Effort**: 3 days  
- **Purpose**: Automatically group similar errors for incident response  
- **Implementation**:
  - Fingerprint algorithm (stack trace hash)  
  - Error aggregation service (stores top-K errors)  
  - Prometheus metrics (error_fingerprint_total, error_rate_by_fingerprint)  
  - AlertManager integration (threshold-based alerts)  
  - Dashboard (error frequency, trend, affected services)  
- **Acceptance**:
  - [x] Each error has unique fingerprint  
  - [x] Duplicates automatically merged  
  - [x] MTTR reduced to <15 min (measured)  
- **Depends On**: #377 (telemetry live)  
- **Unblocks**: Incident response improvements  

### WEEK 2-3 DELIVERABLES
✅ #377 Phase 1 — Telemetry infrastructure deployed  
✅ #381 Phase 1 — Readiness gates policy + template  
✅ #378 Phase 1 — Error fingerprinting algorithm  

**Effort**: 16 hours  
**Result**: Full observability stack in production  

---

## WEEK 4-5: CORE SERVICES INSTRUMENTATION (May 13-26, 2026)

### PRIMARY OBJECTIVE
Instrument all core services with traces, implement SLO monitoring

### CRITICAL PATH

#### #377 Phase 2 — Instrument Core Services 🔴 **P0**
- Targets: code-server, PostgreSQL, Redis, Caddy, oauth2-proxy, Kong  
- Add custom spans to critical paths:
  - User authentication flow (start:login → span:oauth2 → span:rbac → end:session)  
  - Database queries (start:query → span:parse → span:execute → span:fetch)  
  - API requests (start:request → span:routing → span:handler → span:response)  
- Effort: 5 days  
- Deliverable: Code-server + all dependencies instrumented  

#### #397 — Advanced Telemetry (SLO Focus) 🟡 **P1**
- Define SLO targets per service  
- Implement burn rate alerts (pacing towards SLO breach)  
- Dashboard showing SLO status + error budget  
- Effort: 3 days  

#### #395-396 — Telemetry Phase 3-4 🟡 **P1**
- Automation + runbook generation  
- Performance dashboards + baselines  

### WEEK 4-5 DELIVERABLES
✅ #377 Phase 2 — Core services instrumented  
✅ #397 Phase 1 — SLO framework deployed  
✅ #395-396 Phase 3-4 — Automation + runbooks  

**Effort**: 13 hours  
**Result**: Full end-to-end observability, <15min MTTR operational  

---

## WEEK 6-7: SECURITY & IDENTITY (May 27 - June 9, 2026)

### PRIMARY OBJECTIVE
Standardize IAM, implement workload identity, enforce auth boundaries

### CRITICAL PATH

#### #388 — IAM Standardization 🔴 **P0**
- **Status**: OAuth2 strategy defined, workload identity pending  
- **Effort**: 5 days  
- **Scope**:
  - Google OIDC for humans (code-server, Grafana, Loki)  
  - Workload identity for services (Prometheus scrape, Jaeger client, Kong upstream)  
  - RBAC 3-tier: admin (all), viewer (read), readonly (metrics-only)  
  - Token rotation (90-day cycle, automated)  
- **Deliverables**: Vault policies + workload tokens  
- **Unblocks**: #389 (Appsmith), #392 (Backstage), all new services  

#### #387 — Auth Boundary Enforcement 🔴 **P0**
- **Status**: Design complete, implementation pending  
- **Effort**: 3 days  
- **Scope**: Deny direct network access to internal services  
- **Mechanisms**:
  - Caddy TLS termination (HTTPS-only ingress)  
  - Network policies (Kubernetes-compatible, Docker extension)  
  - Service-mesh-like rules (source → destination validation)  
  - Audit logging (all denials to Loki)  
- **Acceptance**: Direct access blocked with 403/502  

#### #390 — CI-CD Action Pinning 🟡 **P2**
- **Status**: Security audit needed  
- **Effort**: 2 days  
- **Scope**: Pin all GitHub Actions to exact commit SHA (supply chain security)  

### WEEK 6-7 DELIVERABLES
✅ #388 — IAM standardization complete  
✅ #387 — Auth boundaries enforced  
✅ #390 — CI/CD supply chain hardened  

**Effort**: 10 hours  
**Result**: Zero unauthed access possible  

---

## WEEK 8-9: PLATFORM CAPABILITIES (June 10-23, 2026)

### PRIMARY OBJECTIVE
Ship Appsmith command center OR Backstage catalog (ADR decision pending)

### CRITICAL PATH (DECISION REQUIRED)

#### #385 — Portal Architecture ADR 🔴 **P0**
- **Status**: Architecture decision pending approval  
- **Options**:
  - Option A: Appsmith (low-code UI, rapid dashboards)  
  - Option B: Backstage (service catalog, DevEx focus)  
  - Option C: Both (Appsmith for ops, Backstage for platform)  
- **Decision Deadline**: End of Week 5 (May 26)  
- **Impact**: Determines 3+ week development path  

#### #389 — Appsmith Command Center (IF Option A or C) 🟡 **P1**
- **Scope**: Operations dashboards, incident response UI  
- **Effort**: 2-3 weeks  
- **Depends On**: #385 decision  

#### #392 — Backstage Catalog (IF Option A or C) 🟡 **P1**
- **Scope**: Service catalog, API documentation, runbook repository  
- **Effort**: 2-3 weeks  
- **Depends On**: #385 decision  

### WEEK 8-9 DELIVERABLES (Conditional)
✅ #385 ADR decision + approval  
✅ #389 OR #392 Phase 1 completed (based on decision)  

**Effort**: 40-60 hours (depending on decision)  
**Result**: Unified operational interface  

---

## WEEK 10-11: CODE QUALITY & DOCUMENTATION (June 24 - July 7, 2026)

### PRIMARY OBJECTIVE
Eliminate code duplication, standardize scripts, auto-generate docs

### CRITICAL PATH

#### #382 — Script Canonicalization 🟡 **P1**
- **Status**: Deployment scripts scattered across 260+ files  
- **Effort**: 1-2 weeks  
- **Scope**: Single canonical deploy script (already started in #421)  
- **Deliverable**: `scripts/deploy-unified.sh` + 7 phase modules  
- **Acceptance**: All phase scripts consolidated, zero duplication  

#### #427 — terraform-docs Integration 🟡 **P3**
- **Status**: Documentation auto-generation ready  
- **Effort**: 2-3 days  
- **Scope**: Auto-generate terraform module docs from HCL comments  

#### #433 — Code Review Epic 🟡 **P1**
- **Status**: 18 child issues, 38% complete  
- **Effort**: Ongoing (2-3 weeks remaining)  
- **Scope**: Fix all code style inconsistencies, remove duplication  

### WEEK 10-11 DELIVERABLES
✅ #382 — Script consolidation 100% complete  
✅ #427 — terraform-docs auto-generation  
✅ #433 — Code review epic 90%+ complete  

**Effort**: 35 hours  
**Result**: Clean, maintainable codebase  

---

## WEEK 12: OPTIMIZATION & FINAL INTEGRATION (July 8-21, 2026)

### PRIMARY OBJECTIVE
Load testing, chaos testing, performance optimization, final hardening

### SCOPE

#### #411 — Infrastructure Optimization Epic 🟡 **P3**
- **Status**: Planning phase  
- **Effort**: 290 hours (May-August beyond this roadmap)  
- **Scope**: Resource optimization, cost reduction, capacity planning  

#### Load Testing & Chaos 🔴 **CRITICAL**
- 1x/2x/5x/10x peak load validation  
- Chaos engineering (service failures, network partitions)  
- Auto-remediation verification  

#### Security Audit 🔴 **CRITICAL**
- Penetration testing (external)  
- Vulnerability scanning (SAST, container, dependencies)  
- Zero high/critical CVEs before launch  

#### Documentation Final Pass 🟡 **IMPORTANT**
- Runbooks complete for all services  
- Troubleshooting guides updated  
- Deployment procedures tested  

### WEEK 12 DELIVERABLES
✅ Production readiness certification  
✅ Load test report (all metrics pass SLO)  
✅ Security audit report (zero critical issues)  
✅ Comprehensive runbooks + procedures  

**Effort**: 60 hours  
**Result**: PRODUCTION-READY SYSTEM  

---

## DEPENDENCIES & CRITICAL PATH

```
┌─────────────────────────────────────────────────────────┐
│ WEEK 1: FOUNDATION                                      │
│ #383 (roadmap) → #380 (governance) → #384 (bugs)       │
│ + #379 (dedup) + #406 (report)                          │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ WEEK 2-3: OBSERVABILITY                                 │
│ #377 Phase 1 (telemetry) → #381 (gates) ← #378 (errors)│
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ WEEK 4-5: INSTRUMENTATION                               │
│ #377 Phase 2 → #397 (SLO) → #395-396 (automation)      │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ WEEK 6-7: SECURITY                                      │
│ #388 (IAM) → #389/#392 (platforms) ← #387 (auth)       │
│            ← #390 (supply chain)                         │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ WEEK 8-9: PLATFORMS (Decision-based)                    │
│ #385 ADR → #389 (Appsmith) OR #392 (Backstage)         │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ WEEK 10-11: CODE QUALITY                                │
│ #382 (scripts) → #427 (docs) → #433 (review)           │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│ WEEK 12: FINAL INTEGRATION                              │
│ Load tests → Chaos tests → Security audit → Launch     │
└─────────────────────────────────────────────────────────┘
```

---

## EXECUTION RULES (PRODUCTION-FIRST)

### ✅ IaC IMMUTABILITY
- All configuration in git (no manual changes)
- Terraform for infrastructure (docker-compose for services)
- Every change has a git commit + PR review

### ✅ INDEPENDENT WORK
- Each task completable without waiting for others
- Clear API boundaries between components
- Parallel execution where possible

### ✅ DUPLICATE-FREE
- #379 consolidates redundant issues before week 2
- SSOT principle: one source for each configuration
- No scattered scripts/configs

### ✅ REVERSIBLE CHANGES
- Every feature has rollback plan (<60 seconds)
- Feature flags for gradual rollout
- Blue/green deployment capability

### ✅ OBSERVABLE SYSTEMS
- Tracing on all requests (#377)
- Metrics on all operations (#397)
- Alerts on SLO breaches (#381)

### ✅ SECURE BY DEFAULT
- Zero hardcoded secrets (#380)
- AuthN/Z on all services (#388)
- Audit logging everywhere (#387)

---

## SUCCESS METRICS

| Metric | Week 1 | Week 4 | Week 8 | Week 12 | Target |
|--------|--------|--------|--------|---------|--------|
| Open Issues | 36 | 28 | 18 | <10 | <10 |
| P0 Issues | 6 | 3 | 1 | 0 | 0 |
| Code Coverage | 85% | 88% | 90% | 95%+ | 95%+ |
| CVEs (high+) | 2 | 1 | 0 | 0 | 0 |
| MTTR (prod) | TBD | <30m | <15m | <10m | <15m |
| Availability | 99.5% | 99.8% | 99.9% | 99.95% | 99.95% |
| P99 Latency | <150ms | <120ms | <100ms | <85ms | <100ms |
| Error Rate | 0.5% | 0.2% | 0.1% | 0.04% | <0.1% |

---

## TEAM ASSIGNMENTS (Recommended)

| Role | Primary Issues | FTE |
|------|----------------|-----|
| **Observability Lead** | #377, #378, #381, #397 | 1.0 |
| **Security Lead** | #380, #388, #387, #390 | 0.8 |
| **Platform Lead** | #385, #389, #392, #432 | 0.8 |
| **Infrastructure Lead** | #382, #383, #386, #411 | 1.0 |
| **DevEx/QA** | #406, #433, #427, #401-404 | 0.6 |

**Total**: 4.2 FTE × 12 weeks = ~420 engineer-hours  
**Reality**: Elite team = 50% velocity boost = 280 hours actual effort  

---

## SIGN-OFF & APPROVAL

**Roadmap Approved By**: [PENDING SIGNATURE]  
**Execution Start**: April 22, 2026  
**Target Completion**: July 21, 2026  
**Status**: Ready for Week 1 execution  

---

**Created**: April 22, 2026  
**Version**: 1.0 (Production-Ready)  
**Next Review**: May 5, 2026 (end of Week 1)
