# Reputation Engine

**Issue:** #1564 Phase 3 - Reputation Scoring & Tier-Based Access  
**Status:** ✅ IMPLEMENTATION COMPLETE  
**Framework:** FastAPI + SQLAlchemy + PostgreSQL + Redis  
**Python:** 3.11+

## Overview

The Reputation Engine tracks performance metrics for engineers and AI agents, computing reputation scores that determine access tiers and permissions. It provides real-time dashboards, event-driven scoring, and integrates with OPA (Open Policy Agent) for policy-based access control.

### Key Features

- **Real-Time Scoring**: Events trigger immediate reputation updates
- **Multi-Tier Access**: Restricted → Standard → Senior → Elite
- **AI Agent Tracking**: Dedicated signals for agent performance
- **Event-Driven Architecture**: Kafka integration for event processing
- **WebSocket Dashboard**: Real-time reputation updates via WebSocket
- **OPA Integration**: Policy-based access control tied to reputation
- **Audit Trail**: All scoring decisions logged for compliance (GOV-004)
- **Weighted Signals**: Configurable signal weights for flexible scoring

## Architecture

### Core Components

#### 1. **FastAPI Application** (`api.py`)
- RESTful API for reputation queries
- WebSocket endpoints for real-time dashboards
- Tier-based access control
- Rate limiting per tier
- Connection management for concurrent users

#### 2. **Score Calculator** (`score_calculator.py`)
- Calculates reputation from signals
- Tier determination logic
- Decay algorithm for time-based scoring
- Anomaly detection for unusual patterns
- Debugging and audit features

#### 3. **Signal Extractor** (`signal_extractor.py`)
- Maps events to reputation signals
- Configurable signal definitions
- Custom signal processors
- Event normalization and validation

#### 4. **Event Processor** (`event_processor.py`)
- Kafka consumer for events
- Async event processing
- Error handling and retries
- Batch processing optimization

#### 5. **OPA Sync** (`opa_sync.py`)
- Synchronizes reputation tiers with OPA policies
- Policy updates based on score changes
- Cross-service policy consistency
- Cache management

#### 6. **Data Models** (`models.py`)
- ReputationScore: Current score and tier
- ScoreSignal: Individual contributing factors
- ScoreHistory: Score timeline and changes
- ReputationAudit: Compliance audit trail

### API Endpoints

```
GET    /reputation/{actor_id}           # Get reputation score
GET    /reputation/{actor_id}/history   # Score history
POST   /reputation/calculate             # Recalculate score
GET    /access-tier/{actor_id}          # Get access tier
GET    /leaderboard                     # Top performers
GET    /signals                         # Available signals
WS     /ws/reputation/{actor_id}        # WebSocket real-time updates
POST   /audit/{actor_id}                # Audit log
GET    /health                          # Health check
```

## Data Models

### Reputation Score

```python
{
    "actor_id": "engineer:alice",
    "actor_type": "engineer",
    "reputation_score": 8450,
    "access_tier": "senior",
    "percentile": 87,
    "last_updated": "2026-04-28T12:00:00Z",
    "signals_count": 124,
    "signals_summary": {
        "deploy_success": 45,
        "pr_merged": 32,
        "review_quality_high": 28,
        "incident_resolved": 12
    }
}
```

### Signal Types

| Category | Signal | Impact | Range |
|----------|--------|--------|-------|
| **Deployment** | deploy_success | +50 | +10 to +50 |
| | deploy_failure | -100 | -200 to -100 |
| **Code Review** | pr_merged | +30 | +10 to +50 |
| | pr_reverted | -150 | -300 to -150 |
| | review_quality_high | +25 | +10 to +25 |
| | review_quality_low | -75 | -100 to -75 |
| **Incident Management** | incident_resolved | +200 | +100 to +200 |
| | incident_caused | -300 | -500 to -300 |
| **Task Management** | task_completed_ontime | +40 | +20 to +40 |
| | task_delayed | -50 | -100 to -50 |
| **Compliance** | policy_violation | -500 | -1000 to -500 |

### Access Tiers

| Tier | Score Range | Rate Limit | Permissions |
|------|-------------|-----------|-------------|
| **Restricted** | 0-2500 | 10 req/min | Read-only access |
| **Standard** | 2500-5000 | 50 req/min | Deployment staging |
| **Senior** | 5000-7500 | 100 req/min | Production deployment |
| **Elite** | 7500+ | 500 req/min | Admin & override permissions |

## Scoring Algorithm

### Base Calculation

```
reputation_score = Σ(signal_value × signal_weight) + time_decay_adjustment
```

### Signal Processing

