## Severity: HIGH (4 findings — auth path completely dark to Prometheus)

---

## Finding 1 — No Prometheus scrape target for oauth2-proxy (prometheus.yml)

oauth2-proxy exposes a full Prometheus metrics endpoint at `/metrics` by default (port 4180).
Neither `oauth2-proxy` nor `oauth2-proxy-portal` are listed as scrape targets in `prometheus.yml`.

**Metrics being lost**: `oauth2_proxy_requests_total`, `oauth2_proxy_response_duration_seconds`, session cookie validation failures, OIDC discovery errors, redirect loops.

---

## Finding 2 — No Prometheus scrape target for session-broker (prometheus.yml)

The session-broker TypeScript service exposes metrics at `/metrics` (confirmed via `renderSessionBrokerPrometheusMetrics` function). It is not scraped.

**Metrics being lost**: session create/destroy rates, container spawn latency, queue depth, active session count.

---

## Finding 3 — Redis and Postgres scrape targets use wrong ports (prometheus.yml:29-35)

```yaml
- job_name: 'redis'
  static_configs:
    - targets: ['redis:6379']   # ← Redis doesn't speak Prometheus protocol on 6379
- job_name: 'postgres'
  static_configs:
    - targets: ['postgres:5432']  # ← Postgres doesn't speak Prometheus protocol on 5432
```

Both jobs will fail scraping and show as DOWN in Prometheus, generating false alert noise. The actual exporters (`redis_exporter` on 9121, `postgres_exporter` on 9187) are not deployed.

---

## Finding 4 — No alert rule for auth path failures (alert-rules.yml)

Zero alert rules covering:
- oauth2-proxy 5xx error rate
- CSRF token mismatch spike
- Session creation failure rate
- OIDC discovery endpoint failures
- Auth redirect loop detection

The April 19 CSRF incident was discovered by users, not by alerting.

Also: `DiskSpaceLow` alert uses `disk_free_bytes / disk_total_bytes` — metric name doesn't exist. Standard node_exporter metric is `node_filesystem_avail_bytes{fstype!="tmpfs"}`.

---

## Required Changes

### 1. Add scrape targets to prometheus.yml
```yaml
- job_name: 'oauth2-proxy'
  static_configs:
    - targets: ['oauth2-proxy:4180']
  metrics_path: /metrics

- job_name: 'oauth2-proxy-portal'
  static_configs:
    - targets: ['oauth2-proxy-portal:4181']
  metrics_path: /metrics

- job_name: 'session-broker'
  static_configs:
    - targets: ['session-broker:5000']
  metrics_path: /metrics
```

### 2. Deploy exporters and fix targets
```yaml
# Add to docker-compose.yml:
redis-exporter:
  image: oliver006/redis_exporter:v1.55.0@sha256:...
  environment:
    - REDIS_ADDR=redis://redis:6379
  networks: [net-app]

postgres-exporter:
  image: prometheuscommunity/postgres-exporter:v0.15.0@sha256:...
  environment:
    - DATA_SOURCE_NAME=postgresql://postgres_exporter:${PG_EXPORTER_PASSWORD}@postgres:5432/postgres?sslmode=disable
  networks: [net-data]
```
Update `prometheus.yml` targets to `redis-exporter:9121` and `postgres-exporter:9187`.

### 3. Add auth path alert rules to alert-rules.yml
```yaml
- alert: OAuth2ProxyHighErrorRate
  expr: rate(oauth2_proxy_requests_total{status=~"5.."}[5m]) > 0.1
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "oauth2-proxy is returning 5xx errors"

- alert: SessionCreationFailureSpike
  expr: rate(session_broker_create_errors_total[5m]) > 0.05
  for: 3m
  labels:
    severity: warning
  annotations:
    summary: "Session creation failure rate elevated"

- alert: DiskSpaceLow
  expr: node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint="/"} / node_filesystem_size_bytes{fstype!="tmpfs",mountpoint="/"} < 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Disk space below 10% on {{ $labels.instance }}"
```

---

## Definition of Done
- [ ] `oauth2-proxy` and `oauth2-proxy-portal` show as UP in Prometheus targets
- [ ] `session-broker` shows as UP in Prometheus targets
- [ ] `redis-exporter` and `postgres-exporter` deployed and showing as UP
- [ ] At least 3 auth path alert rules added and validated (test with `promtool check rules`)
- [ ] `DiskSpaceLow` alert uses correct `node_filesystem_avail_bytes` metric
- [ ] Grafana dashboard shows auth path error rates and session metrics
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
