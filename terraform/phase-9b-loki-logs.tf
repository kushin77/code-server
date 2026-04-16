# Phase 9-B: Log Aggregation with Loki
# Issue #364: Log Aggregation & Centralized Log Storage
# loki_version defined in ../../variables.tf (canonical location)
# NOTE: terraform block and shared variables defined in main.tf and phase-9-variables.tf

variable "promtail_version" {
  description = "Promtail version (immutable)"
  type        = string
  default     = "2.9.4"
}

# Loki Configuration (Log Storage & Query Engine)
resource "local_file" "loki_config" {
  filename = "${path.module}/../config/loki/loki-config.yml"
  content  = <<-EOT
auth_enabled: false

ingester:
  chunk_idle_period: 3m
  chunk_retain_period: 1m
  max_chunk_age: 1h
  chunk_encoding: snappy
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  wal:
    enabled: true
    checkpoint_duration: 5m

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 512
  ingestion_burst_size_mb: 1024
  max_streams_per_user: 10000
  max_global_streams_per_user: 10000
  max_entries_limit_per_second: 1000000

schema_config:
  configs:
    - from: 2020-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /loki/chunks
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
    shared_store: filesystem

server:
  http_listen_port: 3100
  log_level: info
  log_format: json

query_range:
  results_cache:
    cache:
      enable_fifocache: true
      default_validity: 1m
  cache_results: true
  max_cache_freshness_per_query: 10m
  max_retries: 2
  parallelise_shards_min_bytes: 0

querier:
  engine: prometheus
  regex_cache_disabled: false
  cache_results: true
  max_concurrent: 20

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOT
}

# Promtail Configuration (Log Collection Agent)
resource "local_file" "promtail_config" {
  filename = "${path.module}/../config/promtail/promtail-config.yml"
  content  = <<-EOT
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # Docker container logs
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*-json.log
    pipeline_stages:
      - json:
          expressions:
            log: log
      - output:
          source: log

  # Application logs (code-server, oauth2-proxy, etc)
  - job_name: application-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: application
          __path__: /var/log/code-server/*.log
    pipeline_stages:
      - multiline:
          line_start_pattern: '^\d{4}-\d{2}-\d{2}'
      - regex:
          expression: '^(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s+(?P<level>\w+)\s+(?P<message>.*)$'
      - labels:
          level:
          service: code-server
      - output:
          source: message

  # PostgreSQL logs
  - job_name: postgres
    static_configs:
      - targets:
          - localhost
        labels:
          job: postgres
          __path__: /var/log/postgresql/*.log
    pipeline_stages:
      - regex:
          expression: '^(?P<timestamp>\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})\s+\[(?P<pid>\d+)\]\s+(?P<level>\w+):\s+(?P<message>.*)$'
      - labels:
          level:
          service: postgres
      - output:
          source: message

  # HAProxy logs
  - job_name: haproxy
    static_configs:
      - targets:
          - localhost
        labels:
          job: haproxy
          __path__: /var/log/haproxy.log
    pipeline_stages:
      - regex:
          expression: '^(?P<timestamp>\w+\s+\d+\s+\d{2}:\d{2}:\d{2})\s+(?P<host>\S+)\s+haproxy\[(?P<pid>\d+)\]:\s+(?P<message>.*)$'
      - labels:
          service: haproxy
      - output:
          source: message

  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          __path__: /var/log/syslog
    pipeline_stages:
      - regex:
          expression: '^(?P<timestamp>\w+\s+\d+\s+\d{2}:\d{2}:\d{2})\s+(?P<host>\S+)\s+(?P<process>\S+)(?:\[(?P<pid>\d+)\])?:\s+(?P<message>.*)$'
      - labels:
          process:
          service: system
      - output:
          source: message
EOT
}

# Loki Docker Compose Service
resource "local_file" "loki_compose" {
  filename = "${path.module}/../config/docker-compose/loki-service.yml"
  content  = <<-EOT
  loki:
    image: grafana/loki:${var.loki_version}
    container_name: loki
    environment:
      - LOKI_CONFIG_FILE=/etc/loki/loki-config.yml
    ports:
      - "3100:3100"
    volumes:
      - ./config/loki/loki-config.yml:/etc/loki/loki-config.yml
      - loki_chunks:/loki/chunks
      - loki_index:/loki/index
      - loki_cache:/loki/cache
    command: -config.file=/etc/loki/loki-config.yml
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3100/loki/api/v1/status/buildinfo"]
      interval: 10s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - code-server-net

  promtail:
    image: grafana/promtail:${var.promtail_version}
    container_name: promtail
    environment:
      - HOSTNAME=code-server-primary
    ports:
      - "9080:9080"
    volumes:
      - ./config/promtail/promtail-config.yml:/etc/promtail/config.yml
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log:ro
    command: -config.file=/etc/promtail/config.yml
    depends_on:
      - loki
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9080/ready"]
      interval: 10s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - code-server-net

volumes:
  loki_chunks:
  loki_index:
  loki_cache:
EOT
}

# Loki Prometheus Alert Rules
resource "local_file" "loki_monitoring" {
  filename = "${path.module}/../config/prometheus/loki-monitoring.yml"
  content  = <<-EOT
groups:
  - name: loki-health
    interval: 30s
    rules:
      # Loki Service Health
      - alert: LokiDown
        expr: up{job="loki"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Loki is down"

      # Ingestion Rate
      - alert: LokiHighIngestionRate
        expr: rate(loki_distributor_bytes_received_total[5m]) > 100000000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Loki ingestion rate is high ({{ $value | humanize }} bytes/sec)"

      # Chunk Errors
      - alert: LokiChunkProcessingErrors
        expr: rate(loki_chunk_store_index_entries_written_errors_total[5m]) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Loki chunk processing errors"

      # Query Latency
      - alert: LokiQueryLatencyHigh
        expr: histogram_quantile(0.99, rate(loki_request_duration_seconds_bucket[5m])) > 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Loki query latency is high"

      # Promtail Collection Lag
      - alert: PromtailCollectionLag
        expr: promtail_read_bytes_total < 1000000
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Promtail collection lag detected"

  - name: log-aggregation-slo
    interval: 60s
    rules:
      # Log Ingestion SLO (99.9%)
      - record: slo:log_ingestion_success:5m
        expr: rate(loki_distributor_messages_received_total[5m]) / (rate(loki_distributor_messages_received_total[5m]) + rate(loki_distributor_errors_total[5m]))

      # Query Performance SLO (p99 < 500ms)
      - record: slo:query_latency:p99
        expr: histogram_quantile(0.99, rate(loki_request_duration_seconds_bucket[5m]))

      # Data Retention (days)
      - record: slo:data_retention_days
        expr: 7
EOT
}

output "loki_api_url" {
  description = "Loki API endpoint"
  value       = "http://${var.primary_host_ip}:3100"
}

output "loki_query_endpoint" {
  description = "Loki query endpoint"
  value       = "http://${var.primary_host_ip}:3100/api/v1/query_range"
}

output "promtail_metrics_endpoint" {
  description = "Promtail metrics endpoint"
  value       = "http://${var.primary_host_ip}:9080/metrics"
}

output "loki_slo_targets" {
  value = {
    log_ingestion_success  = "99.9%"
    query_latency_p99_ms   = 500
    data_retention_days    = 7
    ingest_rate_mb_per_sec = 512
  }
}
