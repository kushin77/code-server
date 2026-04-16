# Phase 9-C: Kong API Gateway - Core Configuration
# Issue #366: API Gateway, Rate Limiting & Request Management
# kong_version defined in ../../variables.tf (canonical location)
# NOTE: terraform block and shared variables defined in main.tf and phase-9-variables.tf

variable "kong_postgres_version" {
  description = "Kong database version"
  type        = string
  default     = "15"
}

# Kong Configuration
resource "local_file" "kong_config" {
  filename = "${path.module}/../config/kong/kong.conf"
  content  = <<-EOT
# Kong Configuration File
# Production settings for on-premises deployment

############
# DATABASE #
############
database = postgres
pg_host = postgres
pg_port = 5432
pg_user = kong
pg_password = kong_secure_password
pg_database = kong
pg_ssl = off
pg_ssl_verify = off

#############
# ADDRESSES #
#############
# Admin API (internal only)
admin_listen = 0.0.0.0:8001 http, 0.0.0.0:8444 https ssl

# Proxy API (external)
proxy_listen = 0.0.0.0:8000 http, 0.0.0.0:8443 https ssl

#############
# SSL/TLS  #
#############
ssl_cert_file = /etc/kong/ssl/kong.crt
ssl_key_file = /etc/kong/ssl/kong.key
ssl_default_certificate_file = /etc/kong/ssl/kong.crt
ssl_default_certificate_key_file = /etc/kong/ssl/kong.key

#############
# LOGGING  #
#############
log_level = notice
proxy_access_log = /var/log/kong/access.log
proxy_error_log = /var/log/kong/error.log
admin_access_log = /var/log/kong/admin-access.log
admin_error_log = /var/log/kong/admin-error.log

#############
# PLUGINS  #
#############
plugins = bundled,opentelemetry,request-transformer,response-transformer,rate-limiting,authentication,correlation-id

#############
# CLUSTER  #
#############
cluster_listen = 0.0.0.0:7946
cluster_profile = wan
cluster_mtls = shared
lua_ssl_trusted_certificate = system

#############
# MEMORY   #
#############
mem_caching_enabled = on
db_cache_ttl = 3600
resolver = 8.8.8.8 8.8.4.4
resolver_flags = ipv4
upstream_keepalive = 60

#############
# SECURITY #
#############
admin_api_uri = https://admin.code-server.local:8444
anonymous_reports = off
EOF
}

# Kong Docker Compose Service
resource "local_file" "kong_compose" {
  filename = "${path.module}/../config/docker-compose/kong-service.yml"
  content  = <<-EOT
  # Kong API Gateway
  kong:
    image: kong:${var.kong_version}
    container_name: kong
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: postgres
      KONG_PG_PORT: 5432
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_secure_password
      KONG_PG_DATABASE: kong
      KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl
      KONG_ADMIN_LISTEN: 0.0.0.0:8001, 0.0.0.0:8444 ssl
      KONG_ADMIN_URL: http://kong:8001
      KONG_CLUSTER_LISTEN: 0.0.0.0:7946
      KONG_LOG_LEVEL: notice
      KONG_TRUSTED_IPS: 0.0.0.0/0,::/0
      KONG_REAL_IP_HEADER: X-Forwarded-For
      KONG_REAL_IP_RECURSIVE: on
      KONG_PLUGINS: bundled,opentelemetry,request-transformer,rate-limiting
    ports:
      - "8000:8000"    # Proxy HTTP
      - "8443:8443"    # Proxy HTTPS
      - "8001:8001"    # Admin API HTTP
      - "8444:8444"    # Admin API HTTPS
      - "7946:7946"    # Cluster communication
    volumes:
      - ./config/kong/kong.conf:/etc/kong/kong.conf:ro
      - ./config/kong/ssl:/etc/kong/ssl:ro
      - kong_logs:/var/log/kong
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8001/"]
      interval: 10s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - code-server-net

  # Kong Database Initialization
  kong-migrations:
    image: kong:${var.kong_version}
    container_name: kong-migrations
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: postgres
      KONG_PG_PORT: 5432
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_secure_password
      KONG_PG_DATABASE: kong
    command: kong migrations bootstrap
    depends_on:
      - postgres
    restart: on-failure
    networks:
      - code-server-net

  # Kong Admin UI (Optional)
  konga:
    image: pantsel/konga:latest
    container_name: konga
    environment:
      NODE_ENV: production
      DB_ADAPTER: postgres
      DB_HOST: postgres
      DB_PORT: 5432
      DB_USER: konga_user
      DB_PASSWORD: konga_password
      DB_DATABASE: konga
      KONGA_HOOK_TIMEOUT: 120000
    ports:
      - "1337:1337"
    depends_on:
      - postgres
      - kong
    restart: unless-stopped
    networks:
      - code-server-net

volumes:
  kong_logs:
EOT
}

