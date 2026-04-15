# GOV-005: Docker Compose Parameterization

## Overview

GOV-005 eliminates hardcoded configuration values from docker-compose files by introducing environment variable parameterization.

Benefits:
- Environment-specific configurations (dev, staging, prod)
- Version management without editing docker-compose files
- Secret injection without code changes
- CI/CD pipeline integration

## Configuration Files

### .env.example
Reference file documenting all available parameterization options.

Usage:
\`\`\`bash
cp .env.example .env
# Edit .env with your environment-specific values
docker-compose up
\`\`\`

## Parameterized Values

### Service Versions
- POSTGRES_VERSION (default: 15-alpine)
- REDIS_VERSION (default: 7-alpine)
- CODE_SERVER_VERSION (default: 4.115.0)
- OAUTH2_PROXY_VERSION (default: v7.5.1)
- CADDY_VERSION (default: 2.9.1-alpine)
- PROMETHEUS_VERSION (default: v2.49.1)
- GRAFANA_VERSION (default: 10.4.1)
- ALERTMANAGER_VERSION (default: v0.27.0)
- JAEGER_VERSION (default: 1.55)

### Network Configuration
- HOST_IP: Host IP for Cloudflare Tunnel
- HOST_HOSTNAME: Hostname for service registration
- DOMAIN_BASE: Base domain for service discovery (nip.io style)
- DOMAIN_PROD: Production domain

## Docker-Compose Usage

All parameterized values use the VAR syntax in docker-compose.yml

## Security Considerations

- .env file contains secrets: add to .gitignore
- Use strong passwords in production
- Rotate secrets regularly