1. **Event Ingestion**: Kafka event received
2. **Signal Extraction**: Event mapped to signal type
3. **Weight Application**: Signal weighted by actor tier
4. **Score Update**: Reputation updated in real-time
5. **Tier Recalculation**: New tier determined if threshold crossed
6. **OPA Sync**: Policies updated via OPA API
7. **Audit Logging**: Change recorded for compliance

### Time Decay

```
adjusted_score = base_score - (days_since_event × decay_rate)

decay_rate:
  - Recent (< 7 days): 0 (no decay)
  - Standard (7-30 days): 0.5 points/day
  - Old (> 30 days): 0.2 points/day
```

### Anomaly Detection

```
if signal_value > (mean + 3 × std_dev):
    flag_as_anomaly()
    apply_verification_review()
```

## Getting Started

### Prerequisites

- Python 3.11+
- FastAPI 0.124+
- PostgreSQL 14+
- Redis 7+
- Kafka (for event streaming)
- OPA (Open Policy Agent)

### Installation

1. **Install dependencies**:
```bash
cd apps/reputation_engine
pip install -r requirements.txt
```

2. **Configure database**:
```bash
# Set database URL
export DATABASE_URL="postgresql://user:password@localhost/reputation_engine"

# Run migrations
alembic upgrade head
```

3. **Configure services**:
```bash
# .env file
KAFKA_BROKERS=localhost:9092
OPA_URL=http://localhost:8181
REDIS_URL=redis://localhost:6379/0
LOG_LEVEL=INFO
```

### Running Locally

```bash
# Development (with reload)
cd apps/reputation_engine
uvicorn main:app --reload --host 0.0.0.0 --port 8083

# Or via Docker Compose
docker compose -f docker-compose.yml up reputation-engine
```

### Health Check

```bash
curl http://localhost:8083/health
# Response: {"status": "healthy", "database": "connected"}
```

## API Usage Examples

### Get Reputation Score

```bash
curl http://localhost:8083/reputation/engineer:alice

# Response:
{
  "actor_id": "engineer:alice",
  "actor_type": "engineer",
  "reputation_score": 8450,
  "access_tier": "senior",
  "percentile": 87,
  "last_updated": "2026-04-28T12:00:00Z",
  "signals_count": 124,
  "signals_summary": {
    "deploy_success": 45,
    "pr_merged": 32,
    "review_quality_high": 28
  }
}
```

### Get Score History

```bash
curl "http://localhost:8083/reputation/engineer:alice/history?days=30"

# Response:
{
  "actor_id": "engineer:alice",
  "history": [
    {
      "timestamp": "2026-04-28T12:00:00Z",
      "score": 8450,
      "tier": "senior",
      "signal": "deploy_success",
      "value": 50
    },
    {
      "timestamp": "2026-04-28T11:30:00Z",
      "score": 8400,
      "tier": "senior",
      "signal": "pr_merged",
      "value": 30
    }
  ]
}
```

### Get Leaderboard

```bash
curl "http://localhost:8083/leaderboard?limit=10"

# Response:
{
  "leaderboard": [
    {
      "rank": 1,
      "actor_id": "engineer:alice",
      "score": 8450,
      "tier": "senior",
      "deployments": 45
    },
    {
      "rank": 2,
      "actor_id": "engineer:bob",
      "score": 7890,
      "tier": "senior",
      "deployments": 38
    }
  ]
}
```

### WebSocket Real-Time Updates

```javascript
// Connect to WebSocket
const ws = new WebSocket('ws://localhost:8083/ws/reputation/engineer:alice');

ws.onmessage = (event) => {
  const update = JSON.parse(event.data);
  console.log(`Score updated: ${update.reputation_score} (${update.access_tier})`);
};

ws.onopen = () => {
  console.log('Connected to reputation updates');
};
```

### Record Event Signal

```bash
# Signal recorded via Kafka event
# Event format:
{
  "event_type": "deployment",
  "actor_id": "engineer:alice",
  "actor_type": "engineer",
  "result": "success",
  "timestamp": "2026-04-28T12:00:00Z",
  "metadata": {
    "service": "auth-server",
    "environment": "production"
  }
}

# Processed as:
# - Signal: deploy_success
# - Value: +50
# - Score updated from 8400 to 8450
```

## Event Integration

### Kafka Event Format

```python
{
    "event_type": "deployment",      # deployment, code_review, incident, task
    "actor_id": "engineer:alice",    # Unique actor identifier
    "actor_type": "engineer",        # engineer or agent
    "result": "success",             # success, failure, etc.
    "timestamp": "2026-04-28T12:00:00Z",
    "metadata": {
        "service": "auth-server",
        "environment": "production",
        "duration_seconds": 156
    }
}
```

