# P1 #1313: WebSocket Gateway Cluster - Deployment Guide

## Overview

This guide covers deploying the 3-node WebSocket relay cluster with HAProxy load balancing and Redis Pub/Sub message fan-out for 1000+ concurrent connections.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Clients (1000+)                       │
└────────────┬────────────────────────────────────────────────┘
             │ WebSocket Connections (HTTP/HTTPS)
             ▼
┌─────────────────────────────────────────────────────────────┐
│                  HAProxy Load Balancer                       │
│  - Port 8080 (HTTP), 8443 (HTTPS), 8404 (Stats)             │
│  - Consistent hash routing by session_id                     │
│  - Health checks on relay nodes                              │
└───────────┬─────────────────────────┬──────────────┬────────┘
            │                         │              │
     ┌──────▼──────┐          ┌───────▼────┐   ┌────▼───────┐
     │  WS Relay 1 │          │ WS Relay 2 │   │ WS Relay 3 │
     │ (3001, 1/3) │          │(3002, 1/3) │   │(3003, 1/3) │
     └──────┬──────┘          └───────┬────┘   └────┬───────┘
            │                         │              │
            └─────────────────────────┼──────────────┘
                                      │
                            ┌─────────▼────────┐
                            │   Redis Pub/Sub   │
                            │   Port 6379       │
                            └───────────────────┘
```

## Prerequisites

- Linux host (Ubuntu 20.04+) with Docker and Docker Compose
- Minimum 2 CPU cores, 2GB RAM per relay node
- Network ports available: 8080, 8443, 8404, 6379, 3001-3003
- Git and curl installed

## Installation Steps

### 1. Clone Repository

```bash
cd /home/akushnir
git clone https://github.com/kushin77/code-server.git
cd code-server
```

### 2. Install Dependencies

```bash
# Install Node.js dependencies for WebSocket relay
npm install ws redis express
npm install -D k6

# Install HAProxy (if not using Docker)
# sudo apt-get install haproxy redis-server
```

### 3. Deploy with Docker Compose

```bash
# Start the WebSocket gateway cluster
docker-compose -f docker-compose.websocket-gateway.yml up -d

# Verify all services are running
docker-compose -f docker-compose.websocket-gateway.yml ps

# Check logs
docker-compose -f docker-compose.websocket-gateway.yml logs -f
```

### 4. Verify Cluster Health

```bash
# Check HAProxy stats page
curl http://localhost:8404/stats

# Test WebSocket connectivity
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
  -H "Sec-WebSocket-Version: 13" \
  http://localhost:8080/ws?session_id=test-session-1

# Check individual relay nodes
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health

# Verify Redis
redis-cli -p 6379 PING
```

## Load Testing

### Run k6 Load Test (1000 concurrent WebSocket pairs)

```bash
# Option 1: Run locally installed k6
k6 run scripts/tests/k6-websocket-gateway-test.js \
  --vus 1000 \
  --duration 15m \
  --env GATEWAY_HOST=localhost

# Option 2: Run via Docker (if k6 container available)
docker run --rm --network=websocket-cluster \
  -v $(pwd)/scripts/tests:/scripts \
  grafana/k6 run /scripts/k6-websocket-gateway-test.js \
  --vus 1000 \
  --duration 15m \
  -e GATEWAY_HOST=haproxy
```

### Expected Results

- **Connection Time (p95):** < 2 seconds
- **Message Latency (p95):** < 100 milliseconds
- **Throughput:** > 10k messages/second across cluster
- **Error Rate:** < 1%
- **Sustained Connections:** 1000+ concurrent WebSocket pairs

### Performance Tuning

If results don't meet expectations:

```bash
# Increase HAProxy worker processes
haproxy -f /etc/haproxy/haproxy.cfg -c -w

# Increase system limits for open files
ulimit -n 65536

# Tune Linux kernel for high throughput
sysctl -w net.ipv4.tcp_max_syn_backlog=65536
sysctl -w net.core.somaxconn=65536
sysctl -w net.ipv4.tcp_fin_timeout=30

