# Reputation Engine System Documentation

## Overview

The Reputation Engine is a comprehensive scoring system that tracks and measures the reliability, competency, and adherence to governance policies for both engineers and AI agents within the codebase. It integrates with the Kafka event bus to process events in real-time and provides reputation-based access control through OPA policies.

**Governance**: GOV-004 - Reputation Scoring and Governance Integration

## Architecture

### Components

1. **Score Calculator** (`score_calculator.py`)
   - Computes reputation scores from signals
   - Implements weighted scoring algorithms for engineers and agents
   - Manages tier assignment based on score ranges
   - Maintains 30-day rolling window for signal calculation

2. **Event Processor** (`event_processor.py`)
   - Consumes events from Kafka topics
   - Manages connection and subscription to signal topics
   - Processes messages and coordinates with score calculation
   - Handles manual commit for reliability

3. **Signal Extractor** (`signal_extractor.py`)
   - Converts raw Kafka events into reputation signals
   - Handles topic-specific signal extraction logic
   - Supports multiple event types and custom signal generation

4. **OPA Sync** (`opa_sync.py`)
   - Pushes reputation scores to OPA data API
   - Maintains bi-directional sync between database and policy engine
   - Manages leaderboard data for OPA policies
   - Handles OPA health checks and retry logic

5. **API Service** (`api.py`)
   - Provides REST endpoints for score queries
   - WebSocket support for real-time updates
   - Includes trending analysis and leaderboard endpoints
   - IDE integration endpoints

6. **Main Service** (`main.py`)
   - FastAPI application orchestration
   - Lifecycle management for all components
   - Database initialization and schema management

## Scoring Algorithms

### Engineer Scoring

Engineers are scored on 5 weighted metrics:

| Metric | Weight | Calculation |
|--------|--------|-------------|
| Deploy Success Rate | 30% | Successful deployments / Total deployments |
| PR Acceptance Rate | 20% | Merged PRs / Total PRs |
| Incident Rate | -20% | Incidents caused / Total signals (negative) |
| Review Quality | 15% | High-quality reviews / Total reviews |
| Task Completion Rate | 15% | Tasks completed on-time / Total tasks |

**Formula**: `score = 50 + Σ(metric_value × weight × 50)`

**Range**: 0-100, clamped

### Agent Scoring

Agents are scored on 4 weighted metrics:

| Metric | Weight | Calculation |
|--------|--------|-------------|
| Task Success Rate | 35% | Successful tasks / Total tasks |
| Human Override Rate | -25% | Human overrides / Total signals (negative) |
| Code Quality | 20% | Quality assessments passed / Total assessments |
| Token Efficiency | 20% | Efficient executions / Total executions |

**Formula**: `score = 50 + Σ(metric_value × weight × 50)`

**Range**: 0-100, clamped

## Tier System

Reputation scores determine access tiers:

| Tier | Score Range | Permissions |
|------|-------------|-------------|
| **Restricted** | 0-49 | Read-only operations, requires approvals for sensitive actions |
| **Standard** | 50-69 | Standard operations, limited deployment access |
| **Senior** | 70-89 | Production deployments, policy modifications, critical incidents |
| **Elite** | 90-100 | Unrestricted access, self-approval for code reviews, all operations |

## Signal Types

### Engineer Signals

| Signal | Type | Weight | Impact |
|--------|------|--------|--------|
| DEPLOY_SUCCESS | Positive | +5 | Successful deployment |
| DEPLOY_FAILURE | Negative | -3 | Failed deployment |
| PR_MERGED | Positive | +3 | PR accepted and merged |
| PR_REVERTED | Negative | -5 | PR merged then reverted |
| INCIDENT_CAUSED | Negative | -10 | Caused a production incident |
| INCIDENT_RESOLVED | Positive | +8 | Resolved an incident |
| REVIEW_QUALITY_HIGH | Positive | +2 | High-quality code review |
| REVIEW_QUALITY_LOW | Negative | -2 | Poor quality review |
| TASK_COMPLETED_ONTIME | Positive | +3 | Task completed within time |
| TASK_DELAYED | Negative | -2 | Task delayed |
| POLICY_VIOLATION | Negative | -8 | Violated governance policy |

