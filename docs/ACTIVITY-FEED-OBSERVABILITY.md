# Activity Feed & Kafka Event Bus Observability

## Metrics

### Kafka Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|------------------|
| kafka_messages_received_total | Total messages per topic | - |
| kafka_consumer_lag | Lag behind latest offset | > 10,000 messages |
| kafka_broker_up | Broker availability | == 0 (critical) |
| kafka_partition_replica_lag | Partition replication lag | > 1000 |

### Activity Feed Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|------------------|
| activity_feed_api_requests_total | API request count | - |
| activity_feed_api_latency_seconds | API response time | p95 > 1s |
| activity_feed_websocket_connections | Active WebSocket clients | - |
| activity_feed_events_ingested_total | Events processed | - |
| event_parsing_errors_total | Failed event parsing | > 0.1/sec |

## Dashboards

### Kafka Event Bus Health
- Event throughput by topic (5-minute rate)
- Consumer group lag trends
- Broker availability
- Replication status

### Activity Feed Performance
- API request latency (p50, p95, p99)
- WebSocket connection count
- Event ingestion rate
- Error rate breakdown

## Alerts

### Critical (Page On-Call)
- Kafka broker down
- Activity Feed service down
- Consumer lag > 50,000 (unable to catch up)

### Warning (Create Ticket)
- Consumer lag > 10,000
- API latency p95 > 1 second
- Event parsing error rate > 0.1/sec
- WebSocket error rate > 0.05/sec

## Troubleshooting Queries

### Find high-lag topics
```promql
kafka_consumer_lag{job="kafka"} > 1000
order by (value) desc
```

### Activity Feed error rate
```promql
rate(event_parsing_errors_total[5m])
```

### WebSocket connection health
```promql
rate(activity_feed_websocket_errors_total[5m]) / rate(activity_feed_websocket_connections[5m])
```

### Message latency end-to-end
```promql
histogram_quantile(0.95, activity_feed_api_latency_seconds)
```