# Prometheus Metrics Configuration for Kong
resource "local_file" "kong_prometheus_config" {
  filename = "${path.module}/../config/prometheus/kong-monitoring.yml"
  content  = <<-EOT
groups:
  - name: kong-api-gateway
    interval: 30s
    rules:
      # Kong Service Health
      - alert: KongProxyDown
        expr: up{job="kong-proxy"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Kong proxy is down"

      # Request Rate Monitoring
      - alert: KongHighRequestRate
        expr: rate(kong_http_requests_total[5m]) > 10000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Kong request rate is high ({{ $value | humanize }} req/s)"

      # Upstream Service Health
      - alert: KongUpstreamDown
        expr: kong_upstream_target_health != 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Kong upstream target is down: {{ $labels.upstream }}"

      # Rate Limiting Violations
      - alert: KongRateLimitExceeded
        expr: rate(kong_http_requests_total{status="429"}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High rate limit violations detected"

      # Error Rate
      - alert: KongHighErrorRate
        expr: rate(kong_http_requests_total{status=~"5.."}[5m]) / rate(kong_http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Kong error rate is high ({{ $value | humanizePercentage }})"

      # Response Time
      - alert: KongHighLatency
        expr: histogram_quantile(0.99, rate(kong_http_request_duration_ms_bucket[5m])) > 1000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Kong latency is high ({{ $value | humanize }}ms p99)"

  - name: kong-slo
    interval: 60s
    rules:
      # Gateway Availability SLO (99.95%)
      - record: slo:kong_availability:5m
        expr: rate(kong_http_requests_total{status!~"5.."}[5m]) / rate(kong_http_requests_total[5m])

      # Request Latency SLO (p99 < 500ms)
      - record: slo:kong_latency:p99
        expr: histogram_quantile(0.99, rate(kong_http_request_duration_ms_bucket[5m]))

      # Upstream Health SLO (100%)
      - record: slo:kong_upstream_health
        expr: count(kong_upstream_target_health == 1) / count(kong_upstream_target_health)

      # Cache Hit Ratio
      - record: slo:kong_cache_hit_ratio
        expr: rate(kong_cache_hits_total[5m]) / (rate(kong_cache_hits_total[5m]) + rate(kong_cache_misses_total[5m]))
EOT
}

output "kong_proxy_http" {
  description = "Kong proxy HTTP endpoint"
  value       = "http://${var.primary_host_ip}:8000"
}

output "kong_proxy_https" {
  description = "Kong proxy HTTPS endpoint"
  value       = "https://${var.primary_host_ip}:8443"
}

output "kong_admin_api" {
  description = "Kong Admin API endpoint"
  value       = "http://${var.primary_host_ip}:8001"
}

output "konga_dashboard_url" {
  description = "Konga Dashboard URL"
  value       = "http://${var.primary_host_ip}:1337"
}

output "kong_slo_targets" {
  value = {
    availability    = "99.95%"
    latency_p99_ms  = 500
    upstream_health = "100%"
    cache_hit_ratio = "> 80%"
  }
}