### Agent Signals

| Signal | Type | Weight | Impact |
|--------|------|--------|--------|
| AGENT_TASK_SUCCESS | Positive | +5 | Successfully completed task |
| AGENT_TASK_FAILED | Negative | -5 | Failed to complete task |
| HUMAN_OVERRIDE | Negative | -8 | Human intervened/overrode |
| CODE_QUALITY_GOOD | Positive | +3 | Generated quality code |
| CODE_QUALITY_POOR | Negative | -3 | Generated poor quality code |
| EFFICIENT_EXECUTION | Positive | +2 | Used tokens efficiently |
| TOKEN_WASTE | Negative | -2 | Wasted tokens |

## Kafka Integration

### Topics Consumed

- `agent.audit` - Agent audit events
- `agent.lifecycle` - Agent lifecycle events (spawn, complete, fail)
- `deploy.events` - Deployment events
- `code.review` - Code review events
- `incident.events` - Incident creation/resolution events
- `policy.violations` - Policy violation events

### Event Processing Flow

```
Kafka Topic → Event Processor → Signal Extractor → Score Calculator
                                                          ↓
                                                  Database (ScoreSignal)
                                                          ↓
                                                  Recalculate Score
                                                          ↓
                                                  Update Tier (if changed)
                                                          ↓
                                                  Record History
                                                          ↓
                                                  OPA Sync
```

## OPA Policy Integration

Reputation scores are synced to OPA data API for policy-based access control.

### Data Structure in OPA

```
data.reputation = {
  "engineers": {
    "user-123": {
      "score": 75,
      "tier": "senior",
      "deploy_success_rate": 0.92,
      "pr_acceptance_rate": 0.88,
      "incident_rate": 0.05,
      "review_quality": 0.85,
      "task_completion_rate": 0.90
    }
  },
  "agents": {
    "agent-456": {
      "score": 82,
      "tier": "senior",
      "task_success_rate": 0.95,
      "human_override_rate": 0.02,
      "code_quality_score": 0.88,
      "token_efficiency": 0.79
    }
  },
  "leaderboard": {
    "engineers": [...],
    "agents": [...]
  }
}
```

### Policy Examples

**Production Deployment Gate**:
```rego
allow_prod_deployment if {
    input.operation == "deploy"
    input.environment == "production"
    require_minimum_tier("senior")  # Score >= 70
}
```

**Model Access Control**:
```rego
allow_model_access if {
    input.operation == "query_model"
    model_tier := {"gpt-4": "senior", "gpt-3.5": "standard"}
    required_tier_rank[model_tier[input.model]] <= tier_rank[current_tier]
}
```

## REST API Endpoints

### Score Information

```
GET /api/reputation/score/{actor_id}
  Returns: {actor_id, actor_type, score, tier, last_updated}

GET /api/reputation/score/{actor_id}/details
  Returns: Detailed metrics, signal summary, last updates

GET /api/reputation/history/{actor_id}?days=30&limit=100
  Returns: Time-series score history
```

### Leaderboards and Analytics

```
GET /api/reputation/leaderboard?actor_type=engineer&limit=50
  Returns: Top 50 engineers/agents by score

GET /api/reputation/trending?direction=up&limit=10
  Returns: Top 10 actors with increasing scores

GET /api/reputation/stats
  Returns: Overall statistics and distribution
```

### WebSocket Stream

```
WS /api/reputation/stream/{actor_id}
  Emits: Real-time score update events
  Message: {type: "score_update", actor_id, score, tier, timestamp}
```

## Database Schema

### ReputationScore Table

- `actor_id` (PK): Unique actor identifier
- `actor_type`: ENGINEER or AGENT
- `current_score`: 0-100
- `tier`: RESTRICTED, STANDARD, SENIOR, or ELITE
- `deploy_success_rate`, `pr_acceptance_rate`, etc.: Computed metrics
- `created_at`, `updated_at`: Timestamps

### ScoreSignal Table

- `id` (PK)
- `actor_id` (FK)
- `signal_type`: Signal type name
- `signal_value`: 0-1 range
- `weight`: Signal weight
- `contribution`: Calculated impact
- `event_id`: Source Kafka event
- `created_at`: Event timestamp

