## P2: Observability Integration (Prometheus/Grafana for Matrix)

### Summary

Integrate Matrix homeserver, bridges, and presence sidecar with existing Prometheus/Grafana observability stack. Add dashboards and alerts for collaboration infrastructure.

### Metrics to Collect

| Component | Metrics |
|-----------|---------|
| **Synapse** | Active users, message rate, room count, federation lag, DB pool, memory |
| **Bridges** | Messages bridged/sec, errors, latency, connection status |
| **Presence** | Connected users, updates/sec, WebSocket connections, latency |
| **Element Call** | Active calls, participants, call quality, drop rate |

### Prometheus Scrape Configuration

```yaml
# prometheus.yml additions

scrape_configs:
  - job_name: 'synapse'
    static_configs:
      - targets: ['synapse:9000']
    metrics_path: /_synapse/metrics
    scrape_interval: 15s
    
  - job_name: 'slack-bridge'
    static_configs:
      - targets: ['slack-bridge:29328']
    metrics_path: /metrics
    scrape_interval: 30s
    
  - job_name: 'presence-sidecar'
    static_configs:
      - targets: ['presence-sidecar:8089']
    metrics_path: /metrics
    scrape_interval: 15s
    
  - job_name: 'livekit'
    static_configs:
      - targets: ['livekit:7881']
    metrics_path: /metrics
    scrape_interval: 30s
```

### Synapse Metrics Configuration

```yaml
# homeserver.yaml

enable_metrics: true
metrics_port: 9000

# Detailed metrics
metrics_flags:
  known_servers: true
```

### Grafana Dashboards

#### Dashboard 1: Matrix Overview

```json
{
  "title": "Matrix Collaboration - Overview",
  "panels": [
    {
      "title": "Active Users (Matrix)",
      "type": "stat",
      "targets": [{ "expr": "synapse_registered_users" }]
    },
    {
      "title": "Messages/Hour",
      "type": "graph",
      "targets": [{ "expr": "rate(synapse_messages_total[1h])" }]
    },
    {
      "title": "Bridge Status",
      "type": "table",
      "targets": [{ "expr": "up{job=~'.*bridge.*'}" }]
    },
    {
      "title": "Presence Connections",
      "type": "stat",
      "targets": [{ "expr": "presence_websocket_connections_active" }]
    }
  ]
}
```

#### Dashboard 2: Real-Time Collaboration

```json
{
  "title": "Real-Time Collaboration - Live",
  "panels": [
    {
      "title": "Users Currently Editing",
      "type": "stat",
      "targets": [{ "expr": "presence_users_editing" }]
    },
    {
      "title": "Same-File Collaborations",
      "type": "graph",
      "targets": [{ "expr": "presence_same_file_pairs" }]
    },
    {
      "title": "Presence Update Latency (p99)",
      "type": "gauge",
      "targets": [{ "expr": "histogram_quantile(0.99, presence_update_latency_bucket)" }]
    },
    {
      "title": "Active Element Calls",
      "type": "stat",
      "targets": [{ "expr": "livekit_room_count" }]
    }
  ]
}
```

### Alert Rules

```yaml
# alert-rules.yml additions

groups:
  - name: matrix-collaboration-alerts
    rules:
      - alert: SynapseDown
        expr: up{job="synapse"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Matrix homeserver is down"
          runbook: "docs/runbooks/synapse-recovery.md"
          
      - alert: SlackBridgeDisconnected
        expr: up{job="slack-bridge"} == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Slack bridge is disconnected"
          
      - alert: PresenceSidecarDown
        expr: up{job="presence-sidecar"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Presence sidecar is down - real-time collaboration unavailable"
          
      - alert: HighPresenceLatency
        expr: histogram_quantile(0.99, presence_update_latency_bucket) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Presence updates taking >1s (p99)"
          
      - alert: BridgeMessageBacklog
        expr: bridge_message_queue_size > 100
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Bridge has message backlog - sync may be delayed"
          
      - alert: ElementCallQualityDegraded
        expr: livekit_packet_loss_ratio > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Element Call experiencing >5% packet loss"
```

### Presence Sidecar Metrics

```typescript
// apps/presence-sidecar/src/metrics.ts

import { Registry, Counter, Gauge, Histogram } from 'prom-client';

const register = new Registry();

export const metrics = {
  websocketConnections: new Gauge({
    name: 'presence_websocket_connections_active',
    help: 'Number of active WebSocket connections',
    registers: [register]
  }),
  
  usersOnline: new Gauge({
    name: 'presence_users_online',
    help: 'Number of users currently online',
    registers: [register]
  }),
  
  usersEditing: new Gauge({
    name: 'presence_users_editing',
    help: 'Number of users currently editing files',
    registers: [register]
  }),
  
  sameFilePairs: new Gauge({
    name: 'presence_same_file_pairs',
    help: 'Number of user pairs viewing same file',
    registers: [register]
  }),
  
  updateLatency: new Histogram({
    name: 'presence_update_latency',
    help: 'Latency of presence updates in seconds',
    buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
    registers: [register]
  }),
  
  updatesTotal: new Counter({
    name: 'presence_updates_total',
    help: 'Total presence updates processed',
    registers: [register]
  })
};

export { register };
```

### Acceptance Criteria

- [ ] Synapse metrics scraped by Prometheus
- [ ] Bridge metrics scraped (all configured bridges)
- [ ] Presence sidecar metrics scraped
- [ ] Element Call/LiveKit metrics scraped (if enabled)
- [ ] Overview dashboard created in Grafana
- [ ] Real-time collaboration dashboard created
- [ ] Critical alerts configured (Synapse down, presence down)
- [ ] Warning alerts configured (latency, backlog, quality)
- [ ] Alert notifications routed to Slack/PagerDuty
- [ ] Dashboards provisioned via Terraform

### Dependencies

- Requires: #965 (Existing observability infrastructure)
- Requires: #1001 (Matrix homeserver)
- Requires: #1003 (Presence sidecar)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
