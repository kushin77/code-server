# Edge Relay

Lightweight WebSocket proxy service for geographic edge relay nodes in the Kushnir.cloud collaboration platform.

## Overview

The edge relay provides low-latency WebSocket proxying for real-time collaboration traffic. It forwards client connections to the primary presence-sidecar service while maintaining geographic distribution for reduced latency.

## Features

- **Stateless Forwarding**: Simple WebSocket proxy that forwards all traffic to primary server
- **Geographic Distribution**: Deployed at edge locations for <50ms global latency
- **Health Monitoring**: Built-in health checks and Prometheus metrics
- **Connection Tracking**: Active connection monitoring and graceful shutdown
- **GeoDNS Routing**: Integrates with geographic DNS routing for optimal client assignment

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `PORT` | `8090` | Port to listen on |
| `PRIMARY_WS_URL` | `ws://localhost:8089` | Primary presence-sidecar WebSocket URL |
| `REDIS_URL` | `redis://localhost:6379` | Redis URL for metrics (optional) |
| `REGION_ID` | `unknown` | Geographic region identifier |
| `RELAY_ID` | `relay-{REGION_ID}-{timestamp}` | Unique relay identifier |

## Endpoints

- `GET /health` - Health check endpoint
- `GET /metrics` - Prometheus metrics endpoint
- `WS /` - WebSocket proxy endpoint

## Deployment

### Docker

```bash
docker build -t edge-relay .
docker run -p 8090:8090 \
  -e PRIMARY_WS_URL=ws://primary-server:8089 \
  -e REGION_ID=us-east-1 \
  edge-relay
```

### Kubernetes

Deploy with geographic node affinity for optimal latency:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-relay-us-east
spec:
  replicas: 3
  template:
    spec:
      nodeSelector:
        topology.kubernetes.io/region: us-east-1
      containers:
      - name: edge-relay
        image: edge-relay:latest
        env:
        - name: PRIMARY_WS_URL
          value: "ws://presence-sidecar.primary:8089"
        - name: REGION_ID
          value: "us-east-1"
        ports:
        - containerPort: 8090
```

## Architecture

```
Client ── GeoDNS ──> Edge Relay ──> Primary Presence-Sidecar
                    │                    │
                    └─ Health Checks     └─ Matrix/Room State
                    └─ Metrics           └─ Redis Pub/Sub
```

## Monitoring

The service exposes Prometheus metrics:

- `edge_relay_connections_total{direction="inbound|outbound"}` - Total connections
- `edge_relay_active_connections` - Active connection count
- `edge_relay_connection_latency_ms` - Connection establishment latency
- `edge_relay_messages_relayed_total{direction="client_to_upstream|upstream_to_client"}` - Message relay count

## Related Components

- **Presence-Sidecar**: Primary WebSocket service for real-time collaboration
- **EdgeRelayManager**: Manages relay selection and session affinity
- **GeoRouter**: Geographic request routing with region awareness