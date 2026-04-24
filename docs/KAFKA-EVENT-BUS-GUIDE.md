# Kafka Event Bus Architecture - P3-1560

## Overview

The Kafka/Redpanda event bus is the central nervous system of ElevatedIQ DevOS. All engineering actions (deployments, agent tasks, incidents, code reviews) flow through Kafka topics, enabling:

- **Real-time visibility**: Activity Feed shows live engineering events
- **Full auditability**: 90 days - 2 years retention per topic
- **Loose coupling**: Services don't call each other; they publish and consume events
- **Replay capability**: Recover from failures by reprocessing events

## Deployment

### Quick Start

```bash
# Deploy Redpanda broker + Console UI
scripts/ops/setup-redpanda-eventbus.sh --deploy

# Verify deployment
curl http://localhost:9644/v1/cluster/brokers

# Access Redpanda Console
open http://localhost:8080
```

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Kafka Producers (All Services)                          │
│ - Prompt Gateway (ai.interactions)                      │
│ - Agent Runtime (agent.audit, agent.lifecycle)          │
│ - Deploy Orchestrator (deploy.events)                   │
│ - GitHub Actions (code.review)                          │
└─────────────────┬───────────────────────────────────────┘
                  │
        ┌─────────▼────────┐
        │ Redpanda Broker  │
        │ (Kafka API)      │
        │ Port: 9092       │
        │ Schema Registry  │
        │ Port: 8081       │
        └─────────┬────────┘
                  │
    ┌─────────────┼─────────────┬──────────────┐
    │             │             │              │
    ▼             ▼             ▼              ▼
┌────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│Activity│  │Reputation│  │Paperclip │  │Audit Log │
│ Feed   │  │ Engine   │  │Control   │  │PostgreSQL│
│Consumer│  │Consumer  │  │Plane     │  │+ Loki    │
└────────┘  └──────────┘  └──────────┘  └──────────┘
```

## Core Topics

### Agent Topics (90-day retention)

**agent.audit**: Every agent action with full context
```json
{
  "event_id": "uuid",
  "event_type": "agent.audit",
  "timestamp": "2026-04-25T10:00:00Z",
  "actor": {"type": "agent", "id": "agent/incident-responder/abc123"},
  "payload": {
    "task_id": "task-001",
    "task_description": "Fix 502 authentication error",
    "status": "success",
    "duration_seconds": 240,
    "tokens_used": 8432
  }
}
```

**agent.lifecycle**: Agent spawn/complete/fail/timeout events

### Deployment Topics (1-year retention)

**deploy.events**: All deployment starts/completions/failures
```json
{
  "event_id": "uuid",
  "event_type": "deploy.events",
  "payload": {
    "deploy_id": "deploy-2026-04-25-001",
    "status": "completed",
    "services": ["api", "frontend"],
    "environment": "production",
    "git_commit": "abc123def456",
    "duration_seconds": 180
  }
}
```

### Incident Topics (2-year retention)

**incident.events**: Incidents created/resolved/escalated
```json
{
  "event_id": "uuid",
  "event_type": "incident.events",
  "payload": {
    "incident_id": "INC-2026-001",
    "title": "Database connection pool exhausted",
    "severity": "critical",
    "status": "resolved",
    "duration_seconds": 1200
  }
}
```

### Code Review Topics (1-year retention)

**code.review**: PR opened/reviewed/merged/reverted
```json
{
  "event_id": "uuid",
  "event_type": "code.review",
  "payload": {
    "pr_number": 1234,
    "action": "opened|reviewed|merged|reverted",
    "git_commit": "abc123",
    "branch": "main"
  }
}
```

## Activity Feed API

### REST Endpoints

**Get recent activities**:
```bash
curl 'http://localhost:8000/api/activity?limit=50&severity=error'
```

Response:
```json
{
  "activities": [
    {
      "event_id": "uuid",
      "event_type": "agent.audit",
      "timestamp": "2026-04-25T10:00:00Z",
      "actor_id": "agent/incident-responder/abc123",
      "title": "Agent: Fix 502 authentication error",
      "severity": "info",
      "status": "success",
      "tags": ["agent", "success"]
    }
  ],
  "total": 1,
  "timestamp": "2026-04-25T10:01:00Z"
}
```

**WebSocket streaming** (real-time):
```javascript
const ws = new WebSocket('ws://localhost:8000/api/activity/stream');
ws.onmessage = (event) => {
  const activity = JSON.parse(event.data);
  console.log(`New activity: ${activity.data.title}`);
};
```

### Query Parameters

| Parameter | Description | Example |
|-----------|-------------|----------|
| `actor_id` | Filter by actor | `kushin77` or `agent/incident-responder/abc123` |
| `severity` | Filter by severity | `error`, `warning`, `info` |
| `service` | Filter by service | `agent-runtime`, `deploy-orchestrator` |
| `limit` | Result limit (1-500) | `50` |

## Producers (Phase 2 Integration)

### Prompt Gateway → ai.interactions
```python
from event_bus import EventProducer

