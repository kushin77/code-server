# 001. Containerized Code-Server Deployment (Linux Production)

**Status**: Accepted
**Date**: 2026-01-27
**Author(s)**: @kushin77
**Related ADRs**: [ADR-002: OAuth2 Proxy for Authentication](002-oauth2-authentication.md), [ADR-003: Terraform Infrastructure](003-terraform-infrastructure.md)

---

## Context

Enterprise development requires:
- **Multi-developer access** to isolated development environments
- **Infrastructure as Code** management at scale
- **Security enforcement** (authentication, RBAC, audit logging)
- **Reproducible Linux production deployments** (no Windows-only code paths)
- **Resource isolation** to prevent one developer from impacting others

Previously, code-server was deployed manually, leading to:
- Configuration drift between environments
- Inconsistent security posture
- Difficult scaling and onboarding
- No audit trail for access/changes

We needed a containerized, Linux-native, Terraform-managed approach to standardize deployments and mandate production-grade operational practices.

---

## Decision

We will deploy code-server using:

1. **Docker containers** for service isolation and reproducibility
2. **Docker Compose** for local development and testing
3. **Terraform** for cloud infrastructure provisioning
4. **Caddy reverse proxy** for HTTPS termination, URL rewriting, and health checks
5. **OAuth2 Proxy** for centralized authentication (see ADR-002)

This ensures:
- **Consistent deployment** across all environments
- **Reproducible builds** with versioned images
- **Infrastructure as Code** for auditability and drift prevention
- **Security by default** (encrypted communication, auth gating)
- **Horizontal scalability** with container orchestration (future: Kubernetes)

---

## Alternatives Considered

### Alternative 1: Manual Installation + Bash Scripts
**Pros**:
- Direct control, minimal abstraction
- Works on any OS with Bash

**Cons**:
- **Drift-prone** — manual steps diverge across deployments
- **No auditability** — hard to track who changed wha
- **Non-reproducible** — environment-specific quirks accumulate
- **Scaling nightmare** — no automation for multi-instance deployments
- **Security debt** — configuration buried in scripts

**Why not chosen**: Doesn't meet enterprise standards for reproducibility and auditability.

### Alternative 2: Kubernetes-Only
**Pros**:
- Production-grade orchestration
- Auto-scaling, self-healing
- Industry standard

**Cons**:
- **Over-engineered for MVP** — additional complexity, operational burden
- **Requires external infrastructure** — not portable to Windows dev machines
- **Steep learning curve** — team not ready ye
- **Cost** — licensing, infrastructure, operational overhead

**Why not chosen**: Starting with Docker/Compose/Terraform. Can migrate to Kubernetes later (ADR-004 TBD).

### Alternative 3: Cloud-Only SaaS (e.g., GitHub Codespaces)
**Pros**:
- No infrastructure to manage
- Zero DevOps burden
- Autoscaling built-in

**Cons**:
- **Vendor lock-in** — tied to GitHub ecosystem
- **Privacy/security** — code lives on external servers
- **Cost** — per-developer, unbounded
- **Latency** — cloud round-trip not ideal for some use cases
- **No offline capability** — local dev impossible

**Why not chosen**: Org values data sovereignty and cost control.

---

## Consequences

### Positive Consequences
- ✅ **Reproducible deployments** — same Compose/Terraform files produce identical environments
- ✅ **Security hardened** — TLS, auth, isolation by defaul
- ✅ **Auditable** — all changes tracked in Git, no manual drif
- ✅ **Scalable** — easy to provision multiple instances
- ✅ **Developer experience** — lightweight, familiar Docker workflow
- ✅ **IaC enforcement** — code reviews catch infrastructure errors
- ✅ **Faster onboarding** — `docker-compose up` instead of 2-hour manual setup

### Negative Consequences (Accepted Risks)
- ⚠️ **Docker complexity** — team must learn Docker, Compose, Caddy
- ⚠️ **Windows-specific quirks** — Docker Desktop for Windows has performance issues
- ⚠️ **Resource overhead** — containers use more resources than native processes
- ⚠️ **Container registry needed** — must host images (mitigated: GitHub Container Registry free)
- ⚠️ **Orchestration gap** — Compose insufficient for production scale (mitigated: roadmap to K8s)

---

## Security Implications

- **Trust boundaries**:
  - Container boundary isolates code-server from host OS
  - OAuth2 Proxy enforces authentication before traffic reaches code-server
  - Caddy terminates TLS, preventing MITM

