# Contributing — Engineering Constitution

This repository operates at **FAANG-level standards**. Every contribution must be:

- **Secure by default** — Zero hardcoded secrets, least privilege IAM, explicit trust boundaries
- **Observable by default** — Structured logging, metrics, tracing, health endpoints
- **Scalable by design** — Stateless architecture, horizontal scaling validated, no implicit coupling
- **Automated end-to-end** — Deterministic builds, reproducible deployments, versioned artifacts
- **Measurable** — Performance profiled, SLOs defined, alerts configured
- **Defensible in audit** — Policy compliant, security scans enforced, threat models documented

**If it would not survive principal-level review at Amazon, Google, or Meta, it does not merge.**

Working locally is not sufficient. Production-hardened is the baseline.

---

## AI-Assisted Development Directive

All AI-generated contributions (GitHub Copilot, LLMs, internal agents) must operate in **Ruthless Enterprise Mode**.

AI must:
- Challenge assumptions aggressively
- Avoid demo-level implementations
- Avoid insecure defaults
- Avoid hidden scalability ceilings
- Avoid implicit coupling
- Avoid unbounded memory or concurrency

**AI-generated code must meet the same standards as senior staff engineers.**

---

## Mandatory Review Gates

Every PR must satisfy these non-negotiable gates:

### 🏗️ Architecture
- [ ] Horizontal scalability validated
- [ ] Stateless where possible
- [ ] Explicit dependency boundaries documented
- [ ] Failure isolation strategy defined
- [ ] ADR linked (if architectural change)

### 🔐 Security
- [ ] Zero hardcoded secrets (automated scan enforces this)
- [ ] IAM follows least privilege principle
- [ ] Input validation implemented
- [ ] Explicit trust boundaries defined
- [ ] Threat model documented (for new services)

### ⚡ Performance
- [ ] No blocking operations in hot paths
- [ ] No N+1 query patterns
- [ ] Performance measured, not assumed
- [ ] Resource limits defined
- [ ] Benchmarked on target infrastructure

### 📊 Observability
- [ ] Structured logging (JSON, correlation IDs)
- [ ] Metrics emitted (Prometheus format)
- [ ] Distributed tracing enabled (OpenTelemetry ready)
- [ ] Health endpoints implemented
- [ ] Alert conditions defined

### 🔄 CI/CD & Reproducibility
- [ ] Deterministic builds (no floating versions)
- [ ] Automated tests required (unit + integration)
- [ ] Static analysis enforced (lint failures block)
- [ ] Security scans enforced (SAST, dependency, secrets, container)
- [ ] Artifacts versioned immutably
- [ ] Rollback strategy documented

---

## Definition of Done (Enterprise)

A change is complete **only when**:

✅ Secure — No vulnerability paths
✅ Observable — Logs, metrics, traces exis
✅ Load-tested — Performance validated
✅ Documented — Architecture, deployment, rollback clear
✅ Automated — Tests, builds, deploys all pass
✅ Reproducible — Anyone can rebuild from source
✅ Policy compliant — All scans passing, ADRs linked

**"Works locally" is not done.** "Works in production" is the standard.

---

## Local Development Checklis

Before opening a PR, validate locally:

```bash
# Pre-commit checks
pre-commit run --all-files

# Repository validation scrip
./scripts/validate.sh

# IaC policy validation (OPA/Conftest)
conftest test terraform/ -p policies/

# Docker/container builds
docker-compose build --no-cache

# Unit tests
pytest tests/ -v --cov=. --cov-report=term

# Static analysis
pylint src/
shellcheck scripts/*.sh


Failure in any local check = PR must address before review request.

---

## CI/CD Enforcement Pipeline

The following stages are **non-waivable**:

1. **Lint** — Code style, formatting
2. **Unit Tests** — Coverage gate enforced (minimum 80%)
3. **SAST** — Static application security testing
4. **Dependency Scanning** — Known CVE detection
5. **Secrets Scanning** — Hardcoded credentials detection
6. **IaC Policy** — OPA/Conftest validation against security policies
7. **Container Scan** — Image vulnerability scan
8. **Build Artifact** — Versioned, signed, immutable
9. **Integration Tests** — End-to-end contract testing
10. **Coverage Enforcement** — Minimum thresholds non-negotiable

Failure at **any stage blocks merge**. No exceptions.

---

## Branch Protection Rules (Enforced)

All branches follow:

- ✅ Require PR before merge (no direct push)
- ✅ Require 2 approvals (1 must be code owner)
- ✅ Require all status checks passing
- ✅ Require conversations resolved
- ✅ Dismiss stale reviews on new commits
- ✅ Prevent force pushes
- ✅ Require signed commits (elite tier)
- ✅ Linear history (rebasing preferred)

---

## Threat Modeling & Security Review

For any new service or significant architectural change:

1. Document trust boundaries
2. Identify threats using STRIDE or similar
3. Document mitigations
4. Threat model reviewed by security team

Link threat model document in PR.

---

## ADR System (Architectural Discipline)

Major architectural decisions require an ADR (Architecture Decision Record).

**Location**: `/docs/adr/

