# Docker Configuration

**Purpose**: Container orchestration, images, and configuration for code-server-enterprise infrastructure.

## Structure

```
docker/
├── README.md (this file)
├── docker-compose.yml - Base configuration (primary source)
├── docker-compose.override.yml - Development overrides (auto-loaded)
├── docker-compose.prod.yml - Production overrides (-f docker-compose.prod.yml)
│
├── images/ - Custom Docker images
│   ├── code-server/ - Code-server custom image
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   └── README.md
│   ├── caddy/ - Caddy reverse proxy image
│   ├── ssh-proxy/ - SSH proxy image
│   └── monitoring/ - Monitoring tools image
│
├── configs/ - Container configurations
│   ├── code-server/
│   │   └── code-server-config.yaml
│   ├── caddy/
│   │   ├── Caddyfile (base)
│   │   └── Caddyfile.prod (production overrides)
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alert-rules.yml
│   ├── alertmanager/
│   │   └── alertmanager.yml
│   └── grafana/
│       └── grafana-datasources.yml
│
└── volumes/ - Volume definitions and documentation
    └── README.md
```

## Quick Start

### Development (with overrides)

```bash
docker-compose up -d
# Auto-loads docker-compose.override.yml
```

### Production (explicit)

```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### View Status

```bash
docker-compose ps
docker-compose logs -f [service-name]
```

## Composition Strategy

### Base Configuration (docker-compose.yml)

Contains shared service definitions used by all environments:
- Service names and images
- Container networking  
- Volume mounts
- Common environment variables

### Development Overrides (docker-compose.override.yml)

Development-specific settings:
- Port exposures (0.0.0.0:PORT)
- Password credentials (dev values)
- Logging and debug settings

**Auto-loaded** when running `docker-compose up` locally.

### Production Overrides (docker-compose.prod.yml)

Production-specific settings:
- No direct port exposure (behind reverse proxy)
- Production credentials (from .env secrets)
- Resource limits
- Health check improvements

**Explicit**: `docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d`

## Environment Variables

Use `.env.example` as template (never commit real `.env`):

```bash
# Copy template
cp .env.example .env

# Edit with your values
nano .env

# Start containers (loads .env automatically)
docker-compose up -d
```

## Services

Each service has dedicated config directory:

| Service | Dir | Config | Image |
|---------|-----|--------|-------|
| code-server | configs/code-server/ | code-server-config.yaml | codercom/code-server:4.115.0 |
| caddy | configs/caddy/ | Caddyfile | caddy:2-alpine |
| prometheus | configs/prometheus/ | prometheus.yml | prom/prometheus:v2.48.0 |
| grafana | configs/grafana/ | grafana-datasources.yml | grafana/grafana:10.2.3 |
| alertmanager | configs/alertmanager/ | alertmanager.yml | prom/alertmanager:v0.26.0 |

## Common Tasks

### Add New Service

1. Create service in `docker-compose.yml` (base)
2. Create dedicated directory: `docker/configs/[service]/`
3. Place configuration file in that directory
4. Update volume mounts in compose file
5. Document in this README

### Update Configuration

1. Edit config file in `docker/configs/[service]/`
2. Reload: `docker-compose up -d [service-name]`
3. Verify: `docker-compose logs -f [service-name]`

### Add Custom Image

1. Create directory: `docker/images/[service]/`
2. Create `Dockerfile` and `entrypoint.sh`
3. Create `README.md` explaining the image
4. Build: `docker build -t [name]:[tag] docker/images/[service]/`
5. Reference in `docker-compose.yml`

### Port Exposure

**Development** (docker-compose.override.yml):
```yaml
services:
  code-server:
    ports:
      - "0.0.0.0:8080:8080"  # Exposed to host
```

**Production** (docker-compose.prod.yml):
```yaml
services:
  code-server:
    # NO ports exposed (behind Caddy reverse proxy)
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
docker-compose logs -f service-name

# Inspect configuration
docker-compose config

# Validate YAML
docker-compose config --quiet
```

### Port Already in Use

```bash
# Check which process is using port
lsof -i :8080

# Change port:
# Edit docker-compose.override.yml
# Change ports: ["0.0.0.0:9000:8080"]
# Restart: docker-compose up -d
```

### Volume Issues

```bash
# List volumes
docker volume ls | grep code-server

# Inspect volume
docker volume inspect volume-name

# Remove volume (CAREFUL!)
docker volume rm volume-name
```

## Network

All containers share `code-server-enterprise_enterprise` network.

**Service Discovery**: containers can reach each other by service name:
- `code-server:8080`
- `ollama:11434`
- `prometheus:9090`

## References

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
- [GOVERNANCE.md](../docs/GOVERNANCE.md#docker--container-configs)
- [Deployment Guide](../docs/guides/DEPLOYMENT.md)

## Maintenance

**Owner**: @akushnir  
**Last Updated**: April 14, 2026  
**Status**: Active production containers

---

**Related**:
- [../terraform/](../terraform/) - Infrastructure definition
- [../docs/guides/DEPLOYMENT.md](../docs/guides/DEPLOYMENT.md)
