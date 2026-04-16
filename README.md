# code-server — On-Premises VSCode Server

Production-grade self-hosted VSCode in the browser with enterprise security, monitoring, and high availability.

## Quick Start

```bash
# Core services (code-server + auth + proxy)
docker compose up -d

# With AI assistant (Ollama LLM)
COMPOSE_PROFILES=ai docker compose up -d

# With distributed tracing (OTel + Jaeger)
COMPOSE_PROFILES=tracing docker compose up -d

# Full stack
COMPOSE_PROFILES=ai,tracing docker compose up -d
```

## Production Hosts

| Host | Role | Access |
|------|------|--------|
| 192.168.168.31 | Primary | `ssh akushnir@192.168.168.31` |
| 192.168.168.42 | Replica | `ssh akushnir@192.168.168.42` |

## Services

| Service | Port | Profile |
|---------|------|---------|
| code-server | 8080 | core |
| oauth2-proxy | 4180 | core |
| caddy (TLS) | 80/443 | core |
| ollama (LLM) | 11434 | ai |
| otel-collector | 4317/4318 | tracing |
| jaeger UI | 16686 | tracing |

## Deployment

All deployments run **on the production host** (not locally):

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
docker compose up -d
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) and [ADR-001](ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [GitHub Issues](https://github.com/kushin77/code-server/issues).
