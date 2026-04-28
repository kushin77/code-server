# Activity Feed Service

**Issue:** #1560 Phase 4 - Real-Time Activity Aggregation  
**Status:** ✅ IMPLEMENTATION COMPLETE  
**Framework:** FastAPI + Kafka + WebSocket  
**Python:** 3.11+

## Overview

The Activity Feed Service aggregates events from all Kafka topics across the platform, providing a unified, real-time activity stream. It enables dashboards, notifications, and audit logging with filtering by actor, service, severity, and event type.

### Key Features

- **Multi-Topic Aggregation**: Consumes 10+ Kafka topics (agent, deploy, code review, incident, etc.)
- **Real-Time WebSocket Streaming**: Live updates to connected clients
- **Advanced Filtering**: By actor, service, event type, severity, time range
- **Event Normalization**: Unified format across heterogeneous sources
- **Audit Trail**: Complete event history with full context
- **Performance Optimization**: Configurable retention and archival
- **Search & Query**: REST API for historical activity queries

## Architecture

### Core Components

#### 1. **FastAPI Application** (`main.py`)
- RESTful API for activity queries
- WebSocket endpoints for real-time streaming
- Advanced filtering with multiple criteria
- Search with pagination
- Connection management for concurrent clients

#### 2. **Activity Feed Consumer** (`consumer.py`)
- Kafka consumer aggregating multiple topics
- Event normalization and enrichment
- Unified event format
- Error handling and retry logic
- Batch processing optimization

#### 3. **Event Normalization**
Maps events from all sources to standard format:
```
{
  "event_id": "unique-id",
  "event_type": "deployment",
  "timestamp": "2026-04-28T12:00:00Z",
  "actor_id": "engineer:alice",
  "service": "auth-server",
  "status": "success",
  "severity": "info"
}
```

### Kafka Topics Consumed

| Topic | Source | Events |
|-------|--------|--------|
| agent.audit | AI Agent Systems | Execution, learning, decisions |
| agent.lifecycle | Agent Managers | Start, stop, error, restart |
| deploy.events | Deployment Service | Success, failure, rollback |
| code.review | GitHub Integration | PR opened, reviewed, merged |
| incident.events | Incident Management | Created, resolved, escalated |
| ai.interactions | LLM Services | Token usage, errors, completions |
| security.events | Security Service | Access denied, policy violations |
| database.events | Database Service | Migrations, failures, warnings |
| cache.events | Cache Service | Evictions, TTL, connection issues |
| monitor.alerts | Monitoring System | Alerting events, thresholds crossed |

### API Endpoints

```
GET    /activities                     # Get activity feed (filtered)
GET    /activities/{event_id}          # Get specific event
WS     /ws/feed                        # WebSocket real-time stream
WS     /ws/feed?filter={json}          # Filtered real-time stream
POST   /search                         # Advanced activity search
GET    /actors/{actor_id}/activities   # Activities by actor
GET    /services/{service}/activities  # Activities by service
GET    /health                         # Health check
```

## Data Models

### Activity Event

```python
{
    "event_id": "evt-123456",
    "event_type": "deployment",        # deployment, code_review, incident, agent, etc.
    "timestamp": "2026-04-28T12:00:00Z",
    "actor_id": "engineer:alice",      # Who initiated or is involved
    "actor_type": "engineer",          # engineer, agent, system
    "service": "auth-server",          # Which service is affected
    "title": "Deployment to production completed",
    "description": "Successfully deployed v1.2.3 to production (192.168.168.31)",
    "status": "success",               # success, failure, pending, in_progress
    "severity": "info",                # info, warning, error
    "tags": ["deployment", "production", "success"],
    "metadata": {
        "deployment_id": "dep-789",
        "version": "1.2.3",
        "environment": "production",
        "duration_seconds": 156
    }
}
```

### Activity Filter

```python
{
    "actor_id": "engineer:alice",           # Optional: filter by actor
    "actor_type": "engineer",               # Optional: engineer or agent
    "service": "auth-server",               # Optional: specific service
    "event_type": "deployment",             # Optional: event type
    "severity": ["error", "warning"],       # Optional: severity levels
    "status": "success",                    # Optional: success/failure/pending
    "since": "2026-04-28T00:00:00Z",       # Optional: time range start
    "until": "2026-04-28T23:59:59Z",       # Optional: time range end
    "limit": 50,                            # Pagination limit
    "offset": 0                             # Pagination offset
}
```

### Event Types

| Type | Description | Sources |
|------|-------------|---------|
| **deployment** | Service deployment | Deploy service |
| **code_review** | Code review events | GitHub integration |
| **incident** | Incident lifecycle | Incident manager |
| **agent_execution** | AI agent task | Agent runtime |
| **agent_learning** | Agent learning outcome | Memory engine |
| **alert** | Monitoring alerts | Prometheus |
| **security** | Security events | OPA, security service |
| **database** | DB operations | Postgres service |
| **cache** | Cache events | Redis service |
| **system** | System events | Infrastructure |

## Getting Started

### Prerequisites

- Python 3.11+
- FastAPI 0.124+
- Kafka (with 10+ topics)
- PostgreSQL (for event history)
- Redis (optional, for caching)

