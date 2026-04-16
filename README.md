# code-server — On-Premises VSCode Server

Production-grade self-hosted VSCode in the browser with enterprise security, monitoring, and high availability.

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

| Mode | Compose command | Includes |
|---|---|---|
| IDE-only | `docker compose up -d` | code-server, oauth2-proxy, caddy, postgres, redis |
| IDE + AI | `COMPOSE_PROFILES=ai docker compose up -d` | IDE-only + ollama |
| IDE + Observability | `COMPOSE_PROFILES=monitoring,tracing docker compose up -d` | IDE-only + prometheus, grafana, alertmanager, loki, promtail, otel-collector, jaeger |
| Full platform | `COMPOSE_PROFILES=monitoring,tracing,ai docker compose up -d` | IDE, AI, and observability stack |

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
# Dev overlay — bypasses oauth2-proxy, exposes db ports
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

## Deployment

All deployments run **on the production host** (not locally):

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
docker compose up -d
```

For AI or observability in production, use the same profile flags from `Quick Start` on host `192.168.168.31`.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md), [ADR index](docs/adr/README.md), and [Cloudflare tunnel ADR](docs/adr/006-cloudflare-tunnel-architecture.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [GitHub Issues](https://github.com/kushin77/code-server/issues).
