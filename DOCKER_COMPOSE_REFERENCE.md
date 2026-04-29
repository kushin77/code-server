# Docker Compose File Structure

## Current State
- **Main File**: docker-compose.enterprise.yml (canonical)
- **Variants Archive**: docs/archive/docker-compose-variants/ (27 old files)
- **Status**: Consolidated to single source of truth

## File Organization

### Essential Files
```
docker-compose.enterprise.yml       # CANONICAL - All services
.env                                 # Base environment
.env.production                      # Production credentials
.env.cluster                         # Cluster configuration
```

### Archive Files (docs/archive/)
- docker-compose.yml variants (old versions)
- docker-compose.*.yml for specific services (deprecated)
- All consolidated into main file for consistency

## Service Organization in Main File

1. **Infrastructure Services**
   - PostgreSQL, Redis, Redpanda, OPA

2. **Observability Services**
   - Prometheus, Grafana, Loki, Tempo, OTEL Collector

3. **API Gateway & Reverse Proxy**
   - Kong, Caddy

4. **Application Services** (44 services)
   - Core services
   - Agent services
   - Infrastructure automation services

5. **Support Services**
   - Promtail, Vault, Keepalived

## Resource Limits Applied

- **Python services (FastAPI)**: 0.5-1.0 CPU, 512MB-2GB memory
- **Java services**: 1.0-2.0 CPU, 2GB-4GB memory
- **Database (PostgreSQL)**: 2.0 CPU, 4GB memory
- **Cache (Redis)**: 1.0 CPU, 2GB memory
- **Infrastructure (OPA, Caddy)**: 0.25-0.5 CPU, 256MB-512MB memory

## Health Checks Applied

- **HTTP services**: 30s interval, 10s timeout, 3 retries
- **TCP services**: Direct connection test
- **Database**: SQL query test
- **Message queues**: Topic/queue read test

## Networking

- **Services network**: All services connected
- **Exposed ports**: Only ingress (Caddy, Kong, Prometheus)
- **Internal communication**: Service name DNS resolution
- **Cluster VIP**: 192.168.168.250 (HAProxy frontend)