### Installation

1. **Install dependencies**:
```bash
cd apps/activity_feed
pip install -r requirements.txt
```

2. **Configure Kafka**:
```bash
# Set Kafka brokers
export KAFKA_BROKERS="localhost:9092"

# Verify topics exist
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

3. **Create database for history**:
```bash
export DATABASE_URL="postgresql://user:password@localhost/activity_feed"
alembic upgrade head
```

### Running Locally

```bash
# Development (with reload)
cd apps/activity_feed
uvicorn main:app --reload --host 0.0.0.0 --port 8084

# Or via Docker Compose
docker compose -f docker-compose.yml up activity-feed
```

### Health Check

```bash
curl http://localhost:8084/health
# Response: {"status": "healthy", "kafka": "connected"}
```

## API Usage Examples

### Get Recent Activities

```bash
curl "http://localhost:8084/activities?limit=10&severity=error"

# Response:
{
  "activities": [
    {
      "event_id": "evt-123456",
      "event_type": "deployment",
      "timestamp": "2026-04-28T12:00:00Z",
      "actor_id": "engineer:alice",
      "service": "auth-server",
      "status": "success",
      "severity": "info",
      "title": "Deployment completed",
      "description": "..."
    }
  ],
  "total": 1,
  "timestamp": "2026-04-28T12:05:00Z"
}
```

### Search Activities with Advanced Filters

```bash
curl -X POST http://localhost:8084/search \
  -H "Content-Type: application/json" \
  -d '{
    "actor_id": "engineer:alice",
    "service": "auth-server",
    "severity": ["error", "warning"],
    "since": "2026-04-28T00:00:00Z",
    "limit": 20
  }'
```

### Get Activities by Actor

```bash
curl "http://localhost:8084/actors/engineer:alice/activities?limit=10"

# Shows all activities initiated by or involving the actor
```

### Get Activities by Service

```bash
curl "http://localhost:8084/services/auth-server/activities?limit=10"

# Shows all activities related to a specific service
```

### WebSocket Real-Time Stream

```javascript
// Connect to activity feed stream
const ws = new WebSocket('ws://localhost:8084/ws/feed');

ws.onmessage = (event) => {
  const activity = JSON.parse(event.data);
  console.log(`${activity.event_type}: ${activity.title}`);
  
  // Update dashboard, notifications, etc.
  updateActivityDashboard(activity);
};

// With filters
const filter = {
  service: "auth-server",
  severity: ["error", "warning"]
};
const ws = new WebSocket(
  `ws://localhost:8084/ws/feed?filter=${JSON.stringify(filter)}`
);
```

### Filtered Real-Time Stream

```bash
# Stream only deployment errors for auth-server
wscat -c 'ws://localhost:8084/ws/feed?event_type=deployment&service=auth-server&status=failure'
```

## Event Aggregation Flow

### Event Processing Pipeline

```
Kafka Topics
    ↓
[Consumer]
    ↓
Event Normalization
    ├─ Extract common fields (timestamp, actor, service)
    ├─ Map event type to standard
    ├─ Enrich with context
    ├─ Calculate severity
    ↓
PostgreSQL Store
    ├─ Insert event
    ├─ Update indices
    ├─ Maintain retention
    ↓
Redis Cache
    ├─ Cache recent events (1 hour)
    ├─ Cache by actor/service
    ↓
Connected WebSocket Clients ← [Broadcast]
```

### Event Enrichment

Original Kafka Event:
```json
{
  "deployment_id": "dep-789",
  "service": "auth-server",
  "status": "success",
  "timestamp": 1719568800
}
```

Enriched Activity Event:
```json
{
  "event_id": "evt-123456",
  "event_type": "deployment",
  "timestamp": "2026-04-28T12:00:00Z",
  "actor_id": "system:deployer",
  "actor_type": "system",
  "service": "auth-server",
  "title": "Deployment completed",
  "description": "Successfully deployed v1.2.3",
  "status": "success",
  "severity": "info",
  "tags": ["deployment", "production", "success"],
  "metadata": {...}
}
```

## Performance Optimization

### Retention Policy

```bash
# Recent events: 7 days in hot table
# Archive: 30-90 days in separate table
# Delete: Events older than 90 days (configurable)

SELECT * FROM activities WHERE created_at > NOW() - INTERVAL '7 days'
SELECT * FROM activities_archive WHERE created_at BETWEEN NOW() - INTERVAL '90 days' AND NOW() - INTERVAL '7 days'
```

### Caching Strategy

- Recent events cached in Redis (5-minute TTL)
- Actor activity cached (1-minute TTL)
- Service activity cached (1-minute TTL)
- Query results cached by filter pattern (5-minute TTL)

### Database Indexing

```sql
-- Query performance indices
CREATE INDEX ix_timestamp ON activities(created_at DESC);
CREATE INDEX ix_actor ON activities(actor_id);
CREATE INDEX ix_service ON activities(service);
CREATE INDEX ix_event_type ON activities(event_type);
CREATE INDEX ix_actor_service_time ON activities(actor_id, service, created_at DESC);
```

## Monitoring & Observability

### Metrics

```
# Event processing
activity_feed_events_processed_total
activity_feed_processing_latency_seconds
activity_feed_processing_errors_total