# Increase Redis memory
redis-cli CONFIG SET maxmemory 2gb
```

## Monitoring

### Access Dashboards

- **HAProxy Stats:** http://localhost:8404/stats
- **Prometheus:** http://localhost:9090
- **Grafana:** http://localhost:3000 (admin/admin)

### Key Metrics to Monitor

1. **Connection Metrics**
   - Active connections per relay node
   - Connection establishment time
   - Connection drop rate

2. **Message Metrics**
   - Messages/sec per node
   - Message latency distribution
   - Message loss rate

3. **System Metrics**
   - CPU usage per relay node
   - Memory usage
   - Network throughput (bytes/sec)
   - File descriptor usage

4. **Redis Metrics**
   - Pub/Sub subscription count
   - Message throughput (ops/sec)
   - Memory usage
   - Connected clients

## Failover and Recovery

### Node Failure Scenario

If a relay node fails:

1. **HAProxy** automatically removes the node from the backend pool
2. **New connections** are routed to healthy nodes
3. **Existing connections** on failed node are dropped (clients should reconnect)
4. **Restart failed node:**

```bash
docker-compose -f docker-compose.websocket-gateway.yml restart ws-relay-1
```

### Redis Failure Scenario

If Redis goes down:

1. **All relay nodes** lose ability to broadcast messages
2. **Messages are buffered** in client connections
3. **Restart Redis:**

```bash
docker-compose -f docker-compose.websocket-gateway.yml restart redis
```

To prevent Redis as a single point of failure, consider:
- Redis Sentinel for automatic failover
- Redis Cluster for horizontal scaling
- Multiple Redis instances with replication

## Production Deployment

### Deploy to Primary Host (192.168.168.31)

```bash
# Copy files to production host
scp -r docker-compose.websocket-gateway.yml akushnir@192.168.168.31:~/code-server/
scp -r scripts/infrastructure/setup-websocket-gateway-cluster.sh akushnir@192.168.168.31:~/code-server/scripts/infrastructure/
scp -r scripts/tests/k6-websocket-gateway-test.js akushnir@192.168.168.31:~/code-server/scripts/tests/

# SSH to primary host
ssh akushnir@192.168.168.31

# Start cluster
cd ~/code-server
docker-compose -f docker-compose.websocket-gateway.yml up -d

# Verify
docker-compose -f docker-compose.websocket-gateway.yml ps
curl http://localhost:8404/stats
```

### Deploy to Replica Host (192.168.168.42)

Repeat the same steps for the replica host to enable failover.

## Security Considerations

1. **TLS/HTTPS**
   - Generate self-signed certs: `openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365`
   - Place in `certs/` directory
   - HAProxy will use for HTTPS termination

2. **Redis Authentication**
   - Set `requirepass` in redis.conf
   - Update `REDIS_URL` in relay services

3. **Network Isolation**
   - Use Docker network `websocket-cluster` (internal only)
   - Expose only HAProxy ports externally

4. **Rate Limiting**
   - Configure HAProxy rate limiting per session_id
   - Implement application-level rate limiting in relay nodes

## Troubleshooting

### High Latency

```bash
# Check if relay nodes are overloaded
docker stats ws-relay-1 ws-relay-2 ws-relay-3

# Check network latency
ping -c 5 192.168.168.31

# Check Redis latency
redis-cli LATENCY DOCTOR
```

### Connection Drops

```bash
# Check HAProxy logs
docker logs websocket-haproxy | grep ERROR

# Check relay node logs
docker logs websocket-relay-1 | grep error

# Check system limits
ulimit -a
```

### Message Loss

```bash
# Check Redis Pub/Sub
redis-cli PUBSUB CHANNELS
redis-cli PUBSUB NUMSUB workspace:*

# Check relay node message counters
curl http://localhost:3001/health | jq '.messages_received'
```

## Rollback Procedure

If issues arise, rollback to previous version:

```bash
# Stop current cluster
docker-compose -f docker-compose.websocket-gateway.yml down

# Revert git changes
git checkout HEAD~1

# Restart cluster
docker-compose -f docker-compose.websocket-gateway.yml up -d
```

## References

- HAProxy Documentation: http://www.haproxy.org/
- Redis Pub/Sub: https://redis.io/docs/pubsub/
- k6 Load Testing: https://k6.io/docs/
- Docker Compose: https://docs.docker.com/compose/
- WebSocket RFC 6455: https://tools.ietf.org/html/rfc6455

---

**Status:** Implementation complete, deployment-ready
