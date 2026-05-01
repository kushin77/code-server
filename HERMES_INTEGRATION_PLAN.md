# Hermes-agents Migration Epic: Planning & Implementation Guide

**Epic**: #3123 — Hermes-agents Integration & Agent Runtime Modernization  
**Status**: 🚀 PLANNING PHASE  
**Date**: May 1, 2026  
**Target Completion**: Q2 2026  

---

## Executive Summary

This epic tracks the adoption of Hermes-agents orchestration layer into code-server's Agent Runtime. The Hermes model provides:
- **Orchestration**: Central coordination of distributed agent instances
- **IDE Integration**: Native VS Code extension for agent management  
- **Enterprise Patterns**: Production-grade infrastructure (config, logging, health checks)
- **Observability**: Distributed tracing and structured logging

**Key Decision**: Hermes-agents complements (not replaces) Agent Runtime. Code-server already uses a sophisticated FastAPI-based execution engine; Hermes provides an orchestration layer on top.

**Enterprise Patterns Status**: ✅ **COMPLETE** (Phase 1)
- config.py (SSOT) — ✅ Implemented, Terraform updated
- log.py (SLOG) — ✅ Implemented, integrated into 4 modules
- app_factory.py (FastAPI factory) — ✅ Implemented, integrated  
- health.py (liveness + readiness) — ✅ Implemented, wired into docker-compose
- Dockerfile (multi-stage) — ✅ Implemented, non-root user, optimized

---

## Phase Structure

### Phase 1: Enterprise Patterns Foundation ✅ COMPLETE (May 1)

**Completed**:
- [x] Centralized Configuration (SSOT) — config.py with validation
- [x] Structured Logging (SLOG) — JSON logging factory with correlation IDs
- [x] FastAPI App Factory — Idempotent app creation pattern
- [x] Health Checks — Liveness (/health) + Readiness (/health/ready)
- [x] Docker Optimization — Multi-stage build, non-root user
- [x] Terraform Integration — Updated all agent containers
- [x] Documentation — README.md with enterprise patterns guide
- [x] Tests — Integration test suite (test_enterprise_patterns.py)