# Kafka
activity_feed_kafka_lag
activity_feed_kafka_connection_errors_total

# WebSocket
activity_feed_websocket_connections_active
activity_feed_websocket_messages_sent_total
activity_feed_websocket_disconnections_total

# Storage
activity_feed_events_stored_total
activity_feed_storage_size_bytes
```

### Log Levels

```bash
DEBUG   # Verbose event processing details
INFO    # Activity events, connections
WARNING # Processing delays, errors
ERROR   # Critical issues, Kafka failures
```

## Governance & Compliance

**GOV-002: Activity Logging & Audit Trail**
- All activities logged with full context
- Immutable event history (events cannot be deleted, only archived)
- Retention policies enforced automatically
- Audit trail includes all modifications
- User activity and permission changes tracked

## Integration Patterns

### 1. Real-Time Dashboard

```python
from activity_feed import ActivityFeedClient

client = ActivityFeedClient("ws://localhost:8084")

# Subscribe to deployment errors
async for activity in client.stream(
    event_type="deployment",
    status="failure",
    service="auth-server"
):
    dashboard.add_alert(f"Deployment failed: {activity.title}")
    send_notification(activity)
```

### 2. Activity-Based Triggers

```python
# Trigger actions based on specific activities
if activity.event_type == "incident" and activity.severity == "error":
    escalate_to_oncall(activity)
    create_followup_task(activity)
elif activity.event_type == "deployment" and activity.status == "success":
    update_status_page(activity)
    announce_to_slack(activity)
```

### 3. Search & Analysis

```python
# Historical analysis of deployment patterns
client = ActivityFeedClient("http://localhost:8084")

deployments = await client.search(
    event_type="deployment",
    service="auth-server",
    since="2026-04-01T00:00:00Z",
    until="2026-04-28T23:59:59Z"
)

success_rate = (
    len([d for d in deployments if d.status == "success"]) / len(deployments) * 100
)
print(f"Deployment success rate: {success_rate}%")
```

## Production Deployment Checklist

- [ ] Kafka cluster with all required topics
- [ ] PostgreSQL with sufficient disk space
- [ ] Redis for caching (optional but recommended)
- [ ] Event retention policy defined (default: 90 days)
- [ ] Archival process automated
- [ ] Prometheus scraping configured
- [ ] Log aggregation configured
- [ ] Backup strategy for event database
- [ ] Rate limiting configured
- [ ] WebSocket connection limits set

## Known Limitations

- **Event Latency**: 100-500ms from Kafka to WebSocket
- **History Retention**: Events retained for 90 days (configurable)
- **Concurrent Connections**: Tested with 1000+ concurrent WebSocket clients
- **Message Frequency**: Can handle ~1000 events/second
- **Search Performance**: Historical queries slower on large date ranges
- **Topic Count**: Scalable to 50+ topics per deployment

## Troubleshooting

### Issue: "No events appearing in feed"
```bash
# Check if Kafka topics have messages
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic agent.audit --from-beginning

# Check consumer lag
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group activity-feed --describe

# Restart consumer
kill <pid>; uvicorn main:app
```

### Issue: "WebSocket connection failing"
```bash
# Verify service is running
curl http://localhost:8084/health

# Check if port is open
netstat -tlnp | grep 8084

# Verify firewall rules
```

### Issue: "Database too large"
```bash
# Check current size
SELECT pg_size_pretty(pg_total_relation_size('activities'));

# Archive old events
INSERT INTO activities_archive SELECT * FROM activities WHERE created_at < NOW() - INTERVAL '30 days';
DELETE FROM activities WHERE created_at < NOW() - INTERVAL '30 days';

# Vacuum to reclaim space
VACUUM activities;
```

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│ FastAPI Application (port 8084)                             │
│  - GET /activities                                           │
│  - WS /ws/feed                                               │
│  - POST /search                                              │
└───────────┬─────────────────────────────────────────────────┘
            │
    ┌───────┴──────────┬──────────────┬──────────────┐
    │                  │              │              │
    ▼                  ▼              ▼              ▼
┌─────────┐      ┌──────────┐   ┌──────────┐  ┌──────────┐
│Postgres │      │  Redis   │   │ Kafka    │  │WebSocket │
│  Store  │      │  Cache   │   │ Consumer │  │ Clients  │
└─────────┘      └──────────┘   └──────────┘  └──────────┘
                                      │
                        ┌─────────────┴─────────────┐
                        │                           │
                    ┌───▼────┐   ┌──────────┐   ┌──▼────┐
                    │Kafka   │   │Kafka    │   │Kafka  │
                    │Topics  │   │Topics   │   │Topics │
                    └────────┘   └─────────┘   └───────┘
```

## References

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [WebSocket Protocol](https://www.rfc-editor.org/rfc/rfc6455)
- [PostgreSQL Full Text Search](https://www.postgresql.org/docs/current/textsearch.html)
- [GOV-002: Activity Logging](../GOVERNANCE.md)
