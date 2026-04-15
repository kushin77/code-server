# Phase 9-B: Distributed Tracing with Jaeger
# Issue #363: Distributed Tracing & OpenTelemetry Integration
# Immutable version: Jaeger 1.50
# NOTE: terraform block and shared variables defined in main.tf and phase-9-variables.tf

variable "jaeger_version" {
  description = "Jaeger version (immutable)"
  type        = string
  default     = "1.50"
}

# Jaeger All-in-One Configuration
resource "local_file" "jaeger_config" {
  filename = "${path.module}/../config/jaeger/jaeger.yml"
  content  = <<-EOT
# Jaeger Configuration
collector:
  enabled: true
  port: 14250
  gRPC:
    enabled: true
  zipkin:
    enabled: false
  grpc:
    enabled: true

storage:
  type: badger
  badger:
    ephemeral: false
    directory_value: /badger/data
    directory_keys: /badger/keys

query:
  enabled: true
  base_path: /

admin_port: 14269
metrics_port: 14268
EOT
}

# Jaeger Docker Container
resource "local_file" "jaeger_compose" {
  filename = "${path.module}/../config/docker-compose/jaeger-service.yml"
  content  = <<-EOT
  jaeger:
    image: jaegertracing/all-in-one:${var.jaeger_version}
    container_name: jaeger
    environment:
      - COLLECTOR_ZIPKIN_ENABLED=false
      - SPAN_STORAGE_TYPE=badger
      - BADGER_EPHEMERAL=false
      - BADGER_DIRECTORY_VALUE=/badger/data
      - BADGER_DIRECTORY_KEYS=/badger/keys
      - MEMORY_MAX_TRACES=10000
      - COLLECTOR_NUM_WORKERS=10
    ports:
      - "6831:6831/udp"      # Jaeger agent UDP port (Thrift)
      - "6832:6832/udp"      # Jaeger agent UDP port (Thrift Compact)
      - "14250:14250"        # Jaeger collector gRPC
      - "14268:14268"        # Jaeger collector HTTP
      - "16686:16686"        # Jaeger UI
    volumes:
      - jaeger_data:/badger/data
      - jaeger_keys:/badger/keys
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:16686/api/traces"]
      interval: 10s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - code-server-net

volumes:
  jaeger_data:
  jaeger_keys:
EOT
}

# OpenTelemetry Collector Configuration
resource "local_file" "otel_collector_config" {
  filename = "${path.module}/../config/otel-collector/collector-config.yml"
  content  = <<-EOT
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  prometheus:
    config:
      scrape_configs:
        - job_name: 'otel-collector'
          scrape_interval: 10s
          static_configs:
            - targets: ['localhost:8888']
  jaeger:
    protocols:
      grpc:
        endpoint: 0.0.0.0:14250
      thrift_http:
        endpoint: 0.0.0.0:14268

exporters:
  jaeger:
    endpoint: jaeger:14250
    tls:
      insecure: true
  prometheus:
    endpoint: 0.0.0.0:8889
  logging:
    loglevel: debug

processors:
  batch:
    send_batch_size: 1024
    timeout: 5s
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  attributes:
    actions:
      - key: environment
        value: production
        action: upsert
      - key: service.namespace
        value: code-server
        action: upsert

service:
  pipelines:
    traces:
      receivers: [otlp, jaeger]
      processors: [memory_limiter, batch, attributes]
      exporters: [jaeger, logging]
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, batch]
      exporters: [prometheus, logging]

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: 0.0.0.0:1777
EOT
}

# Application Instrumentation Library
resource "local_file" "instrumentation_library" {
  filename = "${path.module}/../config/otel/instrumentation.js"
  content  = <<-EOT
// OpenTelemetry Instrumentation for Node.js Applications
// Automatically instruments:
// - HTTP/HTTPS requests
// - Database queries (PostgreSQL, Redis)
// - External API calls
// - Error tracking

const { NodeTracerProvider } = require("@opentelemetry/node");
const { getNodeAutoInstrumentations } = require("@opentelemetry/auto-instrumentations-node");
const { JaegerExporter } = require("@opentelemetry/exporter-jaeger-grpc");
const { BatchSpanProcessor } = require("@opentelemetry/sdk-trace-node");
const { registerInstrumentations } = require("@opentelemetry/instrumentation");
const { Resource } = require("@opentelemetry/resources");
const { SemanticResourceAttributes } = require("@opentelemetry/semantic-conventions");

// Initialize resource with service metadata
const resource = Resource.default().merge(
  new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: "code-server",
    [SemanticResourceAttributes.SERVICE_VERSION]: "4.115.0",
    environment: "production",
    region: "on-premises",
    host: process.env.HOSTNAME || "unknown"
  })
);

