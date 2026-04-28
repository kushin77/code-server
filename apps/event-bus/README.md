# Event Bus Service

Central message queue and event streaming infrastructure for Code Server Enterprise. Manages asynchronous communication between services, event persistence, and real-time data streaming across the entire platform.

## Architecture Overview

The Event Bus (Kafka) provides:

- **Event Streaming**: Publish-subscribe model for service-to-service communication
- **Topic Management**: 15+ dedicated topics for different event types
- **Event Persistence**: Durable message storage with configurable retention
- **Consumer Groups**: Multiple independent consumers per topic
- **Replication**: Cross-cluster message replication for HA
- **Schema Registry**: Validates events against defined schemas
- **Dead Letter Queues**: Handles failed message processing

### Core Topics

```yaml
# Deployment Events
deploy.events:
  partitions: 12
  replication_factor: 3
  retention_ms: 86400000  # 24 hours
  description: "All deployment lifecycle events"

deploy.rollback:
  partitions: 3
  retention_ms: 604800000  # 7 days
  description: "Rollback trigger events"

# Audit & Security
agent.audit:
  partitions: 6
  retention_ms: 31536000000  # 365 days
  description: "Immutable audit trail"

security.events:
  partitions: 6
  retention_ms: 15552000000  # 180 days
  description: "Authentication, authorization, penetration detection"

# Service Lifecycle
agent.lifecycle:
  partitions: 6
  retention_ms: 604800000  # 7 days
  description: "Service startup, shutdown, error events"

# Code & Development
code.review:
  partitions: 12
  retention_ms: 31536000000  # 365 days
  description: "Pull requests, code reviews, commits"

# Incident Management
incident.events:
  partitions: 9
  retention_ms: 31536000000  # 365 days
  description: "Incident creation, updates, resolutions"

# AI & ML
ai.interactions:
  partitions: 12
  retention_ms: 15552000000  # 180 days
  description: "Agent queries, responses, training data"

# Database Operations
database.events:
  partitions: 6
  retention_ms: 604800000  # 7 days
  description: "Query performance, schema changes, backups"

# Caching
cache.events:
  partitions: 6
  retention_ms: 86400000  # 24 hours
  description: "Cache hits, misses, invalidations"

# Monitoring & Alerting
monitor.alerts:
  partitions: 12
  retention_ms: 604800000  # 7 days
  description: "Prometheus alerts, threshold violations"

# Resource Management
resource.allocation:
  partitions: 6
  retention_ms: 604800000  # 7 days
  description: "CPU, memory, GPU allocation events"

# User Activity
user.activity:
  partitions: 12
  retention_ms: 15552000000  # 180 days
  description: "Login, logout, preference changes"

# System Metrics
system.metrics:
  partitions: 9
  retention_ms: 604800000  # 7 days
  description: "Timestamp-based metrics and statistics"

# Replication
cluster.replication:
  partitions: 3
  retention_ms: 86400000  # 24 hours
  description: "Cluster sync and replication events"
```

## Service Dependencies

```
event-bus (Kafka)
├── Zookeeper (cluster coordination)
├── Schema Registry (message validation)
├── PLAINTEXT & TLS listeners
├── Producers: All services (control-plane, auth-server, agent-runtime, etc.)
└── Consumers:
    ├── activity-feed (all topics)
    ├── memory-engine (learning topics)
    ├── reputation_engine (behavior topics)
    ├── monitoring stack (alerts)
    └── custom subscribers
```

## Core Components

### 1. Topic Management

```python
# Example: Create a new topic for custom events
POST /topics
{
    "name": "custom.service.events",
    "partitions": 6,
    "replication_factor": 3,
    "config": {
        "retention.ms": 604800000,
        "compression.type": "snappy",
        "cleanup.policy": "delete",
        "min.in.sync.replicas": 2
    }
}

Response:
{
    "topic": "custom.service.events",
    "status": "created",
    "partitions": [0, 1, 2, 3, 4, 5],
    "replication_factor": 3,
    "partition_leadership": {
        "0": {"leader": 1, "replicas": [1, 2, 3]},
        "1": {"leader": 2, "replicas": [2, 3, 1]},
        "2": {"leader": 3, "replicas": [3, 1, 2]}
    }
}
```

