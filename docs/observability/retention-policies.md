# Observability Retention Policies

**Issue:** #3151 - Unified Logging, Monitoring, Observability + SLOG Error Capture  
**Purpose:** Define and enforce data retention for logs, metrics, and traces  
**Status:** Active retention reference

## Configuration

Retention policies are configured in Loki and Prometheus and enforced automatically.

### Loki Retention (Logs)

Loki uses a time-series based retention model configured in [config/loki/loki-config.yml](../../config/loki/loki-config.yml):

```yaml
retention_deletes_enabled: true
retention_period: 168h  # Default: 7 days (168 hours)

schema_config:
  configs:
    - from: 2020-01-01
      store: tsdb
      object_store: filesystem
      schema: v12
      index:
        prefix: index_
        period: 24h
```

Labels for retention override (per stream):

- `retention: 90d` → Store for 90 days (e.g., auth logs)
- `retention: 30d` → Store for 30 days (e.g., API errors)
- `retention: 7d` → Store for 7 days (e.g., debug logs)

### Prometheus Retention (Metrics)

Prometheus automatically prunes metrics outside the retention window configured in [config/prometheus/prometheus.yml](../../config/prometheus/prometheus.yml):

```yaml
# Global retention for all series
global:
  external_labels:
    cluster: 'primary'
  # Retention: 15 days
  # Set retention_size to 50GB if disk-bound

# Per-job retention overrides
scrape_configs:
  - job_name: 'critical-metrics'
    # Metrics not deleted for 30 days
    # Requires external retention management (Cortex, Thanos)
```

### Tempo Retention (Traces)

Tempo stores trace segments with configurable retention in [config/tempo/tempo-config.yml](../../config/tempo/tempo-config.yml):

```yaml
retention: 24h  # Default: 1 day; increase if needed

distributor:
  rate_limit_bytes: 10000000  # Limit ingestion to 10MB/sec

compactor:
  compaction:
    compacted_block_retention: 10m  # How long to keep after compaction
```

## Enforcement Workflow

Retention is enforced automatically by the observability stack:

1. **Loki compaction**: Runs hourly to consolidate and prune old data
2. **Prometheus deletion**: Runs on startup and periodically based on retention_time
3. **Tempo compaction**: Runs every 5 minutes to compact and delete old traces
4. **Storage monitoring**: Alerts if retention deletes fail or if storage exceeds limits

## Querying Within Retention Windows

When querying observability data, always keep retention windows in mind:

```logql
# This query will return data from the last 7 days
{job="api-gateway"} | level="ERROR"

# To query older auth logs (retained for 90 days), use:
{job="auth-proxy", retention="90d"} | level="WARNING"

# Time-based query (only works within retention period)
{job="postgres"} | timestamp > "2026-04-01T00:00:00Z"
```

## Escalation: High Storage Usage

If observability storage exceeds available disk:

1. **Immediate action (5 min)**: Reduce retention periods by 50%
2. **Short-term (1 day)**: Export old data to cold storage (S3, GCS)
3. **Long-term (1 week)**: Implement Cortex/Thanos for distributed storage

## Compliance Notes

- Auth/audit logs are retained for 90 days per SOC2 requirements
- Do not reduce auth log retention below 90 days
- Retention policies are immutable and version-controlled in [config/](../../config/)

---

**Last Updated:** May 1, 2026  
**Owner:** Observability / Platform
