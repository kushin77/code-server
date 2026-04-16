# P2 #432: Docker Compose Selective Profiles Implementation Guide
# Enable lightweight dev or full production stack with profiles

## Quick Start

```bash
# Core only (minimal, lightweight dev)
docker-compose up -d

# Core + monitoring (prometheus, grafana, alertmanager)
docker-compose --profile monitoring up -d

# Core + tracing (jaeger distributed traces)
docker-compose --profile tracing up -d

# Core + AI (ollama LLM inference)
docker-compose --profile ai up -d

# Production: all profiles
docker-compose --profile monitoring --profile tracing --profile ai up -d
```

## Profile Architecture

| Profile | Services | Memory | CPU | Use Case |
|---------|----------|--------|-----|----------|
| (none) | code-server, postgres, redis, caddy | 512 MB | 0.5 | Dev |
| monitoring | + prometheus, grafana, alertmanager | 2 GB | 1.0 | Prod metrics |
| tracing | + jaeger | 1 GB | 0.5 | Observability |
| ai | + ollama | 8+ GB | 2+ | LLM inference |
| logging | + loki, promtail | 500 MB | 0.25 | Log aggregation |

## Service Allocation

### Core (Always Running, No Profile)
- **code-server** (4.115.0): VS Code IDE
- **postgres** (15): Application database
- **redis** (7): Cache/session store
- **caddy** (2.7.6): Reverse proxy, TLS termination

### Monitoring Profile
- **prometheus** (v2.48.0): Metrics collection
- **grafana** (10.2.3): Dashboard visualization
- **alertmanager** (v0.26.0): Alert aggregation and routing

### Tracing Profile
- **jaeger** (1.50): Distributed tracing backend

### AI Profile
- **ollama** (latest): LLM inference engine (GPU-optional)

### Logging Profile
- **loki** (2.9.4): Log aggregation
- **promtail** (2.9.4): Log shipper

## Environment Variables

Set in `.env`:
```bash
# Core
CODE_SERVER_PASSWORD=<strong-password>
POSTGRES_PASSWORD=<strong-password>
REDIS_PASSWORD=<strong-password>

# Monitoring
GRAFANA_ADMIN_PASSWORD=<strong-password>
PROMETHEUS_RETENTION=30d

# Tracing
JAEGER_COLLECTOR_HTTP_PORT=14268

# AI
OLLAMA_HOST=0.0.0.0:11434

# Logging
LOKI_RETENTION_DAYS=30
```

## Benefits

✅ **Lightweight dev** (512 MB, no monitoring overhead)
✅ **Production-ready** (add monitoring, tracing, logging as needed)
✅ **Resource control** (enable only what you need)
✅ **Cost optimization** (no unused container overhead)
✅ **Easy experimentation** (toggle profiles on/off instantly)
✅ **Backward compatible** (existing docker-compose.yml still works)

## Integration with Makefile

```makefile
.PHONY: docker-dev docker-prod docker-monitoring docker-ai docker-logs

docker-dev:
	docker-compose up -d
	@echo "✓ Core services running"

docker-prod:
	docker-compose --profile monitoring --profile tracing --profile logging up -d
	@echo "✓ Full production stack running"

docker-monitoring:
	docker-compose --profile monitoring up -d

docker-ai:
	docker-compose --profile ai up -d

docker-logs:
	docker-compose logs -f
```

## Status Checking

```bash
# See which services are running
docker-compose ps

# Check specific profile
docker-compose --profile monitoring ps

# View service logs
docker logs prometheus
docker logs grafana
docker logs jaeger
```

## Resource Limits per Profile

- **Core**: 512 MB RAM, 0.5 CPU
- **Monitoring**: +2 GB RAM, +1 CPU
- **Tracing**: +1 GB RAM, +0.5 CPU
- **AI**: +8 GB RAM, +2 CPU (GPU if available)
- **Logging**: +500 MB RAM, +0.25 CPU

**Total Production (all profiles)**: ~12 GB RAM, ~4 CPU

---

**Status**: ✅ COMPLETE - Ready to update docker-compose.yml with profile definitions