### 2. Event Publishing

```python
# Example: Publish deployment event
POST /events/publish
{
    "topic": "deploy.events",
    "key": "dep-20260428-001",
    "value": {
        "deployment_id": "dep-20260428-001",
        "service": "auth-server",
        "version": "2.1.0",
        "status": "in_progress",
        "timestamp": "2026-04-28T10:00:00Z",
        "actor": "user@company.com",
        "strategy": "canary",
        "replicas": 3
    },
    "headers": {
        "source": "control-plane",
        "correlation_id": "corr-001",
        "trace_id": "trace-001"
    }
}

Response:
{
    "partition": 3,
    "offset": 45678,
    "timestamp": "2026-04-28T10:00:00Z",
    "status": "published"
}
```

### 3. Consumer Management

```python
# Example: Create consumer group for custom application
POST /consumer-groups
{
    "group_id": "custom-processor",
    "topics": ["deploy.events", "agent.lifecycle"],
    "consumer_strategy": "RoundRobin",
    "session_timeout_ms": 30000,
    "heartbeat_interval_ms": 10000,
    "auto_commit": false  # Explicit offset management
}

Response:
{
    "group_id": "custom-processor",
    "status": "created",
    "members": [],
    "state": "Empty",
    "coordinator_id": 1
}
```

### 4. Schema Management

```python
# Example: Register event schema
POST /schemas
{
    "subject": "deploy.events-value",
    "version": 1,
    "schema": {
        "type": "record",
        "name": "DeploymentEvent",
        "fields": [
            {"name": "deployment_id", "type": "string"},
            {"name": "service", "type": "string"},
            {"name": "version", "type": "string"},
            {"name": "status", "type": "string", "default": "pending"},
            {"name": "timestamp", "type": "string"},
            {"name": "actor", "type": "string"},
            {
                "name": "metadata",
                "type": ["null", "string"],
                "default": null
            }
        ]
    }
}

Response:
{
    "id": 1,
    "version": 1,
    "subject": "deploy.events-value",
    "schema": "...",
    "references": []
}
```

### 5. Dead Letter Queue

```python
# Example: Get dead letter queue messages
GET /topics/deploy.events.dlq/messages?limit=50

Response:
{
    "messages": [
        {
            "partition": 0,
            "offset": 123,
            "timestamp": "2026-04-28T09:55:00Z",
            "key": "dep-failed-001",
            "value": {...},
            "error": "SchemaValidationException: Field 'actor' is required",
            "source_topic": "deploy.events",
            "retry_count": 3
        }
    ],
    "total": 5,
    "dlq_size": 5
}
```

## API Endpoints

### Topic Operations

```bash
# List all topics
GET /topics

# Get topic details
GET /topics/{topic_name}

# Get topic metrics
GET /topics/{topic_name}/metrics

Response:
{
    "name": "deploy.events",
    "partitions": 12,
    "replication_factor": 3,
    "size_mb": 1024,
    "message_count": 250000,
    "earliest_offset": 0,
    "latest_offset": 249999
}

# Create topic
POST /topics

# Delete topic (only if retention_days=0)
DELETE /topics/{topic_name}
```

### Event Publishing

```bash
# Publish single event
POST /events/publish
{
    "topic": "deploy.events",
    "key": "key-001",
    "value": {...},
    "headers": {...}
}

# Publish batch events
POST /events/publish-batch
{
    "topic": "deploy.events",
    "events": [
        {"key": "key-001", "value": {...}},
        {"key": "key-002", "value": {...}}
    ]
}
```

### Consumer Groups