- **Attack surface**:
  - **Reduced**: Docker isolation, no exposed ports without proxy
  - **New**: Dependency on Docker daemon security, Caddy/OAuth2 Proxy correctness

- **Data exposure**:
  - Code and secrets confined to container filesystem
  - Container image stored in private registry (requires access control)

- **Authentication/Authorization**:
  - OAuth2 Proxy enforces org-level authentication
  - Code-server runs without direct auth (relies on proxy)

- **Mitigation strategy**:
  - Container images scanned for vulnerabilities (CI gate)
  - Secrets never hardcoded — injected via environment variables from GCP Secret Manager
  - Regular security updates to image base and dependencies
  - RBAC on container registry access

---

## Performance & Scalability Implications

- **Horizontal scaling**:
  - ✅ Can provision multiple code-server instances via Terraform
  - Each instance isolated in separate container
  - Load balancer (Caddy) routes across instances
  - Session-affine routing is required for active IDE sessions; code-server should not be treated as a generic stateless backend under active-active ingress

- **Bottlenecks**:
  - Single Docker Desktop instance on Windows (performance capped)
  - Network I/O for code syncing between instances (if using shared workspace)
  - Storage I/O if using network mounts (NFS, SMB)

- **Resource usage**:
  - Per container: ~300-500MB RAM baseline
  - CPU: minimal unless running heavy build jobs
  - Storage: ~2GB per instance (image + workspace)

- **Latency**:
  - Container startup: ~10-30 seconds
  - Code hot-load: milliseconds (in-memory)
  - Network latency: depends on infrastructure (LAN << cloud)

- **Throughput**:
  - Single instance: handles ~50-100 concurrent connections (Caddy)
  - Additional instances scale linearly with load balancer

---

## Operational Impac

- **Deployment**:
  - CI/CD builds and pushes image to registry
  - Terraform applies infrastructure definition
  - Containers restart with new image
  - Zero-downtime if using blue-green deploymen

- **Monitoring**:
  - Container health checks (HTTP /health endpoint)
  - Container logs streamed to stdout/stderr (capture via Docker logging driver)
  - Prometheus metrics from code-server (if instrumented)
  - Caddy metrics for ingress traffic

- **Alerting**:
  - Alert if container exits unexpectedly
  - Alert if /health endpoint fails
  - Alert if Caddy upstream unreachable
  - Alert if image pulls fail (registry access issue)

- **Rollback**:
  - ✅ Simple: `docker-compose down && docker-compose up -d` with previous image version
  - Rollback time: < 2 minutes
  - Data persistence: workspace files retained (not deleted on rollback)

- **On-call**:
  - Understanding Docker, Compose, Terraform required
  - Understanding Caddy reverse proxy behavior
  - Understanding OAuth2 Proxy authentication flow
  - Runbook created for common issues (see [RUNBOOKS.md](../../RUNBOOKS.md))

---

## Implementation Notes

**Phase 1 (Current)**:
- Docker Compose for local/dev deployments
- Manual Terraform apply for cloud infrastructure

**Phase 2 (Q2 2026)**:
- CI/CD pipeline for automated image builds and pushes
- Automated infrastructure updates via Terraform

**Phase 3 (Q4 2026)**:
- Migration to Kubernetes for production scale
- Helm charts for version managemen
- Increased automation for multi-region deployments

---

## Validation Criteria

- [x] **Deployment reproducibility**: Same Compose file produces identical environments
- [x] **Security posture**: Secrets not in image, TLS enforced, auth gated
- [x] **Scalability**: Can provision multiple instances without modification
- [x] **Developer experience**: New dev can start in < 30 minutes
- [ ] **Performance benchmark**: P99 latency < 500ms (pending load testing)
- [ ] **Uptime SLA**: 99.5% achieved for 1 month (pending production deployment)

---

## References

- [Dockerfile and Compose Configuration](../../Dockerfile)
- [Terraform Infrastructure Code](../../main.tf)
- [Caddy Configuration](../../Caddyfile)
- [OAuth2 Proxy Setup](002-oauth2-authentication.md)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Terraform State Management](https://www.terraform.io/docs/language/state/)

---

## Sign-off

- [x] Technical review: @kushin77
- [x] Security review: @kushin77
- [x] Operations review: @kushin77
- [x] Architecture consensus: @kushin77
