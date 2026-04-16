# P2-432: Docker Compose Profiles Implementation Guide

## Overview

This document explains the Docker Compose profiles system for kushin77/code-server, enabling selective service startup and configuration management for different deployment scenarios.

## Profiles Available

### Core Services (Always Active)
Services without profile specification start with `docker compose up`:
- **code-server**: VS Code editor environment (port 8080)
- **caddy**: Reverse proxy and SSL/TLS termination (ports 80, 443)
- **oauth2-proxy**: OpenID Connect proxy for authentication (port 4180)
- **postgresql**: Primary database (port 5432)
- **redis**: Session cache and data store (port 6379)

### Profile: `ai`
Enables AI/LLM services for Ollama integration:

```bash
COMPOSE_PROFILES=ai docker compose up -d
```

Services:
- **ollama**: Local LLM inference engine (port 11434)
- **ollama-webui**: Web interface for Ollama models (port 3000)

Performance impact: +512MB memory, +1 CPU core under load

### Profile: `tracing`
Enables distributed tracing for observability:

```bash
COMPOSE_PROFILES=tracing docker compose up -d
```

Services:
- **jaeger**: Distributed tracing backend (port 16686)
- **jaeger-collector**: Trace ingestion endpoint (port 14268)

Performance impact: +256MB memory, negligible CPU

### Profile: `monitoring`
Enables comprehensive monitoring stack:

```bash
COMPOSE_PROFILES=monitoring docker compose up -d
```

Services:
- **prometheus**: Metrics collection and storage (port 9090)
- **grafana**: Metrics visualization and dashboards (port 3000)
- **alertmanager**: Alert routing and aggregation (port 9093)
- **node-exporter**: Host metrics exporter (port 9100)

Performance impact: +384MB memory, +1 CPU under load

### Profile: `logging`
Enables centralized logging stack:

```bash
COMPOSE_PROFILES=logging docker compose up -d
```

Services:
- **loki**: Log aggregation and storage (port 3100)
- **promtail**: Log collector and forwarder (port 9080)

Performance impact: +256MB memory, variable based on log volume

### Profile: `iam`
Enables additional IAM/authentication services:

```bash
COMPOSE_PROFILES=iam docker compose up -d
```

Services:
- **token-microservice**: JWT token issuance service (port 5000)
- **vault**: Secrets management (port 8200)

Performance impact: +192MB memory, negligible CPU

## Combined Profiles

Multiple profiles can be enabled together:

```bash
# Development: Core + AI + Monitoring + Tracing
COMPOSE_PROFILES=ai,monitoring,tracing docker compose up -d

# Full Stack: All services
COMPOSE_PROFILES=ai,monitoring,tracing,logging,iam docker compose up -d

# Production: Core + Monitoring + IAM only
COMPOSE_PROFILES=monitoring,iam docker compose up -d
```

## Memory and Resource Allocation

| Scenario | Memory | CPU | Disk |
|----------|--------|-----|------|
| Core only | 512MB | 1.0 | 5GB |
| Core + AI | 1.0GB | 2.0 | 15GB |
| Core + Monitoring | 896MB | 1.5 | 8GB |
| Core + All | 2.5GB | 4.0 | 30GB |

## Configuration via Environment Variables

### AI Profile Configuration
```bash
OLLAMA_MODEL=mistral            # Model to load
OLLAMA_NUM_PARALLEL=4           # Parallel requests
OLLAMA_KEEP_ALIVE=60s           # Model cache duration
```

### Monitoring Profile Configuration
```bash
PROMETHEUS_RETENTION=30d        # Metrics retention
GRAFANA_ADMIN_PASSWORD=admin123 # Grafana admin password
ALERTMANAGER_CONFIG=config/     # Alert rules path
```

### Logging Profile Configuration
```bash
LOKI_RETENTION=7d               # Log retention
PROMTAIL_BATCH_SIZE=1000        # Log batch size
```

### IAM Profile Configuration
```bash
TOKEN_TTL=15m                   # JWT token lifetime
VAULT_ADDR=http://vault:8200    # Vault server address
```

## Service Dependencies

```
[Core]
  ├── code-server
  │   ├── oauth2-proxy ← required
  │   ├── postgresql ← required
  │   └── redis ← required
  ├── caddy
  └── [shared infrastructure]

[AI] → depends on [Core]
  ├── ollama
  └── ollama-webui

[Monitoring] → depends on [Core]
  ├── prometheus
  ├── grafana
  ├── alertmanager
  └── node-exporter

[Tracing] → depends on [Core]
  ├── jaeger
  └── jaeger-collector

[Logging] → depends on [Core]
  ├── loki
  └── promtail

[IAM] → depends on [Core]
  ├── token-microservice
  └── vault
```

## Health Check Commands

### Core Services
```bash
# Code-server
curl http://localhost:8080

# OAuth2-proxy
curl http://localhost:4180/oauth2/healthz

# PostgreSQL
docker compose exec postgresql pg_isready -U postgres

# Redis
docker compose exec redis redis-cli ping
```

### With Profiles
```bash
# Ollama (if ai profile active)
curl http://localhost:11434/api/tags

# Prometheus (if monitoring profile active)
curl http://localhost:9090/-/healthy

# Jaeger (if tracing profile active)
curl http://localhost:16686/api/services
```

## Troubleshooting

### Profile Not Starting
```bash
# Verify profile is listed
docker compose config --profiles

# Check service status
docker compose ps --services --filter "status=running"

# View service logs
docker compose logs -f <service_name>
```

### Port Conflicts
```bash
# Find process using port
lsof -i :8080

# Change port in docker-compose.yml
# Or use environment variable:
CODE_SERVER_PORT=8081 docker compose up -d code-server
```

### Memory/CPU Limits
```bash
# View current usage
docker stats

# Increase docker-compose memory limit
# Edit docker-compose.yml and adjust:
# services:
#   <service>:
#     deploy:
#       resources:
#         limits:
#           memory: 1G
#           cpus: '2.0'
```

## Production Deployment

For production (192.168.168.31):

```bash
# Core + Monitoring + IAM
COMPOSE_PROFILES=monitoring,iam docker compose -f docker-compose.production.yml up -d

# Verify all services healthy
docker compose ps

# Check metrics
curl http://192.168.168.31:9090/api/v1/query?query=up
```

## Migration Between Profiles

### From Core to Core + Monitoring
```bash
# Current state: only core
docker compose ps

# Enable monitoring without disrupting core
COMPOSE_PROFILES=monitoring docker compose up -d

# Verify all services running
docker compose ps
```

### From Full Stack to Minimal
```bash
# Stop all
docker compose down

# Start only core
docker compose up -d

# Or selectively keep only monitoring
COMPOSE_PROFILES=monitoring docker compose up -d
```

## Related Issues

- **#432**: Docker Compose profiles implementation
- **#362**: Production environment abstraction

## See Also

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [docker-compose.yml](../docker-compose.yml) - Main composition file
- [docker-compose.production.yml](../docker-compose.production.yml) - Production overrides
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
