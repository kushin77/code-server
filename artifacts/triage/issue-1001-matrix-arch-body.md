## P1: Design Matrix Homeserver Architecture and Deployment Strategy

### Summary

Define the architectural decisions for Matrix homeserver deployment, including self-hosted vs managed trade-offs, federation policy, data sovereignty, and integration with existing infrastructure.

### Decision Points

#### 1. Deployment Model

| Option | Pros | Cons | Recommendation |
|--------|------|------|----------------|
| **Element Server Suite Pro** (Managed) | Zero ops, SLA, compliance certifications | Cost, less control | ✅ For rapid deployment |
| **Self-Hosted Synapse** | Full control, cost-effective at scale | Ops burden, scaling complexity | For large teams (100+) |
| **Self-Hosted Dendrite** | Lightweight, single-binary | Less mature than Synapse | For edge/IoT scenarios |

#### 2. Federation Policy

| Policy | Use Case |
|--------|----------|
| **Closed (No Federation)** | Enterprise-only, maximum security |
| **Allowlist Federation** | Partner orgs only |
| **Open Federation** | Community collaboration |

#### 3. Data Sovereignty

- Primary storage location (GCP region aligned with existing infra)
- Backup and DR strategy (aligned with #957 Redis HA, #959 PostgreSQL replication)
- Encryption at rest (E2EE + server-side encryption)
- Data retention policies (configurable per space/room)

### Architecture Design

```
┌─────────────────────────────────────────────────────────────────┐
│                    Matrix Homeserver (Synapse)                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Synapse Workers                       │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  │   │
│  │  │ Sync     │  │ Event    │  │ Media    │  │ Push    │  │   │
│  │  │ Worker   │  │ Persist  │  │ Repo     │  │ Gateway │  │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └─────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │           PostgreSQL (Matrix State Store)                 │ │
│  │           Replicates with existing #957 PostgreSQL HA     │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Existing Infrastructure                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│  │ Caddy (Edge) │  │ oauth2-proxy │  │ Prometheus/Grafana    │ │
│  │ Reverse Proxy│  │ SSO Gateway  │  │ Observability         │ │
│  └──────────────┘  └──────────────┘  └───────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Integration with Existing Infrastructure

| Component | Integration Point |
|-----------|-------------------|
| **Caddy** | Reverse proxy for Matrix well-known and client API |
| **oauth2-proxy** | SSO integration via OIDC (same IdP as IDE) |
| **PostgreSQL** | Shared or dedicated DB (evaluate performance) |
| **Redis** | Session state for Matrix workers (optional) |
| **Prometheus** | Matrix metrics export |
| **NAS** | Media repository storage |

### Deliverables

1. **Architecture Decision Record (ADR)**: `docs/architecture/adr-matrix-homeserver.md`
2. **Deployment topology diagram** (Mermaid in ADR)
3. **Capacity planning document** (users, messages/day, storage)
4. **Security review checklist** (aligned with #967 audit)
5. **Cost analysis** (managed vs self-hosted)

### Acceptance Criteria

- [ ] ADR committed with decision rationale
- [ ] Deployment model selected (managed vs self-hosted)
- [ ] Federation policy defined
- [ ] Integration points documented
- [ ] Capacity estimates for team size
- [ ] Security review completed
- [ ] Cost analysis approved

### Dependencies

- Requires: Team size estimate, compliance requirements
- Blocks: All other Matrix child issues

### Parent

EPIC #TBD (Matrix Collaboration Hub)
