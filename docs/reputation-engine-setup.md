# Reputation Engine Configuration

## Docker Compose Integration

Add the reputation engine service to your docker-compose.yml:

```yaml
reputation-engine:
  build: ./apps/reputation-engine
  ports:
    - "8000:8000"
  environment:
    DATABASE_URL: "postgresql://postgres:postgres@postgres:5432/reputation_engine"
    KAFKA_BOOTSTRAP_SERVERS: "redpanda:9092"
    OPA_URL: "http://opa:8181"
    PYTHONUNBUFFERED: "1"
  depends_on:
    - postgres
    - redpanda
    - opa
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
```

## Initial Setup

1. **Create Database**:
```bash
psql -U postgres -c "CREATE DATABASE reputation_engine;"
```

2. **Install Dependencies**:
```bash
pip install -r apps/reputation-engine/requirements.txt
```

3. **Initialize Database**:
```bash
python -c "from apps.reputation_engine.models import Base, engine; Base.metadata.create_all(bind=engine)"
```

4. **Start Service**:
```bash
cd apps/reputation-engine
python main.py
```

## Kafka Topics Required

Ensure these topics exist in your Kafka cluster:

```bash
# Create topics with proper retention
kafka-topics.sh --create --topic agent.audit \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=7776000000  # 90 days

kafka-topics.sh --create --topic agent.lifecycle \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=7776000000

kafka-topics.sh --create --topic deploy.events \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=31536000000  # 1 year

kafka-topics.sh --create --topic code.review \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=31536000000

kafka-topics.sh --create --topic incident.events \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=63072000000  # 2 years

kafka-topics.sh --create --topic policy.violations \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=31536000000
```

## OPA Configuration

The reputation engine requires OPA to be accessible with the Data API enabled:

```json
{
  "services": {
    "opa": {
      "url": "http://opa:8181"
    }
  },
  "decision_logs": {
    "console": true
  }
}
```

## Integration with Existing Services

### Activity Feed Service
The Activity Feed service in `apps/activity-feed/` consumes from the same Kafka topics. Both services:
- Subscribe to the same topics
- Process events independently
- Activity Feed aggregates for display
- Reputation Engine scores for access control

### OPA Policy Engine
The Reputation Engine syncs scores to OPA via:
1. HTTP PUT requests to `/v1/data/reputation/engineers/{actor_id}`
2. Regular leaderboard updates to `/v1/data/reputation/leaderboard`

OPA policies can reference reputation data:
```rego
import data.reputation

allow_deployment if {
    input.operation == "deploy"
    actor_score := data.reputation.engineers[input.actor_id].score
    actor_score >= 70  # Senior tier required
}
```

### CI/CD Integration

Add reputation engine health check to deployment pipeline:

```bash
#!/bin/bash
# scripts/ci/check-reputation-engine.sh

# Wait for reputation engine to be ready
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -f http://reputation-engine:8000/health; then
        echo "Reputation engine is healthy"
        exit 0
    fi
    attempt=$((attempt+1))
    sleep 2
done

echo "Reputation engine failed to start"
exit 1
```

## Performance Tuning

### Database Connection Pool
```python
from sqlalchemy.pool import QueuePool

engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=20,
    max_overflow=40,
)
```

### Kafka Consumer Configuration
```python
conf = {
    "bootstrap.servers": KAFKA_BOOTSTRAP_SERVERS,
    "group.id": "reputation-engine",
    "fetch.min.bytes": 1024,
    "fetch.wait.max.ms": 500,
    "batch.num.messages": 100,
    "linger.ms": 100,
}
```

### OPA Sync Batching
Sync operations are batched to reduce API calls:
- Individual score sync: On each signal
- Leaderboard sync: Every 5 minutes
- Bulk sync: On service startup

## Monitoring

### Metrics to Track

1. **Signal Processing**:
   - Signals per minute
   - Average processing latency
   - Error rate

2. **Score Updates**:
   - Score changes per hour
   - Tier changes per day
   - Average score per actor type

3. **OPA Sync**:
   - Sync success rate
   - OPA health status
   - Data consistency

### Logging

Enable DEBUG logging for troubleshooting:

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

Monitor these log patterns:
- `Recording signal:` - Signal processing
- `Updated reputation:` - Score recalculation
- `Synced score to OPA:` - OPA updates
- `Error` - Any failures

## Backup and Recovery

### Database Backup
```bash
pg_dump reputation_engine > backup.sql
```

### Score Recalculation
In case of data inconsistency, trigger full recalculation:

```python
from sqlalchemy.orm import sessionmaker
from apps.reputation_engine.score_calculator import ScoreCalculator
from apps.reputation_engine.models import ReputationScore

Session = sessionmaker(bind=engine)
session = Session()
calculator = ScoreCalculator(session)

# Recalculate all scores
for score in session.query(ReputationScore).all():
    calculator.recalculate_score(score.actor_id)
```

## Troubleshooting Guide

### Symptoms: Scores Not Updating

**Diagnosis**:
1. Check Kafka connectivity: `kafka-broker-api-versions.sh --bootstrap-server localhost:9092`
2. Verify topic existence: `kafka-topics.sh --list --bootstrap-server localhost:9092`
3. Monitor event processor logs

**Solution**:
- Ensure Kafka is running and accessible
- Verify topics are created with correct names
- Check `DATABASE_URL` environment variable

### Symptoms: OPA Not Receiving Updates

**Diagnosis**:
1. Check OPA health: `curl http://opa:8181/health`
2. Verify OPA URL is correct in service
3. Check for network connectivity

**Solution**:
- Restart OPA service
- Verify `OPA_URL` environment variable
- Check firewall rules

### Symptoms: High Latency

**Diagnosis**:
1. Monitor database query times
2. Check event processing rate
3. Verify network latency

**Solution**:
- Add database indexes: `CREATE INDEX idx_reputation_actor ON reputation_scores(actor_id, updated_at);`
- Tune Kafka consumer batch size
- Review signal extraction logic

## Related Documentation

- [Kafka Event Bus Guide](../KAFKA-EVENT-BUS-GUIDE.md)
- [OPA Policy Engine Guide](../OBSERVABILITY-OPA-POLICIES.md)
- [Architecture Overview](../architecture/)
