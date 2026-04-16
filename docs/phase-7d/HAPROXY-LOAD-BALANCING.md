# HAProxy Load Balancing & Failover (Phase 7d-002)

## Status: ACTIVE (Phase 7d Implementation)

This document describes the HAProxy-based load balancing and failover architecture for the on-prem code-server environment.

## Overview

HAProxy acts as the primary ingress point, providing:
- **High Availability**: Automated failover from primary (192.168.168.31) to replica (192.168.168.42).
- **Session Persistence**: Sticky sessions using the `JSESSIONID` cookie.
- **Health Monitoring**: Continuous health checks of backend services.
- **Observability**: Prometheus-compatible metrics and stats dashboard.

## Deployment Instructions

### Prerequisites
- Docker & Docker Compose on the host.
- Cloudflare Tunnel pointing to the HAProxy service (Port 80/443).

### Step 1: Configuration Validation
Run the setup check script:
```bash
./scripts/haproxy/setup-haproxy.sh
```

### Step 2: Production Host Setup
SSH to the primary production host:
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
```

### Step 3: Service Activation
Update your `docker-compose.production.yml` to include the `haproxy` service:

```yaml
services:
  haproxy:
    build:
      context: .
      dockerfile: docker/haproxy/Dockerfile
    ports:
      - "80:80"
      - "443:443"
      - "8404:8404" # Stats Dashboard
    volumes:
      - ./config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - code-server
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: always
```

## Failover Behavior

1. **Primary Node Healthy**: HAProxy routes all traffic to `192.168.168.31`.
2. **Primary Failure**: After 3 failures (inter 10s), HAProxy redirects traffic to `192.168.168.42` (backup).
3. **Primary Recovery**: After 2 successes, HAProxy gracefully switches back to primary.

## Monitoring
Access the dashboard locally on the host at:
`http://localhost:8404/haproxy-stats` (User: admin, Pass: admin123)

Primetheus metrics are available at:
`http://localhost:8404/metrics`

## Troubleshooting

### Config syntax error
```bash
docker run --rm haproxy:2.8-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

### Service logs
```bash
docker-compose logs -f haproxy
```