```bash
# List consumer groups
GET /consumer-groups

# Get group details
GET /consumer-groups/{group_id}

Response:
{
    "group_id": "activity-feed-processor",
    "state": "Stable",
    "members": 3,
    "topics": ["agent.audit", "deploy.events", "code.review"],
    "lag": {
        "total": 1234,
        "by_topic": {
            "agent.audit": 500,
            "deploy.events": 300,
            "code.review": 434
        }
    }
}

# Get consumer group lag
GET /consumer-groups/{group_id}/lag

# Reset consumer group offset
POST /consumer-groups/{group_id}/reset
{
    "strategy": "earliest|latest|to_offset",
    "target_offset": 12345  # if strategy is to_offset
}
```

### Health & Status

```bash
# Event bus health
GET /health

Response:
{
    "status": "healthy",
    "brokers": {
        "total": 3,
        "healthy": 3,
        "leaders": [1, 2, 3]
    },
    "topics": {
        "total": 15,
        "healthy": 15,
        "unhealthy": 0
    },
    "consumer_groups": {
        "total": 12,
        "active": 12,
        "stalled": 0
    },
    "pending_messages": 45678,
    "dlq_size": 5
}

# Get cluster metrics
GET /metrics

Response:
{
    "broker_count": 3,
    "topic_count": 15,
    "partition_count": 90,
    "replication_factor_avg": 3.0,
    "message_throughput_per_sec": 12000,
    "bytes_in_per_sec": 5240,
    "bytes_out_per_sec": 4810,
    "consumer_groups_count": 12,
    "active_consumers": 24
}
```

## Configuration

### Environment Variables

```bash
# Kafka Broker Configuration
KAFKA_BROKER_ID=1
KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181
KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092,TLS://kafka:9093
KAFKA_SECURITY_PROTOCOL_MAP=PLAINTEXT:PLAINTEXT,TLS:SSL
KAFKA_NUM_NETWORK_THREADS=8
KAFKA_NUM_IO_THREADS=8

# Topic Configuration
KAFKA_NUM_PARTITIONS=6
KAFKA_DEFAULT_REPLICATION_FACTOR=3
KAFKA_MIN_IN_SYNC_REPLICAS=2
KAFKA_LOG_RETENTION_HOURS=168  # 7 days
KAFKA_LOG_RETENTION_BYTES=-1   # Unlimited until time-based retention

# Schema Registry
SCHEMA_REGISTRY_URL=http://schema-registry:8081
SCHEMA_REGISTRY_AVRO_COMPATIBILITY_LEVEL=BACKWARD

# Consumer Group Configuration
KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=3000
KAFKA_OFFSETS_RETENTION_MINUTES=10080  # 7 days

# Security (if TLS enabled)
KAFKA_SSL_KEYSTORE_LOCATION=/etc/kafka/secrets/kafka.keystore.jks
KAFKA_SSL_KEYSTORE_PASSWORD=keystore-password
KAFKA_SSL_KEY_PASSWORD=key-password
```

### Docker Compose Configuration

```yaml
kafka:
  image: kushin77/code-server-kafka:7.6@sha256:def456...
  container_name: kafka
  ports:
    - "9092:9092"
    - "9093:9093"
  environment:
    KAFKA_BROKER_ID: 1
    KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
    KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,TLS://kafka:9093
    KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,TLS:SSL
    KAFKA_NUM_PARTITIONS: 6
    KAFKA_DEFAULT_REPLICATION_FACTOR: 3
    KAFKA_MIN_IN_SYNC_REPLICAS: 2
    KAFKA_LOG_RETENTION_HOURS: 168
    KAFKA_AUTO_CREATE_TOPICS_ENABLE: 'true'
  depends_on:
    - zookeeper
  volumes:
    - kafka-data:/var/lib/kafka/data
    - ./kafka.ssl:/etc/kafka/secrets:ro

zookeeper:
  image: kushin77/code-server-zookeeper:7.6@sha256:ghi789...
  container_name: zookeeper
  ports:
    - "2181:2181"
  environment:
    ZOO_CFG_EXTRA: "dataDir=/var/lib/zookeeper/data"
  volumes:
    - zookeeper-data:/var/lib/zookeeper/data

schema-registry:
  image: kushin77/code-server-schema-registry:7.6@sha256:jkl012...
  container_name: schema-registry
  ports:
    - "8081:8081"
  environment:
    SCHEMA_REGISTRY_HOST_NAME: schema-registry
    SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: kafka:9092
    SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL: PLAINTEXT
  depends_on:
    - kafka
```

