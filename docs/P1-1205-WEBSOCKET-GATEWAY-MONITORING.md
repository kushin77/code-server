# WebSocket Gateway Cluster - Prometheus Configuration

## Scrape Jobs for WSG Monitoring

Add these to prometheus.yml under `scrape_configs`:

```yaml
  - job_name: 'websocket-gateway-cluster'
    static_configs:
      - targets: 
        - 192.168.168.31:19090
        - 192.168.168.31:19091
        - 192.168.168.31:19092
        - 192.168.168.42:19090
        - 192.168.168.42:19091
        - 192.168.168.42:19092
    scrape_interval: 15s
    scrape_timeout: 10s
    metrics_path: /metrics
    scheme: https
    tls_config:
      insecure_skip_verify: true
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
      - source_labels: [__scheme__]
        target_label: scheme
```

---

## Alert Rules for WSG Cluster

Add these to alert-rules.yml under `groups`:

```yaml
  - name: websocket_gateway
    interval: 30s
    rules:
      # Container health alerts
      - alert: WSGContainerDown
        expr: up{job="websocket-gateway-cluster"} == 0
        for: 1m
        labels:
          severity: critical
          component: websocket-gateway
        annotations:
          summary: "WebSocket Gateway container {{ $labels.instance }} is down"
          description: "WSG container at {{ $labels.instance }} has been unreachable for > 1 minute"
      
      # Connection load alerts
      - alert: WSGHighConnectionLoad
        expr: websocket_gateway_active_connections > 5000
        for: 5m
        labels:
          severity: warning
          component: websocket-gateway
        annotations:
          summary: "High connection load on WSG node {{ $labels.node_id }}"
          description: "{{ $value }} active connections on {{ $labels.node_id }}"
      
      # Message latency alerts
      - alert: WSGHighLatency
        expr: histogram_quantile(0.99, websocket_gateway_message_latency_bucket) > 500
        for: 5m
        labels:
          severity: warning
          component: websocket-gateway
        annotations:
          summary: "High p99 latency on {{ $labels.node_id }}"
          description: "p99 message latency {{ $value }}ms on {{ $labels.node_id }}"
      
      # Hash ring consistency
      - alert: WSGHashRingInconsistent
        expr: websocket_gateway_hash_ring_nodes != 3
        for: 2m
        labels:
          severity: high
          component: websocket-gateway
        annotations:
          summary: "Hash ring inconsistency detected on {{ $labels.node_id }}"
          description: "Hash ring reports {{ $value }} nodes (expected 3)"
      
      # Redis connectivity
      - alert: WSGRedisDisconnected
        expr: websocket_gateway_redis_connected == 0
        for: 1m
        labels:
          severity: critical
          component: websocket-gateway
        annotations:
          summary: "WebSocket Gateway {{ $labels.node_id }} lost Redis connection"
          description: "WSG cannot connect to Redis on {{ $labels.node_id }}"
      
      # Session eviction rate
      - alert: WSGHighSessionEviction
        expr: rate(websocket_gateway_sessions_evicted_total[5m]) > 10
        for: 5m
        labels:
          severity: warning
          component: websocket-gateway
        annotations:
          summary: "High session eviction rate on {{ $labels.node_id }}"
          description: "{{ $value }} sessions/sec being evicted on {{ $labels.node_id }}"
      
      # Error rate
      - alert: WSGHighErrorRate
        expr: rate(websocket_gateway_errors_total[5m]) > 0.01
        for: 5m
        labels:
          severity: high
          component: websocket-gateway
        annotations:
          summary: "High error rate on {{ $labels.node_id }}"
          description: "Error rate {{ $value }} on {{ $labels.node_id }}"
```

---

## Grafana Dashboard Configuration

Create a new dashboard "WebSocket Gateway Cluster" with these panels:

### Panel 1: Node Status
```
expr: up{job="websocket-gateway-cluster"}
title: Node Status
legend: {{instance}}
visualization: Status
```

### Panel 2: Active Connections
```
expr: websocket_gateway_active_connections{job="websocket-gateway-cluster"}
title: Active Connections
legend: {{node_id}}
visualization: Graph
```

### Panel 3: Message Latency (p99)
```
expr: histogram_quantile(0.99, websocket_gateway_message_latency_bucket{job="websocket-gateway-cluster"})
title: Message Latency (p99)
legend: {{node_id}}
visualization: Graph
unit: ms
```

