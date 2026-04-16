# ADR-008: Portal Platform — Appsmith vs Backstage

**Date**: 2026-04-16  
**Status**: Accepted  
**Deciders**: Platform Team  
**Refs**: [Issue #324](https://github.com/kushin77/code-server/issues/324)

---

## Context

The project requires an internal developer portal for:
- Service catalog (runbooks, service health, links)
- Automation trigger pages (deploy, rotate secrets, run DR test)
- OAuth2 SSO integration with existing identity flow
- On-prem deployment — no SaaS dependency

Two candidates were evaluated: **Appsmith** (low-code app builder) and **Backstage** (CNCF developer portal framework).

---

## Decision Criteria (Weighted)

| Criterion                     | Weight | Appsmith | Backstage |
|-------------------------------|--------|----------|-----------|
| On-prem deployability         | 20%    | ✅ 9/10  | ✅ 8/10   |
| OAuth2/OIDC SSO integration   | 20%    | ✅ 8/10  | ✅ 9/10   |
| Maintenance burden            | 20%    | ✅ 8/10  | ⚠️ 5/10   |
| Plugin / extension model      | 15%    | ⚠️ 6/10  | ✅ 9/10   |
| Observability integration     | 15%    | ⚠️ 6/10  | ✅ 8/10   |
| Security (RBAC, secrets)      | 10%    | ✅ 7/10  | ✅ 8/10   |
| **Weighted Score**            |        | **7.65** | **7.85**  |

---

## Decision

**Selected: Appsmith** — despite marginally lower weighted score, Appsmith is chosen for this environment because:

1. **Maintenance burden is the dominant cost signal.** Backstage requires a Node.js application server, plugin compilation, and active catalog schema management. For a 1-2 person platform team, this overhead is prohibitive without dedicated portal maintenance.
2. **On-prem Docker deployment is simpler.** Appsmith ships as a single-service Docker Compose stack with built-in PostgreSQL and Redis — no additional infrastructure beyond what already exists.
3. **Automation trigger pages are the primary use case.** Appsmith's REST API widget and JS trigger model covers the portal's primary function (triggering scripts, displaying health status) without requiring custom plugin development.
4. **Backstage backlog risk.** Backstage plugin ecosystem maintenance (dependency drift, breaking changes between catalog versions) frequently causes unplanned work. This matches no-overlap governance policy.

Backstage remains the preferred choice if the team grows to 5+ members or a service catalog with code ownership/dependency graphs becomes a P1 requirement.

---

## Architecture

```
Internet
    │
 Caddy (TLS termination, /portal path)
    │
 Appsmith (port 8080, internal)
    │  │
    │  └── REST calls to internal services (prometheus, alertmanager, code-server)
    │
 PostgreSQL (existing — separate database: appsmith_db)
 Redis (existing — separate keyspace: appsmith:*)
```

### OAuth2 SSO Integration

Appsmith supports OAuth2 provider configuration via environment variables:
- `APPSMITH_OAUTH2_GITHUB_CLIENT_ID`
- `APPSMITH_OAUTH2_GITHUB_CLIENT_SECRET`
- `APPSMITH_SIGNUP_DISABLED=true` (restrict to OAuth only)

Existing oauth2-proxy identity flow is preserved; Appsmith authenticates users independently via GitHub OAuth2.

---

## Compose Profile

The Appsmith service is deployed under the optional `portal` compose profile to avoid affecting core service startup:

```yaml
# In docker-compose.yml
appsmith:
  profiles: ["portal"]
  image: appsmith/appsmith-ce:v1.47
  ...
```

Deploy with: `COMPOSE_PROFILES=portal docker compose up -d`

---

## Security Constraints

- Appsmith instance is **not** exposed on public port — only via Caddy path `/portal`
- `APPSMITH_SIGNUP_DISABLED=true` enforced — no open registration
- Appsmith database uses isolated PostgreSQL user `appsmith` with no access to `coder` schema
- Redis keyspace prefix `appsmith:*` segregated from session cache

---

## Rollback Plan

Disable the `portal` compose profile: `docker compose --profile portal down`  
No changes to core services required.

---

## Consequences

- **Positive**: Single-command portal deployment, no custom plugin code, existing PG/Redis reused
- **Positive**: SSO via GitHub OAuth2 with signup disabled — minimal attack surface
- **Negative**: Appsmith JS sandbox limits complex automation; complex ops pages may need API relay
- **Negative**: Appsmith CE is MIT-licensed but less extensible than Backstage for catalog use cases
- **Deferred**: If service catalog (software component graph, ownership) becomes required, revisit Backstage on next architecture review cycle

---

## References

- [Appsmith Docker deployment docs](https://docs.appsmith.com/getting-started/setup/installation-guides/docker)
- [Backstage deployment guide](https://backstage.io/docs/deployment/)
- [docs/ADR-002-DUAL-PORTAL-ARCHITECTURE.md](../ADR-002-DUAL-PORTAL-ARCHITECTURE.md)
- Issue #324: PORTAL-ARCH-008 Architecture Decision POC