### Event to Signal Mapping

| Event Type | Result | Signal | Value |
|-----------|--------|--------|-------|
| deployment | success | deploy_success | +50 |
| deployment | failure | deploy_failure | -100 |
| code_review | merged | pr_merged | +30 |
| code_review | reverted | pr_reverted | -150 |
| incident | resolved | incident_resolved | +200 |
| incident | caused | incident_caused | -300 |
| task | completed_ontime | task_completed_ontime | +40 |
| task | delayed | task_delayed | -50 |

## OPA Integration

### Policy Synchronization

```bash
# Reputation engine updates OPA with actor scores
POST http://localhost:8181/v1/data/reputation/actor_tiers \
  -H "Content-Type: application/json" \
  -d '{
    "engineer:alice": "senior",
    "engineer:bob": "standard",
    "agent:deployer-1": "elite"
  }'

# OPA policy uses for access control
package deployment

allow {
    actor_tier := reputation.actor_tiers[input.actor_id]
    actor_tier in ["senior", "elite"]
    input.environment == "production"
}
```

## Governance & Compliance

**GOV-004: Reputation Scoring & Tier-Based Access**
- All scoring decisions are auditable with full history
- Score changes logged with reason and timestamp
- Anomalies flagged for manual review
- Quarterly reputation audits for accuracy
- Signal weights reviewed and tuned quarterly

## Performance Tuning

### Caching Strategy
- Current reputation cached in Redis (5-minute TTL)
- Leaderboard cached (15-minute TTL)
- OPA policy cache (30-minute TTL)

### Database Optimization
- Indexes on actor_id, created_at for fast queries
- Score history partitioned by month
- Archived old signals to separate table

### Batch Processing
- Events batched in 100ms windows
- Bulk score updates every 1 second
- Leaderboard recalculated every 5 minutes

## Monitoring & Observability

### Metrics

```
# Reputation changes
reputation_score_updates_total
reputation_tier_changes_total
reputation_anomalies_detected_total

# Event processing
reputation_events_processed_total
reputation_event_latency_seconds
reputation_event_errors_total

# Access control
reputation_access_denied_total
reputation_rate_limit_exceeded_total
```

## Production Deployment Checklist

- [ ] PostgreSQL 14+ with replication
- [ ] Redis cluster for caching
- [ ] Kafka cluster for event streaming
- [ ] OPA deployment with policy sync
- [ ] Prometheus scraping configured
- [ ] Log aggregation configured
- [ ] Alert rules set for anomalies
- [ ] Backup strategy for reputation database
- [ ] Regular audit schedule established

## Known Limitations

- **Scoring Lag**: Events processed within 1-5 seconds (depends on Kafka backlog)
- **Tier Cooldown**: Tier changes effective immediately, but visible in API with <1s delay
- **Signal Retention**: Detailed signals retained for 2 years, then archived
- **Actor Limit**: ~1M concurrent actors per deployment
- **Leaderboard Size**: Top 10,000 updated every 5 minutes

## Troubleshooting

### Issue: "Kafka connection failed"
```bash
# Verify Kafka is running
kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Check KAFKA_BROKERS env var
echo $KAFKA_BROKERS
```

### Issue: "Reputation not updating"
```bash
# Check if events are being consumed
# Monitor Kafka consumer group
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group reputation-engine --describe

# Manually trigger recalculation
curl -X POST http://localhost:8083/reputation/recalculate/engineer:alice
```

### Issue: "OPA sync failed"
```bash
# Verify OPA is running
curl http://localhost:8181/health

# Check if policies can be updated
curl -X PUT http://localhost:8181/v1/data/reputation/test -d '{}'
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│ FastAPI Application (port 8083)                        │
│  - GET /reputation/{actor_id}                          │
│  - WS /ws/reputation/{actor_id}                        │
│  - POST /learn/record                                  │
└────────────┬────────────┬──────────────┬───────────────┘
             │            │              │
       ┌─────▼──┐  ┌──────▼────┐  ┌─────▼──┐
       │Postgres│  │   Redis   │  │  OPA   │
       │  DB    │  │   Cache   │  │ Policy │
       │        │  │           │  │        │
       └────────┘  └───────────┘  └────────┘
       
       ┌──────────────────────────────────┐
       │      Kafka Event Stream          │
       │ (deployment, code_review, etc)   │
       └──────────────────────────────────┘
```

## References

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [SQLAlchemy ORM](https://docs.sqlalchemy.org/)
- [Kafka Python Client](https://kafka-python.readthedocs.io/)
- [Open Policy Agent (OPA)](https://www.openpolicyagent.org/)
- [GOV-004: Tier-Based Access Control](../GOVERNANCE.md)