// Configure Jaeger exporter
const jaegerExporter = new JaegerExporter({
  host: process.env.JAEGER_HOST || "jaeger",
  port: process.env.JAEGER_PORT || 14250,
  maxPacketSize: 65000
});

// Create and register tracer provider
const tracerProvider = new NodeTracerProvider({ resource });
tracerProvider.addSpanProcessor(new BatchSpanProcessor(jaegerExporter));

// Auto-instrument all supported libraries
registerInstrumentations({
  instrumentations: [
    getNodeAutoInstrumentations({
      "@opentelemetry/instrumentation-http": {
        enabled: true,
        requestHook: (span, request) => {
          span.setAttribute("http.request.body.size", request.socket?.bytesWritten || 0);
        },
        responseHook: (span, response) => {
          span.setAttribute("http.response.body.size", response.socket?.bytesRead || 0);
        }
      },
      "@opentelemetry/instrumentation-pg": {
        enabled: true,
        enhancedDatabaseReporting: true
      },
      "@opentelemetry/instrumentation-redis": {
        enabled: true
      },
      "@opentelemetry/instrumentation-express": {
        enabled: true
      },
      "@opentelemetry/instrumentation-dns": {
        enabled: true
      }
    })
  ],
  tracerProvider
});

module.exports = tracerProvider;
EOT
}

# Monitoring Configuration for Jaeger
resource "local_file" "jaeger_monitoring" {
  filename = "${path.module}/../config/prometheus/jaeger-monitoring.yml"
  content  = <<-EOT
groups:
  - name: jaeger-tracing
    interval: 30s
    rules:
      # Jaeger Collector Health
      - alert: JaegerCollectorDown
        expr: up{job="jaeger-collector"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Jaeger collector is down"

      # Span Processing Latency
      - alert: JaegerSpanProcessingLatencyHigh
        expr: histogram_quantile(0.99, rate(jaeger_collector_span_received_total[5m])) > 0.1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Jaeger span processing latency is high"

      # Queue Size
      - alert: JaegerQueueSizeHigh
        expr: jaeger_collector_queue_length > 5000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Jaeger queue size is high ({{ $value }} spans)"

      # Storage Errors
      - alert: JaegerStorageErrors
        expr: rate(jaeger_storage_write_errors_total[5m]) > 0.01
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Jaeger storage errors detected"

      # Trace Sampling Rate
      - alert: JaegerSamplingRateAnomalous
        expr: abs(rate(jaeger_sampler_samplings_total[5m])[1m:5m] - rate(jaeger_sampler_samplings_total[5m])) > 0.1
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Jaeger sampling rate is anomalous"

  - name: distributed-tracing-slo
    interval: 60s
    rules:
      # Trace Ingestion SLO (99.9% of traces captured)
      - record: slo:trace_capture_rate:5m
        expr: rate(jaeger_collector_spans_received_total[5m]) / rate(jaeger_collector_span_dropped_total[5m] + jaeger_collector_spans_received_total[5m])

      # Span Query Latency SLO (< 100ms p99)
      - record: slo:span_query_latency:p99
        expr: histogram_quantile(0.99, rate(jaeger_query_latency_seconds_bucket[5m]))

      # Collector Availability (99.99%)
      - record: slo:collector_availability:5m
        expr: up{job="jaeger-collector"}
EOT
}

output "jaeger_ui_url" {
  description = "Jaeger UI endpoint"
  value       = "http://${var.primary_host_ip}:16686"
}

output "jaeger_otlp_grpc_endpoint" {
  description = "OpenTelemetry gRPC collector endpoint"
  value       = "${var.primary_host_ip}:4317"
}

output "jaeger_otlp_http_endpoint" {
  description = "OpenTelemetry HTTP collector endpoint"
  value       = "http://${var.primary_host_ip}:4318"
}

output "jaeger_agent_endpoint" {
  description = "Jaeger agent endpoint (UDP)"
  value       = "${var.primary_host_ip}:6831"
}

output "jaeger_slo_targets" {
  value = {
    trace_capture_rate        = "99.9%"
    span_query_latency_p99_ms = 100
    collector_availability    = "99.99%"
  }
}