### Panel 4: Messages Per Second
```
expr: rate(websocket_gateway_messages_total[1m]){job="websocket-gateway-cluster"}
title: Throughput (msg/sec)
legend: {{node_id}}
visualization: Graph
```

### Panel 5: Hash Ring Consistency
```
expr: websocket_gateway_hash_ring_nodes
title: Hash Ring Nodes
legend: {{node_id}}
visualization: Stat
thresholds: [0, 3]
```

### Panel 6: Redis Connection Status
```
expr: websocket_gateway_redis_connected
title: Redis Connection Status
legend: {{node_id}}
visualization: Stat
thresholds: [0, 1]
```

### Panel 7: Error Rate
```
expr: rate(websocket_gateway_errors_total[5m]){job="websocket-gateway-cluster"}
title: Error Rate
legend: {{node_id}}
visualization: Graph
```

### Panel 8: Session TTL Distribution
```
expr: websocket_gateway_session_ttl_seconds
title: Session TTL (seconds)
legend: {{node_id}}
visualization: Heatmap
```

---

## Alert Routing

Add to alertmanager.yml to route WebSocket Gateway alerts to critical channels:

```yaml
routes:
  - match:
      component: websocket-gateway
      severity: critical
    receiver: critical_alerts
    group_by: ['component', 'severity']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    
  - match:
      component: websocket-gateway
      severity: high
    receiver: high_priority_alerts
    group_by: ['component', 'severity']
    group_wait: 1m
    group_interval: 5m
    repeat_interval: 12h
    
  - match:
      component: websocket-gateway
      severity: warning
    receiver: channel_alerts
    group_by: ['component', 'severity']
    group_wait: 5m
    group_interval: 30m
    repeat_interval: 24h
```

---

## Key Metrics Explained

| Metric | Unit | Purpose |
|--------|------|---------|
| `websocket_gateway_active_connections` | count | Number of active WebSocket connections per node |
| `websocket_gateway_message_latency_bucket` | ms | Histogram of message processing latency |
| `websocket_gateway_hash_ring_nodes` | count | Current number of nodes in hash ring (should be 3) |
| `websocket_gateway_redis_connected` | 0/1 | Redis connectivity status |
| `websocket_gateway_sessions_evicted_total` | count | Sessions evicted due to TTL |
| `websocket_gateway_errors_total` | count | Total errors encountered |
| `websocket_gateway_session_ttl_seconds` | seconds | Current session TTL |

---

## Expected Metrics Output

Each WSG node will export metrics on its `/metrics` endpoint:

```
# HELP websocket_gateway_active_connections Current number of active WebSocket connections
# TYPE websocket_gateway_active_connections gauge
websocket_gateway_active_connections{node_id="wsg-1"} 125

# HELP websocket_gateway_message_latency_bucket Message processing latency histogram
# TYPE websocket_gateway_message_latency_bucket histogram
websocket_gateway_message_latency_bucket{node_id="wsg-1",le="10"} 1000
websocket_gateway_message_latency_bucket{node_id="wsg-1",le="50"} 9500
websocket_gateway_message_latency_bucket{node_id="wsg-1",le="100"} 9750
websocket_gateway_message_latency_bucket{node_id="wsg-1",le="+Inf"} 10000

# HELP websocket_gateway_hash_ring_nodes Current number of nodes in hash ring
# TYPE websocket_gateway_hash_ring_nodes gauge
websocket_gateway_hash_ring_nodes{node_id="wsg-1"} 3

# HELP websocket_gateway_redis_connected Redis connection status
# TYPE websocket_gateway_redis_connected gauge
websocket_gateway_redis_connected{node_id="wsg-1"} 1

# HELP websocket_gateway_errors_total Total errors encountered
# TYPE websocket_gateway_errors_total counter
websocket_gateway_errors_total{node_id="wsg-1",error_type="connection_failed"} 2
websocket_gateway_errors_total{node_id="wsg-1",error_type="message_timeout"} 1
```

---

## Deployment Steps

1. Add scrape job configuration to `prometheus.yml`
2. Add alert rules to `alert-rules.yml`
3. Configure alert routing in `alertmanager.yml`
4. Reload Prometheus: `docker-compose exec prometheus kill -HUP 1`
5. Verify targets in Prometheus UI: `https://prometheus.kushnir.cloud/targets`
6. Create Grafana dashboard using panel definitions above

