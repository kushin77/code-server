# Network Topology — kushin77/code-server

**Purpose**: Network Topology — kushin77/code-server — reference and operational document.

> Implements: [#887](https://github.com/kushin77/code-server/issues/887) — Air-gap network segmentation
> Last updated: 2026-04-22

## Overview

All Docker services are assigned to one or more named network tiers. The defining security invariant is:

> **No service is attached to both `net-edge` and `net-data` directly.**

This ensures the data tier (Postgres, pgbouncer) has no reachable path from internet-facing proxies.

---

## Network Tiers

| Network | Subnet | Purpose |
|---------|--------|---------|
| `net-edge` | `172.28.1.0/24` | Internet-facing proxies (Caddy, oauth2-proxy) |
| `net-app` | `172.28.2.0/24` | Application tier — code execution, session management, AI, Redis |
| `net-data` | `172.28.3.0/24` | Data tier — Postgres, pgbouncer. No external routes. |
| `net-management` | `172.28.4.0/24` | Observability — Grafana, Prometheus, AlertManager, Jaeger |

---

## Service → Network Assignments

| Service | net-edge | net-app | net-data | net-management | Notes |
|---------|----------|---------|----------|----------------|-------|
| `caddy` | ✅ | ✅ | — | — | Bridges edge → app for reverse proxy routing |
| `oauth2-proxy` | ✅ | ✅ | — | — | Bridges edge → app; Redis (session store) is on net-app |
| `oauth2-proxy-portal` | ✅ | ✅ | — | — | Same as above, for portal domain |
| `code-server` | — | ✅ | — | — | App tier only |
| `session-broker` | — | ✅ | ✅ | — | Needs Postgres on net-data |
| `ollama` | — | ✅ | — | — | AI, app tier only |
| `ollama-init` | — | ✅ | — | — | One-shot model puller |
| `redis` | — | ✅ | — | — | Session store — app tier, not data tier |
| `appsmith` | — | ✅ | — | — | Portal, fronted by oauth2-proxy-portal |
| `code-server-profile-backup` | — | ✅ | — | — | Reads from code-server volume |
| `postgres` | — | — | ✅ | — | Data tier only |
| `pgbouncer` | — | — | ✅ | — | Connection pooler — data tier only |
| `prometheus` | ✅* | ✅ | ✅ | ✅ | Pull-only metrics scraping across all tiers (see note) |
| `grafana` | — | — | — | ✅ | Management tier — access via Cloudflare Access (#876) |
| `alertmanager` | — | — | — | ✅ | Management tier |
| `jaeger` | — | ✅ | — | ✅ | Receives OTLP traces from app tier |

### Prometheus Cross-Tier Exception

Prometheus is attached to all 4 networks because it scrapes targets on every tier:
- `caddy:2019` (net-edge), `oauth2-proxy:4180` (net-edge)
- `code-server:8080`, `session-broker:5000`, `ollama:11434`, `redis:6379` (net-app)
- `postgres:5432` (net-data)
- Self-scrape + node exporter via `localhost` (net-management)

This is an accepted exception: Prometheus exposes no external ports and performs read-only metric pulls. It is not a lateral movement vector. Grafana (the access point) is restricted to Cloudflare Access.

---

## Security Invariants

1. **net-edge ↔ net-data isolation**: No service bridges these two networks. Postgres and pgbouncer are unreachable from Caddy or oauth2-proxy.

2. **Management tier isolation**: Grafana, AlertManager, and Prometheus web UIs (ports 3000, 9090, 9093) are only accessible via Cloudflare Access or Cloudflare WARP (see [#876](https://github.com/kushin77/code-server/issues/876)).

3. **Data tier firewall**: Host-level firewall rules block all inbound connections on ports 5432 (Postgres) and 6379 (Redis) from external sources.

4. **Cloudflare Tunnel origin concealment**: All inbound traffic flows through `cloudflared` tunnel. Origin IP (192.168.168.31) must not appear in public DNS A records.

---

## Migration Notes
## Internal DNS Scheme (#888)

> Implements: [#888](https://github.com/kushin77/code-server/issues/888) — Internal DNS service discovery

### Host-level canonical names

Managed via Terraform `/etc/hosts` injection on both hosts (avoid CoreDNS overhead on free-tier):

| Hostname | Resolves to | Purpose |
|----------|-------------|---------|
| `primary.internal` | `${DEPLOY_HOST}` (192.168.168.31) | Primary on-prem host |
| `replica.internal` | `${REPLICA_HOST}` (192.168.168.42) | Replica / HA standby |
| `nas.internal` | `${NAS_HOST}` (192.168.168.56) | NAS (NFS volumes) |

### Docker service discovery

Within the Docker network, all services already resolve by container name (Docker DNS). Scripts and config should use these names rather than IPs:

| Service name | Used by | Replaces |
|--------------|---------|---------|
| `postgres` | session-broker, pgbouncer | `${DEPLOY_HOST}:5432` |
| `redis` | oauth2-proxy, oauth2-proxy-portal | `${DEPLOY_HOST}:6379` |
| `code-server` | oauth2-proxy upstream | (internal only) |
| `session-broker` | caddy upstream | (internal only) |
| `ollama` | code-server env var | `OLLAMA_ENDPOINT` |

All scripts must use env vars (`${DEPLOY_HOST}`, `${REPLICA_HOST}`, `${NAS_HOST}`) — never literal IPs.
The CI gate (`scripts/ci/check-hardcoded-ips.sh`) enforces this on every commit.

---


> **Requires full stack restart**: Because Docker network names changed from `enterprise` to the new tier names, an in-place restart is insufficient.
>
> ```bash
> # On production host (192.168.168.31)
> docker compose down
> docker compose up -d
> # The old 'enterprise' network can be removed after all containers are on new networks:
> docker network rm enterprise 2>/dev/null || true
> ```

---

## Diagrams

```
Internet
   │
   ▼
[Cloudflare Tunnel / CF Access]
   │
   ▼  ┌─────────────────────────────────────┐
      │           net-edge                   │
      │  caddy ←──→ oauth2-proxy             │
      │              oauth2-proxy-portal     │
      └───────────────┬─────────────────────┘
                      │ (app tier bridge)
      ┌───────────────▼─────────────────────┐
      │           net-app                    │
      │  code-server   session-broker        │
      │  ollama        redis                 │
      │  appsmith      jaeger (ingest)       │
      └───────────────┬─────────────────────┘
                      │ (session-broker only)
      ┌───────────────▼─────────────────────┐
      │           net-data                   │
      │  postgres   pgbouncer                │
      └─────────────────────────────────────┘

      ┌─────────────────────────────────────┐
      │        net-management                │
      │  prometheus  grafana                 │
      │  alertmanager  jaeger (UI)           │
      └─────────────────────────────────────┘
      (prometheus also spans net-edge/app/data for scraping)
```