**Deliverables**:
- 5 new Python modules (74-95 LOC each)
- 4 git commits
- 6 GitHub issues (#3136-#3141) tracked
- Terraform validation passing

---

### Phase 2: Hermes-agents Integration ✅ COMPLETE (May 1)

**Goal**: Plan integration without breaking existing Agent Runtime.

**Sub-tasks** (GitHub Issues #3124-#3127):

#### #3124: Hermes Model Research & Documentation ✅
- [x] Document Hermes architecture: agents, orchestrator, message bus
- [x] Compare with code-server Agent Runtime: similarities & differences
- [x] Design integration points without modifying existing execution path
- [x] Deliverable: HERMES_INTEGRATION_PLAN.md (this document)

#### #3125: Agent Registration with Hermes Orchestrator ✅
- [x] Update agent-runtime to register with Hermes on startup
- [x] Implement heartbeat/liveness reporting to Hermes (30s interval)
- [x] Fallback: agent starts normally if Hermes unavailable (3 retries)
- [x] Deliverable: apps/agent-runtime/hermes_registration.py

#### #3126: Hermes IDE Extension Integration 🗓️ QUEUED
- [ ] Evaluate VS Code extension from hermes-agent repo
- [ ] Design IDE plugin for code-server (agent status, manual triggers)
- [ ] Plan packaging as VS Code extension
- [ ] Deliverable: ide-extension/hermes-agent-controller extension stub

#### #3127: Distributed Tracing & Observability ✅
- [x] Wire OpenTelemetry spans across Hermes + Agent Runtime
- [x] Integrate with Grafana Tempo via OTEL Collector (gRPC 4317)
- [x] Hermes calls traced via trace_hermes_call() context manager
- [x] Graceful degradation when opentelemetry packages absent
- [x] Deliverable: apps/agent-runtime/hermes_tracing.py

**Phase 2 Deliverables (May 1, 2026):**
- hermes_registration.py — lifecycle client (register / heartbeat / deregister)
- hermes_tracing.py — OTEL tracing with Tempo integration
- app_factory.py — wired both modules into startup/shutdown
- config.py — HERMES_URL, intervals added to SSOT
- docker-compose.yml — HERMES_URL, OTEL env vars added
- tests/test_hermes_integration.py — 12 unit tests

---

### Phase 3: Per-Agent Hermes Enablement 🗓️ QUEUED (May 8-21)

**Goal**: Enable each of 4 agents to work with Hermes orchestration.

**Sub-tasks** (GitHub Issues #3128-#3131):

#### #3128: Code Reviewer Agent + Hermes
- [ ] Register agent with Hermes on startup
- [ ] Update execution flow to report to Hermes
- [ ] Test: run code review via Hermes orchestrator
- [ ] Deliverable: Updated code-reviewer container

#### #3129: Incident Responder Agent + Hermes
- [ ] Register agent with Hermes
- [ ] Update incident response workflow (Hermes coordination)
- [ ] Test: trigger incident response via Hermes
- [ ] Deliverable: Updated incident-responder container

#### #3130: Doc Writer Agent + Hermes
- [ ] Register agent with Hermes
- [ ] Document generation flow via Hermes
- [ ] Test: trigger doc generation via Hermes
- [ ] Deliverable: Updated doc-writer container

#### #3131: Test Generator Agent + Hermes
- [ ] Register agent with Hermes
- [ ] Test generation flow via Hermes
- [ ] Test: trigger test gen via Hermes
- [ ] Deliverable: Updated test-generator container

---

### Phase 4: Infrastructure-as-Code for Hermes 🗓️ QUEUED (May 22-28)

**Goal**: Deploy Hermes as part of Terraform-managed stack.

**Sub-tasks** (GitHub Issues #3132-#3133):

#### #3132: Terraform Hermes Orchestrator Container
- [ ] Add hermes-orchestrator service to Terraform (Docker container)
- [ ] Wire dependencies: agents, Kafka (Redpanda), Postgres
- [ ] Add health checks (/health → Hermes endpoint)
- [ ] Deliverable: terraform/modules/stack/containers-hermes.tf

#### #3133: Kubernetes Deployment (Optional)
- [ ] Create Kubernetes manifests for Hermes deployment
- [ ] Add Hermes orchestrator StatefulSet
- [ ] Update agent Deployments to register with Hermes
- [ ] Deliverable: kubernetes/hermes-orchestrator/ manifests

---

### Phase 5: End-to-End Testing & Validation 🗓️ QUEUED (May 29-Jun 4)

**Goal**: Validate full Hermes + Agent Runtime integration.

**Sub-tasks** (GitHub Issue #3134):

#### #3134: E2E Testing Suite
- [ ] Test: All 4 agents report liveness to Hermes
- [ ] Test: Hermes orchestration triggers agent execution
- [ ] Test: Fallback to direct execution if Hermes down
- [ ] Test: Distributed tracing captures full request path
- [ ] Test: Terraform apply/destroy cycles work
- [ ] Deliverable: tests/test_hermes_integration.py (50+ test cases)

---

### Phase 6: Documentation & Handoff 🗓️ QUEUED (Jun 5-11)

**Goal**: Document architecture, operations, and migration.

**Sub-tasks** (GitHub Issue #3135):

#### #3135: Hermes Integration Documentation
- [ ] Architecture diagram: Hermes + Agent Runtime integration
- [ ] Operations guide: deploying, monitoring, troubleshooting Hermes
- [ ] Migration guide: activating Hermes in existing deployments
- [ ] Observability guide: viewing traces, metrics, logs
- [ ] Deliverable: docs/HERMES_INTEGRATION_GUIDE.md (5-10KB)

---

## Technology Stack

### Current Agent Runtime (Existing ✅)
- **Framework**: FastAPI (Python)
- **Execution**: 4 agent containers (code-reviewer, incident-responder, doc-writer, test-generator)
- **Approval**: Paperclip Control Plane
- **Routing**: Execution Router (local/CI/edge/cloud)
- **Logging**: Structured JSON via python-json-logger
- **Config**: Centralized SSOT (config.py)

### Hermes Integration (Proposed 🚀)
- **Orchestration**: Hermes-orchestrator service (Redis queue or Kafka backend)
- **Message Bus**: Redpanda (Kafka-compatible) — already in stack
- **Agent Registration**: Each agent registers with Hermes on startup
- **Liveness**: Agents report heartbeats to Hermes
- **IDE Integration**: VS Code extension for agent management UI
- **Tracing**: OpenTelemetry spans via Grafana Tempo (already in stack)

### Infrastructure (Terraform 🔧)
- **Containers**: Agent Runtime + 4 agents + Hermes orchestrator
- **Database**: PostgreSQL (stores agent metadata, execution logs)
- **Cache**: Redis (agent session state)
- **Message Bus**: Redpanda (agent-to-Hermes coordination)
- **Monitoring**: Prometheus + Grafana + Loki + Tempo
- **Orchestration**: Docker Compose (local), Kubernetes (optional)

---

## Integration Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      VS Code IDE Extension                      │
│            (Hermes Agent Controller — NEW in Phase 2)           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│          Hermes Orchestrator Service (NEW in Phase 4)           │
│  - Agent registration & lifecycle                              │
│  - Liveness/heartbeat monitoring                               │
│  - Execution coordination via Redpanda                         │
│  - OpenTelemetry span collection                               │
└──┬────────────────────────────────────────────────────────────┬─┘
   │                                                            │
   ▼                                                            ▼
┌─────────────────────────────┐      ┌──────────────────────────────┐
│  Redpanda Message Bus       │      │  PostgreSQL Metadata Store   │
│  (Agent coordination queue) │      │  (Agent states, exec logs)   │
└─────────────────────────────┘      └──────────────────────────────┘
   ▲                                           ▲
   │                                           │
   │  (Updated in Phase 3: per-agent)         │
   │                                           │
┌──┴──────────────────────────────────────────┴──────────────────┐
│                    Agent Runtime Service                       │
│              (Existing — NOT MODIFIED)                         │
│  - Code Reviewer Agent  (Port 9001)                           │
│  - Incident Responder   (Port 9002)                           │
│  - Doc Writer           (Port 9003)                           │
│  - Test Generator       (Port 9004)                           │
│  - Agent Runtime Core   (Port 8020)                           │
└─┬─────────────────────────────────────────────────────────┬───┘
  │                                                         │
  ▼                                                         ▼
┌─────────────────────────┐      ┌──────────────────────────────┐
│ OPA Policy Engine       │      │ Paperclip Control Plane      │
│ (Capability checks)     │      │ (Approval gating)            │
└─────────────────────────┘      └──────────────────────────────┘
```

---

## Risk Mitigation

### Risk 1: Breaking Existing Agent Runtime
**Mitigation**: Hermes integration is **additive only** (Phase 2-6).
- Existing execution path unchanged
- Agents register with Hermes optionally
- Fallback to direct execution if Hermes unavailable
- No changes to core FastAPI handlers

### Risk 2: Infrastructure Complexity
**Mitigation**: Gradual rollout with clear phases.
- Phase 1: Enterprise patterns (✅ DONE)
- Phase 2: Hermes research & design (planning)
- Phase 3-4: Per-agent registration (staged)
- Phase 5: Full E2E validation before prod

### Risk 3: Observability Overhead
**Mitigation**: Optional tracing, structured logging already in place.
- OpenTelemetry spans only created if enabled
- Structured JSON logging works regardless
- Health checks don't depend on Hermes

---

## Success Criteria

| Criterion | Phase | Target | Status |
|-----------|-------|--------|--------|
| Enterprise patterns complete | 1 | May 1 | ✅ DONE |
| Hermes design document | 2 | May 7 | 🚀 IN PROGRESS |
| Agent registration working | 3 | May 21 | 🗓️ QUEUED |
| Terraform deployment ready | 4 | May 28 | 🗓️ QUEUED |
| E2E tests passing (50+ cases) | 5 | Jun 4 | 🗓️ QUEUED |
| Ops guide + runbook complete | 6 | Jun 11 | 🗓️ QUEUED |

---

## GitHub Issues Tracking

### Enterprise Patterns (✅ COMPLETE)
- [x] #3136 — Integrate config validation
- [x] #3137 — Integrate logging factory
- [x] #3138 — Migrate to app factory
- [x] #3139 — Add readiness health checks
- [x] #3140 — Deploy multi-stage Dockerfile
- [x] #3141 — Document enterprise patterns

### Hermes Integration (🚀 IN PROGRESS)
- [ ] #3123 — **Epic**: Hermes-agents integration
- [ ] #3124 — Hermes research & design
- [ ] #3125 — Agent registration
- [ ] #3126 — IDE extension integration
- [ ] #3127 — Distributed tracing
- [ ] #3128 — Code Reviewer + Hermes
- [ ] #3129 — Incident Responder + Hermes
- [ ] #3130 — Doc Writer + Hermes
- [ ] #3131 — Test Generator + Hermes
- [ ] #3132 — Terraform Hermes container
- [ ] #3133 — Kubernetes deployment
- [ ] #3134 — E2E integration tests
- [ ] #3135 — Documentation & handoff

---

## Next Steps

1. **Immediately** (May 1-2):
   - Review this plan with team
   - Confirm Hermes integration approach
   - Start Phase 2 research (#3124)

2. **Week 1** (May 3-7):
   - Complete Hermes design document
   - Create agent registration module stub
   - Review IDE extension from hermes-agent repo

3. **Week 2-3** (May 8-21):
   - Implement per-agent Hermes registration
   - Add heartbeat reporting
   - Test each agent with Hermes

4. **Week 4-5** (May 22-Jun 4):
   - Terraform integration
   - Full E2E testing
   - Performance & stress testing

5. **Week 6** (Jun 5-11):
   - Documentation & runbooks
   - Team handoff
   - Production deployment readiness

---

## References

- **GitHub Epic**: https://github.com/kushin77/code-server/issues/3123
- **Agent Runtime**: apps/agent-runtime/README.md
- **Hermes Reference**: /home/akushnir/hermes-agent (local clone)
- **Enterprise Patterns**: apps/agent-runtime/README.md → "Enterprise Patterns" section
- **Terraform State**: terraform/environments/private/

---

*Document created: May 1, 2026 — 12:00 UTC*  
*Last updated: May 1, 2026*  
*Next review: May 7, 2026 (Phase 2 checkpoint)*
