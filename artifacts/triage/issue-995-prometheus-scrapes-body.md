## P1: Add Prometheus Scrapes and Alerts for session-broker and Redis Sentinel

### Problem

#### Gap 1: No session-broker Metrics Scrape

**File**: `prometheus.yml`

Prometheus scrapes `code-server`, `caddy`, `redis`, `postgres` but NOT `session-broker:5000/metrics`. 

The session-broker has telemetry (`SessionBrokerTelemetryState` in the code) but no scrape configured.

#### Gap 2: No Redis Sentinel Alerts

**File**: `alert-rules.yml`

Alert rules cover PostgreSQL replication but NOT Redis Sentinel events:
- No alert for Sentinel master switch
- No alert for Sentinel quorum loss
- No alert for Redis replica lag

### Impact

1. **Session broker invisible**: Can't see session creation rate, queue depth, container spawn failures
2. **Redis failover silent**: Sentinel promotes new master without notification
3. **Session loss undetected**: Users lose sessions without any alert

### Required Changes

#### 1. Add session-broker Scrape

```yaml
# prometheus.yml:
scrape_configs:
  - job_name: 'session-broker'
    static_configs:
      - targets: ['session-broker:5000']
    metrics_path: /metrics
    scrape_interval: 15s
```

#### 2. Add oauth2-proxy Scrape

```yaml
scrape_configs:
  - job_name: 'oauth2-proxy'
    static_configs:
      - targets: ['oauth2-proxy:4180']
    metrics_path: /metrics
    scrape_interval: 30s
```

#### 3. Add Redis Sentinel Scrape

```yaml
scrape_configs:
  - job_name: 'redis-sentinel'
    static_configs:
      - targets: ['redis-sentinel-1:26379', 'redis-sentinel-arbiter:26379']
    metrics_path: /metrics
```

**Note**: May need redis_exporter for Sentinel metrics.

#### 4. Add Alert Rules

```yaml
# alert-rules.yml:

groups:
  - name: session-broker-alerts
    rules:
      - alert: SessionBrokerDown
        expr: up{job="session-broker"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Session broker is down"
          
      - alert: SessionCreationFailures
        expr: rate(session_creation_failures_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High session creation failure rate"
          
      - alert: TooManyActiveSessions
        expr: active_sessions_total > 50
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High number of active sessions"

  - name: redis-sentinel-alerts
    rules:
      - alert: RedisSentinelMasterSwitch
        expr: changes(redis_sentinel_master_switch_total[5m]) > 0
        labels:
          severity: warning
        annotations:
          summary: "Redis Sentinel performed master switch"
          
      - alert: RedisSentinelQuorumLost
        expr: redis_sentinel_sentinels < 2
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis Sentinel quorum lost"
          
      - alert: RedisReplicaLag
        expr: redis_connected_slaves == 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Redis has no connected replicas"
```

### Validation

```bash
# Verify scrape targets
curl http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job == "session-broker")'

# Verify session-broker metrics
curl http://session-broker:5000/metrics

# Verify alerts loaded
curl http://prometheus:9090/api/v1/rules | jq '.data.groups[] | select(.name | contains("session"))'
```

### Definition of Done

- [ ] session-broker scrape job added to prometheus.yml
- [ ] oauth2-proxy scrape job added
- [ ] Redis Sentinel scrape job added (may need exporter)
- [ ] SessionBrokerDown alert added
- [ ] RedisSentinelMasterSwitch alert added
- [ ] RedisSentinelQuorumLost alert added
- [ ] Grafana dashboard updated with new metrics
- [ ] Alert test: simulate session-broker failure, verify alert fires

### Cross-References

- Parent: #965 (Observability)
- Related: #957 (Redis HA)
- Related: #975 (Auth path observability)