## Event Schema Examples

### Deployment Event

```json
{
    "event_type": "deployment_created",
    "deployment_id": "dep-20260428-001",
    "service": "auth-server",
    "version": "2.1.0",
    "status": "pending",
    "strategy": "canary",
    "replicas": 3,
    "timestamp": "2026-04-28T10:00:00Z",
    "actor": "user@company.com",
    "correlation_id": "corr-001",
    "metadata": {
        "region": "us-east-1",
        "environment": "production"
    }
}
```

### Audit Event

```json
{
    "event_type": "user_login",
    "user_id": "user-001",
    "username": "user@company.com",
    "timestamp": "2026-04-28T10:00:00Z",
    "ip_address": "192.168.1.100",
    "user_agent": "Mozilla/5.0...",
    "status": "success",
    "mfa_verified": true,
    "correlation_id": "corr-002"
}
```

### Incident Event

```json
{
    "event_type": "incident_triggered",
    "incident_id": "inc-20260428-001",
    "severity": "critical",
    "service": "auth-server",
    "error_code": "E_AUTH_001",
    "error_message": "Database connection pool exhausted",
    "timestamp": "2026-04-28T10:00:00Z",
    "affected_users": 250,
    "correlation_id": "corr-003",
    "trace_id": "trace-003"
}
```

## Consumer Integration Examples

### Activity Feed Consumer

```python
from kafka import KafkaConsumer
import json

consumer = KafkaConsumer(
    'agent.audit',
    'deploy.events',
    'code.review',
    'incident.events',
    bootstrap_servers=['kafka:9092'],
    group_id='activity-feed-processor',
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
    auto_offset_reset='earliest',
    enable_auto_commit=False
)

for message in consumer:
    print(f"Topic: {message.topic}, Offset: {message.offset}")
    print(f"Event: {message.value}")
    
    # Process event
    # Store in database
    # Publish to WebSocket
    
    # Commit offset after successful processing
    consumer.commit()
```

### Memory Engine Consumer

```python
consumer = KafkaConsumer(
    'ai.interactions',
    'incident.events',
    'code.review',
    bootstrap_servers=['kafka:9092'],
    group_id='memory-engine-processor',
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
    enable_auto_commit=False
)

for message in consumer:
    event = message.value
    
    # Extract learning content
    if event['event_type'] == 'incident_resolved':
        learning = {
            'type': 'incident_resolution',
            'service': event['service'],
            'solution': event['resolution_details'],
            'tags': event['tags']
        }
        # Store in vector database for semantic search
```

### Reputation Engine Consumer

```python
consumer = KafkaConsumer(
    'deploy.events',
    'code.review',
    'incident.events',
    'agent.audit',
    bootstrap_servers=['kafka:9092'],
    group_id='reputation-engine-processor',
    value_deserializer=lambda m: json.loads(m.decode('utf-8'))
)

signal_mapping = {
    'deployment_completed': 50,
    'deployment_failed': -100,
    'pr_merged': 30,
    'incident_resolved': 200,
    'incident_caused': -300,
}

for message in consumer:
    event = message.value
    signal_type = event.get('event_type')
    
    if signal_type in signal_mapping:
        points = signal_mapping[signal_type]
        # Update reputation score for actor
```

## Monitoring & Observability

### Key Metrics

```
# Topic Metrics
kafka_topic_size_bytes
kafka_topic_message_count
kafka_topic_partition_count
kafka_consumer_lag_bytes
kafka_consumer_group_lag_bytes

# Producer Metrics
kafka_producer_record_send_rate
kafka_producer_batch_size_avg
kafka_producer_compression_rate
kafka_producer_record_error_rate

# Consumer Metrics
kafka_consumer_fetch_rate
kafka_consumer_records_consumed_rate
kafka_consumer_records_lag_max
kafka_consumer_rebalance_latency_total

# Broker Metrics
kafka_broker_requests_per_sec
kafka_broker_bytes_in_per_sec
kafka_broker_bytes_out_per_sec
kafka_broker_network_processor_avg_idle_percent

# Cluster Metrics
kafka_cluster_broker_count
kafka_cluster_under_replicated_partitions
kafka_cluster_offline_partitions
```