**When required**:
- New service architecture
- Technology selection (framework, database, message queue)
- Infrastructure topology change
- Security boundary change
- Major refactoring

**ADR template** located at [docs/adr/TEMPLATE.md](docs/adr/TEMPLATE.md)

**Example ADRs**:
- [ADR-001: Containerized code-server Deployment](docs/adr/001-containerized-deployment.md)
- [ADR-002: OAuth2 Proxy for Authentication](docs/adr/002-oauth2-authentication.md)

All ADRs are immutable; new decisions require new ADRs with `Supersedes` link.

---

## SLO & Observability

For production services, define:

- **SLI** (Service Level Indicator): What we measure
- **SLO** (Service Level Objective): The target (e.g., 99.9% uptime)
- **Error Budget**: How much failure is acceptable
- **Alert Thresholds**: When to page on-call

**Location**: `/docs/slos/

Without SLOs, you're not running engineering — you're gambling.

---

## Code Review Standards

Reviewers must validate:

1. **Does it follow the architecture?** — Check against ADRs
2. **Is it secure?** — Threat model, input validation, least privilege
3. **Is it observable?** — Logs, metrics, traces
4. **Is it scalable?** — No hidden limits, blocking calls
5. **Is it tested?** — Unit + integration coverage
6. **Is it documented?** — Can a new engineer understand it 6 months later?

**Red flags that block approval**:
- Hardcoded configuration
- No error handling
- No logging
- No tests
- No documentation
- Blocking operations in hot paths
- Implicit dependencies

---

## Rollback Strategy (Mandatory)

Every production change must answer:

- How do we revert safely?
- What is the rollback time SLA?
- What data migrations need reversal?
- Are there dependencies that break?

### Rollback playbook format:

```markdown
## Rollback Plan

**Time to rollback**: <X minutes>
**Data considerations**: <impact of reverting>
**Dependent services**: <systems that might break>
**Steps**:
1. [Specific step]
2. [Specific step]
3. [Verification step]


---

## CI Pipeline Configuration

Refer to [.github/workflows/](github/workflows/) for implementation details:

- `ci-validate.yml` — Lint, unit tests, SAS
- `security.yml` — Dependency, secrets, container scans
- `deploy.yml` — Artifact versioning, rollback capability
- `validate.yml` — IaC policy enforcemen

---

## When in Doub

Ask the following:

1. **Would a principal engineer at Google accept this?** If no, rework it.
2. **Is this secure by default?** If defaults are insecure, fix it.
3. **Is this observable?** If you can't debug it in production, it's not done.
4. **Is this scalable?** If it has hidden limits, document them.
5. **Are we measuring this?** If there are no metrics, we can't manage it.
6. **Can we rollback this safely?** If not, the risk profile is unacceptable.

---

## Ruthless Truth

If:
- Policies are not automated → This entire document is corporate cosplay
- Reviews are optional → Engineers will skip them
- Security scans are warnings only → Vulnerabilities will ship
- Performance is not measured → You'll be surprised in production
- ADRs are ignored → Architectural debt accumulates
- Rollbacks are undocumented → Incidents become disasters

Elite engineering = **enforcement + culture + automation**.

No exceptions. No compromises. No "we'll clean it up later."