producer = EventProducer()
event = EventEnvelope.create(
    event_type="ai.interactions",
    payload={"prompt": "...", "model": "gpt-4", "tokens": 1024},
    service="prompt-gateway",
    actor_id="user123"
)
producer.publish("ai.interactions", event)
```

### Agent Runtime → agent.audit
```python
event = EventEnvelope.create(
    event_type="agent.audit",
    payload={
        "task_id": task_id,
        "status": "success",
        "duration_seconds": elapsed,
        "tokens_used": token_count
    },
    service="agent-runtime",
    actor_id=agent_id
)
producer.publish("agent.audit", event)
```

## Consumers (Phase 2 Integration)

### Activity Feed Consumer
```python
consumer = ActivityFeedConsumer(topics=["agent.audit", "deploy.events", ...])
await consumer.consume_all_topics()

# All events aggregated into unified feed
# Available via REST API and WebSocket
```

### Reputation Engine Consumer
Listens to all topics, extracts signals for reputation scoring:
- Agent success rate
- Deployment velocity
- Incident resolution time
- Code review participation

### Audit Logger Consumer
Persists all events to:
- PostgreSQL: structured event table
- Loki: log aggregation for grep queries
- S3 (optional): long-term compliance storage

## Observability

### Prometheus Metrics

- `kafka_messages_received_total{topic}`: Messages per topic
- `kafka_consumer_lag{topic,consumer_group}`: Consumer lag
- `event_parsing_errors_total`: Failed event parsing
- `activity_feed_api_requests_total`: API request rate
- `activity_feed_websocket_connections`: Active WebSocket clients

### Grafana Dashboards

**Event Bus Health**:
- Message throughput per topic
- Consumer lag trends
- Error rate
- Producer latency p95

**Activity Feed**:
- Event count by type
- Severity distribution
- Actor activity heatmap
- Service-to-service event flow

## Troubleshooting

### Redpanda not starting
```bash
# Check logs
docker logs redpanda

# Verify broker connectivity
rpk cluster info --brokers=localhost:9092

# Check Schema Registry
curl http://localhost:8081/subjects
```

### High consumer lag
```bash
# Monitor consumer group lag
rpk group list --brokers=localhost:9092
rpk group describe activity-feed --brokers=localhost:9092

# Increase consumer parallelism or add more partitions
rpk topic alter-config agent.audit --brokers=localhost:9092 --set partitions=6
```

### WebSocket disconnections
- Check Activity Feed service logs: `docker logs activity-feed`
- Verify network connectivity between IDE and service
- Monitor memory usage on Activity Feed pod

## Security

- **Authentication**: Client certificates (GSM-managed)
- **Encryption**: TLS for broker-to-producer, broker-to-consumer
- **Authorization**: Topic ACLs per service
- **Data retention**: Encrypted on disk via EBS/NAS
- **Compliance**: All events audit-logged for SOC 2 attestation

## Performance Tuning

### Batch Settings
```python
producer = EventProducer(
    batch_size=1000,
    batch_timeout_ms=100,
    compression="snappy"
)
```

### Consumer Parallelism
```bash
# Create topic with more partitions
rpk topic create agent.audit --brokers=localhost:9092 --partitions=12

# Run multiple consumer instances
docker-compose scale activity-feed=3
```

## References

- **Redpanda Docs**: https://docs.redpanda.com/
- **Kafka Protocol**: https://kafka.apache.org/documentation/
- **Schema Registry**: https://docs.confluent.io/platform/current/schema-registry/
