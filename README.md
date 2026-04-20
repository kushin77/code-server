# code-server — On-Premises VSCode Server

Production-grade self-hosted VSCode in the browser with enterprise
security, monitoring, and high availability.

## Quick Start

```bash
# Core services only (code-server + oauth2-proxy + caddy + postgres + redis)
docker compose up -d

# With monitoring (Prometheus + Grafana + AlertManager)
COMPOSE_PROFILES=monitoring docker compose up -d

# With distributed tracing (OTel Collector + Jaeger + Loki + Promtail)
COMPOSE_PROFILES=tracing docker compose up -d

# With AI assistant (Ollama LLM — requires GPU)
COMPOSE_PROFILES=ai docker compose up -d

# Full stack (monitoring + tracing + AI)
COMPOSE_PROFILES=monitoring,tracing,ai docker compose up -d
```

## Run Mode Matrix

- IDE-only: `docker compose up -d`
  Includes code-server, oauth2-proxy, caddy, postgres, and redis.
- IDE + AI: `COMPOSE_PROFILES=ai docker compose up -d`
  Includes IDE-only plus ollama.
- IDE + Observability:
  `COMPOSE_PROFILES=monitoring,tracing docker compose up -d`
  Includes IDE-only plus prometheus, grafana, alertmanager, loki,
  promtail, otel-collector, and jaeger.
- Full platform:
  `COMPOSE_PROFILES=monitoring,tracing,ai docker compose up -d`
  Includes IDE, AI, and the observability stack.

## Services

| Service | Port | Profile | Notes |
|---------|------|---------|-------|
| code-server | 8080 | core | VS Code in browser |
| oauth2-proxy | 4180 | core | Authentication gateway |
| caddy (TLS) | 80/443 | core | Reverse proxy |
| postgres | 5432 | core | Session/audit DB |
| redis | 6379 | core | Cache/session store |
| prometheus | 9090 | monitoring | Metrics scraper |
| grafana | 3000 | monitoring | Dashboards |
| alertmanager | 9093 | monitoring | Alert routing |
| loki | 3100 | tracing | Log aggregation |
| promtail | — | tracing | Log shipping agent |
| otel-collector | 4317/4318 | tracing | Trace aggregator |
| jaeger UI | 16686 | tracing | Trace visualiser |
| ollama (LLM) | 11434 | ai | Local LLM server |

## Local Development

```bash
# Dev overlay — start the core stack locally, then apply the documented development overlay if needed
docker compose up -d
```

## Deployment

All deployments run **on the production host** (not locally):

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
docker compose up -d
```

For AI or observability in production, use the same profile flags from
`Quick Start` on host `192.168.168.31`.

## Profile Persistence And Backups

code-server user state is persisted across logins, container
recreation, and image upgrades.

- Primary persistence: Docker volume mounted at `/home/coder`
- User profile path: `/home/coder/.local/share/code-server/User`
- Extensions path: `/home/coder/.local/share/code-server/extensions`
- Backup service: `code-server-profile-backup`
- Backup cadence: every 6 hours
- Retention: 30 days

### Verify Runtime Persistence

Run on production host:

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
docker compose ps --format 'table {{.Names}}  {{.Status}}' |
  egrep '^(code-server|code-server-profile-backup)\s'
docker exec code-server \
  ls -la /home/coder/.local/share/code-server/User | head -20
```

### Restore A Profile Backup

```bash
ssh akushnir@192.168.168.31
docker run --rm \
  -v code-server-enterprise_code-server-profile-backups:/backups \
  alpine:3.20 ls -la /backups
docker run --rm \
  -v code-server-enterprise_code-server-data:/target \
  -v code-server-enterprise_code-server-profile-backups:/backups \
  alpine:3.20 \
  sh -lc \
    'tar -xzf /backups/code-server-user-profile-YYYYMMDD-HHMMSS.tgz \
    -C /target'
```

After restore:

```bash
cd code-server-enterprise
docker compose up -d --force-recreate code-server
```

## Architecture

See [ARCHITECTURE.md](docs/status/ARCHITECTURE.md),
[ADR index](docs/adr/README.md), and
[Cloudflare tunnel ADR](docs/adr/006-cloudflare-tunnel-architecture.md).

## Contributing

See [CONTRIBUTING.md](docs/status/CONTRIBUTING.md) and
[GitHub Issues](https://github.com/kushin77/code-server/issues).

## Governance SSOT

- Elite best-practices index: [docs/governance/elite-best-practices/README.md](docs/governance/elite-best-practices/README.md)
- On-prem immutable/idempotent redeploy: [docs/governance/elite-best-practices/ssot/ON-PREM-REDEPLOY-IMMUTABLE-IDEMPOTENT.md](docs/governance/elite-best-practices/ssot/ON-PREM-REDEPLOY-IMMUTABLE-IDEMPOTENT.md)
- Repository structure and clean-tree policy: [docs/governance/elite-best-practices/structure/ELITE-FOLDER-STRUCTURE.md](docs/governance/elite-best-practices/structure/ELITE-FOLDER-STRUCTURE.md)
- Redeploy preflight automation: [scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh](scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh)

## Monorepo Workspace

- staged pnpm workspace plan: [docs/governance/elite-best-practices/monorepo/MONOREPO-PNPM-PLAN.md](docs/governance/elite-best-practices/monorepo/MONOREPO-PNPM-PLAN.md)