### Prometheus Scrape

```yaml
- job_name: 'kafka'
  static_configs:
    - targets: ['kafka:9099']  # JMX exporter
  metrics_path: '/metrics'
  scrape_interval: 15s
```

### Grafana Dashboards

1. **Topic Health**: Partition distribution, replication status, throughput
2. **Consumer Lag**: Lag trends, bottleneck identification, stalled consumers
3. **Broker Performance**: CPU, memory, disk I/O, network usage
4. **Message Flow**: Events per second by topic, error rates, DLQ depth

## Production Deployment Checklist

- [ ] Zookeeper cluster operational (3+ nodes recommended)
- [ ] Kafka cluster operational (3+ brokers recommended)
- [ ] TLS certificates installed for encrypted communication
- [ ] Schema Registry operational and validated
- [ ] All topics created with proper replication and retention
- [ ] Consumer groups configured and tested
- [ ] Dead Letter Queue configured for failed messages
- [ ] Monitoring and alerting configured
- [ ] Backup procedures for Zookeeper and Kafka data
- [ ] Disaster recovery plan tested
- [ ] Team trained on Kafka operations
- [ ] Documentation accessible and up-to-date

## Troubleshooting

### Consumer Lag Increasing

```bash
# Check consumer group status
kafka-consumer-groups --bootstrap-server kafka:9092 \
  --group activity-feed-processor --describe

# If lagging, check broker logs
docker logs kafka | grep "activity-feed-processor"

# Restart consumer if needed (loses current position)
# OR reset to latest offset
kafka-consumer-groups --bootstrap-server kafka:9092 \
  --group activity-feed-processor \
  --reset-offsets --to-latest --execute
```

### Partition Leadership Issues

```bash
# Check partition distribution
kafka-topics --bootstrap-server kafka:9092 \
  --topic deploy.events --describe

# Trigger leader election if needed
kafka-preferred-replica-election \
  --bootstrap-server kafka:9092 \
  --path-to-json-file preferred-replica.json
```

### DLQ Messages Accumulating

```bash
# Investigate DLQ messages
kafka-console-consumer --bootstrap-server kafka:9092 \
  --topic deploy.events.dlq \
  --property print.key=true \
  --max-messages 10

# Fix schema and replay from DLQ
# OR delete DLQ topic and recreate consumer group
```

## Performance Tuning

### High Throughput Configuration

```bash
# Increase number of partitions per topic
KAFKA_NUM_PARTITIONS=12

# Increase producer batch size and linger time
producer_linger_ms=100
producer_batch_size=32768

# Increase consumer fetch size
fetch_min_bytes=1024
fetch_max_bytes=52428800
```

### Low Latency Configuration

```bash
# Smaller batches and linger
producer_batch_size=1024
producer_linger_ms=0

# Faster consumer fetches
fetch_min_bytes=1
fetch_max_bytes=1048576
consumer_session_timeout_ms=10000
```

## Related Services

- **activity-feed**: Primary consumer of all events
- **memory-engine**: Learns from historical events
- **reputation_engine**: Updates scores based on events
- **control-plane**: Publishes deployment events
- **auth-server**: Publishes security events
- **agent-runtime**: Publishes lifecycle events

## Support & Documentation

For additional support, see:

- [Kafka Official Documentation](https://kafka.apache.org/documentation/)
- [Schema Registry Guide](https://docs.confluent.io/schema-registry/)
- [Event Specifications](../../COMPLETE_35_SERVICE_REFERENCE.md)
- [GitHub Issues](https://github.com/kushin77/code-server/issues) - Tag: messaging

---

**Status**: Production Ready  
**Last Updated**: April 28, 2026  
**Maintainer**: Code Server Enterprise Team