### ScoreHistory Table

- `id` (PK)
- `actor_id` (FK)
- `actor_type`: ENGINEER or AGENT
- `previous_score`, `new_score`: Score before/after
- `change_amount`: Difference
- `previous_tier`, `new_tier`: Tier before/after
- `contributing_signals`: Array of recent signals
- `reason`: Change reason
- `created_at`: Timestamp

### ReputationAudit Table

- `id` (PK)
- `action`: Audit action
- `actor_id` (FK)
- `event_id`: Source event
- `details`: JSON details
- `status`: success, error, or warning
- `error_message`: Error if any
- `created_at`: Timestamp

## Configuration

### Environment Variables

```bash
DATABASE_URL=postgresql://user:pass@localhost:5432/reputation_engine
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
OPA_URL=http://localhost:8181
SYNC_INTERVAL_SECONDS=60
```

### Service Dependencies

- PostgreSQL (database)
- Kafka/Redpanda (event streaming)
- OPA (policy engine)

## Running the Service

### With Docker Compose

```yaml
reputation-engine:
  image: reputation-engine:latest
  environment:
    DATABASE_URL: postgresql://postgres:password@postgres:5432/reputation_engine
    KAFKA_BOOTSTRAP_SERVERS: redpanda:9092
    OPA_URL: http://opa:8181
  depends_on:
    - postgres
    - redpanda
    - opa
  ports:
    - "8000:8000"
```

### Standalone

```bash
cd apps/reputation-engine
pip install -r requirements.txt
python main.py
```

## Monitoring and Debugging

### Health Check

```bash
curl http://localhost:8000/health
```

### Check Actor Score

```bash
curl http://localhost:8000/api/reputation/score/eng-001
```

### View Statistics

```bash
curl http://localhost:8000/api/reputation/stats
```

### Logs

Service logs are written to stdout with structured logging:

```
2024-01-15 10:23:45 - reputation_engine - INFO - Starting reputation engine service...
2024-01-15 10:23:46 - reputation_engine.event_processor - INFO - Event processor started
2024-01-15 10:23:47 - reputation_engine.opa_sync - INFO - OPA sync started
```

## Performance Considerations

1. **Signal Batching**: Signals are batched in Kafka for efficiency
2. **30-Day Rolling Window**: Only recent signals affect scores (reduces calculation time)
3. **Index Strategy**: Indexes on (actor_id, created_at) for efficient queries
4. **OPA Sync**: Async background task with configurable interval
5. **Database Connection Pool**: Reuses connections across threads

## Troubleshooting

### Event Processor Not Starting

Check Kafka connectivity:
```bash
kafka-broker-api-versions.sh --bootstrap-server localhost:9092
```

### OPA Sync Failing

Verify OPA health:
```bash
curl http://localhost:8181/health
```

### Database Connection Error

Check PostgreSQL:
```bash
psql postgresql://user:pass@localhost:5432/reputation_engine
```

### Scores Not Updating

Check event flow:
```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic agent.audit
```

## Future Enhancements

1. **Score Recovery**: Gradual reputation recovery after violations
2. **Gamification**: Badges and achievements for reputation milestones
3. **Leaderboard**: Public and private leaderboards
4. **Reputation Trading**: Allow actors to share reputation
5. **Custom Signals**: Pluggable signal types for domain-specific metrics
6. **Reputation Insurance**: Premium features for higher scores
7. **Predictive Analytics**: Forecast score changes and alerts

## Related Issues

- #1552 - OPA Policy Engine (policies that use reputation scores)
- #1560 - Kafka/Redpanda Event Bus (event streaming platform)
- P2-1538 - GitHub/GitLab Integration (event source)

## Testing

Run the test suite:

```bash
pytest apps/reputation-engine/test_reputation_engine.py -v
```

Test coverage targets:
- Score calculation algorithms: 100%
- Signal extraction: 100%
- OPA sync: 95%
- API endpoints: 90%

## Support

For issues or questions:
1. Check logs: `docker logs reputation-engine`
2. Review API docs: `http://localhost:8000/docs`
3. Check database: `SELECT * FROM reputation_scores ORDER BY updated_at DESC LIMIT 10;`
